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
    path: root
    |> @pathx.join("artifacts")
    |> @pathx.join("artifact-1")
    |> @pathx.join("meta.json"),
    metadata: { "paper_id": "2501.01234v1" },
    created_at: 13,
    scope: ["research", "paper:2501.01234v1"],
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
