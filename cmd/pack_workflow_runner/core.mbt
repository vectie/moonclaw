///|
pub(all) enum RunnerJsonSource {
  JsonFile(String)
  JsonStdin
} derive(Debug, Eq)

///|
pub(all) struct PackWorkflowRunnerOptions {
  workspace : String
  pack_id : String
  workflow_id : String
  run_id : String
  policy : RunnerJsonSource
  input : RunnerJsonSource?
} derive(Debug, Eq)

///|
pub(all) struct PackWorkflowRunnerResult {
  contract : String
  ok : Bool
  pack_id : String?
  workflow_id : String?
  run_id : String?
  job_id : String?
  durable_workflow_id : String?
  status : @job.RunStatus?
  outputs : Map[String, Json]
  error : String?
} derive(Debug, ToJson, FromJson)

///|
pub fn pack_workflow_runner_usage() -> String {
  (
    #|Usage: pack_workflow_runner \
    #|  --workspace <path> \
    #|  --pack-id <id> \
    #|  --workflow-id <id> \
    #|  --run-id <id> \
    #|  --policy <json-path|-> \
    #|  [--input <json-path|->]
    #|
    #|Use '-' for one stdin JSON source. Policy JSON is an InvocationPolicy.
    #|
  )
}

///|
fn runner_json_source(value : String) -> RunnerJsonSource {
  if value == "-" {
    JsonStdin
  } else {
    JsonFile(value)
  }
}

///|
pub fn parse_pack_workflow_runner_args(
  args : ArrayView[String],
) -> Result[PackWorkflowRunnerOptions, String] {
  let mut workspace = None
  let mut pack_id = None
  let mut workflow_id = None
  let mut run_id = None
  let mut policy = None
  let mut input = None
  for rest = args {
    match rest {
      ["--workspace", value, .. tail] => {
        if workspace is Some(_) {
          return Err("duplicate --workspace")
        }
        workspace = Some(value)
        continue tail
      }
      ["--pack-id", value, .. tail] => {
        if pack_id is Some(_) {
          return Err("duplicate --pack-id")
        }
        pack_id = Some(value)
        continue tail
      }
      ["--workflow-id", value, .. tail] => {
        if workflow_id is Some(_) {
          return Err("duplicate --workflow-id")
        }
        workflow_id = Some(value)
        continue tail
      }
      ["--run-id", value, .. tail] => {
        if run_id is Some(_) {
          return Err("duplicate --run-id")
        }
        run_id = Some(value)
        continue tail
      }
      ["--policy", value, .. tail] => {
        if policy is Some(_) {
          return Err("duplicate --policy")
        }
        policy = Some(runner_json_source(value))
        continue tail
      }
      ["--input", value, .. tail] => {
        if input is Some(_) {
          return Err("duplicate --input")
        }
        input = Some(runner_json_source(value))
        continue tail
      }
      [
        "--workspace"
        | "--pack-id"
        | "--workflow-id"
        | "--run-id"
        | "--policy"
        | "--input" as option,
      ] => return Err("missing value for " + option)
      [option, ..] => return Err("unknown argument: " + option)
      [] => break
    }
  }
  guard workspace is Some(workspace) else {
    return Err("missing required --workspace")
  }
  guard pack_id is Some(pack_id) else {
    return Err("missing required --pack-id")
  }
  guard workflow_id is Some(workflow_id) else {
    return Err("missing required --workflow-id")
  }
  guard run_id is Some(run_id) else { return Err("missing required --run-id") }
  guard policy is Some(policy) else { return Err("missing required --policy") }
  if policy is JsonStdin && input is Some(JsonStdin) {
    return Err("only one of --policy or --input may use stdin")
  }
  Ok({ workspace, pack_id, workflow_id, run_id, policy, input })
}

///|
pub fn PackWorkflowRunnerOptions::uses_stdin(
  self : PackWorkflowRunnerOptions,
) -> Bool {
  self.policy is JsonStdin || self.input is Some(JsonStdin)
}

///|
fn runner_error_result(
  options : PackWorkflowRunnerOptions?,
  error : String,
) -> PackWorkflowRunnerResult {
  {
    contract: "moonsuite.pack-workflow-runner-result.v1",
    ok: false,
    pack_id: options.map(option => option.pack_id),
    workflow_id: options.map(option => option.workflow_id),
    run_id: options.map(option => option.run_id),
    job_id: None,
    durable_workflow_id: None,
    status: None,
    outputs: {},
    error: Some(error),
  }
}

///|
fn runner_execution_result(
  options : PackWorkflowRunnerOptions,
  job_id : String,
  durable_workflow_id : String,
  status : @job.RunStatus,
  outputs : Map[String, Json],
  error : String?,
) -> PackWorkflowRunnerResult {
  {
    contract: "moonsuite.pack-workflow-runner-result.v1",
    ok: status is Succeeded,
    pack_id: Some(options.pack_id),
    workflow_id: Some(options.workflow_id),
    run_id: Some(options.run_id),
    job_id: Some(job_id),
    durable_workflow_id: Some(durable_workflow_id),
    status: Some(status),
    outputs,
    error,
  }
}

///|
async fn read_runner_json(
  source : RunnerJsonSource,
  stdin_text : String,
  label : String,
) -> Result[Json, String] {
  let text = match source {
    JsonStdin => stdin_text
    JsonFile(path) =>
      @fsx.read_file(path) catch {
        error => return Err("failed to read \{label} JSON: \{error}")
      }
  }
  if text.trim().is_blank() {
    return Err(label + " JSON is empty")
  }
  Ok(@json.parse(text)) catch {
    error => Err("invalid \{label} JSON: \{error}")
  }
}

///|
pub async fn execute_pack_workflow_runner(
  options : PackWorkflowRunnerOptions,
  stdin_text~ : String,
) -> PackWorkflowRunnerResult {
  let policy_json = match
    read_runner_json(options.policy, stdin_text, "policy") {
    Ok(policy) => policy
    Err(error) => return runner_error_result(Some(options), error)
  }
  let policy : @packtool.InvocationPolicy = @json.from_json(policy_json) catch {
    error =>
      return runner_error_result(
        Some(options),
        "invalid policy contract: \{error}",
      )
  }
  let input = match options.input {
    Some(source) =>
      match read_runner_json(source, stdin_text, "input") {
        Ok(input) => Some(input)
        Err(error) => return runner_error_result(Some(options), error)
      }
    None => None
  }
  let hosted = try {
    match input {
      Some(input) =>
        @packtool.run_installed_command_workflow(
          workspace=options.workspace,
          pack_id=options.pack_id,
          workflow_id=options.workflow_id,
          run_id=options.run_id,
          policy~,
          now=fn() { @clock.epoch.now().ms().to_int() },
          initial_input=input,
        )
      None =>
        @packtool.run_installed_command_workflow(
          workspace=options.workspace,
          pack_id=options.pack_id,
          workflow_id=options.workflow_id,
          run_id=options.run_id,
          policy~,
          now=fn() { @clock.epoch.now().ms().to_int() },
        )
    }
  } catch {
    error => return runner_error_result(Some(options), "\{error}")
  }
  runner_execution_result(
    options,
    hosted.intake.definition.id,
    hosted.intake.workflow.id,
    hosted.execution.run.status,
    hosted.execution.outputs,
    hosted.execution.run.error,
  )
}

///|
pub fn pack_workflow_runner_argument_error(
  error : String,
) -> PackWorkflowRunnerResult {
  runner_error_result(None, error)
}
