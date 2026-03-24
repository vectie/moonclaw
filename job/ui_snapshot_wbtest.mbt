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
      profile_id: None,
      profile_role: None,
      profile_metadata: {},
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

///|
async test "build_job_ui_snapshot adds split and merge nodes for controller runs" {
  @fsx.with_temporary_directory("job-ui-controller-XXXXXX", dir => {
    let store = SystemStore::new(root=dir)
    let definition = JobDefinition::{
      id: "job-controller",
      kind: "job.controller",
      enabled: true,
      config: { "family": "opc_feature_sprint", "role": "controller" },
      schedule: None,
      retry_policy: None,
      workflow_id: Some("wf-controller"),
      created_at: 10,
      updated_at: 10,
      tags: [],
    }
    let workflow = WorkflowDefinition::{
      id: "wf-controller",
      kind: "job.controller",
      steps: [
        WorkflowStepDefinition::{
          id: "ceo_review",
          kind: "job.analysis",
          config: {},
          retry_policy: None,
        },
        WorkflowStepDefinition::{
          id: "implement",
          kind: "job.delegate",
          config: {},
          retry_policy: None,
        },
      ],
      output_bindings: [],
    }
    let run = JobRun::{
      id: "run-controller",
      job_id: "job-controller",
      trigger: Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: Some("/tmp/opc-ws"),
      status: Running,
      attempt: 1,
      retry_of: None,
      started_at: Some(100),
      completed_at: None,
      summary: Some("shipping feature"),
      error: None,
    }
    let child_run = JobRun::{
      id: "run-worker",
      job_id: "job-worker",
      trigger: Manual,
      parent_run_id: Some("run-controller"),
      parent_step_id: Some("implement"),
      depth: 1,
      workspace_dir: Some("/tmp/opc-worker"),
      status: Running,
      attempt: 1,
      retry_of: None,
      started_at: Some(120),
      completed_at: None,
      summary: Some("implementing"),
      error: None,
    }
    let worker_definition = JobDefinition::{
      id: "job-worker",
      kind: "job.proposal",
      enabled: true,
      config: {
        "family": "opc_impl_worker",
        "profile_metadata": { "worker_role": "implementation" },
      },
      schedule: None,
      retry_policy: None,
      workflow_id: None,
      created_at: 12,
      updated_at: 12,
      tags: [],
    }
    let artifact = ArtifactRecord::{
      id: "artifact-merge",
      run_id: "run-controller",
      job_id: "job-controller",
      artifact_type: "report",
      logical_key: Some("ship-brief"),
      version: 1,
      status: Active,
      path: "/tmp/opc-ws/ship.md",
      content_type: "text/markdown",
      metadata: {},
      created_at: 150,
      archived_at: None,
      scope: [],
    }
    store.save_definition(definition)
    store.save_definition(worker_definition)
    store.save_workflow(workflow)
    store.save_run(run)
    store.save_run(child_run)
    store.save_controller_state(JobControllerState::{
      controller_job_id: "job-controller",
      controller_run_id: "run-controller",
      family: "opc_feature_sprint",
      profile_id: Some("opc_feature_sprint"),
      objective: "Ship the feature",
      active_iteration_ids: [
        "run-controller:iter:root", "run-controller:iter:implement",
      ],
      accepted_iteration_ids: ["run-controller:iter:implement"],
      rejected_iteration_ids: [],
      best_iteration_id: Some("run-controller:iter:implement"),
      frontier: ["run-controller:iter:implement"],
      metadata: {},
      created_at: 101,
      updated_at: 170,
    })
    store.save_controller_decision(JobControllerDecision::{
      id: "decision-1",
      controller_job_id: "job-controller",
      controller_run_id: "run-controller",
      iteration_id: "run-controller:iter:implement",
      step_id: "implement",
      verdict: "accept",
      reason: Some("ready to ship"),
      next_action: Some("merge"),
      metadata: {},
      created_at: 171,
      updated_at: 171,
    })
    store.save_artifact(artifact)

    let snapshot = build_job_ui_snapshot(store, "run-controller").unwrap()
    let kinds = snapshot.nodes.map(fn(node) { node.kind.to_json().stringify() })
    json_inspect(kinds, content=[
      "\"Workflow\"", "\"Split\"", "\"Step\"", "\"Step\"", "\"ChildRun\"", "\"Merge\"",
      "\"Artifact\"",
    ])
    let split = snapshot.nodes.filter(fn(node) {
        node.kind.to_json().stringify() == "\"Split\""
      })[0]
    let merge = snapshot.nodes.filter(fn(node) {
        node.kind.to_json().stringify() == "\"Merge\""
      })[0]
    json_inspect(split.status, content="\"Running\"")
    json_inspect(
      split.summary.unwrap_or(""),
      content="1 delegated steps · 1 worker runs · 1 active",
    )
    json_inspect(merge.status, content="\"Running\"")
    json_inspect(
      merge.summary.unwrap_or(""),
      content="1 accepted · 1 decisions · 1 artifacts · shipping feature",
    )
    let implement = snapshot.nodes.filter(fn(node) {
        node.step_id == Some("implement")
      })[0]
    json_inspect(
      implement.parent_id.unwrap_or(""),
      content="split:run-controller",
    )
    let artifact_node = snapshot.nodes.filter(fn(node) {
        node.artifact_id == Some("artifact-merge")
      })[0]
    let child_node = snapshot.nodes.filter(fn(node) {
        node.run_id == Some("run-worker")
      })[0]
    json_inspect(
      artifact_node.parent_id.unwrap_or(""),
      content="merge:run-controller",
    )
    json_inspect(child_node.metadata, content={
      "depth": 1,
      "job_id": "job-worker",
      "parent_run_id": "run-controller",
      "family": "opc_impl_worker",
      "role": null,
      "worker_role": "implementation",
    })
  })
}
