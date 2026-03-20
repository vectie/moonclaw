///|
test "decide_active_job_notifications emits verbose progress and heartbeat" {
  let run = JobRun::{
    id: "run-1",
    job_id: "job-1",
    trigger: TriggerSource::Manual,
    parent_run_id: None,
    parent_step_id: None,
    depth: 0,
    workspace_dir: None,
    status: RunStatus::Running,
    attempt: 1,
    retry_of: None,
    started_at: Some(1_000),
    completed_at: None,
    summary: None,
    error: None,
  }
  let decision = decide_active_job_notifications(
    "job-1",
    run,
    [
      JobRunEvent::{
        run_id: "run-1",
        job_id: "job-1",
        event_type: "step.started",
        timestamp: 1_050,
        step_id: Some("step-a"),
        status: Some(RunStatus::Running),
        message: "Starting step A",
        data: {},
      },
    ],
    JobNotifyTarget::{
      channel_id: "feishu",
      account_id: "default",
      recipient: "oc_chat_1",
      thread_id: None,
      verbosity: NotificationVerbosity::Verbose,
      heartbeat_interval_ms: 100,
      warn_after_ms: 1_000,
    },
    JobNotificationRuntimeState::{
      last_sent_at: 1_000,
      last_notified_event_count: 0,
      long_running_warned: false,
    },
    1_150,
  )
  inspect(decision.messages.length(), content="2")
  inspect(decision.messages[0].contains("Job progress: job-1"), content="true")
  inspect(decision.messages[1], content="Job heartbeat")
  inspect(decision.next_state.last_notified_event_count, content="1")
  inspect(decision.next_state.last_sent_at, content="1150")
}

///|
test "decide_active_job_notifications warns once for long-running jobs" {
  let run = JobRun::{
    id: "run-2",
    job_id: "job-2",
    trigger: TriggerSource::Manual,
    parent_run_id: None,
    parent_step_id: None,
    depth: 0,
    workspace_dir: None,
    status: RunStatus::Running,
    attempt: 1,
    retry_of: None,
    started_at: Some(1_000),
    completed_at: None,
    summary: None,
    error: None,
  }
  let decision = decide_active_job_notifications(
    "job-2",
    run,
    [],
    JobNotifyTarget::{
      channel_id: "feishu",
      account_id: "default",
      recipient: "oc_chat_1",
      thread_id: None,
      verbosity: NotificationVerbosity::Normal,
      heartbeat_interval_ms: 100,
      warn_after_ms: 200,
    },
    JobNotificationRuntimeState::{
      last_sent_at: 1_000,
      last_notified_event_count: 0,
      long_running_warned: false,
    },
    1_250,
  )
  inspect(decision.messages.join("|"), content="Job is still running")
  inspect(decision.next_state.long_running_warned, content="true")
}

///|
test "decide_active_job_notifications emits step start for normal verbosity" {
  let run = JobRun::{
    id: "run-3",
    job_id: "job-3",
    trigger: TriggerSource::Manual,
    parent_run_id: None,
    parent_step_id: None,
    depth: 0,
    workspace_dir: None,
    status: RunStatus::Running,
    attempt: 1,
    retry_of: None,
    started_at: Some(1_000),
    completed_at: None,
    summary: None,
    error: None,
  }
  let decision = decide_active_job_notifications(
    "job-3",
    run,
    [
      JobRunEvent::{
        run_id: "run-3",
        job_id: "job-3",
        event_type: "step.started",
        timestamp: 1_050,
        step_id: Some("step-a"),
        status: Some(RunStatus::Running),
        message: "Starting step A",
        data: {},
      },
      JobRunEvent::{
        run_id: "run-3",
        job_id: "job-3",
        event_type: "step.succeeded",
        timestamp: 1_120,
        step_id: Some("step-a"),
        status: Some(RunStatus::Succeeded),
        message: "Step A finished",
        data: {},
      },
    ],
    JobNotifyTarget::{
      channel_id: "feishu",
      account_id: "default",
      recipient: "oc_chat_1",
      thread_id: None,
      verbosity: NotificationVerbosity::Normal,
      heartbeat_interval_ms: 1_000,
      warn_after_ms: 10_000,
    },
    JobNotificationRuntimeState::{
      last_sent_at: 1_000,
      last_notified_event_count: 0,
      long_running_warned: false,
    },
    1_150,
  )
  inspect(decision.messages.length(), content="1")
  inspect(decision.messages[0].contains("Step started: step-a"), content="true")
  inspect(decision.next_state.last_notified_event_count, content="2")
}

///|
test "resolve_job_notify_target applies persisted preference overrides" {
  let store = SystemStore::new(root="unused")
  let definition = JobDefinition::{
    id: "job-1",
    kind: "job",
    enabled: true,
    config: {
      "notify": {
        "channel": "feishu",
        "account_id": "default",
        "to": "oc_chat_1",
        "heartbeat_interval_ms": 120000,
        "warn_after_ms": 300000,
      },
    },
    schedule: None,
    retry_policy: None,
    workflow_id: None,
    created_at: 1,
    updated_at: 1,
    tags: [],
  }
  store.notification_preferences.set("feishu:default:oc_chat_1", JobNotificationPreference::{
    id: "feishu:default:oc_chat_1",
    channel_id: "feishu",
    account_id: "default",
    recipient: "oc_chat_1",
    thread_id: None,
    verbosity: NotificationVerbosity::Verbose,
    heartbeat_interval_ms: Some(60_000),
    warn_after_ms: Some(180_000),
    created_at: 1,
    updated_at: 2,
  })
  let target = resolve_job_notify_target(store, definition)
  inspect(
    target.map(fn(t) { t.verbosity.to_json().stringify() }).unwrap_or(""),
    content="\"Verbose\"",
  )
  inspect(
    target.map(fn(t) { t.heartbeat_interval_ms.to_string() }).unwrap_or(""),
    content="60000",
  )
}

///|
test "parse_job_notify_target accepts legacy optional-json array encoding" {
  let target = parse_job_notify_target({
    "notify": {
      "channel": ["feishu"],
      "account_id": ["default"],
      "to": ["oc_chat_1"],
      "thread_id": ["thread_1"],
      "heartbeat_interval_ms": 1000,
      "warn_after_ms": 2000,
    },
  })
  guard target is Some(target) else {
    fail("Expected legacy encoded notify target to parse")
  }
  inspect(target.channel_id, content="feishu")
  inspect(target.account_id, content="default")
  inspect(target.recipient, content="oc_chat_1")
  inspect(target.thread_id.unwrap_or(""), content="thread_1")
  inspect(target.heartbeat_interval_ms, content="1000")
  inspect(target.warn_after_ms, content="2000")
}

///|
test "render_confirmed_job_reply includes title and created time" {
  let rendered = render_confirmed_job_reply(
    "20260320-track-vla-abc123", "Fetch Top 10 VLA Articles from arXiv", "2026-03-20 18:42:33",
    "job.proposal.20260320-track-vla-abc123", "run-20260320-184233-abc123", "topic_watch_controller",
  )
  inspect(
    rendered.contains("Title: Fetch Top 10 VLA Articles from arXiv"),
    content="true",
  )
  inspect(rendered.contains("Created: 2026-03-20 18:42:33"), content="true")
  inspect(
    rendered.contains("Created job `job.proposal.20260320-track-vla-abc123`"),
    content="true",
  )
}

///|
async test "save_job_notification_preference preserves created_at when updating" {
  @fsx.with_temporary_directory("job-chat-service-notify-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = SystemStore::new(root~)
    save_job_notification_preference(
      store,
      "feishu",
      "default",
      "oc_chat_1",
      None,
      NotificationVerbosity::Normal,
      100,
    )
    save_job_notification_preference(
      store,
      "feishu",
      "default",
      "oc_chat_1",
      None,
      NotificationVerbosity::Verbose,
      200,
      heartbeat_interval_ms=Some(30_000),
    )
    let pref = store.get_notification_preference("feishu:default:oc_chat_1")
    inspect(
      pref.map(fn(p) { p.created_at.to_string() }).unwrap_or(""),
      content="100",
    )
    inspect(
      pref.map(fn(p) { p.updated_at.to_string() }).unwrap_or(""),
      content="200",
    )
    inspect(
      pref.map(fn(p) { p.verbosity.to_json().stringify() }).unwrap_or(""),
      content="\"Verbose\"",
    )
  })
}

///|
async test "save_presented_job_proposal stores presented message id" {
  @fsx.with_temporary_directory("job-chat-service-proposal-save-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = SystemStore::new(root~)
    let proposal = JobProposal::{
      ..draft_job_proposal(
        "proposal-1", "Track important research papers.", 100,
      ),
      presented_message_id: None,
    }
    save_presented_job_proposal(store, proposal, "message-1")
    inspect(
      store
      .get_job_proposal("proposal-1")
      .map(fn(saved) { saved.presented_message_id.unwrap_or("") })
      .unwrap_or(""),
      content="message-1",
    )
  })
}

///|
test "resolve_target_proposal prefers explicit id and falls back to reply lookup" {
  let store = SystemStore::new(root="unused")
  let proposal = JobProposal::{
    ..draft_job_proposal("proposal-2", "Review yesterday's papers.", 100),
    presented_message_id: Some("message-2"),
  }
  store.proposals.set(proposal.id, proposal)
  inspect(
    resolve_target_proposal(store, "proposal-2", None)
    .map(fn(found) { found.id })
    .unwrap_or(""),
    content="proposal-2",
  )
  inspect(
    resolve_target_proposal(store, "", Some("message-2"))
    .map(fn(found) { found.id })
    .unwrap_or(""),
    content="proposal-2",
  )
  inspect(
    resolve_target_proposal(store, "", Some("missing")) is None,
    content="true",
  )
}

///|
test "proposal command render helpers produce expected text" {
  inspect(
    render_unknown_proposal_message("confirm"),
    content="Unknown proposal. Use `/confirm <proposal_id>` or reply `confirm` to a proposal message.",
  )
  inspect(
    render_confirm_proposal_failure("proposal-1", "boom"),
    content="Failed to confirm proposal proposal-1: boom",
  )
  inspect(
    render_rejected_job_reply("proposal-2"),
    content="Rejected proposal `proposal-2`.",
  )
  inspect(
    render_revise_usage(true),
    content="Usage: /revise <proposal_id> <extra guidance> or reply `revise <guidance>` to a proposal message.",
  )
  inspect(
    render_job_notify_usage(),
    content="Usage: /job-notify <off|normal|verbose>",
  )
  inspect(
    render_job_workspace_usage(),
    content="Usage: /job-workspace <job_id|run_id>",
  )
  inspect(
    render_job_notify_updated(NotificationVerbosity::Verbose),
    content="Job notifications set to \"Verbose\" for this chat scope.",
  )
}

///|
async test "dispatch_job_chat_action routes commands through callbacks" {
  inspect(
    dispatch_job_chat_action(
      Some(JobChatAction::Jobs),
      fn(_args) { "plan" },
      fn(_args) { "confirm" },
      fn(_args) { "reject" },
      fn(_args) { "revise" },
      fn(_args) { "status" },
      fn(_args) { "workspace" },
      fn() { "jobs" },
      fn(args, force) { "\{args}:\{force}" },
      fn(_args) { "notify" },
      fn(_args) { "remember" },
      fn() { "memories" },
      fn(_args) { "memory-search" },
    ).unwrap_or(""),
    content="jobs",
  )
  inspect(
    dispatch_job_chat_action(
      Some(JobChatAction::JobForceStop("run-1")),
      fn(_args) { "plan" },
      fn(_args) { "confirm" },
      fn(_args) { "reject" },
      fn(_args) { "revise" },
      fn(_args) { "status" },
      fn(_args) { "workspace" },
      fn() { "jobs" },
      fn(args, force) { "\{args}:\{force}" },
      fn(_args) { "notify" },
      fn(_args) { "remember" },
      fn() { "memories" },
      fn(_args) { "memory-search" },
    ).unwrap_or(""),
    content="run-1:true",
  )
  inspect(
    dispatch_job_chat_action(
      Some(JobChatAction::Remember("note")),
      fn(_args) { "plan" },
      fn(_args) { "confirm" },
      fn(_args) { "reject" },
      fn(_args) { "revise" },
      fn(_args) { "status" },
      fn(_args) { "workspace" },
      fn() { "jobs" },
      fn(args, force) { "\{args}:\{force}" },
      fn(_args) { "notify" },
      fn(args) { "remember:\{args}" },
      fn() { "memories" },
      fn(args) { "search:\{args}" },
    ).unwrap_or(""),
    content="remember:note",
  )
  inspect(
    dispatch_job_chat_action(
      Some(JobChatAction::Memories),
      fn(_args) { "plan" },
      fn(_args) { "confirm" },
      fn(_args) { "reject" },
      fn(_args) { "revise" },
      fn(_args) { "status" },
      fn(_args) { "workspace" },
      fn() { "jobs" },
      fn(args, force) { "\{args}:\{force}" },
      fn(_args) { "notify" },
      fn(_args) { "remember" },
      fn() { "memories" },
      fn(args) { "search:\{args}" },
    ).unwrap_or(""),
    content="memories",
  )
}
