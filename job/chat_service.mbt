///|
pub(all) struct JobNotifyTarget {
  channel_id : String
  account_id : String
  recipient : String
  thread_id : String?
  verbosity : NotificationVerbosity
  heartbeat_interval_ms : Int
  warn_after_ms : Int
} derive(Show)

///|
pub(all) enum JobChatAction {
  PlanJob(String)
  Confirm(String)
  Reject(String)
  Revise(String)
  JobStatus(String)
  Jobs
  JobStop(String)
  JobForceStop(String)
  JobNotify(String)
} derive(Show)

///|
pub(all) struct ChildRunStatus {
  run_id : String
  status : String
} derive(Show, ToJson, FromJson)

///|
pub(all) struct JobStatusSnapshot {
  definition_id : String
  run_id : String
  status : String
  family : String
  template : String
  current_step : String
  done_steps : Int
  total_steps : Int
  elapsed_ms : Int
  lineage_line : String?
  capabilities : String
  missing_capabilities : String
  compiler_notes : Array[String]
  summary : String?
  error : String?
  child_runs : Array[ChildRunStatus]
  latest_event_line : String
} derive(Show, ToJson, FromJson)

///|
pub(all) struct ActiveJobSnapshot {
  definition_id : String
  run_id : String
  status : String
  family : String
  depth : Int
  current_step : String
} derive(Show, ToJson, FromJson)

///|
pub(all) struct JobNotificationRuntimeState {
  last_sent_at : Int
  last_notified_event_count : Int
  long_running_warned : Bool
} derive(Show, ToJson, FromJson)

///|
pub(all) struct JobNotificationDecision {
  messages : Array[String]
  next_state : JobNotificationRuntimeState
} derive(Show, ToJson, FromJson)

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
pub fn parse_job_notify_target(config : Json) -> JobNotifyTarget? {
  match config {
    {
      "notify": {
        "channel": String(channel_id),
        "account_id": String(account_id),
        "to": String(recipient),
        ..
      },
      ..
    } =>
      Some(JobNotifyTarget::{
        channel_id,
        account_id,
        recipient,
        thread_id: match config {
          { "notify": { "thread_id": String(thread_id), .. }, .. } =>
            Some(thread_id)
          _ => None
        },
        verbosity: NotificationVerbosity::Normal,
        heartbeat_interval_ms: match config {
          { "notify": { "heartbeat_interval_ms": Number(ms, ..), .. }, .. } =>
            ms.to_int()
          _ => 120_000
        },
        warn_after_ms: match config {
          { "notify": { "warn_after_ms": Number(ms, ..), .. }, .. } =>
            ms.to_int()
          _ => 300_000
        },
      })
    _ => None
  }
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
      Some(JobNotifyTarget::{
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
  store.save_notification_preference(JobNotificationPreference::{
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
  store.save_job_proposal(JobProposal::{
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
  let trimmed = proposal_id.trim().to_string()
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
    RunStatus::Succeeded => "Job completed"
    RunStatus::Failed => "Job failed"
    RunStatus::Cancelled => "Job cancelled"
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
) -> JobNotificationRuntimeState {
  JobNotificationRuntimeState::{
    last_sent_at: now_ms,
    last_notified_event_count: 0,
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
  if target.verbosity is NotificationVerbosity::Off {
    return JobNotificationDecision::{ messages: [], next_state: state }
  }
  let messages : Array[String] = []
  let mut next_state = state
  if next_state.last_notified_event_count < events.length() &&
    target.verbosity is NotificationVerbosity::Verbose {
    for event in events[next_state.last_notified_event_count:] {
      match format_progress_event(event) {
        Some(content) =>
          messages.push(
            render_progress_notification(definition_id, run.id, content),
          )
        None => ()
      }
    }
  }
  next_state = JobNotificationRuntimeState::{
    ..next_state,
    last_notified_event_count: events.length(),
  }
  let elapsed_ms = match run.started_at {
    Some(started_at) => now_ms - started_at
    None => 0
  }
  if elapsed_ms >= target.warn_after_ms && !next_state.long_running_warned {
    next_state = JobNotificationRuntimeState::{
      ..next_state,
      long_running_warned: true,
      last_sent_at: now_ms,
    }
    return JobNotificationDecision::{
      messages: [..messages, "Job is still running"],
      next_state,
    }
  }
  if now_ms - next_state.last_sent_at >= target.heartbeat_interval_ms {
    next_state = JobNotificationRuntimeState::{
      ..next_state,
      last_sent_at: now_ms,
    }
    return JobNotificationDecision::{
      messages: [..messages, "Job heartbeat"],
      next_state,
    }
  }
  JobNotificationDecision::{ messages, next_state }
}

///|
pub fn parse_notification_verbosity(text : String) -> NotificationVerbosity? {
  match text.trim().to_lower() {
    "off" | "mute" | "silent" => Some(NotificationVerbosity::Off)
    "normal" | "default" => Some(NotificationVerbosity::Normal)
    "verbose" | "full" => Some(NotificationVerbosity::Verbose)
    _ => None
  }
}

///|
pub fn parse_reply_thread_job_action(text : String) -> (String, String)? {
  let trimmed = text.trim().to_string()
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
    return Some(("revise", trimmed[7:].to_string().trim().to_string()))
  }
  if lower.has_prefix("/revise ") {
    return Some(("revise", trimmed[8:].to_string().trim().to_string()))
  }
  None
}

///|
pub fn split_job_chat_command(text : String) -> (String, String) {
  let trimmed = text.trim()
  match trimmed.find(" ") {
    Some(index) =>
      (trimmed[:index].to_string(), trimmed[index + 1:].trim().to_string())
    None => (trimmed.to_string(), "")
  }
}

///|
pub fn parse_job_chat_action(
  text : String,
  in_reply_thread : Bool,
) -> JobChatAction? {
  let trimmed = text.trim().to_string()
  if in_reply_thread {
    match parse_reply_thread_job_action(trimmed) {
      Some(("confirm", _)) => return Some(JobChatAction::Confirm(""))
      Some(("reject", _)) => return Some(JobChatAction::Reject(""))
      Some(("revise", guidance)) => return Some(JobChatAction::Revise(guidance))
      _ => ()
    }
  }
  guard trimmed.has_prefix("/") else { return None }
  let (command, args) = split_job_chat_command(trimmed)
  match command {
    "/plan-job" => Some(JobChatAction::PlanJob(args))
    "/confirm" => Some(JobChatAction::Confirm(args))
    "/reject" => Some(JobChatAction::Reject(args))
    "/revise" => Some(JobChatAction::Revise(args))
    "/job-status" => Some(JobChatAction::JobStatus(args))
    "/jobs" | "/job-runs" => Some(JobChatAction::Jobs)
    "/job-stop" => Some(JobChatAction::JobStop(args))
    "/job-force-stop" => Some(JobChatAction::JobForceStop(args))
    "/job-notify" => Some(JobChatAction::JobNotify(args))
    _ => None
  }
}

///|
pub async fn[T] dispatch_job_chat_action(
  action : JobChatAction?,
  on_plan : async (String) -> T,
  on_confirm : async (String) -> T,
  on_reject : async (String) -> T,
  on_revise : async (String) -> T,
  on_status : async (String) -> T,
  on_jobs : async () -> T,
  on_stop : async (String, Bool) -> T,
  on_notify : async (String) -> T,
) -> T? {
  match action {
    Some(JobChatAction::PlanJob(args)) => Some(on_plan(args))
    Some(JobChatAction::Confirm(args)) => Some(on_confirm(args))
    Some(JobChatAction::Reject(args)) => Some(on_reject(args))
    Some(JobChatAction::Revise(args)) => Some(on_revise(args))
    Some(JobChatAction::JobStatus(args)) => Some(on_status(args))
    Some(JobChatAction::Jobs) => Some(on_jobs())
    Some(JobChatAction::JobStop(args)) => Some(on_stop(args, false))
    Some(JobChatAction::JobForceStop(args)) => Some(on_stop(args, true))
    Some(JobChatAction::JobNotify(args)) => Some(on_notify(args))
    None => None
  }
}

///|
pub fn parse_revise_args(text : String) -> (String, String)? {
  let trimmed = text.trim().to_string()
  guard trimmed.find(" ") is Some(index) else { return None }
  let proposal_id = trimmed[:index].to_string().trim().to_string()
  let guidance = trimmed[index + 1:].to_string().trim().to_string()
  guard !proposal_id.is_blank() && !guidance.is_blank() else { return None }
  Some((proposal_id, guidance))
}

///|
pub fn render_job_status(
  snapshot : JobStatusSnapshot,
  prefix : String,
) -> String {
  let compiler_notes_text = snapshot.compiler_notes.join(" | ")
  let child_run_line = if snapshot.child_runs.is_empty() {
    None
  } else {
    let rendered = snapshot.child_runs
      .map(fn(child) { "\{child.run_id}=\{child.status}" })
      .join(", ")
    Some("Child runs: \{rendered}")
  }
  [
    "\{prefix}: \{snapshot.definition_id}",
    "Run: \{snapshot.run_id}",
    "Status: \{snapshot.status}",
    "Family: \{snapshot.family}",
    "Template: \{snapshot.template}",
    "Current step: \{snapshot.current_step}",
    "Progress: \{snapshot.done_steps}/\{snapshot.total_steps}",
    "Elapsed: \{snapshot.elapsed_ms}ms",
    snapshot.lineage_line.unwrap_or(""),
    if snapshot.capabilities.is_blank() {
      ""
    } else {
      "Capabilities: \{snapshot.capabilities}"
    },
    if snapshot.missing_capabilities.is_blank() {
      ""
    } else {
      "Missing capabilities: \{snapshot.missing_capabilities}"
    },
    if snapshot.compiler_notes.is_empty() {
      ""
    } else {
      "Compiler notes: \{compiler_notes_text}"
    },
    snapshot.summary.map(fn(text) { "Summary: \{text}" }).unwrap_or(""),
    snapshot.error.map(fn(text) { "Error: \{text}" }).unwrap_or(""),
    child_run_line.unwrap_or(""),
    snapshot.latest_event_line,
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
        "- `\{run.definition_id}`",
        "run=`\{run.run_id}`",
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
  definition_id : String,
  run_id : String,
  family : String,
  template : String,
  missing_capabilities : Array[String],
  compiler_notes : Array[String],
) -> String {
  let missing_capabilities_text = missing_capabilities.join(", ")
  let compiler_notes_text = compiler_notes.join(" | ")
  [
    "Confirmed proposal `\{proposal_id}`.",
    "Created job `\{definition_id}` and started run `\{run_id}`.",
    "Compiled as `\{family}` / `\{template}`.",
    if missing_capabilities.is_empty() {
      ""
    } else {
      "Missing capabilities: \{missing_capabilities_text}"
    },
    if compiler_notes.is_empty() {
      ""
    } else {
      "Compiler notes: \{compiler_notes_text}"
    },
    "Check status with `/job-status \{definition_id}` or `/job-status \{run_id}`.",
    "You will receive start, progress, and completion notifications here.",
  ]
  .filter(fn(line) { !line.is_blank() })
  .join("\n")
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
pub fn render_job_notify_updated(verbosity : NotificationVerbosity) -> String {
  "Job notifications set to \{verbosity.to_json().stringify()} for this chat scope."
}
