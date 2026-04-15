///|
/// Provider-backed extension task bridge.
/// It lets workspace-local providers shape domain work while MoonClaw keeps
/// execution, artifacts, lineage, and operator visibility generic.
///

///|
pub(all) struct ProviderTaskSpec {
  id : String
  title : String
  kind : String
  prompt : String
  priority : Int
  requires_review : Bool
  target_pages : Array[String]
} derive(Show, ToJson, FromJson)

///|
pub(all) struct ProviderTaskBatch {
  goal_id : String
  goal : String
  summary : String
  tasks : Array[ProviderTaskSpec]
} derive(Show, ToJson, FromJson)

///|
/// Provider-owned context schema. Some field names remain wiki-shaped for
/// compatibility with existing extensions, but MoonClaw treats this as generic
/// extension task context.
pub(all) struct ProviderTaskWorkerContext {
  book_id : String
  workspace_root : String
  task_id : String
  prompt : String
  policy : Array[String]
  routines : Array[String]
  skill_paths : Array[String]
  context_pages : Array[String]
  active_memory : Array[String]
  user_memory : Array[String]
  working_memory : Array[String]
  memory_summary : String
  output_contract : Array[String]
} derive(Show, ToJson, FromJson)

///|
pub(all) struct ProviderTaskMemoryCandidate {
  kind : String
  title : String
  detail : String
  durable : Bool
  target_page : String?
} derive(Show, Eq, ToJson, FromJson)

///|
pub(all) struct ProviderTaskResult {
  task_id : String
  summary : String
  artifacts : Array[String]
  memory_candidates : Array[ProviderTaskMemoryCandidate]
  requires_review : Bool
  notify_town : Bool
} derive(Show, ToJson, FromJson)

///|
pub(all) struct ProviderTaskPersistOutcome {
  log_path : String
  updated_pages : Array[String]
  review_queued : Bool
  notify_town : Bool
  evidence_id : String
} derive(Show, ToJson, FromJson)

///|
pub(all) struct ProviderTaskCommand {
  provider : @resource_providers.RegisteredResourceProvider
  command : String
  args : Array[String]
  cwd : String?
  workspace_root : String
} derive(Show)

///|
fn provider_execution_requested(mode : String?) -> Bool {
  match mode {
    Some(mode) => {
      let normalized = mode.trim().to_lower()
      normalized == "provider" ||
      normalized == "extension" ||
      normalized == "provider.task" ||
      normalized == "extension.task" ||
      normalized == "bookapi" ||
      normalized == "moonbook.bookapi"
    }
    None => false
  }
}

///|
fn provider_metadata_string(metadata : Json, key : String) -> String? {
  match metadata {
    Object(obj) =>
      match obj.get(key) {
        Some(String(value)) if !value.trim().to_string().is_blank() =>
          Some(value.trim().to_string())
        _ => None
      }
    _ => None
  }
}

///|
fn provider_metadata_string_array(
  metadata : Json,
  key : String,
) -> Array[String] {
  match metadata {
    Object(obj) =>
      match obj.get(key) {
        Some(Array(values)) => {
          let items : Array[String] = []
          for value in values {
            guard value is String(text) else { continue }
            let trimmed = text.trim().to_string()
            if !trimmed.is_blank() {
              items.push(trimmed)
            }
          }
          items
        }
        _ => []
      }
    _ => []
  }
}

///|
/// Provider capability matching stays permissive during migration so existing
/// extension implementations can move to generic names without breaking runs.
fn provider_supports_extension_execution(
  provider : @resource_providers.RegisteredResourceProvider,
) -> Bool {
  provider.kind == "extension" ||
  provider.kind == "task-provider" ||
  provider.kind == "book-harness" ||
  provider.kind == "moonbook" ||
  provider.capabilities.contains("provider") ||
  provider.capabilities.contains("extension") ||
  provider.capabilities.contains("provider.task") ||
  provider.capabilities.contains("extension.task") ||
  provider.capabilities.contains("bookapi") ||
  provider.capabilities.contains("moonbook.bookapi")
}

///|
fn provider_workspace_root(
  provider : @resource_providers.RegisteredResourceProvider,
) -> String? {
  provider_metadata_string(provider.metadata, "workspace_root").map(fn(root) {
    @pathx.normalize(root)
  })
}

///|
fn path_is_within(root : String, path : String) -> Bool {
  let normalized_root = @pathx.normalize(root)
  let normalized_path = @pathx.normalize(path)
  normalized_path == normalized_root ||
  normalized_path.has_prefix("\{normalized_root}/")
}

///|
fn select_provider_by_workspace_affinity(
  providers : Array[@resource_providers.RegisteredResourceProvider],
  cwd : String,
) -> @resource_providers.RegisteredResourceProvider? {
  let matches = providers.iter().filter(fn(provider) {
    match provider_workspace_root(provider) {
      Some(root) => path_is_within(root, cwd)
      None => false
    }
  }).to_array()
  match matches {
    [provider] => Some(provider)
    _ => None
  }
}

///|
async fn resolve_provider_task_command(
  cwd : String,
  home : String?,
  target_id : String?,
) -> Result[ProviderTaskCommand, String] {
  let provider = match target_id {
    Some(target_id) if !target_id.trim().to_string().is_blank() =>
      match @resource_providers.find_resource_provider(cwd, target_id, home~) {
        Some(provider) => provider
        None => return Err("Unknown provider task target: \{target_id}")
      }
    _ => {
      let providers = @resource_providers.load_resource_providers(cwd, home~)
        .iter()
        .filter(fn(provider) { provider_supports_extension_execution(provider) })
        .to_array()
      match providers {
        [provider] => provider
        _ =>
          match select_provider_by_workspace_affinity(providers, cwd) {
            Some(provider) => provider
            None =>
              match providers {
                [] =>
                  return Err(
                    "Extension task execution requires execution_target or exactly one registered provider target",
                  )
                _ =>
                  return Err(
                    "Extension task execution requires execution_target because multiple provider targets are registered",
                  )
              }
          }
      }
    }
  }
  guard provider_supports_extension_execution(provider) else {
    return Err(
      "Execution target \{provider.name} does not expose extension task capability",
    )
  }
  let command = provider_metadata_string(provider.metadata, "command").unwrap_or(
    "moon",
  )
  let args = provider_metadata_string_array(provider.metadata, "args")
  let command_cwd = provider_metadata_string(provider.metadata, "cwd")
  let workspace_root = match
    provider_metadata_string(provider.metadata, "workspace_root") {
    Some(root) => root
    None =>
      return Err(
        "Extension task target \{provider.name} is missing metadata.workspace_root",
      )
  }
  Ok(ProviderTaskCommand::{
    provider,
    command,
    args,
    cwd: command_cwd,
    workspace_root,
  })
}

///|
fn parse_provider_task_payload(
  text : String,
  context : String,
) -> Result[Json, String] {
  let trimmed = text.trim().to_string()
  if trimmed.is_blank() {
    return Err("Provider task \{context} returned empty stdout")
  }
  let json = @json.parse(trimmed) catch {
    error =>
      return Err("Provider task \{context} returned invalid JSON: \{error}")
  }
  Ok(json)
}

///|
fn parse_provider_task_task_batch_json(
  text : String,
  context : String,
) -> Result[ProviderTaskBatch, String] {
  let json = match parse_provider_task_payload(text, context) {
    Ok(json) => json
    Err(error) => return Err(error)
  }
  let decoded : ProviderTaskBatch = @json.from_json(json) catch {
    error =>
      return Err(
        "Provider task \{context} returned unexpected payload: \{error}",
      )
  }
  Ok(decoded)
}

///|
fn parse_provider_task_worker_context_json(
  text : String,
  context : String,
) -> Result[ProviderTaskWorkerContext, String] {
  let json = match parse_provider_task_payload(text, context) {
    Ok(json) => json
    Err(error) => return Err(error)
  }
  let decoded : ProviderTaskWorkerContext = @json.from_json(json) catch {
    error =>
      return Err(
        "Provider task \{context} returned unexpected payload: \{error}",
      )
  }
  Ok(decoded)
}

///|
fn parse_provider_task_persist_outcome_json(
  text : String,
  context : String,
) -> Result[ProviderTaskPersistOutcome, String] {
  let json = match parse_provider_task_payload(text, context) {
    Ok(json) => json
    Err(error) => return Err(error)
  }
  let decoded : ProviderTaskPersistOutcome = @json.from_json(json) catch {
    error =>
      return Err(
        "Provider task \{context} returned unexpected payload: \{error}",
      )
  }
  Ok(decoded)
}

///|
async fn run_provider_task_stdout(
  command : ProviderTaskCommand,
  subcommand : String,
  extra_args : Array[String],
  context : String,
) -> Result[String, String] {
  let arguments : Array[String] = [
    ..command.args,
    "wiki",
    "book",
    subcommand,
    command.workspace_root,
    ..extra_args,
  ]
  let process = @spawn.spawn(
    command.command,
    arguments.map(fn(arg) { arg[:] }),
    cwd?=command.cwd.map(fn(value) { value[:] }),
  ) catch {
    error => return Err("Failed to launch provider task \{context}: \{error}")
  }
  if process.status != 0 {
    let stderr = process.stderr.trim().to_string()
    let stdout = process.stdout.trim().to_string()
    let reason = if !stderr.is_blank() {
      stderr
    } else if !stdout.is_blank() {
      stdout
    } else {
      "exit status \{process.status}"
    }
    return Err("Provider task \{context} failed: \{reason}")
  }
  Ok(process.stdout)
}

///|
async fn load_provider_task_task_batch(
  cwd : String,
  home : String?,
  target_id : String?,
  goal : String,
) -> Result[(ProviderTaskCommand, ProviderTaskBatch), String] {
  let command = match resolve_provider_task_command(cwd, home, target_id) {
    Ok(command) => command
    Err(error) => return Err(error)
  }
  let stdout = match
    run_provider_task_stdout(command, "tasks", [goal], "tasks") {
    Ok(stdout) => stdout
    Err(error) => return Err(error)
  }
  let batch : ProviderTaskBatch = match
    parse_provider_task_task_batch_json(stdout, "tasks") {
    Ok(batch) => batch
    Err(error) => return Err(error)
  }
  Ok((command, batch))
}

///|
async fn load_provider_task_context(
  command : ProviderTaskCommand,
  goal : String,
  task_id : String,
) -> Result[ProviderTaskWorkerContext, String] {
  let stdout = match
    run_provider_task_stdout(
      command,
      "context",
      [goal, "--task", task_id],
      "context",
    ) {
    Ok(stdout) => stdout
    Err(error) => return Err(error)
  }
  match parse_provider_task_worker_context_json(stdout, "context") {
    Ok(context) => Ok(context)
    Err(error) => Err(error)
  }
}

///|
fn select_provider_task_task(
  batch : ProviderTaskBatch,
  task_id : String?,
) -> Result[ProviderTaskSpec, String] {
  match task_id {
    Some(task_id) if !task_id.trim().to_string().is_blank() =>
      match batch.tasks.iter().find_first(fn(task) { task.id == task_id }) {
        Some(task) => Ok(task)
        None => Err("Provider task task batch does not contain task \{task_id}")
      }
    _ =>
      if batch.tasks.is_empty() {
        Err("Provider task task batch is empty")
      } else {
        Ok(batch.tasks[0])
      }
  }
}

///|
fn provider_task_step_metadata(
  goal : String,
  goal_id : String,
  task : ProviderTaskSpec,
) -> Json {
  {
    // `bookapi_*` keys are compatibility aliases for older extension packs.
    "bookapi_goal": goal,
    "bookapi_goal_id": goal_id,
    "bookapi_task_id": task.id,
    "bookapi_task_kind": task.kind,
    "bookapi_priority": task.priority,
    "bookapi_requires_review": task.requires_review,
    "bookapi_target_pages": task.target_pages,
    "extension_goal": goal,
    "extension_goal_id": goal_id,
    "extension_task_id": task.id,
    "extension_task_kind": task.kind,
    "extension_priority": task.priority,
    "extension_requires_review": task.requires_review,
    "extension_target_pages": task.target_pages,
  }
}

///|
fn provider_task_child_proposal(
  request_text : String,
  batch : ProviderTaskBatch,
  config : SubjobStepConfig,
  now_ms : Int,
) -> JobProposal {
  let steps = batch.tasks.map(fn(task) {
    JobProposalStep::{
      id: task.id,
      title: task.title,
      prompt: task.prompt,
      kind: "job.analysis",
      metadata: provider_task_step_metadata(batch.goal, batch.goal_id, task),
      child_profile: None,
      execution_mode: config.execution_mode,
      execution_target: config.execution_target,
      include_parent_outputs: None,
      max_depth: None,
    }
  })
  JobProposal::{
    id: human_readable_proposal_id(batch.goal, now_ms, now_ms.to_string()),
    title: compact_title(batch.goal),
    request_text,
    summary: batch.summary,
    revision_history: [],
    suggested_family: Some("extension"),
    profile_id: config.child_profile,
    profile_role: None,
    profile_metadata: {
      "execution": {
        "mode": config.execution_mode,
        "target": config.execution_target,
      },
      "extension": {
        "goal": batch.goal,
        "goal_id": batch.goal_id,
        "task_count": batch.tasks.length(),
      },
    },
    status: Draft,
    steps,
    tags: ["job", "extension"],
    channel_id: None,
    account_id: None,
    recipient: None,
    thread_id: None,
    presented_message_id: None,
    job_id: None,
    workflow_id: None,
    last_run_id: None,
    created_at: now_ms,
    updated_at: now_ms,
  }
}

///|
fn metadata_string_value(metadata : Json, key : String) -> String? {
  match metadata {
    Object(obj) =>
      match obj.get(key) {
        Some(String(value)) if !value.trim().to_string().is_blank() =>
          Some(value.trim().to_string())
        _ => None
      }
    _ => None
  }
}

///|
fn join_bullets(items : Array[String]) -> String {
  if items.is_empty() {
    "- none"
  } else {
    items.map(fn(item) { "- \{item}" }).join("\n")
  }
}

///|
fn provider_task_system_prompt(
  request : AnalysisRequest,
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
) -> String {
  [
    request.system_prompt,
    "You are executing a domain-local extension task.",
    "Return strict JSON only matching this shape:",
    "{\"task_id\":string,\"summary\":string,\"artifacts\":string[],\"memory_candidates\":[{\"kind\":string,\"title\":string,\"detail\":string,\"durable\":bool,\"target_page\":string|null}],\"requires_review\":bool,\"notify_town\":bool}",
    "Use task_id = \{task.id}.",
    "Summary should describe the actual work completed inside the extension boundary.",
    "Artifacts should list durable output paths relative to the workspace when relevant.",
    "Only emit memory_candidates that are worth persisting back into the extension provider.",
    "Do not wrap the JSON in markdown fences.",
    "Output contract from the harness:",
    join_bullets(context.output_contract),
  ]
  .filter(fn(line) { !line.trim().to_string().is_blank() })
  .join("\n\n")
}

///|
fn provider_task_prompt(
  request : AnalysisRequest,
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
) -> String {
  let goal = metadata_string_value(request.step_metadata, "extension_goal").unwrap_or(
    metadata_string_value(request.step_metadata, "bookapi_goal").unwrap_or(
      request.source_prompt,
    ),
  )
  let sections : Array[String] = [
    "Provider Scope: \{context.book_id}",
    "Workspace: \{context.workspace_root}",
    "Goal: \{goal}",
    "Task: \{task.title}",
    "",
    "Task Prompt:",
    context.prompt,
    "",
    "Policy:",
    join_bullets(context.policy),
    "",
    "Routines:",
    join_bullets(context.routines),
    "",
    "Relevant Pages:",
    join_bullets(context.context_pages),
    "",
    "Active Memory:",
    join_bullets(context.active_memory),
    "",
    "User Memory:",
    join_bullets(context.user_memory),
    "",
    "Working Memory:",
    join_bullets(context.working_memory),
    "",
    "Memory Summary:",
    if context.memory_summary.trim().to_string().is_blank() {
      "none"
    } else {
      context.memory_summary
    },
  ]
  if !context.skill_paths.is_empty() {
    sections.push("")
    sections.push("Available Skill Files:")
    sections.push(join_bullets(context.skill_paths))
  }
  sections.push("")
  sections.push("Original MoonClaw Request:")
  sections.push(request.prompt)
  sections.join("\n")
}

///|
fn parse_provider_task_result(
  content : String,
) -> Result[ProviderTaskResult, String] {
  let trimmed = content.trim().to_string()
  if trimmed.is_blank() || !trimmed.has_prefix("{") {
    return Err("Provider task analysis must return a JSON object")
  }
  let json = match parse_provider_task_payload(trimmed, "analysis") {
    Ok(json) => json
    Err(error) => return Err(error)
  }
  let decoded : ProviderTaskResult = @json.from_json(json) catch {
    error =>
      return Err(
        "Provider task analysis returned invalid ProviderTaskResult: \{error}",
      )
  }
  Ok(decoded)
}

///|
fn persisted_provider_task_report(
  task : ProviderTaskSpec,
  result : ProviderTaskResult,
  outcome : ProviderTaskPersistOutcome,
) -> String {
  let updated_pages = if outcome.updated_pages.is_empty() {
    "- none"
  } else {
    outcome.updated_pages.map(fn(page) { "- \{page}" }).join("\n")
  }
  [
    "# Extension Task Result",
    "",
    "## Task",
    "- id: \{task.id}",
    "- title: \{task.title}",
    "- kind: \{task.kind}",
    "",
    "## Summary",
    result.summary,
    "",
    "## Persisted Pages",
    updated_pages,
    "",
    "## Persist Outcome",
    "- evidence_id: \{outcome.evidence_id}",
    "- review_queued: \{outcome.review_queued}",
    "- notify_town: \{outcome.notify_town}",
    "- log_path: \{outcome.log_path}",
  ].join("\n")
}

///|
fn execution_metadata_value(metadata : Json, key : String) -> Json? {
  match metadata {
    Object(obj) => obj.get(key)
    _ => None
  }
}

///|
fn persisted_provider_task_execution(
  execution : AnalysisExecution,
  task : ProviderTaskSpec,
  result : ProviderTaskResult,
  outcome : ProviderTaskPersistOutcome,
  target_id : String,
) -> AnalysisExecution {
  AnalysisExecution::{
    ..execution,
    content: persisted_provider_task_report(task, result, outcome),
    metadata: {
      "job_id": execution_metadata_value(execution.metadata, "job_id"),
      "run_id": execution_metadata_value(execution.metadata, "run_id"),
      "step_id": execution_metadata_value(execution.metadata, "step_id"),
      "execution_mode": "provider",
      "execution_target": target_id,
      // Emit both generic and compatibility metadata so newer UIs/configs can
      // switch immediately while older packs keep working.
      "extension_task_id": task.id,
      "extension_result": result,
      "extension_persist_outcome": outcome,
      "bookapi_task_id": task.id,
      "bookapi_result": result,
      "bookapi_persist_outcome": outcome,
      "execution_isolation": execution_metadata_value(
        execution.metadata,
        "execution_isolation",
      ),
      "role_runtime_contract": execution_metadata_value(
        execution.metadata,
        "role_runtime_contract",
      ),
    },
  }
}

///|
async fn persist_provider_task_result(
  command : ProviderTaskCommand,
  request : AnalysisRequest,
  _task : ProviderTaskSpec,
  result : ProviderTaskResult,
) -> Result[ProviderTaskPersistOutcome, String] {
  let result_path = @pathx.join(
    request.cwd,
    ".moonclaw-provider-result-\{request.run_id}-\{request.step_id}.json",
  )
  @fsx.write_to_file(
    result_path,
    result.to_json().stringify(indent=2),
    create=0o644,
  )
  let stdout = match
    run_provider_task_stdout(command, "persist", [result_path], "persist") {
    Ok(stdout) => stdout
    Err(error) => return Err(error)
  }
  let outcome : ProviderTaskPersistOutcome = match
    parse_provider_task_persist_outcome_json(stdout, "persist") {
    Ok(outcome) => outcome
    Err(error) => return Err(error)
  }
  Ok(outcome)
}

///|
async fn run_provider_task_analysis_runner(
  request : AnalysisRequest,
  inner_runner : async (AnalysisRequest) -> Result[AnalysisExecution, String],
) -> Result[AnalysisExecution, String] {
  let goal = metadata_string_value(request.step_metadata, "extension_goal").unwrap_or(
    metadata_string_value(request.step_metadata, "bookapi_goal").unwrap_or(
      request.source_prompt,
    ),
  )
  let selected_task_id = match
    metadata_string_value(request.step_metadata, "extension_task_id") {
    Some(task_id) => Some(task_id)
    None => metadata_string_value(request.step_metadata, "bookapi_task_id")
  }
  let (command, batch) = match
    load_provider_task_task_batch(
      request.cwd,
      request.home,
      request.execution_target,
      goal,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let resolved_target_id = command.provider.name
  let task = match select_provider_task_task(batch, selected_task_id) {
    Ok(task) => task
    Err(error) => return Err(error)
  }
  let context = match load_provider_task_context(command, goal, task.id) {
    Ok(context) => context
    Err(error) => return Err(error)
  }
  let delegated_request = AnalysisRequest::{
    ..request,
    prompt: provider_task_prompt(request, task, context),
    system_prompt: provider_task_system_prompt(request, task, context),
    source_prompt: goal,
    execution_mode: None,
    execution_target: None,
    web_search: false,
    preferred_skills: request.preferred_skills,
  }
  let raw_execution = inner_runner(delegated_request)
  let raw_execution = match raw_execution {
    Ok(execution) => execution
    Err(error) => return Err(error)
  }
  let result = match parse_provider_task_result(raw_execution.content) {
    Ok(result) => result
    Err(error) => return Err(error)
  }
  let outcome = match
    persist_provider_task_result(command, request, task, result) {
    Ok(outcome) => outcome
    Err(error) => return Err(error)
  }
  Ok(
    persisted_provider_task_execution(
      raw_execution, task, result, outcome, resolved_target_id,
    ),
  )
}
