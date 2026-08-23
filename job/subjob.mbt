///|
pub(all) struct SubjobStepConfig {
  request_text : String
  cwd : String?
  home : String?
  child_profile : String?
  execution_mode : String?
  execution_target : String?
  include_parent_outputs : Bool
  max_depth : Int
} derive(ToJson, FromJson, Debug)

///|
pub fn SubjobStepConfig::new(
  request_text~ : String,
  cwd? : String? = None,
  home? : String? = None,
  child_profile? : String? = None,
  execution_mode? : String? = None,
  execution_target? : String? = None,
  include_parent_outputs? : Bool = true,
  max_depth? : Int = 2,
) -> SubjobStepConfig {
  {
    request_text,
    cwd,
    home,
    child_profile,
    execution_mode,
    execution_target,
    include_parent_outputs,
    max_depth,
  }
}

///|
fn proposal_with_execution_override(
  proposal : JobProposal,
  execution_mode : String?,
  execution_target : String?,
) -> JobProposal {
  let trimmed_mode = execution_mode.map(fn(mode) { mode.trim().to_owned() })
  let trimmed_target = execution_target.map(fn(target) {
    target.trim().to_owned()
  })
  if trimmed_mode.unwrap_or("").is_blank() &&
    trimmed_target.unwrap_or("").is_blank() {
    return proposal
  }
  let base_metadata = match proposal.profile_metadata {
    Object(obj) => obj
    _ => {}
  }
  let execution_metadata = match base_metadata.get("execution") {
    Some(Object(obj)) => obj
    _ => {}
  }
  let merged_execution_metadata : Map[String, Json] = Map([])
  for key, value in execution_metadata {
    merged_execution_metadata.set(key, value)
  }
  match trimmed_mode {
    Some(mode) if !mode.is_blank() =>
      merged_execution_metadata.set("mode", mode.to_json())
    _ => ()
  }
  match trimmed_target {
    Some(target) if !target.is_blank() =>
      merged_execution_metadata.set("target", target.to_json())
    _ => ()
  }
  let merged_profile_metadata : Map[String, Json] = Map([])
  for key, value in base_metadata {
    merged_profile_metadata.set(key, value)
  }
  merged_profile_metadata.set(
    "execution",
    Json::object(merged_execution_metadata),
  )
  { ..proposal, profile_metadata: Json::object(merged_profile_metadata) }
}

///|
fn proposal_execution_override(
  proposal : JobProposal,
  config : SubjobStepConfig,
) -> (String?, String?) {
  if provider_execution_requested(config.execution_mode) {
    let profile_target = match proposal.profile_metadata {
      { "execution": { "target": String(target), .. }, .. } =>
        Some(target.trim().to_owned())
      _ => None
    }
    let profile_mode = match proposal.profile_metadata {
      { "execution": { "mode": String(mode), .. }, .. } =>
        Some(mode.trim().to_owned())
      _ => None
    }
    let execution_mode = match profile_mode {
      Some(mode) => Some(mode)
      None => config.execution_mode
    }
    let execution_target = match profile_target {
      Some(target) => Some(target)
      None => config.execution_target
    }
    (execution_mode, execution_target)
  } else {
    (config.execution_mode, config.execution_target)
  }
}

///|
fn proposal_with_isolation_policy(proposal : JobProposal) -> JobProposal {
  let updated_steps = proposal.steps.map(fn(step) {
    let isolation_metadata = subtask_execution_isolation_metadata(
      step.id,
      step.title,
      step.prompt,
      Some(step.kind),
    )
    if isolation_metadata.stringify() == "{}" {
      step
    } else {
      let merged_step_metadata : Map[String, Json] = Map([])
      match step.metadata {
        Object(obj) =>
          for key, value in obj {
            merged_step_metadata.set(key, value)
          }
        _ => ()
      }
      match isolation_metadata {
        Object(obj) =>
          for key, value in obj {
            merged_step_metadata.set(key, value)
          }
        _ => ()
      }
      { ..step, metadata: Json::object(merged_step_metadata) }
    }
  })
  { ..proposal, steps: updated_steps }
}

///|
fn inherited_missing_input_policy(
  context : WorkflowStepContext,
  store : SystemStore,
) -> (Bool?, Bool?) {
  let from_step_disable = waiting_for_input_disabled_from_metadata(
    context.step.config,
  )
  let from_step_best_effort = best_effort_on_missing_input_from_metadata(
    context.step.config,
  )
  let definition = store.get_definition(context.run.job_id)
  let from_job_disable = definition.bind(fn(definition) {
    disable_waiting_for_input_in_job_config(definition.config)
  })
  let from_job_best_effort = definition.bind(fn(definition) {
    best_effort_on_missing_input_in_job_config(definition.config)
  })
  (
    match from_step_disable {
      Some(value) => Some(value)
      None => from_job_disable
    },
    match from_step_best_effort {
      Some(value) => Some(value)
      None => from_job_best_effort
    },
  )
}

///|
fn proposal_with_missing_input_policy(
  proposal : JobProposal,
  disable_waiting : Bool?,
  best_effort_on_missing_input : Bool?,
) -> JobProposal {
  if disable_waiting is None && best_effort_on_missing_input is None {
    return proposal
  }
  let policy_metadata : Map[String, Json] = Map([])
  match disable_waiting {
    Some(value) =>
      policy_metadata.set("disable_waiting_for_input", value.to_json())
    None => ()
  }
  match best_effort_on_missing_input {
    Some(value) =>
      policy_metadata.set("best_effort_on_missing_input", value.to_json())
    None => ()
  }
  let policy_json = Json::object(policy_metadata)
  let steps = proposal.steps.map(fn(step) {
    JobProposalStep::{
      ..step,
      metadata: merge_json_metadata(step.metadata, policy_json),
    }
  })
  {
    ..proposal,
    profile_metadata: merge_json_metadata(
      proposal.profile_metadata,
      policy_json,
    ),
    steps,
  }
}

///|
async fn planned_subjob_proposal(
  request_text : String,
  cwd : String,
  home : String?,
  config : SubjobStepConfig,
  planner : ProposalPlanner,
  now : () -> Int,
) -> Result[JobProposal, String] {
  // For provider-backed delegation, the provider owns task decomposition and
  // MoonClaw only compiles the returned task batch into child analysis steps.
  if provider_execution_requested(config.execution_mode) {
    // `cwd` is normally the isolated run workspace. Provider discovery must
    // instead remain affine to the domain workspace declared by the delegate;
    // otherwise a book-local provider disappears as soon as isolation begins.
    let provider_workspace = config.cwd
      .map(fn(value) { value.trim().to_owned() })
      .filter(fn(value) { !value.is_blank() })
      .unwrap_or(cwd)
    let (command, batch) = match
      load_provider_task_task_batch(
        cwd,
        home,
        config.execution_target,
        request_text,
        metadata={ "workspace_root": provider_workspace },
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let resolved_config = SubjobStepConfig::{
      ..config,
      execution_target: Some(command.provider.name),
    }
    Ok(
      provider_task_child_proposal(
        request_text,
        batch,
        command,
        resolved_config,
        now(),
      ),
    )
  } else {
    Ok((planner.run)(request_text, cwd, home))
  }
}

///|
fn render_parent_outputs(outputs : Map[String, Json]) -> String {
  if outputs.is_empty() {
    return ""
  }
  let rendered : Array[String] = []
  for step_id, output in outputs {
    rendered.push("[\{step_id}] \{output.stringify()}")
  }
  rendered.join("\n")
}

///|
fn compiled_subjob_request(
  context : WorkflowStepContext,
  config : SubjobStepConfig,
) -> String {
  if !config.include_parent_outputs || context.outputs.is_empty() {
    config.request_text
  } else {
    [
      config.request_text,
      "Parent workflow outputs:",
      render_parent_outputs(context.outputs),
    ].join("\n\n")
  }
}

///|
pub(all) struct ProposalPlanner {
  run : async (String, String, String?) -> JobProposal
}

///|
pub fn ProposalPlanner::new(
  run~ : async (String, String, String?) -> JobProposal,
) -> ProposalPlanner {
  { run, }
}

///|
pub(all) struct ProposalCompiler {
  run : (JobProposal, Int, String, String) -> ProposalCompilation
}

///|
pub fn ProposalCompiler::new(
  run~ : (JobProposal, Int, String, String) -> ProposalCompilation,
) -> ProposalCompiler {
  { run, }
}

///|
pub(all) struct ChildRunExecutionRequest {
  parent_context : WorkflowStepContext
  child_run : JobRun
  compilation : ProposalCompilation
  config : SubjobStepConfig
  control : WorkflowExecutionControl
}

///|
pub(all) struct ChildRunExecutionResult {
  outputs : Map[String, Json]
}

///|
pub(all) struct ChildRunExecutor {
  run : async (ChildRunExecutionRequest) -> Result[
    ChildRunExecutionResult?,
    String,
  ]
}

///|
pub fn ChildRunExecutor::new(
  run~ : async (ChildRunExecutionRequest) -> Result[
    ChildRunExecutionResult?,
    String,
  ],
) -> ChildRunExecutor {
  { run, }
}

///|
async fn execute_child_run_locally(
  child_run : JobRun,
  engine_factory : () -> WorkflowEngine,
  now : () -> Int,
  control : WorkflowExecutionControl,
) -> Result[ChildRunExecutionResult, String] {
  let engine = engine_factory()
  let child_result = match engine.execute_run(child_run.id, now, control~) {
    Ok(result) => result
    Err(error) => return Err("Subjob \{child_run.id} failed: \{error}")
  }
  if child_result.run.status is WaitingForInput {
    let summary = child_result.run.summary.unwrap_or(
      "Child run \{child_run.id} is waiting for input",
    )
    return Err("Subjob \{child_run.id} is waiting for input: \{summary}")
  }
  Ok({ outputs: child_result.outputs })
}

///|
async fn record_parent_child_run_event(
  store : SystemStore,
  context : WorkflowStepContext,
  compilation : ProposalCompilation,
  child_run : JobRun,
  event_type : String,
  status : RunStatus,
  message : String,
  now_ms : Int,
) -> Unit {
  store.append_run_event({
    run_id: context.run.id,
    job_id: context.run.job_id,
    event_type,
    timestamp: now_ms,
    step_id: Some(context.step.id),
    status: Some(status),
    message,
    data: {
      "child_job_id": compilation.definition.id,
      "child_run_id": child_run.id,
      "child_family": compilation.family,
    },
  })
}

///|
async fn record_parent_child_run_started(
  store : SystemStore,
  context : WorkflowStepContext,
  compilation : ProposalCompilation,
  child_run : JobRun,
  now_ms : Int,
) -> Unit {
  record_parent_child_run_event(
    store,
    context,
    compilation,
    child_run,
    "child_run.started",
    Running,
    "Child run \{child_run.id} started for step \{context.step.id}",
    now_ms,
  )
}

///|
async fn record_parent_child_run_finished(
  store : SystemStore,
  context : WorkflowStepContext,
  compilation : ProposalCompilation,
  child_run : JobRun,
  status : RunStatus,
  message : String,
  now_ms : Int,
) -> Unit {
  record_parent_child_run_event(
    store,
    context,
    compilation,
    child_run,
    if status is Succeeded {
      "child_run.succeeded"
    } else {
      "child_run.failed"
    },
    status,
    message,
    now_ms,
  )
}

///|
pub fn subjob_step_handler(
  runtime~ : RuntimeManager,
  planner~ : ProposalPlanner,
  compiler~ : ProposalCompiler,
  engine_factory~ : () -> WorkflowEngine,
  child_executor? : ChildRunExecutor? = None,
  now? : () -> Int = fn() { @async.now().to_int() },
  next_run_id? : () -> String = fn() { "run.\{now()}" },
  kind? : String = "job.delegate",
) -> WorkflowStepHandler {
  let store = runtime.store()
  WorkflowStepHandler::new(kind~, run=async fn(context) {
    let config : SubjobStepConfig = @json.from_json(context.step.config) catch {
      error => return Err("Invalid subjob step config: \{error}")
    }
    guard context.run.depth < config.max_depth else {
      return Err(
        "Subjob depth limit reached: \{context.run.depth} >= \{config.max_depth}",
      )
    }
    let cwd = context.run.workspace_dir.unwrap_or(config.cwd.unwrap_or("."))
    let home = config.home
    let request_text = compiled_subjob_request(context, config)
    let proposal = match
      planned_subjob_proposal(request_text, cwd, home, config, planner, now) {
      Ok(proposal) => proposal
      Err(error) => return Err(error)
    }
    let proposal = apply_named_job_profile(
      proposal,
      cwd,
      home.unwrap_or(cwd),
      cwd,
      config.child_profile,
    )
    let (disable_waiting, best_effort_on_missing_input) = inherited_missing_input_policy(
      context, store,
    )
    let proposal = proposal_with_missing_input_policy(
      proposal, disable_waiting, best_effort_on_missing_input,
    )
    let proposal = proposal_with_isolation_policy(proposal)
    let (execution_mode, execution_target) = proposal_execution_override(
      proposal, config,
    )
    let proposal = proposal_with_execution_override(
      proposal, execution_mode, execution_target,
    )
    let compilation = (compiler.run)(proposal, now(), cwd, home.unwrap_or("."))
    store.save_job_proposal({
      ..proposal,
      status: Confirmed,
      job_id: Some(compilation.definition.id),
      workflow_id: Some(compilation.workflow.id),
      updated_at: now(),
    })
    runtime.register_definition(compilation.definition)
    runtime.register_workflow(compilation.workflow)
    for binding in compilation.bindings {
      store.save_chat_binding(binding)
    }
    let child_run = match
      runtime.trigger_definition(
        next_run_id(),
        compilation.definition.id,
        Custom("subjob"),
        now(),
        parent_run_id=Some(context.run.id),
        parent_step_id=Some(context.step.id),
        depth=context.run.depth + 1,
      ) {
      Ok(run) => run
      Err(error) => return Err(error)
    }
    record_controller_child_run(
      store,
      context.run,
      context.step,
      compilation.definition.id,
      child_run.id,
      compilation.family,
      now(),
    )
    record_parent_child_run_started(
      store,
      context,
      compilation,
      child_run,
      now(),
    )
    store.save_job_proposal({
      ..proposal,
      status: Confirmed,
      job_id: Some(compilation.definition.id),
      workflow_id: Some(compilation.workflow.id),
      last_run_id: Some(child_run.id),
      updated_at: now(),
    })
    let child_request = ChildRunExecutionRequest::{
      parent_context: context,
      child_run,
      compilation,
      config,
      control: context.control,
    }
    let child_result = match child_executor {
      Some(executor) =>
        match (executor.run)(child_request) {
          Ok(Some(result)) => result
          Ok(None) =>
            match
              execute_child_run_locally(
                child_run,
                engine_factory,
                now,
                context.control,
              ) {
              Ok(result) => result
              Err(error) => {
                record_parent_child_run_finished(
                  store,
                  context,
                  compilation,
                  child_run,
                  Failed,
                  "Child run \{child_run.id} failed: \{error}",
                  now(),
                )
                return Err(error)
              }
            }
          Err(error) => {
            record_parent_child_run_finished(
              store,
              context,
              compilation,
              child_run,
              Failed,
              "Child run \{child_run.id} failed: \{error}",
              now(),
            )
            return Err(error)
          }
        }
      None =>
        match
          execute_child_run_locally(
            child_run,
            engine_factory,
            now,
            context.control,
          ) {
          Ok(result) => result
          Err(error) => {
            record_parent_child_run_finished(
              store,
              context,
              compilation,
              child_run,
              Failed,
              "Child run \{child_run.id} failed: \{error}",
              now(),
            )
            return Err(error)
          }
        }
    }
    record_parent_child_run_finished(
      store,
      context,
      compilation,
      child_run,
      Succeeded,
      "Child run \{child_run.id} completed",
      now(),
    )
    let logs = [
      "spawned child run \{child_run.id}",
      "child family: \{compilation.family}",
    ]
    match config.execution_mode {
      Some(mode) if !mode.trim().to_owned().is_blank() =>
        logs.push("child execution mode: \{mode}")
      _ => ()
    }
    match config.execution_target {
      Some(target) if !target.trim().to_owned().is_blank() =>
        logs.push("child execution target: \{target}")
      _ => ()
    }
    Ok(
      WorkflowStepResult::new(
        output={
          "status": "completed",
          "child_job_id": compilation.definition.id,
          "child_run_id": child_run.id,
          "child_family": compilation.family,
          "child_outputs": child_result.outputs,
        },
        summary=Some(
          "Subjob \{compilation.definition.id} completed as \{compilation.family}",
        ),
        logs~,
      ),
    )
  })
}
