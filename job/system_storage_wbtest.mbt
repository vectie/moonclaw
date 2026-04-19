///|
fn sample_definition() -> JobDefinition {
  JobDefinition::{
    id: "job.sample.sync",
    kind: "job.sample.sync",
    enabled: true,
    config: { "query": "llm agents", "limit": 20 },
    schedule: Some(SchedulePolicy::{
      kind: "interval",
      interval_minutes: Some(360),
      timezone: Some("Asia/Shanghai"),
    }),
    retry_policy: Some(RetryPolicy::{ max_attempts: 2, backoff_ms: Some(5000) }),
    workflow_id: Some("job.sample.workflow"),
    created_at: 1,
    updated_at: 2,
    tags: ["job", "monitoring"],
  }
}

///|
fn sample_workflow() -> WorkflowDefinition {
  WorkflowDefinition::{
    id: "job.sample.workflow",
    kind: "job",
    steps: [
      WorkflowStepDefinition::{
        id: "fetch",
        kind: "job.analysis",
        config: { "source": "arxiv" },
        retry_policy: Some(RetryPolicy::{
          max_attempts: 2,
          backoff_ms: Some(5000),
        }),
      },
      WorkflowStepDefinition::{
        id: "parse",
        kind: "job.analysis",
        config: {},
        retry_policy: None,
      },
    ],
    output_bindings: ["papers", "chunks"],
  }
}

///|
fn sample_delegate_definition() -> JobDefinition {
  JobDefinition::{
    ..sample_definition(),
    id: "job.sample.delegate",
    workflow_id: Some("job.sample.delegate.workflow"),
  }
}

///|
fn sample_delegate_workflow() -> WorkflowDefinition {
  WorkflowDefinition::{
    id: "job.sample.delegate.workflow",
    kind: "job",
    steps: [
      WorkflowStepDefinition::{
        id: "delegate",
        kind: "job.delegate",
        config: {},
        retry_policy: None,
      },
    ],
    output_bindings: [],
  }
}

///|
fn sample_run() -> JobRun {
  JobRun::{
    id: "run-1",
    job_id: "job.sample.sync",
    trigger: TriggerSource::Manual,
    parent_run_id: None,
    parent_step_id: None,
    depth: 0,
    workspace_dir: None,
    status: RunStatus::Running,
    attempt: 1,
    retry_of: None,
    started_at: Some(10),
    finished_at: None,
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
    finished_at: Some(12),
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
    job_id: "job.sample.sync",
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
    scope: ["job", "paper:2501.01234v1"],
  }
}

///|
fn sample_memory() -> MemoryRecord {
  MemoryRecord::{
    id: "memory-1",
    kind: "note",
    title: Some("daily digest"),
    content: "Remember to review VLA benchmarks in daily digests.",
    metadata: { "importance": "high" },
    tags: ["job", "digest"],
    scope: ["workspace:main", "job"],
    workspace: Some("/tmp/workspace"),
    agent_id: Some("main"),
    channel_id: Some("feishu"),
    account_id: Some("default"),
    recipient: Some("oc_chat_123"),
    thread_id: None,
    source_artifact_id: Some("artifact-1"),
    status: MemoryStatus::Active,
    created_at: 14,
    updated_at: 14,
    archived_at: None,
  }
}

///|
fn sample_proposal() -> JobProposal {
  JobProposal::{
    id: "proposal-1",
    title: "Track recent agent papers",
    request_text: "Track recent agent papers and summarize findings.",
    summary: "Draft proposal for job tracking.",
    revision_history: [],
    suggested_family: Some("generic"),
    profile_id: None,
    profile_role: None,
    profile_metadata: {},
    status: JobProposalStatus::Draft,
    steps: [
      JobProposalStep::{
        id: "collect",
        title: "Collect sources",
        prompt: "Collect relevant papers.",
        kind: "job.analysis",
        metadata: {},
        child_profile: None,
        execution_mode: None,
        execution_target: None,
        include_parent_outputs: None,
        max_depth: None,
      },
    ],
    tags: ["job", "monitoring"],
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
    let memory = sample_memory()

    store.save_definition(definition)
    store.save_workflow(workflow)
    store.save_run(run)
    store.save_step_run(step)
    store.save_artifact(artifact)
    store.save_memory(memory)

    let reloaded = SystemStore::new(root~)
    reloaded.load()

    inspect(reloaded.list_definitions().length(), content="1")
    inspect(reloaded.list_workflows().length(), content="1")
    inspect(reloaded.list_runs().length(), content="1")
    inspect(reloaded.list_step_runs("run-1").length(), content="1")
    inspect(reloaded.list_artifacts().length(), content="1")
    inspect(reloaded.list_memories().length(), content="1")
    inspect(
      reloaded
      .get_definition("job.sample.sync")
      .map(fn(d) { d.kind })
      .unwrap_or(""),
      content="job.sample.sync",
    )
    inspect(
      reloaded
      .get_workflow("job.sample.workflow")
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
    inspect(
      reloaded
      .get_memory("memory-1")
      .map(fn(memory) { memory.kind })
      .unwrap_or(""),
      content="note",
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
        |> @pathx.join(safe_step_file_segment("fetch") + ".json"),
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
      job_id: "job.sample.sync",
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

///|
async test "SystemStore reconciles stale running delegate parent from terminal child run" {
  @fsx.with_temporary_directory("job-system-reconcile-parent-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = SystemStore::new(root~)
    let definition = sample_delegate_definition()
    let workflow = sample_delegate_workflow()
    let parent_run = JobRun::{
      ..sample_run(),
      id: "run-parent",
      job_id: definition.id,
    }
    let parent_step = JobStepRun::{
      ..sample_step_run(),
      id: "run-parent:delegate",
      run_id: "run-parent",
      step_id: "delegate",
      status: RunStatus::Running,
      finished_at: None,
      summary: None,
      output: None,
      error: None,
    }
    let child_run = JobRun::{
      ..sample_run(),
      id: "run-child",
      job_id: "job.child",
      trigger: TriggerSource::Custom("subjob"),
      parent_run_id: Some("run-parent"),
      parent_step_id: Some("delegate"),
      depth: 1,
      status: RunStatus::Succeeded,
      finished_at: Some(33),
      summary: Some("done"),
    }

    store.save_definition(definition)
    store.save_workflow(workflow)
    store.save_run(parent_run)
    store.save_step_run(parent_step)
    store.save_run(child_run)

    let reloaded = SystemStore::new(root~)
    reloaded.load()

    inspect(
      reloaded
      .get_run("run-parent")
      .map(fn(run) { run.status.to_json().stringify() })
      .unwrap_or(""),
      content="\"Succeeded\"",
    )
    inspect(
      reloaded
      .get_step_run("run-parent", "delegate")
      .map(fn(step) { step.status.to_json().stringify() })
      .unwrap_or(""),
      content="\"Succeeded\"",
    )
    inspect(
      reloaded
      .get_step_run("run-parent", "delegate")
      .bind(fn(step) { step.output })
      .map(fn(output) {
        output.stringify().contains("\"child_run_id\":\"run-child\"")
      })
      .unwrap_or(false),
      content="true",
    )
  })
}

///|
async test "SystemStore shortens step file names for long step ids" {
  @fsx.with_temporary_directory("job-system-long-step-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = SystemStore::new(root~)
    store.save_run(sample_run())
    let long_step_id = "goal-run-the-domain-local-ingest-extension-for-this-request-request-load-skills-wiki-ingest-skill-md-inspect-raw-wiki-sources-and-wiki-synthesis-maintenance-plan-md-then-bootstrap-durable-book-coverage-for-the-goal-discover-or-stage-high-signal-sources-populate-maintained-source-pages-and-revise-the-wiki-so-later-synthesis-can-cite-durable-pages-research-moontown-moonbook-and-moonclaw-the-extension-owns-source-discovery-durable-wiki-updates-and-readiness-signals-ingest-followup"
    store.save_step_run(JobStepRun::{
      id: "step-run-long",
      run_id: "run-1",
      step_id: long_step_id,
      status: RunStatus::Failed,
      started_at: Some(11),
      finished_at: Some(12),
      metrics: {},
      logs: ["failed"],
      retry_count: 0,
      summary: Some("failed"),
      output: None,
      error: Some("boom"),
    })

    let step_file = safe_step_file_segment(long_step_id) + ".json"
    inspect(step_file.length() < 100, content="true")
    inspect(
      @fsx.exists(
        root
        |> @pathx.join("runs")
        |> @pathx.join("run-1")
        |> @pathx.join("steps")
        |> @pathx.join(step_file),
      ),
      content="true",
    )

    let reloaded = SystemStore::new(root~)
    reloaded.load()
    inspect(
      reloaded
      .get_step_run("run-1", long_step_id)
      .map(fn(step) { step.step_id == long_step_id })
      .unwrap_or(false),
      content="true",
    )
  })
}

///|
async test "SystemStore merges run index across concurrent store instances" {
  @fsx.with_temporary_directory("job-system-merge-runs-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store_a = SystemStore::new(root~)
    let store_b = SystemStore::new(root~)
    let run_a = JobRun::{ ..sample_run(), id: "run-a", job_id: "job-a" }
    let run_b = JobRun::{
      ..sample_run(),
      id: "run-b",
      job_id: "job-b",
      status: RunStatus::Succeeded,
      finished_at: Some(20),
      summary: Some("done"),
    }
    let step_a = JobStepRun::{
      ..sample_step_run(),
      id: "step-a",
      run_id: "run-a",
    }
    let step_b = JobStepRun::{
      ..sample_step_run(),
      id: "step-b",
      run_id: "run-b",
    }

    store_a.save_run(run_a)
    store_a.save_step_run(step_a)
    store_b.save_run(run_b)
    store_b.save_step_run(step_b)

    let reloaded = SystemStore::new(root~)
    reloaded.load()

    inspect(reloaded.list_runs().length(), content="2")
    inspect(reloaded.list_step_runs("run-a").length(), content="1")
    inspect(reloaded.list_step_runs("run-b").length(), content="1")
    inspect(
      reloaded
      .get_run("run-b")
      .map(fn(run) { run.status.to_json().stringify() })
      .unwrap_or(""),
      content="\"Succeeded\"",
    )
  })
}

///|
async test "SystemStore rebuilds runs index from run metadata when runs index is malformed" {
  @fsx.with_temporary_directory("job-system-rebuild-runs-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = SystemStore::new(root~)

    store.save_run(sample_run())
    store.save_step_run(sample_step_run())
    @fsx.write_to_file(
      root |> @pathx.join("index") |> @pathx.join("runs.json"),
      "{",
    )

    let reloaded = SystemStore::new(root~)
    reloaded.load()

    inspect(reloaded.list_runs().length(), content="1")
    inspect(reloaded.list_step_runs("run-1").length(), content="1")
    inspect(
      reloaded
      .get_run("run-1")
      .map(fn(run) { run.status.to_json().stringify() })
      .unwrap_or(""),
      content="\"Running\"",
    )
    inspect(
      reloaded
      .get_step_run("run-1", "fetch")
      .map(fn(step) { step.status.to_json().stringify() })
      .unwrap_or(""),
      content="\"Succeeded\"",
    )
  })
}

///|
async test "SystemStore rebuilds missing runs index from per-run metadata" {
  @fsx.with_temporary_directory("job-system-missing-runs-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = SystemStore::new(root~)

    store.save_run(sample_run())
    store.save_step_run(sample_step_run())
    @fsx.remove(root |> @pathx.join("index") |> @pathx.join("runs.json"))

    let reloaded = SystemStore::new(root~)
    reloaded.load()

    inspect(reloaded.list_runs().length(), content="1")
    inspect(reloaded.list_step_runs("run-1").length(), content="1")
    inspect(
      reloaded
      .get_run("run-1")
      .map(fn(run) { run.status.to_json().stringify() })
      .unwrap_or(""),
      content="\"Running\"",
    )
    inspect(
      @fsx.exists(root |> @pathx.join("index") |> @pathx.join("runs.json")),
      content="true",
    )
  })
}

///|
async test "SystemStore prefers per-run metadata over a stale but valid runs index" {
  @fsx.with_temporary_directory("job-system-stale-runs-index-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = SystemStore::new(root~)

    let stale_run = sample_run()
    let authoritative_run = JobRun::{
      ..sample_run(),
      status: RunStatus::Failed,
      finished_at: Some(22),
      summary: Some("crashed"),
      error: Some("disk truth"),
    }
    let stale_step = JobStepRun::{
      ..sample_step_run(),
      status: RunStatus::Running,
    }
    let authoritative_step = JobStepRun::{
      ..sample_step_run(),
      status: RunStatus::Succeeded,
      summary: Some("authoritative"),
    }

    store.save_run(authoritative_run)
    store.save_step_run(authoritative_step)
    @fsx.write_to_file(
      root |> @pathx.join("index") |> @pathx.join("runs.json"),
      RunsIndexFile::{ runs: [stale_run], steps: [stale_step] }
      .to_json()
      .stringify(),
    )

    let reloaded = SystemStore::new(root~)
    reloaded.load()

    inspect(
      reloaded
      .get_run("run-1")
      .map(fn(run) { run.status.to_json().stringify() })
      .unwrap_or(""),
      content="\"Failed\"",
    )
    inspect(
      reloaded
      .get_run("run-1")
      .map(fn(run) { run.error.unwrap_or("") })
      .unwrap_or(""),
      content="disk truth",
    )
    inspect(
      reloaded
      .get_step_run("run-1", "fetch")
      .map(fn(step) { step.status.to_json().stringify() })
      .unwrap_or(""),
      content="\"Succeeded\"",
    )
  })
}
