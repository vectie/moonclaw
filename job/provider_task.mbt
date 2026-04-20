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
  let matches = providers
    .iter()
    .filter(fn(provider) {
      match provider_workspace_root(provider) {
        Some(root) => path_is_within(root, cwd)
        None => false
      }
    })
    .to_array()
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
  let payload = extract_first_json_object(trimmed).unwrap_or(trimmed)
  let json = @json.parse(payload) catch {
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
  metadata? : Json = {},
) -> Result[(ProviderTaskCommand, ProviderTaskBatch), String] {
  let command = match resolve_provider_task_command(cwd, home, target_id) {
    Ok(command) => command
    Err(error) =>
      match embedded_provider_task_command(metadata, target_id) {
        Some(command) => command
        None => return Err(error)
      }
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
fn embedded_provider_task_command(
  metadata : Json,
  target_id : String?,
) -> ProviderTaskCommand? {
  guard metadata is Object(obj) else { return None }
  guard obj.get("provider_command") is Some(Object(command_obj)) else {
    return None
  }
  let provider_name = match command_obj.get("provider_name") {
    Some(String(value)) if !value.trim().to_string().is_blank() =>
      value.trim().to_string()
    _ => return None
  }
  match target_id {
    Some(target) if !target.trim().to_string().is_blank() &&
      target.trim().to_string() != provider_name => return None
    _ => ()
  }
  let command = match command_obj.get("command") {
    Some(String(value)) if !value.trim().to_string().is_blank() =>
      value.trim().to_string()
    _ => "moon"
  }
  let args = match command_obj.get("args") {
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
  let cwd = match command_obj.get("cwd") {
    Some(String(value)) if !value.trim().to_string().is_blank() =>
      Some(value.trim().to_string())
    _ => None
  }
  let workspace_root = match command_obj.get("workspace_root") {
    Some(String(value)) if !value.trim().to_string().is_blank() =>
      value.trim().to_string()
    _ => return None
  }
  Some(ProviderTaskCommand::{
    provider: @resource_providers.RegisteredResourceProvider::new(
      name=provider_name,
      title=provider_name,
      description="Embedded provider task command",
      kind="task-provider",
      capabilities=["provider.task"],
      metadata={
        "command": command,
        "args": args,
        "cwd": cwd,
        "workspace_root": workspace_root,
      },
    ),
    command,
    args,
    cwd,
    workspace_root,
  })
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
  command : ProviderTaskCommand,
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
    "provider_command": {
      "provider_name": command.provider.name,
      "command": command.command,
      "args": command.args,
      "cwd": command.cwd,
      "workspace_root": command.workspace_root,
    },
    // Provider-backed extension runs need a bounded execution window so they
    // fail cleanly instead of remaining Running indefinitely after partial tool
    // progress.
    "timeout_ms": 600000,
    "max_total_tokens": 24000,
  }
}

///|
fn provider_task_child_proposal(
  request_text : String,
  batch : ProviderTaskBatch,
  command : ProviderTaskCommand,
  config : SubjobStepConfig,
  now_ms : Int,
) -> JobProposal {
  let execution_tasks = provider_task_execution_tasks(batch.tasks)
  let deferred_tasks = batch.tasks.length() - execution_tasks.length()
  let steps = execution_tasks.map(fn(task) {
    let runtime_step_id = "provider-task-\{safe_step_file_segment(task.id)}"
    JobProposalStep::{
      id: runtime_step_id,
      title: compact_title(task.title),
      prompt: task.prompt,
      kind: "job.analysis",
      metadata: provider_task_step_metadata(
        batch.goal,
        batch.goal_id,
        task,
        command,
      ),
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
        "task_count": execution_tasks.length(),
        "deferred_task_count": deferred_tasks,
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
fn provider_task_is_planning_kind(kind : String) -> Bool {
  let normalized = kind.trim().to_string().to_lower()
  normalized == "planning" ||
  normalized == "plan" ||
  normalized.has_suffix(".planning") ||
  normalized.has_suffix(".plan")
}

///|
fn provider_task_execution_tasks(
  tasks : Array[ProviderTaskSpec],
) -> Array[ProviderTaskSpec] {
  let executable = tasks
    .iter()
    .filter(fn(task) { !provider_task_is_planning_kind(task.kind) })
    .to_array()
  if executable.is_empty() {
    tasks
  } else {
    executable
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
fn compact_provider_prompt_text(
  text : String,
  max_chars? : Int = 600,
) -> String {
  let trimmed = text.trim().to_string()
  if trimmed.is_blank() {
    return ""
  }
  if trimmed.length() <= max_chars {
    return trimmed
  }
  let prefix = trimmed[:max_chars].to_string().trim_end()
  "\{prefix}\n...[truncated by MoonClaw runtime]"
}

///|
fn provider_task_request_excerpt(
  request : AnalysisRequest,
  goal : String,
) -> String? {
  let prompt = request.prompt.trim().to_string()
  if prompt.is_blank() {
    return None
  }
  let compact_prompt = compact_provider_prompt_text(prompt, max_chars=1200)
  let compact_goal = compact_provider_prompt_text(goal, max_chars=1200)
  if compact_prompt == compact_goal {
    None
  } else {
    Some(compact_prompt)
  }
}

///|
fn provider_task_preferred_skills(
  request : AnalysisRequest,
  repair? : Bool = false,
) -> Array[String] {
  let skills : Array[String] = []
  skills.push(
    if repair {
      "provider-task-repair"
    } else {
      "provider-task-execution"
    },
  )
  for skill in request.preferred_skills {
    if !skills.contains(skill) {
      skills.push(skill)
    }
  }
  skills
}

///|
fn provider_task_tool_contract(
  request : AnalysisRequest,
) -> AnalysisToolContract {
  AnalysisToolContract::{ ..request.tool_contract, todo: false }
}

///|
fn provider_task_system_prompt(
  request : AnalysisRequest,
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
) -> String {
  [
    "You are executing a domain-local extension task.",
    "The loaded `provider-task-execution` skill defines the execution method.",
    "Return strict JSON only matching this shape:",
    "{\"task_id\":string,\"summary\":string,\"artifacts\":string[],\"memory_candidates\":[{\"kind\":string,\"title\":string,\"detail\":string,\"durable\":bool,\"target_page\":string|null}],\"requires_review\":bool,\"notify_town\":bool}",
    "Use task_id = \{task.id}.",
    "Do not wrap the JSON in markdown fences.",
    "Output contract from the harness:",
    join_bullets(context.output_contract),
    "Execution discipline:",
    "- Treat `Relevant Pages` and `Available Skill Files` as the primary working set.",
    "- Read concrete candidate files directly before using broad repo-wide search tools.",
    "- Only use broad search to fill a named gap after the primary working set is exhausted.",
    "- Ignore generated or dependency trees such as `.git`, `.moonclaw`, `.mooncakes`, `_build`, `node_modules`, `dist`, and temporary output directories unless the task explicitly requires them.",
    "- For bootstrap gather work, produce at least one `raw/bootstrap/*` artifact before claiming durable wiki revision success.",
    if request.system_prompt.trim().to_string().is_blank() {
      ""
    } else {
      "Additional runtime instruction:\n\{request.system_prompt}"
    },
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
    "Goal Summary: \{compact_provider_prompt_text(goal, max_chars=600)}",
    "Task: \{task.title}",
    "Task Kind: \{task.kind}",
    "",
    "Task Prompt Summary:",
    compact_provider_prompt_text(context.prompt, max_chars=1400),
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
      compact_provider_prompt_text(context.memory_summary, max_chars=800)
    },
  ]
  if !context.skill_paths.is_empty() {
    sections.push("")
    sections.push("Available Skill Files:")
    sections.push(join_bullets(context.skill_paths))
  }
  match provider_task_request_excerpt(request, goal) {
    Some(excerpt) => {
      sections.push("")
      sections.push("Original MoonClaw Request Excerpt:")
      sections.push(excerpt)
    }
    None => ()
  }
  sections.join("\n")
}

///|
fn extract_first_json_object(content : String) -> String? {
  let trimmed = content.trim().to_string()
  if trimmed.is_blank() {
    return None
  }
  if trimmed.has_prefix("{") {
    return Some(trimmed)
  }
  let buf = StringBuilder::new()
  let mut started = false
  let mut depth = 0
  let mut in_string = false
  let mut escaped = false
  for c in content.to_array() {
    if !started {
      if c == '{' {
        started = true
        depth = 1
        buf.write_char(c)
      }
      continue
    }
    buf.write_char(c)
    if in_string {
      if escaped {
        escaped = false
        continue
      }
      if c == '\\' {
        escaped = true
      } else if c == '"' {
        in_string = false
      }
      continue
    }
    match c {
      '"' => in_string = true
      '{' => depth += 1
      '}' => {
        depth -= 1
        if depth == 0 {
          return Some(buf.to_string())
        }
      }
      _ => ()
    }
  }
  None
}

///|
fn parse_provider_task_result(
  content : String,
) -> Result[ProviderTaskResult, String] {
  let trimmed = match extract_first_json_object(content) {
    Some(payload) => payload.trim().to_string()
    None => return Err("Provider task analysis must return a JSON object")
  }
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
fn provider_task_json_string_field(json : Json, key : String) -> String? {
  match json {
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
fn provider_task_json_bool_field(json : Json, key : String) -> Bool? {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
    _ => None
  }
}

///|
fn provider_task_json_string_array_field(
  json : Json,
  key : String,
) -> Array[String] {
  match json {
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
fn plan_summary_from_json(json : Json) -> String? {
  let keys = ["plan", "steps"]
  for key in keys {
    guard json is Object(obj) else { break }
    guard obj.get(key) is Some(Array(items)) else { continue }
    let titles : Array[String] = []
    for item in items {
      let title = provider_task_json_string_field(item, "title").unwrap_or(
        provider_task_json_string_field(item, "step").unwrap_or(""),
      )
      if !title.is_blank() {
        titles.push(title)
      }
      if titles.length() >= 3 {
        break
      }
    }
    if !titles.is_empty() {
      let joined_titles = titles.join(", ")
      return Some("Completed provider task using plan steps: \{joined_titles}.")
    }
  }
  None
}

///|
fn provider_task_plan_substeps_from_json(
  json : Json,
) -> Array[AdaptiveSubstepPayload] {
  let keys = ["plan", "steps", "suggested_substeps", "substeps"]
  for key in keys {
    guard json is Object(obj) else { break }
    guard obj.get(key) is Some(Array(items)) else { continue }
    let substeps : Array[AdaptiveSubstepPayload] = []
    for item in items {
      guard item is Object(step) else { continue }
      let title = provider_task_json_string_field(item, "title").unwrap_or(
        provider_task_json_string_field(item, "step").unwrap_or(
          provider_task_json_string_field(item, "name").unwrap_or(""),
        ),
      )
      if title.is_blank() {
        continue
      }
      let prompt = provider_task_json_string_field(item, "prompt").unwrap_or(
        provider_task_json_string_field(item, "instruction").unwrap_or(
          provider_task_json_string_field(item, "detail").unwrap_or(title),
        ),
      )
      let kind = match step.get("kind") {
        Some(String(kind)) if !kind.trim().to_string().is_blank() =>
          Some(kind.trim().to_string())
        _ => None
      }
      substeps.push(AdaptiveSubstepPayload::{ title, prompt, kind })
    }
    if !substeps.is_empty() {
      return substeps
    }
  }
  []
}

///|
fn provider_task_breadth_summary(
  task : ProviderTaskSpec,
  json : Json,
) -> String {
  provider_task_json_string_field(json, "summary").unwrap_or(
    provider_task_json_string_field(json, "message").unwrap_or(
      "Split provider task \{task.title} into narrower executable steps before running it.",
    ),
  )
}

///|
fn provider_task_substep_prompt(task : ProviderTaskSpec) -> String {
  let target_lines = if task.target_pages.is_empty() {
    "No explicit target pages were declared."
  } else {
    join_bullets(task.target_pages)
  }
  [
    task.prompt,
    "",
    "Provider-owned narrowed execution task:",
    "- task_id: \{task.id}",
    "- task_kind: \{task.kind}",
    "",
    "Declared target surfaces:",
    target_lines,
    "",
    "Execute this narrowed task directly. Do not expand back into a broad plan unless you hit a concrete blocker.",
  ].join("\n")
}

///|
fn provider_task_followup_execution_tasks(
  batch : ProviderTaskBatch,
  current_task : ProviderTaskSpec,
) -> Array[ProviderTaskSpec] {
  let execution_tasks = provider_task_execution_tasks(batch.tasks)
  let mut selected_index : Int? = None
  for index = 0; index < execution_tasks.length(); index = index + 1 {
    if execution_tasks[index].id == current_task.id {
      selected_index = Some(index)
      break
    }
  }
  match selected_index {
    Some(index) => execution_tasks[index + 1:].iter().to_array()
    None => []
  }
}

///|
fn provider_task_followup_substeps(
  batch : ProviderTaskBatch,
  current_task : ProviderTaskSpec,
) -> Array[AdaptiveSubstepPayload] {
  provider_task_followup_execution_tasks(batch, current_task).map(fn(task) {
    AdaptiveSubstepPayload::{
      title: task.title,
      prompt: provider_task_substep_prompt(task),
      kind: Some("job.analysis"),
    }
  })
}

///|
fn provider_task_requires_local_tool_loop(task : ProviderTaskSpec) -> Bool {
  ignore(task)
  false
}

///|
fn provider_task_execution_step_metadata(
  metadata : Json,
  force_single_response : Bool,
) -> Json {
  let merged : Map[String, Json] = {}
  match metadata {
    Object(obj) =>
      for key, value in obj {
        merged.set(key, value)
      }
    _ => ()
  }
  merged.set("provider_force_single_response", force_single_response.to_json())
  Json::object(merged)
}

///|
fn provider_task_breadth_envelope_from_content(
  batch : ProviderTaskBatch,
  task : ProviderTaskSpec,
  content : String,
) -> AdaptiveAnalysisEnvelope? {
  let trimmed = match extract_first_json_object(content) {
    Some(payload) => payload.trim().to_string()
    None => return None
  }
  let json = @json.parse(trimmed) catch { _ => return None }
  match parse_adaptive_analysis_envelope(trimmed) {
    Some(envelope) if envelope.verdict.trim().to_lower() == "needs_subplan" =>
      if adaptive_substeps(envelope).is_empty() {
        let followup_substeps = provider_task_followup_substeps(batch, task)
        if followup_substeps.is_empty() {
          Some(envelope)
        } else {
          Some(AdaptiveAnalysisEnvelope::{
            verdict: "needs_subplan",
            summary: envelope.summary,
            missing_inputs: envelope.missing_inputs,
            suggested_substeps: Some(followup_substeps),
            substeps: None,
          })
        }
      } else {
        Some(envelope)
      }
    _ => {
      let substeps = provider_task_plan_substeps_from_json(json)
      let summary = provider_task_breadth_summary(task, json)
      let lower = trimmed.to_lower()
      let substeps = if substeps.is_empty() &&
        (
          lower.contains("too broad") ||
          lower.contains("decompos") ||
          lower.contains("split") ||
          lower.contains("\"plan\"") ||
          lower.contains("\"steps\"")
        ) {
        provider_task_followup_substeps(batch, task)
      } else {
        substeps
      }
      if substeps.is_empty() {
        if lower.contains("too broad") ||
          lower.contains("decompos") ||
          lower.contains("split") ||
          lower.contains("\"plan\"") ||
          lower.contains("\"steps\"") {
          Some(AdaptiveAnalysisEnvelope::{
            verdict: "needs_subplan",
            summary: Some(summary),
            missing_inputs: None,
            suggested_substeps: None,
            substeps: None,
          })
        } else {
          None
        }
      } else {
        Some(AdaptiveAnalysisEnvelope::{
          verdict: "needs_subplan",
          summary: Some(summary),
          missing_inputs: None,
          suggested_substeps: Some(substeps),
          substeps: None,
        })
      }
    }
  }
}

///|
fn provider_task_guardrail_split_execution(
  execution : AnalysisExecution,
  request : AnalysisRequest,
  task : ProviderTaskSpec,
  envelope : AdaptiveAnalysisEnvelope,
  target_id : String,
) -> AnalysisExecution {
  let envelope_json : Map[String, Json] = {
    "verdict": "needs_subplan".to_json(),
    "summary": envelope.summary
    .unwrap_or("Provider task requires splitting before execution.")
    .to_json(),
  }
  match adaptive_substeps(envelope) {
    [] => ()
    substeps =>
      envelope_json["suggested_substeps"] = Json::array(
        substeps.map(fn(step) {
          { "title": step.title, "prompt": step.prompt, "kind": step.kind }
        }),
      )
  }
  AnalysisExecution::{
    ..execution,
    content: Json::object(envelope_json).stringify(),
    metadata: {
      "job_id": execution_metadata_value(execution.metadata, "job_id"),
      "run_id": execution_metadata_value(execution.metadata, "run_id"),
      "step_id": execution_metadata_value(execution.metadata, "step_id"),
      "execution_mode": "provider",
      "execution_target": target_id,
      "extension_task_id": task.id,
      "extension_task_kind": task.kind,
      "extension_guardrail_verdict": "needs_subplan",
      "extension_guardrail_summary": envelope.summary.unwrap_or(
        "Provider task requires splitting before execution.",
      ),
      "bookapi_task_id": task.id,
      "bookapi_guardrail_verdict": "needs_subplan",
      "bookapi_guardrail_summary": envelope.summary.unwrap_or(
        "Provider task requires splitting before execution.",
      ),
      "execution_isolation": execution_metadata_value(
        execution.metadata,
        "execution_isolation",
      ),
      "role_runtime_contract": execution_metadata_value(
        execution.metadata,
        "role_runtime_contract",
      ),
      "disable_waiting_for_input": waiting_for_input_disabled_from_metadata(
        request.step_metadata,
      ),
      "best_effort_on_missing_input": best_effort_on_missing_input_from_metadata(
        request.step_metadata,
      ),
    },
  }
}

///|
fn provider_task_guardrail_reject_error(
  task : ProviderTaskSpec,
  envelope : AdaptiveAnalysisEnvelope,
) -> String {
  let detail = envelope.summary.unwrap_or(
    "Provider task requires splitting before execution.",
  )
  "Provider task \{task.id} is too broad to execute directly and no executable substeps were provided: \{detail}"
}

///|
fn normalize_provider_task_result(
  task : ProviderTaskSpec,
  content : String,
) -> Result[ProviderTaskResult, String] {
  let trimmed = match extract_first_json_object(content) {
    Some(payload) => payload.trim().to_string()
    None => return Err("Provider task analysis must return a JSON object")
  }
  let json = match parse_provider_task_payload(trimmed, "analysis") {
    Ok(json) => json
    Err(error) => return Err(error)
  }
  let summary = provider_task_json_string_field(json, "summary").unwrap_or(
    provider_task_json_string_field(json, "message").unwrap_or(
      plan_summary_from_json(json).unwrap_or(
        "Completed provider task \{task.title}.",
      ),
    ),
  )
  let artifacts = provider_task_json_string_array_field(json, "artifacts")
  let memory_candidates = match json {
    Object(obj) =>
      match obj.get("memory_candidates") {
        Some(Array(_)) =>
          @json.from_json(obj.get("memory_candidates").unwrap()) catch {
            _ => []
          }
        _ => []
      }
    _ => []
  }
  Ok(ProviderTaskResult::{
    task_id: task.id,
    summary,
    artifacts,
    memory_candidates,
    requires_review: provider_task_json_bool_field(json, "requires_review").unwrap_or(
      task.requires_review,
    ),
    notify_town: provider_task_json_bool_field(json, "notify_town").unwrap_or(
      false,
    ),
  })
}

///|
fn provider_task_result_is_empty_pseudo_success(
  result : ProviderTaskResult,
) -> Bool {
  result.artifacts.is_empty() &&
  result.memory_candidates.is_empty() &&
  result.summary.trim().to_lower().contains("completed provider task")
}

///|
fn provider_task_blocker_result(
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
  result : ProviderTaskResult,
) -> ProviderTaskResult {
  let target_pages = if task.target_pages.is_empty() {
    "no target pages were declared"
  } else {
    task.target_pages.join(", ")
  }
  let context_pages = if context.context_pages.is_empty() {
    "no context pages were provided"
  } else {
    context.context_pages.join(", ")
  }
  ProviderTaskResult::{
    task_id: result.task_id,
    summary: "Blocked provider task \{task.title}: provider returned generic completion text without durable artifacts or memory candidates.",
    artifacts: [],
    memory_candidates: [
      ProviderTaskMemoryCandidate::{
        kind: "blocker",
        title: "No durable provider outputs",
        detail: "Provider returned a generic completion for \{task.title} but produced no durable artifacts or memory candidates. Expected target pages: \{target_pages}. Context pages: \{context_pages}.",
        durable: false,
        target_page: None,
      },
      ProviderTaskMemoryCandidate::{
        kind: "next_step",
        title: "Materialize durable outputs or return concrete blocker",
        detail: "Re-run provider execution so it creates durable source, entity, concept, query, or synthesis outputs, or return a structured blocker that names the missing source material.",
        durable: false,
        target_page: None,
      },
    ],
    requires_review: true,
    notify_town: result.notify_town,
  }
}

///|
fn enforce_provider_task_result_semantics(
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
  result : ProviderTaskResult,
) -> ProviderTaskResult {
  if provider_task_result_is_empty_pseudo_success(result) {
    provider_task_blocker_result(task, context, result)
  } else {
    result
  }
}

///|
fn provider_task_repair_system_prompt(task : ProviderTaskSpec) -> String {
  [
    "You repair invalid provider task outputs into the required runtime contract.",
    "The loaded `provider-task-repair` skill defines the repair method.",
    "Return strict JSON only.",
    "The required shape is:",
    "{\"task_id\":string,\"summary\":string,\"artifacts\":string[],\"memory_candidates\":[{\"kind\":string,\"title\":string,\"detail\":string,\"durable\":bool,\"target_page\":string|null}],\"requires_review\":bool,\"notify_town\":bool}",
    "Use task_id = \{task.id}.",
  ].join("\n\n")
}

///|
fn provider_task_repair_prompt(
  task : ProviderTaskSpec,
  raw_content : String,
) -> String {
  [
    "The previous provider task analysis output did not match the required runtime contract.",
    "Convert it into the required JSON object without inventing unrelated fields.",
    "If the previous output is planner-shaped, collapse it into one completed task result for the current task.",
    "Task id: \{task.id}",
    "Task title: \{task.title}",
    "Task kind: \{task.kind}",
    "",
    "Previous invalid output:",
    raw_content,
  ].join("\n")
}

///|
async fn repair_provider_task_result(
  request : AnalysisRequest,
  task : ProviderTaskSpec,
  raw_execution : AnalysisExecution,
  inner_runner : async (AnalysisRequest) -> Result[AnalysisExecution, String],
) -> Result[ProviderTaskResult, String] {
  let preferred_skills = provider_task_preferred_skills(request, repair=true)
  let loaded_skills = loaded_skills_prompt(
    request.cwd,
    request.home,
    preferred_skills,
  )
  let repair_request = AnalysisRequest::{
    ..request,
    prompt: [
      provider_task_repair_prompt(task, raw_execution.content),
      loaded_skills,
    ]
    .filter(fn(section) { !section.is_blank() })
    .join("\n\n"),
    system_prompt: provider_task_repair_system_prompt(task),
    enable_tools: false,
    execution_mode: None,
    execution_target: None,
    web_search: false,
    preferred_skills,
  }
  let repaired_execution = match inner_runner(repair_request) {
    Ok(execution) => execution
    Err(error) => return Err(error)
  }
  match parse_provider_task_result(repaired_execution.content) {
    Ok(result) => Ok(result)
    Err(_) => normalize_provider_task_result(task, repaired_execution.content)
  }
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
  let result_path = match
    provider_task_runtime_artifact_path(
      request,
      command.workspace_root,
      "result",
    ) {
    Ok(path) => path
    Err(error) => return Err(error)
  }
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
fn provider_task_runtime_artifact_root(
  request : AnalysisRequest,
  workspace_root : String,
) -> String {
  let provider_root = workspace_root.trim().to_string()
  if !provider_root.is_blank() {
    provider_root
  } else {
    request.cwd
  }
}

///|
fn provider_task_runtime_artifact_dir(
  request : AnalysisRequest,
  workspace_root : String,
) -> String {
  @pathx.join(
    provider_task_runtime_artifact_root(request, workspace_root),
    ".moonclaw/provider-task",
  )
}

///|
async fn provider_task_runtime_artifact_path(
  request : AnalysisRequest,
  workspace_root : String,
  artifact_kind : String,
) -> Result[String, String] {
  let step_key = safe_step_file_segment(request.step_id)
  let artifact_dir = provider_task_runtime_artifact_dir(request, workspace_root)
  @fsx.make_directory(artifact_dir, recursive=true, exists_ok=true) catch {
    error =>
      return Err(
        "Failed to prepare provider task artifact directory \{artifact_dir}: \{error}",
      )
  }
  Ok(
    @pathx.join(
      artifact_dir,
      ".moonclaw-provider-\{artifact_kind}-\{request.run_id}-\{step_key}.json",
    ),
  )
}

///|
async fn provider_task_failure_debug_path(
  request : AnalysisRequest,
  workspace_root : String,
) -> Result[String, String] {
  provider_task_runtime_artifact_path(request, workspace_root, "failure")
}

///|
async fn persist_provider_task_failure_debug(
  request : AnalysisRequest,
  workspace_root : String,
  task : ProviderTaskSpec,
  execution : AnalysisExecution,
  error : String,
) -> String {
  let path = match provider_task_failure_debug_path(request, workspace_root) {
    Ok(path) => path
    Err(path_error) =>
      return "provider-task-failure-debug-unavailable: \{path_error}; original error: \{error}"
  }
  let payload : Map[String, Json] = {
    "error": error.to_json(),
    "task_id": task.id.to_json(),
    "task_title": task.title.to_json(),
    "conversation_id": execution.conversation_id.to_json(),
    "model_name": execution.model_name.to_json(),
    "raw_content": execution.content.to_json(),
    "usage": usage_json(execution.usage),
    "metadata": execution.metadata,
  }
  @fsx.write_to_file(
    path,
    Json::object(payload).stringify(indent=2),
    create=0o644,
  )
  path
}

///|
fn is_provider_result_artifact_path(path : String) -> Bool {
  let normalized = path.trim().to_string()
  !normalized.is_blank() &&
  !normalized.has_prefix("/") &&
  !normalized.contains("://") &&
  !normalized.has_suffix("/") &&
  @pathx.basename(normalized).contains(".")
}

///|
fn is_provider_result_workspace_artifact(path : String) -> Bool {
  let normalized = path.trim().to_string()
  normalized.has_prefix("wiki/") ||
  normalized.has_prefix("raw/") ||
  normalized.has_prefix("keeper/")
}

///|
async fn provider_task_existing_workspace_artifacts(
  workspace_root : String,
  artifacts : Array[String],
) -> Array[String] {
  let sanitized : Array[String] = []
  for artifact in artifacts {
    let normalized = artifact.trim().to_string()
    if !is_provider_result_artifact_path(normalized) ||
      !is_provider_result_workspace_artifact(normalized) {
      continue
    }
    let absolute = @pathx.join(workspace_root, normalized)
    if !(@fsx.exists(absolute) catch { _ => false }) {
      continue
    }
    if !sanitized.contains(normalized) {
      sanitized.push(normalized)
    }
  }
  sanitized
}

///|
async fn align_provider_task_result(
  workspace_root : String,
  task : ProviderTaskSpec,
  result : ProviderTaskResult,
) -> ProviderTaskResult {
  ProviderTaskResult::{
    ..result,
    task_id: task.id,
    artifacts: provider_task_existing_workspace_artifacts(
      workspace_root,
      result.artifacts,
    ),
  }
}

///|
fn provider_task_artifact_paths_from_line(line : String) -> Array[String] {
  let paths : Array[String] = []
  let normalized = line
    .replace_all(old="`", new=" ")
    .replace_all(old=",", new=" ")
    .replace_all(old=":", new=" ")
    .replace_all(old=";", new=" ")
    .replace_all(old="(", new=" ")
    .replace_all(old=")", new=" ")
    .replace_all(old="[", new=" ")
    .replace_all(old="]", new=" ")
    .replace_all(old="{", new=" ")
    .replace_all(old="}", new=" ")
  for token in normalized.split(" ") {
    let candidate = token.trim().trim(chars=".'\"").to_string()
    if candidate.is_blank() {
      continue
    }
    if is_provider_result_artifact_path(candidate) && !paths.contains(candidate) {
      paths.push(candidate)
    }
  }
  paths
}

///|
fn provider_task_collect_artifacts_from_json(
  value : Json,
  artifacts : Array[String],
) -> Unit {
  match value {
    String(text) =>
      for raw_line in text.split("\n") {
        for path in provider_task_artifact_paths_from_line(raw_line.to_string()) {
          if !artifacts.contains(path) {
            artifacts.push(path)
          }
        }
      }
    Array(items) =>
      for item in items {
        provider_task_collect_artifacts_from_json(item, artifacts)
      }
    Object(obj) =>
      for _, item in obj {
        provider_task_collect_artifacts_from_json(item, artifacts)
      }
    _ => ()
  }
}

///|
async fn provider_task_target_artifacts(
  workspace_root : String,
  task : ProviderTaskSpec,
) -> Array[String] {
  let artifacts : Array[String] = []
  for path in task.target_pages {
    let normalized = path.trim().to_string()
    if normalized.is_blank() {
      continue
    }
    if normalized.has_suffix("/") {
      let absolute_dir = @pathx.join(workspace_root, normalized)
      let entries = @fsx.list_directory(absolute_dir) catch { _ => continue }
      for entry in entries {
        guard entry.kind is Regular else { continue }
        let relative = "\{normalized}\{entry.name}"
        if is_provider_result_artifact_path(relative) &&
          !artifacts.contains(relative) {
          artifacts.push(relative)
        }
      }
      continue
    }
    let absolute = @pathx.join(workspace_root, normalized)
    if (@fsx.exists(absolute) catch { _ => false }) &&
      is_provider_result_artifact_path(normalized) &&
      !artifacts.contains(normalized) {
      artifacts.push(normalized)
    }
  }
  artifacts
}

///|
fn provider_task_synthesized_subplan_result(
  task : ProviderTaskSpec,
  execution : AnalysisExecution,
  artifacts : Array[String],
) -> ProviderTaskResult {
  let summary = metadata_string_value(
    execution.metadata,
    "extension_guardrail_summary",
  ).unwrap_or(
    "Adaptive subplan for \{task.title} completed and produced durable workspace outputs.",
  )
  ProviderTaskResult::{
    task_id: task.id,
    summary,
    artifacts,
    memory_candidates: [],
    requires_review: task.requires_review,
    notify_town: false,
  }
}

///|
async fn finalize_provider_task_subplan_execution(
  request : AnalysisRequest,
  execution : AnalysisExecution,
  child_outputs : Json,
) -> Result[AnalysisExecution, String]? {
  guard provider_execution_requested(request.execution_mode) else {
    return None
  }
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
      metadata=request.step_metadata,
    ) {
    Ok(value) => value
    Err(error) => return Some(Err(error))
  }
  let resolved_target_id = command.provider.name
  let task = match select_provider_task_task(batch, selected_task_id) {
    Ok(task) => task
    Err(error) => return Some(Err(error))
  }
  let context = match load_provider_task_context(command, goal, task.id) {
    Ok(context) => context
    Err(error) => return Some(Err(error))
  }
  let artifacts : Array[String] = []
  provider_task_collect_artifacts_from_json(child_outputs, artifacts)
  let artifact_root = if context.workspace_root.is_blank() {
    request.cwd
  } else {
    context.workspace_root
  }
  for path in provider_task_target_artifacts(artifact_root, task) {
    if !artifacts.contains(path) {
      artifacts.push(path)
    }
  }
  let result = provider_task_synthesized_subplan_result(
    task, execution, artifacts,
  )
  let result = align_provider_task_result(artifact_root, task, result)
  let result = enforce_provider_task_result_semantics(task, context, result)
  let outcome = match
    persist_provider_task_result(command, request, task, result) {
    Ok(outcome) => outcome
    Err(error) => return Some(Err(error))
  }
  Some(
    Ok(
      persisted_provider_task_execution(
        execution, task, result, outcome, resolved_target_id,
      ),
    ),
  )
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
      metadata=request.step_metadata,
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
  let use_local_tool_loop = provider_task_requires_local_tool_loop(task)
  let preferred_skills = provider_task_preferred_skills(request)
  let loaded_skills = loaded_skills_prompt(
    request.cwd,
    request.home,
    preferred_skills,
  )
  let delegated_request = AnalysisRequest::{
    ..request,
    prompt: [provider_task_prompt(request, task, context), loaded_skills]
    .filter(fn(section) { !section.is_blank() })
    .join("\n\n"),
    system_prompt: provider_task_system_prompt(request, task, context),
    source_prompt: goal,
    enable_tools: request.enable_tools && use_local_tool_loop,
    tool_contract: provider_task_tool_contract(request),
    execution_mode: None,
    execution_target: None,
    web_search: request.web_search && use_local_tool_loop,
    preferred_skills,
    step_metadata: provider_task_execution_step_metadata(
      request.step_metadata,
      !use_local_tool_loop,
    ),
  }
  let raw_execution = inner_runner(delegated_request)
  let raw_execution = match raw_execution {
    Ok(execution) => execution
    Err(error) => return Err(error)
  }
  match
    provider_task_breadth_envelope_from_content(
      batch,
      task,
      raw_execution.content,
    ) {
    Some(envelope) =>
      if adaptive_substeps(envelope).is_empty() {
        return Err(provider_task_guardrail_reject_error(task, envelope))
      } else {
        return Ok(
          provider_task_guardrail_split_execution(
            raw_execution, request, task, envelope, resolved_target_id,
          ),
        )
      }
    None => ()
  }
  let result = match parse_provider_task_result(raw_execution.content) {
    Ok(result) => result
    Err(error) =>
      match
        repair_provider_task_result(request, task, raw_execution, inner_runner) {
        Ok(result) => result
        Err(repair_error) => {
          let debug_path = persist_provider_task_failure_debug(
            request,
            command.workspace_root,
            task,
            raw_execution,
            "\{error}; repair failed: \{repair_error}",
          )
          return Err("\{error} (raw response: \{debug_path})")
        }
      }
  }
  let artifact_root = if context.workspace_root.is_blank() {
    request.cwd
  } else {
    context.workspace_root
  }
  let result = align_provider_task_result(artifact_root, task, result)
  let result = enforce_provider_task_result_semantics(task, context, result)
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
