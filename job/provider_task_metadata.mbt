///|
fn provider_task_step_metadata(
  goal : String,
  goal_id : String,
  task : ProviderTaskSpec,
  command : ProviderTaskCommand,
) -> Json {
  let metadata : Map[String, Json] = {
    "extension_goal": goal,
    "extension_goal_id": goal_id,
    "extension_task_id": task.id,
    "extension_task_spec": task.to_json(),
    "extension_task_kind": task.kind,
    "extension_priority": task.priority,
    "extension_requires_review": task.requires_review,
    "extension_target_pages": task.target_pages,
    // Keep provider discovery affine to the declared domain workspace after
    // MoonClaw creates an isolated child run for this task.
    "workspace_root": command.workspace_root,
    "provider_command": {
      "provider_name": command.provider.name,
      "command": command.command,
      "args": command.args,
      "task_args_prefix": provider_metadata_string_array(
        command.provider.metadata,
        "task_args_prefix",
      ),
      "cwd": command.cwd,
      "workspace_root": command.workspace_root,
    },
    // Provider-backed extension runs need a bounded execution window so they
    // fail cleanly instead of remaining Running indefinitely after partial tool
    // progress.
    "timeout_ms": 600000,
    "max_total_tokens": 24000,
  }
  metadata.set("enable_tools", true.to_json())
  metadata.set("web_search", true.to_json())
  metadata.set(
    "tool_contract",
    AnalysisToolContract::new(web_fetch=true, web_search=true).to_json(),
  )
  Json::object(metadata)
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
  {
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
  let normalized = kind.trim().to_owned().to_lower()
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
  let selected = if executable.is_empty() { tasks } else { executable }
  let bootstrap_execution = selected
    .iter()
    .filter(fn(task) {
      let rank = provider_task_phase_rank(task.kind)
      rank >= 0 && rank <= 4
    })
    .to_array()
  let selected = if bootstrap_execution.is_empty() {
    selected
  } else {
    bootstrap_execution
  }
  let indexed : Array[(Int, Int, Int, ProviderTaskSpec)] = []
  let mut i = 0
  while i < selected.length() {
    let task = selected[i]
    indexed.push((provider_task_phase_rank(task.kind), -task.priority, i, task))
    i += 1
  }
  indexed.sort_by(fn(a, b) {
    let phase_order = a.0.compare(b.0)
    if phase_order != 0 {
      phase_order
    } else {
      let priority_order = a.1.compare(b.1)
      if priority_order != 0 {
        priority_order
      } else {
        a.2.compare(b.2)
      }
    }
  })
  indexed.map(fn(item) { item.3 })
}

///|
fn provider_task_phase_rank(kind : String) -> Int {
  match kind.trim().to_lower() {
    "bootstrap_gather" => 0
    "source_materialize" => 1
    "knowledge_revise" => 2
    "review_finalize" => 3
    "review" => 4
    _ => 10
  }
}

///|
fn metadata_string_value(metadata : Json, key : String) -> String? {
  match metadata_with_step_metadata(metadata, key) {
    Some(String(value)) if !value.trim().to_owned().is_blank() =>
      Some(value.trim().to_owned())
    _ => None
  }
}

///|
fn metadata_bool_value(metadata : Json, key : String) -> Bool? {
  match metadata_with_step_metadata(metadata, key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
fn metadata_int_value(metadata : Json, key : String) -> Int? {
  match metadata_with_step_metadata(metadata, key) {
    Some(Number(value, ..)) => Some(value.to_int())
    _ => None
  }
}

///|
fn metadata_string_array_value(metadata : Json, key : String) -> Array[String] {
  match metadata_with_step_metadata(metadata, key) {
    Some(Array(values)) => {
      let items : Array[String] = []
      for value in values {
        guard value is String(text) else { continue }
        let trimmed = text.trim().to_owned()
        if !trimmed.is_blank() {
          items.push(trimmed)
        }
      }
      items
    }
    _ => []
  }
}

///|
fn provider_task_canonical_title(kind : String) -> String? {
  match kind.trim().to_lower() {
    "bootstrap_gather" => Some("Gather bootstrap materials")
    "source_materialize" => Some("Materialize durable source pages")
    "knowledge_revise" => Some("Revise knowledge surfaces")
    "review_finalize" => Some("Finalize bootstrap review")
    "review" => Some("Review pending book updates")
    _ => None
  }
}

///|
fn provider_task_result_task_id(task : ProviderTaskSpec) -> String {
  let task_id = task.id.trim().to_owned()
  if task_id.length() <= 80 {
    task_id
  } else {
    let base = provider_task_canonical_title(task.kind).unwrap_or(task.kind)
    let slug = safe_step_file_segment(base)
    let suffix = task_id.hash().to_string().trim(chars="-").to_owned()
    "provider-\{slug}-\{suffix}"
  }
}

///|
fn provider_task_cancelled_error() -> String {
  "Provider task cancelled before completion"
}

///|
fn provider_task_cancellation_requested() -> Bool {
  @async.is_being_cancelled()
}

///|
fn provider_task_spec_from_metadata(metadata : Json) -> ProviderTaskSpec? {
  fn decode(value : Json) -> ProviderTaskSpec? {
    let decoded : ProviderTaskSpec = @json.from_json(value) catch {
      _ => return None
    }
    Some(decoded)
  }
  match metadata_with_step_metadata(metadata, "extension_task_spec") {
    Some(spec) =>
      match decode(spec) {
        Some(task) => return Some(task)
        None => ()
      }
    None => ()
  }
  None
}

///|
fn provider_task_effective_workspace_root(
  command_workspace_root : String,
  context_workspace_root : String,
  request_cwd : String,
) -> String {
  let normalized_command = command_workspace_root.trim().to_owned()
  let normalized_context = context_workspace_root.trim().to_owned()
  if !normalized_command.is_blank() {
    normalized_command
  } else if !normalized_context.is_blank() {
    normalized_context
  } else {
    request_cwd
  }
}

///|
fn normalize_provider_task_spec_from_metadata(
  metadata : Json,
  task : ProviderTaskSpec,
) -> ProviderTaskSpec {
  let kind = metadata_string_value(metadata, "extension_task_kind").unwrap_or(
    task.kind,
  )
  let title = provider_task_canonical_title(kind).unwrap_or(task.title)
  let priority = metadata_int_value(metadata, "extension_priority").unwrap_or(
    task.priority,
  )
  let requires_review = metadata_bool_value(
    metadata, "extension_requires_review",
  ).unwrap_or(task.requires_review)
  let target_pages = {
    let extension_targets = metadata_string_array_value(
      metadata, "extension_target_pages",
    )
    if !extension_targets.is_empty() {
      extension_targets
    } else {
      task.target_pages
    }
  }
  { ..task, kind, title, priority, requires_review, target_pages }
}
