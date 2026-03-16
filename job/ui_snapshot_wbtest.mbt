///|
async test "build_job_ui_snapshot includes proposal workflow steps child runs and timeline" {
  @fsx.with_temporary_directory("job-ui-snapshot-XXXXXX", dir => {
    let store = SystemStore::new(root=dir)
    let definition = JobDefinition::{
      id: "job-1",
      kind: "job.proposal",
      enabled: true,
      config: { "family": "generic" },
      schedule: None,
      retry_policy: None,
      workflow_id: Some("wf-1"),
      created_at: 10,
      updated_at: 10,
      tags: [],
    }
    let workflow = WorkflowDefinition::{
      id: "wf-1",
      kind: "job.proposal",
      steps: [
        WorkflowStepDefinition::{
          id: "step-a",
          kind: "job.analysis",
          config: {},
          retry_policy: None,
        },
        WorkflowStepDefinition::{
          id: "step-b",
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
      trigger: Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: Some("/tmp/ws-1"),
      status: Running,
      attempt: 1,
      retry_of: None,
      started_at: Some(100),
      completed_at: None,
      summary: Some("watching"),
      error: None,
    }
    let child_run = JobRun::{
      id: "run-2",
      job_id: "job-1",
      trigger: Manual,
      parent_run_id: Some("run-1"),
      parent_step_id: Some("step-b"),
      depth: 1,
      workspace_dir: Some("/tmp/ws-2"),
      status: Pending,
      attempt: 1,
      retry_of: None,
      started_at: None,
      completed_at: None,
      summary: None,
      error: None,
    }
    let step_run = JobStepRun::{
      id: "run-1:step-a",
      run_id: "run-1",
      step_id: "step-a",
      status: Succeeded,
      started_at: Some(110),
      completed_at: Some(130),
      metrics: {},
      logs: [],
      retry_count: 0,
      summary: Some("synced"),
      output: Some({ "papers": 3 }),
      error: None,
    }
    let artifact = ArtifactRecord::{
      id: "artifact-1",
      run_id: "run-1",
      job_id: "job-1",
      artifact_type: "report",
      logical_key: Some("daily"),
      version: 1,
      status: Active,
      path: "/tmp/ws-1/report.md",
      content_type: "text/markdown",
      metadata: {},
      created_at: 140,
      archived_at: None,
      scope: [],
    }
    let memory = MemoryRecord::{
      id: "memory-1",
      kind: "job.summary",
      title: Some("summary"),
      content: "done",
      metadata: {},
      tags: [],
      scope: [],
      workspace: Some("/tmp/ws-1"),
      agent_id: None,
      channel_id: None,
      account_id: None,
      recipient: None,
      thread_id: None,
      source_artifact_id: Some("artifact-1"),
      status: Active,
      created_at: 150,
      updated_at: 150,
      archived_at: None,
    }
    let proposal = JobProposal::{
      id: "proposal-1",
      title: "Daily VLA Review",
      request_text: "watch papers",
      summary: "summary",
      revision_history: [],
      suggested_family: Some("generic"),
      status: Confirmed,
      steps: [],
      tags: [],
      channel_id: None,
      account_id: None,
      recipient: None,
      thread_id: None,
      presented_message_id: None,
      job_id: Some("job-1"),
      workflow_id: Some("wf-1"),
      last_run_id: Some("run-1"),
      created_at: 90,
      updated_at: 100,
    }
    store.save_definition(definition)
    store.save_workflow(workflow)
    store.save_run(run)
    store.save_run(child_run)
    store.save_step_run(step_run)
    store.save_artifact(artifact)
    store.save_memory(memory)
    store.save_job_proposal(proposal)
    store.append_run_event(JobRunEvent::{
      run_id: "run-1",
      job_id: "job-1",
      event_type: "step.started",
      timestamp: 111,
      step_id: Some("step-a"),
      status: Some(Running),
      message: "started",
      data: {},
    })

    let snapshot = build_job_ui_snapshot(store, "run-1").unwrap()
    json_inspect(snapshot.current_step_id.unwrap_or(""), content="step-a")
    json_inspect(snapshot.child_runs.length(), content=1)
    json_inspect(snapshot.artifacts.length(), content=1)
    json_inspect(snapshot.memories.length(), content=1)
    json_inspect(snapshot.linked_remote.length(), content=0)
    json_inspect(snapshot.handoffs.length(), content=0)
    json_inspect(snapshot.timeline.length(), content=1)
    json_inspect(
      snapshot.nodes.map(fn(node) { node.kind.to_json().stringify() }),
      content=[
        "\"Proposal\"", "\"Workflow\"", "\"Step\"", "\"Step\"", "\"ChildRun\"", "\"Artifact\"",
        "\"Memory\"",
      ],
    )
  })
}

///|
async test "build_job_ui_snapshot includes explicit handoffs when provided" {
  @fsx.with_temporary_directory("job-ui-handoffs-XXXXXX", dir => {
    let store = SystemStore::new(root=dir)
    let definition = JobDefinition::{
      id: "job-1",
      kind: "analysis",
      enabled: true,
      config: {},
      schedule: None,
      retry_policy: None,
      workflow_id: Some("wf-1"),
      created_at: 10,
      updated_at: 10,
      tags: [],
    }
    let workflow = WorkflowDefinition::{
      id: "wf-1",
      kind: "analysis",
      steps: [
        WorkflowStepDefinition::{
          id: "step-a",
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
      trigger: Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: None,
      status: Running,
      attempt: 1,
      retry_of: None,
      started_at: Some(100),
      completed_at: None,
      summary: None,
      error: None,
    }
    store.save_definition(definition)
    store.save_workflow(workflow)
    store.save_run(run)
    let snapshot = build_job_ui_snapshot(
      store,
      "run-1",
      linked_remote=[
        JobUiRemoteLink::{
          id: "acp-run:remote-1",
          kind: "acp_run",
          title: "remote-1",
          status: "running",
          summary: Some("working"),
          detail: None,
          metadata: {},
        },
      ],
      handoffs=[
        JobUiHandoff::{
          node_id: "step:run-1:step-a",
          step_id: Some("step-a"),
          remote: [
            JobUiRemoteLink::{
              id: "acp-run:remote-1",
              kind: "acp_run",
              title: "remote-1",
              status: "running",
              summary: Some("working"),
              detail: None,
              metadata: {},
            },
          ],
        },
      ],
    ).unwrap()
    json_inspect(snapshot.handoffs.length(), content=1)
    json_inspect(snapshot.handoffs[0].node_id, content="step:run-1:step-a")
    json_inspect(snapshot.handoffs[0].step_id.unwrap_or(""), content="step-a")
    json_inspect(snapshot.handoffs[0].remote[0].id, content="acp-run:remote-1")
    json_inspect(snapshot.timeline.length(), content=1)
    json_inspect(snapshot.timeline[0].event_type, content="remote.handoff")
    json_inspect(snapshot.timeline[0].step_id.unwrap_or(""), content="step-a")
  })
}
