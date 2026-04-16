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
  let task_id = provider_task_json_string_field(json, "task_id").unwrap_or(
    task.id,
  )
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
    task_id,
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
  let step_key = safe_step_file_segment(request.step_id)
  let result_path = @pathx.join(
    request.cwd,
    ".moonclaw-provider-result-\{request.run_id}-\{step_key}.json",
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
fn provider_task_failure_debug_path(request : AnalysisRequest) -> String {
  let step_key = safe_step_file_segment(request.step_id)
  @pathx.join(
    request.cwd,
    ".moonclaw-provider-failure-\{request.run_id}-\{step_key}.json",
  )
}

///|
async fn persist_provider_task_failure_debug(
  request : AnalysisRequest,
  task : ProviderTaskSpec,
  execution : AnalysisExecution,
  error : String,
) -> String {
  let path = provider_task_failure_debug_path(request)
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
    enable_tools: false,
    execution_mode: None,
    execution_target: None,
    web_search: false,
    preferred_skills,
  }
  let raw_execution = inner_runner(delegated_request)
  let raw_execution = match raw_execution {
    Ok(execution) => execution
    Err(error) => return Err(error)
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
            task,
            raw_execution,
            "\{error}; repair failed: \{repair_error}",
          )
          return Err("\{error} (raw response: \{debug_path})")
        }
      }
  }
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
