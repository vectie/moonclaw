///|
struct JobNotifyTarget {
  channel_id : String
  account_id : String
  recipient : String
  thread_id : String?
  verbosity : @job.NotificationVerbosity
  heartbeat_interval_ms : Int
  warn_after_ms : Int
} derive(Show)

///|
fn notification_preference_id(
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
fn parse_job_notify_target(config : Json) -> JobNotifyTarget? {
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
        verbosity: @job.NotificationVerbosity::Normal,
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
fn Gateway::job_notification_target(
  self : Gateway,
  definition : @job.JobDefinition,
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
  match self.jobs.store().get_notification_preference(preference_id) {
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
fn Gateway::job_reply_message(
  self : Gateway,
  channel_id : String,
  account_id : String,
  incoming : @channel.Message,
  content : String,
) -> @channel.Message {
  @channel.Message::{
    id: self.uuid.v4().to_string(),
    channel: channel_id,
    from: account_id,
    to: incoming.to,
    content,
    content_type: "text",
    timestamp: current_time_ms(),
    thread_id: incoming.thread_id,
    reply_to: Some(incoming.id),
    attachments: [],
  }
}

///|
async fn Gateway::save_job_notification_preference(
  self : Gateway,
  channel_id : String,
  account_id : String,
  recipient : String,
  thread_id : String?,
  verbosity : @job.NotificationVerbosity,
  heartbeat_interval_ms? : Int? = None,
  warn_after_ms? : Int? = None,
) -> Unit {
  let now_ms = current_time_ms()
  let id = notification_preference_id(
    channel_id, account_id, recipient, thread_id,
  )
  let existing = self.jobs.store().get_notification_preference(id)
  self.jobs
  .store()
  .save_notification_preference(@job.JobNotificationPreference::{
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
async fn Gateway::save_presented_job_proposal(
  self : Gateway,
  proposal : @job.JobProposal,
  reply : @channel.Message,
) -> Unit {
  self.jobs
  .store()
  .save_job_proposal(@job.JobProposal::{
    ..proposal,
    presented_message_id: Some(reply.id),
  })
}

///|
fn Gateway::proposal_for_reply(
  self : Gateway,
  message : @channel.Message,
) -> @job.JobProposal? {
  match message.reply_to {
    Some(message_id) =>
      self.jobs.store().find_job_proposal_by_message_id(message_id)
    None => None
  }
}

///|
fn format_progress_event(event : @job.JobRunEvent) -> String? {
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
fn parse_notification_verbosity(text : String) -> @job.NotificationVerbosity? {
  match text.trim().to_lower() {
    "off" | "mute" | "silent" => Some(@job.NotificationVerbosity::Off)
    "normal" | "default" => Some(@job.NotificationVerbosity::Normal)
    "verbose" | "full" => Some(@job.NotificationVerbosity::Verbose)
    _ => None
  }
}

///|
fn parse_reply_thread_job_action(text : String) -> (String, String)? {
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
async fn Gateway::send_job_notification(
  self : Gateway,
  target : JobNotifyTarget,
  content : String,
) -> Unit {
  let message = @channel.Message::{
    id: self.uuid.v4().to_string(),
    channel: target.channel_id,
    from: target.account_id,
    to: target.recipient,
    content,
    content_type: "text",
    timestamp: current_time_ms(),
    thread_id: target.thread_id,
    reply_to: None,
    attachments: [],
  }
  let result = try? self.channel_manager.send_message(
    target.channel_id,
    target.recipient,
    message,
    Some(target.account_id),
  )
  match result {
    Ok(_) => ()
    Err(error) => self.logger.warn("Failed to send job notification: \{error}")
  }
}

///|
fn run_elapsed_ms(run : @job.JobRun, now_ms : Int) -> Int {
  match run.started_at {
    Some(started_at) => now_ms - started_at
    None => 0
  }
}

///|
fn Gateway::job_current_step_label(
  self : Gateway,
  definition : @job.JobDefinition,
  run_id : String,
) -> String {
  let steps = self.jobs.store().list_step_runs(run_id)
  let running = steps.filter(fn(step) { step.status is @job.RunStatus::Running })
  if !running.is_empty() {
    return running[0].step_id
  }
  if steps.is_empty() {
    match definition.workflow_id {
      Some(workflow_id) =>
        match self.jobs.store().get_workflow(workflow_id) {
          Some(workflow) =>
            workflow.steps.get(0).map(fn(step) { step.id }).unwrap_or("pending")
          None => "pending"
        }
      None => "pending"
    }
  } else {
    steps.sort_by(fn(left, right) {
      let left_ts = left.completed_at.unwrap_or(left.started_at.unwrap_or(0))
      let right_ts = right.completed_at.unwrap_or(right.started_at.unwrap_or(0))
      right_ts.compare(left_ts)
    })
    steps[0].step_id
  }
}

///|
fn Gateway::child_runs_for(
  self : Gateway,
  run_id : String,
) -> Array[@job.JobRun] {
  self.jobs
  .store()
  .list_runs()
  .filter(fn(run) { run.parent_run_id == Some(run_id) })
}

///|
async fn Gateway::job_status_text(
  self : Gateway,
  definition : @job.JobDefinition,
  run : @job.JobRun,
  prefix : String,
  now_ms : Int,
) -> String {
  let steps = self.jobs.store().list_step_runs(run.id)
  let total_steps = match definition.workflow_id {
    Some(workflow_id) =>
      self.jobs
      .store()
      .get_workflow(workflow_id)
      .map(fn(workflow) { workflow.steps.length() })
      .unwrap_or(steps.length())
    None => steps.length()
  }
  let done_steps = steps
    .filter(fn(step) { step.status is @job.RunStatus::Succeeded })
    .length()
  let current_step = self.job_current_step_label(definition, run.id)
  let elapsed_ms = run_elapsed_ms(run, now_ms)
  let lineage_line = match (run.parent_run_id, run.parent_step_id) {
    (Some(parent_run_id), Some(parent_step_id)) =>
      Some(
        "Lineage: child of run \{parent_run_id} via step \{parent_step_id} (depth \{run.depth})",
      )
    (Some(parent_run_id), None) =>
      Some("Lineage: child of run \{parent_run_id} (depth \{run.depth})")
    _ => if run.depth > 0 { Some("Lineage: depth \{run.depth}") } else { None }
  }
  let family = match definition.config {
    { "family": String(family), .. } => family
    _ => "unknown"
  }
  let template = match definition.config {
    { "template": String(template), .. } => template
    _ => "unknown"
  }
  let capabilities = match definition.config {
    { "required_capabilities": Array(items), .. } =>
      items
      .map(fn(item) {
        match item {
          String(text) => text
          _ => ""
        }
      })
      .filter(fn(text) { !text.is_blank() })
      .join(", ")
    _ => ""
  }
  let missing_capabilities = match definition.config {
    { "missing_capabilities": Array(items), .. } =>
      items
      .map(fn(item) {
        match item {
          String(text) => text
          _ => ""
        }
      })
      .filter(fn(text) { !text.is_blank() })
      .join(", ")
    _ => ""
  }
  let compiler_notes = match definition.config {
    { "compiler_notes": Array(items), .. } =>
      items
      .map(fn(item) {
        match item {
          String(text) => text
          _ => ""
        }
      })
      .filter(fn(text) { !text.is_blank() })
    _ => []
  }
  let compiler_notes_text = compiler_notes.join(" | ")
  let run_events = self.jobs.store().list_run_events(run.id)
  let latest_event = if run_events.is_empty() {
    None
  } else {
    run_events.get(run_events.length() - 1)
  }
  let latest_event_line = match latest_event {
    Some(event) => "Latest event: \{event.event_type} - \{event.message}"
    None => "Latest event: none"
  }
  let error_line = match run.error {
    Some(error) if !error.is_blank() => Some("Error: \{error}")
    _ => None
  }
  let summary_line = match run.summary {
    Some(summary) if !summary.is_blank() => Some("Summary: \{summary}")
    _ => None
  }
  let child_runs = self.child_runs_for(run.id)
  let child_run_line = if child_runs.is_empty() {
    None
  } else {
    let rendered = child_runs
      .map(fn(child) { "\{child.id}=\{child.status.to_json().stringify()}" })
      .join(", ")
    Some("Child runs: \{rendered}")
  }
  [
    "\{prefix}: \{definition.id}",
    "Run: \{run.id}",
    "Status: \{run.status.to_json().stringify()}",
    "Family: \{family}",
    "Template: \{template}",
    "Current step: \{current_step}",
    "Progress: \{done_steps}/\{total_steps}",
    "Elapsed: \{elapsed_ms}ms",
    lineage_line.unwrap_or(""),
    if capabilities.is_blank() {
      ""
    } else {
      "Capabilities: \{capabilities}"
    },
    if missing_capabilities.is_blank() {
      ""
    } else {
      "Missing capabilities: \{missing_capabilities}"
    },
    if compiler_notes.is_empty() {
      ""
    } else {
      "Compiler notes: \{compiler_notes_text}"
    },
    summary_line.unwrap_or(""),
    error_line.unwrap_or(""),
    child_run_line.unwrap_or(""),
    latest_event_line,
    "Use `/job-status \{definition.id}` for a fresh status check.",
  ]
  .filter(fn(line) { !line.is_blank() })
  .join("\n")
}

///|
async fn Gateway::format_active_jobs(
  self : Gateway,
  runs : Array[@job.JobRun],
) -> String {
  if runs.is_empty() {
    return "No pending or running jobs."
  }
  let lines = ["Active jobs:"]
  for run in runs {
    match self.jobs.store().get_definition(run.job_id) {
      Some(definition) => {
        let family = match definition.config {
          { "family": String(family), .. } => family
          _ => "unknown"
        }
        lines.push(
          [
            "- `\{definition.id}`",
            "run=`\{run.id}`",
            "status=\{run.status.to_json().stringify()}",
            "family=\{family}",
            "depth=\{run.depth}",
            "step=\{self.job_current_step_label(definition, run.id)}",
          ].join(" "),
        )
      }
      None => ()
    }
  }
  lines.join("\n")
}

///|
async fn Gateway::handle_jobs_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
) -> @channel.Message {
  self.job_reply_message(
    channel_id,
    account_id,
    message,
    self.format_active_jobs(self.active_job_runs()),
  )
}

///|
async fn Gateway::handle_job_stop_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  args : String,
  force? : Bool = false,
) -> @channel.Message {
  let trimmed = args.trim().to_string()
  guard !trimmed.is_blank() else {
    return self.job_reply_message(
      channel_id,
      account_id,
      message,
      if force {
        "Usage: /job-force-stop <job_id|run_id>"
      } else {
        "Usage: /job-stop <job_id|run_id>"
      },
    )
  }
  let (definition, _run) = match self.resolve_job_status_target(trimmed) {
    Some(resolved) => resolved
    None =>
      return self.job_reply_message(
        channel_id,
        account_id,
        message,
        "Unknown job or run id: \{trimmed}",
      )
  }
  match self.cancel_job_definition_run(definition.id, force~) {
    Ok(run) =>
      self.job_reply_message(
        channel_id,
        account_id,
        message,
        if force {
          "Force-stop requested for `\{definition.id}` (`\{run.id}`)."
        } else {
          "Stop requested for `\{definition.id}` (`\{run.id}`)."
        },
      )
    Err(error) => self.job_reply_message(channel_id, account_id, message, error)
  }
}

///|
async fn Gateway::maybe_notify_active_jobs(self : Gateway) -> Unit {
  let now_ms = current_time_ms()
  for run in self.active_job_runs() {
    let definition = match self.jobs.store().get_definition(run.job_id) {
      Some(definition) => definition
      None => continue
    }
    let target = match self.job_notification_target(definition) {
      Some(target) => target
      None => continue
    }
    if target.verbosity is @job.NotificationVerbosity::Off {
      continue
    }
    let events = self.jobs.store().list_run_events(run.id)
    let sent_count = self.job_last_notified_event_count.get(run.id).unwrap_or(0)
    if sent_count < events.length() &&
      target.verbosity is @job.NotificationVerbosity::Verbose {
      for event in events[sent_count:] {
        match format_progress_event(event) {
          Some(content) =>
            self.send_job_notification(
              target,
              ["Job progress: \{definition.id}", "Run: \{run.id}", content].join(
                "\n",
              ),
            )
          None => ()
        }
      }
    }
    self.job_last_notified_event_count.set(run.id, events.length())
    let elapsed_ms = run_elapsed_ms(run, now_ms)
    if elapsed_ms >= target.warn_after_ms &&
      !self.job_long_running_warned.get(run.id).unwrap_or(false) {
      self.send_job_notification(
        target,
        self.job_status_text(definition, run, "Job is still running", now_ms),
      )
      self.job_long_running_warned.set(run.id, true)
      self.job_status_last_sent_at.set(run.id, now_ms)
      continue
    }
    let last_sent = self.job_status_last_sent_at.get(run.id).unwrap_or(0)
    if now_ms - last_sent >= target.heartbeat_interval_ms {
      self.send_job_notification(
        target,
        self.job_status_text(definition, run, "Job heartbeat", now_ms),
      )
      self.job_status_last_sent_at.set(run.id, now_ms)
    }
  }
}

///|
async fn Gateway::notify_job_run_started(
  self : Gateway,
  definition : @job.JobDefinition,
  run : @job.JobRun,
) -> Unit {
  let target = match self.job_notification_target(definition) {
    Some(target) => target
    None => return
  }
  if target.verbosity is @job.NotificationVerbosity::Off {
    return
  }
  self.send_job_notification(
    target,
    self.job_status_text(definition, run, "Job started", current_time_ms()),
  )
  self.job_status_last_sent_at.set(run.id, current_time_ms())
  self.job_last_notified_event_count.set(run.id, 0)
}

///|
async fn Gateway::notify_job_run_finished(
  self : Gateway,
  definition : @job.JobDefinition,
  run : @job.JobRun,
) -> Unit {
  let target = match self.job_notification_target(definition) {
    Some(target) => target
    None => return
  }
  if !(target.verbosity is @job.NotificationVerbosity::Off) {
    let prefix = match run.status {
      @job.RunStatus::Succeeded => "Job completed"
      @job.RunStatus::Failed => "Job failed"
      @job.RunStatus::Cancelled => "Job cancelled"
      _ => "Job finished"
    }
    self.send_job_notification(
      target,
      self.job_status_text(definition, run, prefix, current_time_ms()),
    )
  }
  self.job_status_last_sent_at.remove(run.id) |> ignore()
  self.job_last_notified_event_count.remove(run.id) |> ignore()
  self.job_long_running_warned.remove(run.id) |> ignore()
}

///|
fn split_command(text : String) -> (String, String) {
  let trimmed = text.trim()
  match trimmed.find(" ") {
    Some(index) =>
      (trimmed[:index].to_string(), trimmed[index + 1:].trim().to_string())
    None => (trimmed.to_string(), "")
  }
}

///|
async fn Gateway::handle_plan_job_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  request_text : String,
) -> @channel.Message {
  guard !request_text.is_blank() else {
    return self.job_reply_message(
      channel_id, account_id, message, "Usage: /plan-job <job description>",
    )
  }
  let proposal = @job.plan_job_proposal(
    self.uuid.v4().to_string(),
    request_text,
    current_time_ms(),
    channel_id=Some(channel_id),
    account_id=Some(account_id),
    recipient=Some(message.to),
    thread_id=message.thread_id,
    cwd=self.cwd,
    home=Some(self.home),
  )
  self.save_job_notification_preference(
    channel_id,
    account_id,
    message.to,
    message.thread_id,
    @job.NotificationVerbosity::Normal,
  )
  let reply = self.job_reply_message(
    channel_id,
    account_id,
    message,
    @job.render_job_proposal_for_chat(proposal),
  )
  self.save_presented_job_proposal(proposal, reply)
  reply
}

///|
fn parse_revise_args(text : String) -> (String, String)? {
  let trimmed = text.trim().to_string()
  guard trimmed.find(" ") is Some(index) else { return None }
  let proposal_id = trimmed[:index].to_string().trim().to_string()
  let guidance = trimmed[index + 1:].to_string().trim().to_string()
  guard !proposal_id.is_blank() && !guidance.is_blank() else { return None }
  Some((proposal_id, guidance))
}

///|
fn Gateway::resolve_target_proposal(
  self : Gateway,
  message : @channel.Message,
  proposal_id : String,
) -> @job.JobProposal? {
  let trimmed = proposal_id.trim().to_string()
  if !trimmed.is_blank() {
    return self.jobs.store().get_job_proposal(trimmed)
  }
  self.proposal_for_reply(message)
}

///|
async fn Gateway::handle_confirm_job_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  proposal_id : String,
) -> @channel.Message {
  let proposal = match self.resolve_target_proposal(message, proposal_id) {
    Some(proposal) => proposal
    None =>
      return self.job_reply_message(
        channel_id, account_id, message, "Unknown proposal. Use `/confirm <proposal_id>` or reply `confirm` to a proposal message.",
      )
  }
  guard proposal.status is @job.JobProposalStatus::Draft else {
    return self.job_reply_message(
      channel_id,
      account_id,
      message,
      "Proposal \{proposal_id} is already \{proposal.status.to_json().stringify()}",
    )
  }
  let compilation = @job.compile_job_proposal(
    proposal,
    current_time_ms(),
    self.cwd,
    self.home,
  )
  let definition = compilation.definition
  let workflow = compilation.workflow
  let missing_capabilities_text = compilation.missing_capabilities.join(", ")
  let compiler_notes_text = compilation.compiler_notes.join(" | ")
  self.jobs.register_definition(definition)
  self.jobs.register_workflow(workflow)
  for binding in compilation.bindings {
    self.jobs.store().save_chat_binding(binding)
  }
  let run = match self.trigger_job_definition(definition.id) {
    Ok(run) => run
    Err(error) =>
      return self.job_reply_message(
        channel_id,
        account_id,
        message,
        "Failed to confirm proposal \{proposal_id}: \{error}",
      )
  }
  self.jobs
  .store()
  .save_job_proposal(@job.JobProposal::{
    ..proposal,
    suggested_family: Some(compilation.family),
    suggested_template: Some(compilation.template),
    required_capabilities: compilation.required_capabilities,
    missing_capabilities: compilation.missing_capabilities,
    compiler_notes: compilation.compiler_notes,
    status: @job.JobProposalStatus::Confirmed,
    job_id: Some(definition.id),
    workflow_id: Some(workflow.id),
    last_run_id: Some(run.id),
    updated_at: current_time_ms(),
  })
  self.job_reply_message(
    channel_id,
    account_id,
    message,
    [
      "Confirmed proposal `\{proposal_id}`.",
      "Created job `\{definition.id}` and started run `\{run.id}`.",
      "Compiled as `\{compilation.family}` / `\{compilation.template}`.",
      if compilation.missing_capabilities.is_empty() {
        ""
      } else {
        "Missing capabilities: \{missing_capabilities_text}"
      },
      if compilation.compiler_notes.is_empty() {
        ""
      } else {
        "Compiler notes: \{compiler_notes_text}"
      },
      "Check status with `/job-status \{definition.id}` or `/job-status \{run.id}`.",
      "You will receive start, progress, and completion notifications here.",
    ].join("\n"),
  )
}

///|
async fn Gateway::handle_reject_job_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  proposal_id : String,
) -> @channel.Message {
  let proposal = match self.resolve_target_proposal(message, proposal_id) {
    Some(proposal) => proposal
    None =>
      return self.job_reply_message(
        channel_id, account_id, message, "Unknown proposal. Use `/reject <proposal_id>` or reply `reject` to a proposal message.",
      )
  }
  self.jobs
  .store()
  .save_job_proposal(@job.JobProposal::{
    ..proposal,
    status: @job.JobProposalStatus::Rejected,
    updated_at: current_time_ms(),
  })
  self.job_reply_message(
    channel_id,
    account_id,
    message,
    "Rejected proposal `\{proposal_id}`.",
  )
}

///|
async fn Gateway::handle_revise_job_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  args : String,
) -> @channel.Message {
  let (proposal_id, guidance) = match parse_revise_args(args) {
    Some(parts) => parts
    None =>
      if message.reply_to is Some(_) && !args.trim().to_string().is_blank() {
        ("", args.trim().to_string())
      } else {
        return self.job_reply_message(
          channel_id, account_id, message, "Usage: /revise <proposal_id> <extra guidance> or reply `revise <guidance>` to a proposal message.",
        )
      }
  }
  let proposal = match self.resolve_target_proposal(message, proposal_id) {
    Some(proposal) => proposal
    None =>
      return self.job_reply_message(
        channel_id, account_id, message, "Unknown proposal. Use `/revise <proposal_id> ...` or reply to a proposal message.",
      )
  }
  guard proposal.status is @job.JobProposalStatus::Draft else {
    return self.job_reply_message(
      channel_id,
      account_id,
      message,
      "Proposal \{proposal_id} is already \{proposal.status.to_json().stringify()}",
    )
  }
  let revised = @job.revise_job_proposal(
    proposal,
    guidance,
    current_time_ms(),
    cwd=self.cwd,
    home=Some(self.home),
  )
  let reply = self.job_reply_message(
    channel_id,
    account_id,
    message,
    @job.render_job_proposal_for_chat(revised),
  )
  self.save_presented_job_proposal(revised, reply)
  reply
}

///|
async fn Gateway::handle_job_status_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  job_or_run_id : String,
) -> @channel.Message {
  let trimmed = job_or_run_id.trim().to_string()
  let (definition, run) = match self.resolve_job_status_target(trimmed) {
    Some(resolved) => resolved
    None =>
      return self.job_reply_message(
        channel_id,
        account_id,
        message,
        "Unknown job or run id: \{trimmed}",
      )
  }
  self.job_reply_message(
    channel_id,
    account_id,
    message,
    self.job_status_text(
      definition,
      run,
      "Current job status",
      current_time_ms(),
    ),
  )
}

///|
fn Gateway::resolve_job_status_target(
  self : Gateway,
  job_or_run_id : String,
) -> (@job.JobDefinition, @job.JobRun)? {
  let trimmed = job_or_run_id.trim().to_string()
  match self.jobs.store().get_definition(trimmed) {
    Some(definition) =>
      match self.job_run_for_definition(trimmed) {
        Some(run) => Some((definition, run))
        None => None
      }
    None =>
      match self.jobs.store().get_run(trimmed) {
        Some(run) =>
          match self.jobs.store().get_definition(run.job_id) {
            Some(definition) => Some((definition, run))
            None => None
          }
        None => None
      }
  }
}

///|
async fn Gateway::handle_job_notify_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  args : String,
) -> @channel.Message {
  let verbosity = match parse_notification_verbosity(args) {
    Some(verbosity) => verbosity
    None =>
      return self.job_reply_message(
        channel_id, account_id, message, "Usage: /job-notify <off|normal|verbose>",
      )
  }
  self.save_job_notification_preference(
    channel_id,
    account_id,
    message.to,
    message.thread_id,
    verbosity,
  )
  self.job_reply_message(
    channel_id,
    account_id,
    message,
    "Job notifications set to \{verbosity.to_json().stringify()} for this chat scope.",
  )
}

///|
async fn Gateway::handle_job_chat_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
) -> @channel.Message? {
  let trimmed = message.content.trim().to_string()
  if message.reply_to is Some(_) {
    match parse_reply_thread_job_action(trimmed) {
      Some(("confirm", _)) =>
        return Some(
          self.handle_confirm_job_command(channel_id, account_id, message, ""),
        )
      Some(("reject", _)) =>
        return Some(
          self.handle_reject_job_command(channel_id, account_id, message, ""),
        )
      Some(("revise", guidance)) =>
        return Some(
          self.handle_revise_job_command(
            channel_id, account_id, message, guidance,
          ),
        )
      _ => ()
    }
  }
  guard trimmed.has_prefix("/") else { return None }
  let (command, args) = split_command(trimmed)
  match command {
    "/plan-job" =>
      Some(self.handle_plan_job_command(channel_id, account_id, message, args))
    "/confirm" =>
      Some(
        self.handle_confirm_job_command(channel_id, account_id, message, args),
      )
    "/reject" =>
      Some(
        self.handle_reject_job_command(channel_id, account_id, message, args),
      )
    "/revise" =>
      Some(
        self.handle_revise_job_command(channel_id, account_id, message, args),
      )
    "/job-status" =>
      Some(
        self.handle_job_status_command(channel_id, account_id, message, args),
      )
    "/jobs" | "/job-runs" =>
      Some(self.handle_jobs_command(channel_id, account_id, message))
    "/job-stop" =>
      Some(self.handle_job_stop_command(channel_id, account_id, message, args))
    "/job-force-stop" =>
      Some(
        self.handle_job_stop_command(
          channel_id,
          account_id,
          message,
          args,
          force=true,
        ),
      )
    "/job-notify" =>
      Some(
        self.handle_job_notify_command(channel_id, account_id, message, args),
      )
    _ => None
  }
}
