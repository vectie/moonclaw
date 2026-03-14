///|
fn sample_definition() -> JobDefinition {
  JobDefinition::{
    id: "research.topic.sync",
    kind: "research.topic.sync",
    enabled: true,
    config: { "query": "llm agents", "limit": 20 },
    schedule: Some(SchedulePolicy::{
      kind: "interval",
      interval_minutes: Some(360),
      timezone: Some("Asia/Shanghai"),
    }),
    retry_policy: Some(RetryPolicy::{ max_attempts: 2, backoff_ms: Some(5000) }),
    workflow_id: Some("research.sync.default"),
    created_at: 1,
    updated_at: 2,
    tags: ["research", "arxiv"],
  }
}

///|
fn sample_workflow() -> WorkflowDefinition {
  WorkflowDefinition::{
    id: "research.sync.default",
    kind: "research",
    steps: [
      WorkflowStepDefinition::{
        id: "fetch",
        kind: "research.paper.fetch",
        config: { "source": "arxiv" },
        retry_policy: Some(RetryPolicy::{
          max_attempts: 2,
          backoff_ms: Some(5000),
        }),
      },
      WorkflowStepDefinition::{
        id: "parse",
        kind: "research.paper.parse",
        config: {},
        retry_policy: None,
      },
    ],
    output_bindings: ["papers", "chunks"],
  }
}

///|
fn sample_run() -> JobRun {
  JobRun::{
    id: "run-1",
    job_id: "research.topic.sync",
    trigger: TriggerSource::Manual,
    status: RunStatus::Running,
    attempt: 1,
    retry_of: None,
    started_at: Some(10),
    completed_at: None,
    summary: None,
    error: None,
  }
}

///|
fn sample_step_run() -> JobStepRun {
  JobStepRun::{
    id: "step-run-1",
    run_id: "run-1",
    step_id: "fetch",
    status: RunStatus::Succeeded,
    started_at: Some(11),
    completed_at: Some(12),
    metrics: { "paper_count": 4 },
    logs: ["started", "finished"],
    retry_count: 0,
    summary: Some("fetched"),
    output: Some({ "papers": 4 }),
    error: None,
  }
}

///|
fn sample_artifact(root : String) -> ArtifactRecord {
  ArtifactRecord::{
    id: "artifact-1",
    run_id: "run-1",
    job_id: "research.topic.sync",
    artifact_type: "paper.meta",
    logical_key: Some("paper:2501.01234v1"),
    version: 1,
    status: ArtifactStatus::Active,
    path: root
    |> @pathx.join("artifacts")
    |> @pathx.join("artifact-1")
    |> @pathx.join("meta.json"),
    content_type: "application/json",
    metadata: { "paper_id": "2501.01234v1" },
    created_at: 13,
    archived_at: None,
    scope: ["research", "paper:2501.01234v1"],
  }
}

///|
fn sample_proposal() -> JobProposal {
  JobProposal::{
    id: "proposal-1",
    title: "Track recent agent papers",
    request_text: "Track recent agent papers and summarize findings.",
    summary: "Draft proposal for research tracking.",
    status: JobProposalStatus::Draft,
    steps: [
      JobProposalStep::{
        id: "collect",
        title: "Collect sources",
        prompt: "Collect relevant papers.",
        kind: "job.analysis",
      },
    ],
    tags: ["job", "research"],
    channel_id: Some("feishu"),
    account_id: Some("default"),
    recipient: Some("oc_chat_123"),
    thread_id: None,
    presented_message_id: Some("message-1"),
    job_id: None,
    workflow_id: None,
    last_run_id: None,
    created_at: 20,
    updated_at: 20,
  }
}

///|
async test "SystemStore persists definitions workflows runs steps and artifacts" {
  @fsx.with_temporary_directory("job-system-store-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = SystemStore::new(root~)
    let definition = sample_definition()
    let workflow = sample_workflow()
    let run = sample_run()
    let step = sample_step_run()
    let artifact = sample_artifact(root)

    store.save_definition(definition)
    store.save_workflow(workflow)
    store.save_run(run)
    store.save_step_run(step)
    store.save_artifact(artifact)

    let reloaded = SystemStore::new(root~)
    reloaded.load()

    inspect(reloaded.list_definitions().length(), content="1")
    inspect(reloaded.list_workflows().length(), content="1")
    inspect(reloaded.list_runs().length(), content="1")
    inspect(reloaded.list_step_runs("run-1").length(), content="1")
    inspect(reloaded.list_artifacts().length(), content="1")
    inspect(
      reloaded
      .get_definition("research.topic.sync")
      .map(fn(d) { d.kind })
      .unwrap_or(""),
      content="research.topic.sync",
    )
    inspect(
      reloaded
      .get_workflow("research.sync.default")
      .map(fn(w) { w.steps.length() })
      .unwrap_or(0),
      content="2",
    )
    inspect(
      reloaded
      .get_run("run-1")
      .map(fn(r) { r.status.to_json().stringify() })
      .unwrap_or(""),
      content="\"Running\"",
    )
    inspect(
      reloaded
      .get_step_run("run-1", "fetch")
      .map(fn(s) { s.retry_count })
      .unwrap_or(-1),
      content="0",
    )
    inspect(
      reloaded
      .get_artifact("artifact-1")
      .map(fn(a) { a.artifact_type })
      .unwrap_or(""),
      content="paper.meta",
    )
  })
}

///|
async test "SystemStore keeps indexes and per-run files in expected layout" {
  @fsx.with_temporary_directory("job-system-layout-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = SystemStore::new(root~)
    let run = sample_run()
    let step = sample_step_run()
    let artifact = sample_artifact(root)

    store.save_definition(sample_definition())
    store.save_workflow(sample_workflow())
    store.save_run(run)
    store.save_step_run(step)
    store.save_artifact(artifact)

    inspect(
      @fsx.exists(root |> @pathx.join("definitions.json")),
      content="true",
    )
    inspect(
      @fsx.exists(root |> @pathx.join("index") |> @pathx.join("runs.json")),
      content="true",
    )
    inspect(
      @fsx.exists(root |> @pathx.join("index") |> @pathx.join("artifacts.json")),
      content="true",
    )
    inspect(
      @fsx.exists(
        root
        |> @pathx.join("runs")
        |> @pathx.join("run-1")
        |> @pathx.join("meta.json"),
      ),
      content="true",
    )
    inspect(
      @fsx.exists(
        root
        |> @pathx.join("runs")
        |> @pathx.join("run-1")
        |> @pathx.join("steps")
        |> @pathx.join("fetch.json"),
      ),
      content="true",
    )
    inspect(
      @fsx.exists(
        root
        |> @pathx.join("artifacts")
        |> @pathx.join("artifact-1")
        |> @pathx.join("record.json"),
      ),
      content="true",
    )
  })
}

///|
async test "SystemStore persists job proposals and run events" {
  @fsx.with_temporary_directory("job-system-proposals-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = SystemStore::new(root~)
    let proposal = sample_proposal()

    store.save_job_proposal(proposal)
    store.append_run_event(JobRunEvent::{
      run_id: "run-1",
      job_id: "research.topic.sync",
      event_type: "job.started",
      timestamp: 30,
      step_id: None,
      status: Some(RunStatus::Running),
      message: "Run started",
      data: {},
    })

    let reloaded = SystemStore::new(root~)
    reloaded.load()

    inspect(reloaded.list_job_proposals().length(), content="1")
    inspect(
      reloaded
      .get_job_proposal("proposal-1")
      .map(fn(p) { p.title })
      .unwrap_or(""),
      content="Track recent agent papers",
    )
    inspect(
      reloaded
      .find_job_proposal_by_message_id("message-1")
      .map(fn(p) { p.id })
      .unwrap_or(""),
      content="proposal-1",
    )
    inspect(reloaded.list_run_events("run-1").length(), content="1")
    inspect(
      reloaded.list_run_events("run-1")[0].event_type,
      content="job.started",
    )
    inspect(
      @fsx.exists(
        root
        |> @pathx.join("runs")
        |> @pathx.join("run-1")
        |> @pathx.join("events.jsonl"),
      ),
      content="true",
    )
  })
}

///|
async test "SystemStore persists notification preferences" {
  @fsx.with_temporary_directory("job-system-notify-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = SystemStore::new(root~)
    store.save_notification_preference(JobNotificationPreference::{
      id: "feishu:default:oc_chat_123",
      channel_id: "feishu",
      account_id: "default",
      recipient: "oc_chat_123",
      thread_id: None,
      verbosity: NotificationVerbosity::Verbose,
      heartbeat_interval_ms: Some(60_000),
      warn_after_ms: Some(180_000),
      created_at: 50,
      updated_at: 55,
    })

    let reloaded = SystemStore::new(root~)
    reloaded.load()

    inspect(reloaded.list_notification_preferences().length(), content="1")
    inspect(
      reloaded
      .get_notification_preference("feishu:default:oc_chat_123")
      .map(fn(pref) { pref.verbosity.to_json().stringify() })
      .unwrap_or(""),
      content="\"Verbose\"",
    )
  })
}
