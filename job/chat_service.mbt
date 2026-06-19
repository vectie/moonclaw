///|
pub(all) struct JobNotifyTarget {
  channel_id : String
  account_id : String
  recipient : String
  thread_id : String?
  verbosity : NotificationVerbosity
  heartbeat_interval_ms : Int
  warn_after_ms : Int
} derive(Debug)

///|
pub(all) enum JobChatAction {
  Plan(String)
  Preview(String)
  PlanJob(String)
  E2EJob(String)
  Promote(String)
  Confirm(String)
  Reject(String)
  Revise(String)
  Resume(String)
  JobStatus(String)
  JobWorkspace(String)
  Jobs
  JobStop(String)
  JobForceStop(String)
  JobNotify(String)
  Remember(String)
  Memories
  MemorySearch(String)
} derive(Debug)

///|
fn is_plan_mode_command(command : String) -> Bool {
  command == "/plan"
}

///|
fn is_plan_job_command(command : String) -> Bool {
  command == "/plan-job"
}

///|
fn is_e2e_job_command(command : String) -> Bool {
  command == "/e2e"
}

///|
pub(all) struct ChildRunStatus {
  run_id : String
  status : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct JobStatusSnapshot {
  definition_id : String
  definition_title : String
  created_at_label : String
  run_id : String
  status : String
  family : String
  current_step : String
  done_steps : Int
  total_steps : Int
  elapsed_ms : Int
  lineage_line : String?
  summary : String?
  error : String?
  missing_input_line : String?
  child_runs : Array[ChildRunStatus]
  latest_event_line : String
  output_lines : Array[String]
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ActiveJobSnapshot {
  definition_id : String
  definition_title : String
  created_at_label : String
  run_id : String
  status : String
  family : String
  depth : Int
  current_step : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct JobNotificationRuntimeState {
  last_sent_at : Int
  last_notified_event_count : Int
  long_running_warned : Bool
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct JobNotificationDecision {
  messages : Array[String]
  next_state : JobNotificationRuntimeState
} derive(Debug, ToJson, FromJson)

///|
pub fn notification_preference_id(
  channel_id : String,
  account_id : String,
  recipient : String,
  thread_id : String?,
) -> String {
  match thread_id {
    Some(thread_id) => "\{channel_id}:\{account_id}:\{recipient}:\{thread_id}"
    None => "\{channel_id}:\{account_id}:\{recipient}"
  }
}

///|
fn notify_string_field(value : Json?) -> String? {
  match value {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
pub fn parse_job_notify_target(config : Json) -> JobNotifyTarget? {
  let notify = match config {
    { "notify": Object(notify), .. } => Some(notify)
    _ => None
  }
  guard notify is Some(notify) else { return None }
  guard notify_string_field(notify.get("channel")) is Some(channel_id) else {
    return None
  }
  guard notify_string_field(notify.get("account_id")) is Some(account_id) else {
    return None
  }
  guard notify_string_field(notify.get("to")) is Some(recipient) else {
    return None
  }
  Some({
    channel_id,
    account_id,
    recipient,
    thread_id: notify_string_field(notify.get("thread_id")),
    verbosity: Normal,
    heartbeat_interval_ms: match notify.get("heartbeat_interval_ms") {
      Some(Number(ms, ..)) => ms.to_int()
      _ => 120_000
    },
    warn_after_ms: match notify.get("warn_after_ms") {
      Some(Number(ms, ..)) => ms.to_int()
      _ => 300_000
    },
  })
}

///|
pub fn resolve_job_notify_target(
  store : SystemStore,
  definition : JobDefinition,
) -> JobNotifyTarget? {
  let target = match parse_job_notify_target(definition.config) {
    Some(target) => target
    None => return None
  }
  let preference_id = notification_preference_id(
    target.channel_id,
    target.account_id,
    target.recipient,
    target.thread_id,
  )
  match store.get_notification_preference(preference_id) {
    Some(preference) =>
      Some({
        ..target,
        verbosity: preference.verbosity,
        heartbeat_interval_ms: preference.heartbeat_interval_ms.unwrap_or(
          target.heartbeat_interval_ms,
        ),
        warn_after_ms: preference.warn_after_ms.unwrap_or(target.warn_after_ms),
      })
    None => Some(target)
  }
}

///|
pub async fn save_job_notification_preference(
  store : SystemStore,
  channel_id : String,
  account_id : String,
  recipient : String,
  thread_id : String?,
  verbosity : NotificationVerbosity,
  now_ms : Int,
  heartbeat_interval_ms? : Int? = None,
  warn_after_ms? : Int? = None,
) -> Unit {
  let id = notification_preference_id(
    channel_id, account_id, recipient, thread_id,
  )
  let existing = store.get_notification_preference(id)
  store.save_notification_preference({
    id,
    channel_id,
    account_id,
    recipient,
    thread_id,
    verbosity,
    heartbeat_interval_ms,
    warn_after_ms,
    created_at: existing.map(fn(pref) { pref.created_at }).unwrap_or(now_ms),
    updated_at: now_ms,
  })
}

///|
pub async fn save_presented_job_proposal(
  store : SystemStore,
  proposal : JobProposal,
  presented_message_id : String,
) -> Unit {
  store.save_job_proposal({
    ..proposal,
    presented_message_id: Some(presented_message_id),
  })
}

///|
pub fn proposal_for_reply(
  store : SystemStore,
  reply_to_message_id : String?,
) -> JobProposal? {
  match reply_to_message_id {
    Some(message_id) => store.find_job_proposal_by_message_id(message_id)
    None => None
  }
}

///|
pub fn resolve_target_proposal(
  store : SystemStore,
  proposal_id : String,
  reply_to_message_id : String?,
) -> JobProposal? {
  let trimmed = proposal_id.trim().to_owned()
  if !trimmed.is_blank() {
    return store.get_job_proposal(trimmed)
  }
  proposal_for_reply(store, reply_to_message_id)
}

///|
pub fn format_progress_event(event : JobRunEvent) -> String? {
  let step_label = event.step_id.unwrap_or("unknown")
  match event.event_type {
    "step.started" =>
      Some(["Step started: \{step_label}", event.message].join("\n"))
    "step.succeeded" =>
      Some(["Step completed: \{step_label}", event.message].join("\n"))
    "step.failed" =>
      Some(["Step failed: \{step_label}", event.message].join("\n"))
    _ => None
  }
}

///|
pub fn finished_status_prefix(status : RunStatus) -> String {
  match status {
    Succeeded => "Job completed"
    Failed => "Job failed"
    Cancelled => "Job cancelled"
    WaitingForInput => "Job waiting for input"
    _ => "Job finished"
  }
}

///|
pub fn render_progress_notification(
  definition_id : String,
  run_id : String,
  content : String,
) -> String {
  ["Job progress: \{definition_id}", "Run: \{run_id}", content].join("\n")
}

///|
pub fn initial_notification_runtime_state(
  now_ms : Int,
  last_notified_event_count? : Int = 0,
) -> JobNotificationRuntimeState {
  {
    last_sent_at: now_ms,
    last_notified_event_count,
    long_running_warned: false,
  }
}

///|
pub fn decide_active_job_notifications(
  definition_id : String,
  run : JobRun,
  events : Array[JobRunEvent],
  target : JobNotifyTarget,
  state : JobNotificationRuntimeState,
  now_ms : Int,
) -> JobNotificationDecision {
  if target.verbosity is Off {
    return { messages: [], next_state: state }
  }
  let messages : Array[String] = []
  let mut next_state = state
  if next_state.last_notified_event_count < events.length() {
    for event in events[next_state.last_notified_event_count:] {
      let should_send = match target.verbosity {
        Verbose => true
        Normal =>
          event.event_type == "step.started" ||
          event.event_type == "step.failed"
        Off => false
      }
      if !should_send {
        continue
      }
      match format_progress_event(event) {
        Some(content) =>
          messages.push(
            render_progress_notification(definition_id, run.id, content),
          )
        None => ()
      }
    }
  }
  next_state = { ..next_state, last_notified_event_count: events.length() }
  let elapsed_ms = match run.started_at {
    Some(started_at) => now_ms - started_at
    None => 0
  }
  if elapsed_ms >= target.warn_after_ms && !next_state.long_running_warned {
    next_state = {
      ..next_state,
      long_running_warned: true,
      last_sent_at: now_ms,
    }
    return { messages: [..messages, "Job is still running"], next_state }
  }
  if now_ms - next_state.last_sent_at >= target.heartbeat_interval_ms {
    next_state = { ..next_state, last_sent_at: now_ms }
    return { messages: [..messages, "Job heartbeat"], next_state }
  }
  { messages, next_state }
}

///|
pub fn parse_notification_verbosity(text : String) -> NotificationVerbosity? {
  match text.trim().to_lower() {
    "off" | "mute" | "silent" => Some(Off)
    "normal" | "default" => Some(Normal)
    "verbose" | "full" => Some(Verbose)
    _ => None
  }
}

///|
pub fn parse_reply_thread_job_action(text : String) -> (String, String)? {
  let trimmed = text.trim().to_owned()
  if trimmed.is_blank() {
    return None
  }
  let lower = trimmed.to_lower()
  if lower == "confirm" || lower == "/confirm" {
    return Some(("confirm", ""))
  }
  if lower == "reject" || lower == "/reject" {
    return Some(("reject", ""))
  }
  if lower.has_prefix("revise ") {
    return Some(("revise", trimmed[7:].to_owned().trim().to_owned()))
  }
  if lower.has_prefix("/revise ") {
    return Some(("revise", trimmed[8:].to_owned().trim().to_owned()))
  }
  None
}

///|
pub fn split_job_chat_command(text : String) -> (String, String) {
  let trimmed = text.trim()
  match trimmed.find(" ") {
    Some(index) =>
      (trimmed[:index].to_owned(), trimmed[index + 1:].trim().to_owned())
    None => (trimmed.to_owned(), "")
  }
}

///|
pub fn parse_job_chat_action(
  text : String,
  in_reply_thread : Bool,
) -> JobChatAction? {
  let trimmed = text.trim().to_owned()
  if in_reply_thread {
    match parse_reply_thread_job_action(trimmed) {
      Some(("confirm", _)) => return Some(Confirm(""))
      Some(("reject", _)) => return Some(Reject(""))
      Some(("revise", guidance)) => return Some(Revise(guidance))
      _ => ()
    }
  }
  guard trimmed.has_prefix("/") else { return None }
  let (command, args) = split_job_chat_command(trimmed)
  match command {
    _ if is_plan_mode_command(command) => Some(Plan(args))
    "/preview" => Some(Preview(args))
    _ if is_plan_job_command(command) => Some(PlanJob(args))
    _ if is_e2e_job_command(command) => Some(E2EJob(args))
    "/promote" => Some(Promote(args))
    "/confirm" => Some(Confirm(args))
    "/reject" => Some(Reject(args))
    "/revise" => Some(Revise(args))
    "/resume" => Some(Resume(args))
    "/job-status" => Some(JobStatus(args))
    "/job-workspace" | "/job-workspace-status" => Some(JobWorkspace(args))
    "/jobs" | "/job-runs" => Some(Jobs)
    "/job-stop" => Some(JobStop(args))
    "/job-force-stop" => Some(JobForceStop(args))
    "/job-notify" => Some(JobNotify(args))
    "/remember" => Some(Remember(args))
    "/memories" => Some(Memories)
    "/memory-search" => Some(MemorySearch(args))
    _ => None
  }
}

///|
pub async fn[T] dispatch_job_chat_action(
  action : JobChatAction?,
  on_plan_mode : async (String) -> T,
  on_preview : async (String) -> T,
  on_plan : async (String) -> T,
  on_e2e : async (String) -> T,
  on_promote : async (String) -> T,
  on_confirm : async (String) -> T,
  on_reject : async (String) -> T,
  on_revise : async (String) -> T,
  on_resume : async (String) -> T,
  on_status : async (String) -> T,
  on_workspace : async (String) -> T,
  on_jobs : async () -> T,
  on_stop : async (String, Bool) -> T,
  on_notify : async (String) -> T,
  on_remember : async (String) -> T,
  on_memories : async () -> T,
  on_memory_search : async (String) -> T,
) -> T? {
  match action {
    Some(Plan(args)) => Some(on_plan_mode(args))
    Some(Preview(args)) => Some(on_preview(args))
    Some(PlanJob(args)) => Some(on_plan(args))
    Some(E2EJob(args)) => Some(on_e2e(args))
    Some(Promote(args)) => Some(on_promote(args))
    Some(Confirm(args)) => Some(on_confirm(args))
    Some(Reject(args)) => Some(on_reject(args))
    Some(Revise(args)) => Some(on_revise(args))
    Some(Resume(args)) => Some(on_resume(args))
    Some(JobStatus(args)) => Some(on_status(args))
    Some(JobWorkspace(args)) => Some(on_workspace(args))
    Some(Jobs) => Some(on_jobs())
    Some(JobStop(args)) => Some(on_stop(args, false))
    Some(JobForceStop(args)) => Some(on_stop(args, true))
    Some(JobNotify(args)) => Some(on_notify(args))
    Some(Remember(args)) => Some(on_remember(args))
    Some(Memories) => Some(on_memories())
    Some(MemorySearch(args)) => Some(on_memory_search(args))
    None => None
  }
}

///|
pub fn parse_revise_args(text : String) -> (String, String)? {
  let trimmed = text.trim().to_owned()
  guard trimmed.find(" ") is Some(index) else { return None }
  let proposal_id = trimmed[:index].to_owned().trim().to_owned()
  let guidance = trimmed[index + 1:].to_owned().trim().to_owned()
  guard !proposal_id.is_blank() && !guidance.is_blank() else { return None }
  Some((proposal_id, guidance))
}

///|
pub fn render_job_status(
  snapshot : JobStatusSnapshot,
  prefix : String,
) -> String {
  let child_run_line = if snapshot.child_runs.is_empty() {
    None
  } else {
    let rendered = snapshot.child_runs
      .map(fn(child) { child.status })
      .join(", ")
    Some("Child runs: \{rendered}")
  }
  let waiting_guidance = if snapshot.status == "\"WaitingForInput\"" {
    [
      "Reply in this Feishu thread with `/resume` and the missing data, optionally with attachments.",
      "Ordinary plain chat messages do not resume the job.",
    ]
  } else {
    []
  }
  let missing_input_lines = match snapshot.missing_input_line {
    Some(line) if line.has_prefix("Missing inputs: ") => {
      let detail = line["Missing inputs: ".length():].trim().to_owned()
      let items : Array[String] = detail
        .split(";")
        .map(fn(part) { part.trim().to_owned() })
        .filter(fn(part) { !part.is_blank() })
        .to_array()
      if items.is_empty() {
        []
      } else {
        ["Missing inputs required:", ..items.map(fn(item) { "- \{item}" })]
      }
    }
    Some(line) if !line.trim().is_blank() => [line]
    _ => []
  }
  let missing_input_detail = match snapshot.missing_input_line {
    Some(line) if line.has_prefix("Missing inputs: ") =>
      Some(line["Missing inputs: ".length():].trim().to_owned())
    Some(line) if !line.trim().is_blank() => Some(line.trim().to_owned())
    _ => None
  }
  let summary_line = match snapshot.summary {
    Some(text) if snapshot.status == "\"WaitingForInput\"" =>
      match missing_input_detail {
        Some(detail) if text.contains(detail) =>
          match text.find(": \{detail}") {
            Some(index) =>
              Some("Summary: \{text[:index].to_owned().trim().to_owned()}")
            None => Some("Summary: \{text}")
          }
        _ => Some("Summary: \{text}")
      }
    Some(text) => Some("Summary: \{text}")
    None => None
  }
  let latest_event_line = if snapshot.status == "\"WaitingForInput\"" {
    match missing_input_detail {
      Some(detail) if snapshot.latest_event_line.contains(detail) =>
        "Latest event: job.waiting_for_input"
      _ => snapshot.latest_event_line
    }
  } else {
    snapshot.latest_event_line
  }
  [
    "\{prefix}: \{snapshot.definition_id}",
    "Title: \{snapshot.definition_title}",
    "Created: \{snapshot.created_at_label}",
    "Run: \{snapshot.run_id}",
    "Status: \{snapshot.status}",
    "Family: \{snapshot.family}",
    "Current step: \{snapshot.current_step}",
    "Progress: \{snapshot.done_steps}/\{snapshot.total_steps}",
    "Elapsed: \{snapshot.elapsed_ms}ms",
    snapshot.lineage_line.unwrap_or(""),
    summary_line.unwrap_or(""),
    snapshot.error.map(fn(text) { "Error: \{text}" }).unwrap_or(""),
    ..missing_input_lines,
    child_run_line.unwrap_or(""),
    latest_event_line,
    ..snapshot.output_lines,
    ..waiting_guidance,
    "Use `/job-status \{snapshot.definition_id}` for a fresh status check.",
  ]
  .filter(fn(line) { !line.is_blank() })
  .join("\n")
}

///|
pub fn render_active_jobs(runs : Array[ActiveJobSnapshot]) -> String {
  if runs.is_empty() {
    return "No pending or running jobs."
  }
  let lines = ["Active jobs:"]
  for run in runs {
    lines.push(
      [
        "- `\{run.definition_title}`",
        "job=`\{run.definition_id}`",
        "run=`\{run.run_id}`",
        "created=\{run.created_at_label}",
        "status=\{run.status}",
        "family=\{run.family}",
        "depth=\{run.depth}",
        "step=\{run.current_step}",
      ].join(" "),
    )
  }
  lines.join("\n")
}

///|
pub fn render_confirmed_job_reply(
  proposal_id : String,
  title : String,
  created_at_label : String,
  definition_id : String,
  run_id : String,
  family : String,
) -> String {
  let lines = [
    "Confirmed proposal `\{proposal_id}`.",
    "Title: \{title}",
    "Created: \{created_at_label}",
    "Created job `\{definition_id}` and started run `\{run_id}`.",
    "Check status with `/job-status \{definition_id}` or `/job-status \{run_id}`.",
    "You will receive start, progress, and completion notifications here.",
  ]
  if family.is_blank() {
    lines.join("\n")
  } else {
    [lines[0], lines[1], "Compiled as `\{family}`.", lines[2], lines[3]].join(
      "\n",
    )
  }
}

///|
pub fn render_unknown_proposal_message(command : String) -> String {
  match command {
    "confirm" =>
      "Unknown proposal. Use `/confirm <proposal_id>` or reply `confirm` to a proposal message."
    "reject" =>
      "Unknown proposal. Use `/reject <proposal_id>` or reply `reject` to a proposal message."
    "revise" =>
      "Unknown proposal. Use `/revise <proposal_id> ...` or reply to a proposal message."
    _ => "Unknown proposal."
  }
}

///|
pub fn render_confirm_proposal_failure(
  proposal_id : String,
  error : String,
) -> String {
  "Failed to confirm proposal \{proposal_id}: \{error}"
}

///|
pub fn render_rejected_job_reply(proposal_id : String) -> String {
  "Rejected proposal `\{proposal_id}`."
}

///|
pub fn render_revise_usage(in_reply_thread : Bool) -> String {
  if in_reply_thread {
    "Usage: /revise <proposal_id> <extra guidance> or reply `revise <guidance>` to a proposal message."
  } else {
    "Usage: /revise <proposal_id> <extra guidance>"
  }
}

///|
pub fn render_job_notify_usage() -> String {
  "Usage: /job-notify <off|normal|verbose>"
}

///|
pub fn render_job_workspace_usage() -> String {
  "Usage: /job-workspace <job_id|run_id>"
}

///|
pub fn render_job_notify_updated(verbosity : NotificationVerbosity) -> String {
  "Job notifications set to \{verbosity.to_json().stringify()} for this chat scope."
}

///|
pub fn render_remember_usage() -> String {
  "Usage: /remember <note>"
}

///|
pub fn render_memory_search_usage() -> String {
  "Usage: /memory-search <question>"
}

///|
pub fn render_memory_saved_reply(memory : MemoryRecord) -> String {
  let title = memory.title.unwrap_or(memory.id)
  ["Saved memory `\{memory.id}`.", "Kind: \{memory.kind}", "Title: \{title}"].join(
    "\n",
  )
}

///|
pub fn render_memories_reply(memories : Array[MemoryRecord]) -> String {
  if memories.is_empty() {
    return "No active memories for this chat scope."
  }
  let lines = ["Memories:"]
  for memory in memories {
    lines.push(
      "- `\{memory.id}` \{memory.title.unwrap_or(memory.kind)} [\{memory.kind}]",
    )
  }
  lines.join("\n")
}

///|
pub fn render_memory_search_reply(
  question : String,
  hits : Array[MemorySearchHit],
) -> String {
  if hits.is_empty() {
    return "No matching memories found for: \{question}"
  }
  let lines = ["Memory matches for: \{question}"]
  for index in 0..<hits.length() {
    let hit = hits[index]
    lines.push(
      "[\{index + 1}] \{hit.title.unwrap_or(hit.memory_id)}: \{hit.snippet}",
    )
  }
  lines.join("\n")
}
