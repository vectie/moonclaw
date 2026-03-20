///|
async test "render_job_status_command_reply resolves run targets" {
  let store = SystemStore::new(root="unused")
  let definition = JobDefinition::{
    id: "job-1",
    kind: "job.proposal",
    enabled: true,
    config: { "family": "generic" },
    schedule: None,
    retry_policy: None,
    workflow_id: Some("workflow-1"),
    created_at: 1,
    updated_at: 1,
    tags: [],
  }
  let workflow = WorkflowDefinition::{
    id: "workflow-1",
    kind: "job.proposal",
    steps: [
      WorkflowStepDefinition::{
        id: "step-1",
        kind: "job.analysis",
        config: {},
        retry_policy: None,
      },
      WorkflowStepDefinition::{
        id: "step-2",
        kind: "job.analysis",
        config: {},
        retry_policy: None,
      },
    ],
    output_bindings: [],
  }
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
    started_at: Some(10),
    completed_at: None,
    summary: None,
    error: None,
  }
  store.save_definition(definition)
  store.save_workflow(workflow)
  store.save_run(run)
  let created_at = format_job_timestamp(1)
  let expected = "Current job status: job-1\n" +
    "Title: job-1\n" +
    "Created: \{created_at}\n" +
    "Run: run-1\n" +
    "Status: \"Running\"\n" +
    "Family: generic\n" +
    "Current step: step-1\n" +
    "Progress: 0/2\n" +
    "Elapsed: 90ms\n" +
    "Latest event: none\n" +
    "Use `/job-status job-1` for a fresh status check."
  inspect(
    render_job_status_command_reply(store, "job-1", 100, "Current job status").unwrap_or(
      "",
    ),
    content=expected,
  )
}

///|
async test "request_job_stop resolves run ids before calling cancel" {
  let store = SystemStore::new(root="unused")
  let definition = JobDefinition::{
    id: "job-1",
    kind: "generic",
    enabled: true,
    config: {},
    schedule: None,
    retry_policy: None,
    workflow_id: Some("workflow-1"),
    created_at: 1,
    updated_at: 1,
    tags: [],
  }
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
    started_at: Some(10),
    completed_at: None,
    summary: None,
    error: None,
  }
  store.save_definition(definition)
  store.save_run(run)
  let cancelled : Array[String] = []
  let result = request_job_stop(store, "run-1", fn(job_id, force) {
    cancelled.push("\{job_id}:\{force}")
    Ok(run)
  })
  inspect(
    match result {
      Ok(text) => text
      Err(error) => error
    },
    content="Stop requested for `job-1` (`run-1`).",
  )
  inspect(cancelled.join(","), content="job-1:false")
}

///|
async test "render_job_workspace_command_reply shows workspace path" {
  @fsx.with_temporary_directory("job-workspace-status-XXXXXX", async fn(dir) {
    let workspace_root = dir |> @pathx.join("workspace")
    ignore(@workspace.load_workspace_snapshot_from_root(workspace_root))
    let store = SystemStore::new(root=dir |> @pathx.join("jobs"))
    let definition = JobDefinition::{
      id: "job-1",
      kind: "generic",
      enabled: true,
      config: { "workspace": workspace_root },
      schedule: None,
      retry_policy: None,
      workflow_id: None,
      created_at: 1,
      updated_at: 1,
      tags: [],
    }
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
      started_at: Some(10),
      completed_at: None,
      summary: None,
      error: None,
    }
    store.save_definition(definition)
    store.save_run(run)
    let prepared = prepare_run_workspace(store, definition, run)
    inspect(prepared.workspace_dir is Some(_), content="true")
    let reply = render_job_workspace_command_reply(store, "run-1").unwrap_or("")
    inspect(reply.contains("Job workspace: job-1"), content="true")
    inspect(reply.contains("Recent commits:"), content="true")
  })
}
