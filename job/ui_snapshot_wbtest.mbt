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
      metadata: { "step_id": "step-a" },
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
    let artifact_node = snapshot.nodes.filter(fn(node) {
        node.artifact_id == Some("artifact-1")
      })[0]
    json_inspect(
      artifact_node.parent_id.unwrap_or(""),
      content="step:run-1:step-a",
    )
    json_inspect(artifact_node.step_id.unwrap_or(""), content="step-a")
  })
}

///|
async test "artifact nodes surface execution isolation cleanup policy" {
  @fsx.with_temporary_directory("job-ui-snapshot-isolation-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let runtime = RuntimeManager::new(root~)
    let store = runtime.store()
    store.save_definition(JobDefinition::{
      id: "job-1",
      kind: "generic.analysis",
      enabled: true,
      config: { "family": "generic" },
      schedule: None,
      retry_policy: None,
      workflow_id: Some("wf-1"),
      created_at: 1,
      updated_at: 1,
      tags: [],
    })
    store.save_workflow(WorkflowDefinition::{
      id: "wf-1",
      kind: "generic.analysis",
      steps: [],
      output_bindings: [],
    })
    store.save_run(JobRun::{
      id: "run-1",
      job_id: "job-1",
      trigger: Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: None,
      status: Succeeded,
      attempt: 1,
      retry_of: None,
      started_at: Some(10),
      completed_at: Some(20),
      summary: Some("done"),
      error: None,
    })
    let artifacts = ArtifactStore::new(store~)
    ignore(
      artifacts.write(
        ArtifactWriteRequest::new(
          run_id="run-1",
          job_id="job-1",
          artifact_type="analysis.result",
          logical_key=Some("result"),
          content="{}",
          content_type="application/json",
          metadata={
            "execution_isolation": {
              "mode": "git_worktree",
              "cleanup_policy": "on_success",
              "cwd": "/tmp/worktree",
            },
          },
        ),
        "artifact-1",
        30,
      ),
    )
    let snapshot = build_job_ui_snapshot(store, "run-1").unwrap()
    let artifact_node = match
      snapshot.nodes
      .filter(fn(node) { node.kind.to_json().stringify() == "\"Artifact\"" })
      .get(0) {
      Some(node) => node
      None => fail("missing artifact node")
    }
    inspect(
      artifact_node.summary
      .unwrap_or("")
      .contains("git worktree · cleanup on success"),
      content="true",
    )
    inspect(
      artifact_node.detail.unwrap_or("") ==
      "analysis.result (git worktree · cleanup on success)",
      content="true",
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
async test "build_job_ui_snapshot gives starter attachment artifacts operator-friendly labels" {
  @fsx.with_temporary_directory("job-ui-starter-artifacts-XXXXXX", dir => {
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
      steps: [],
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
      summary: None,
      error: None,
    }
    let starter_text = ArtifactRecord::{
      id: "artifact-starter-text",
      run_id: "run-1",
      job_id: "job-1",
      artifact_type: "starter_attachment.text",
      logical_key: Some("starter-attachment:file-1:text"),
      version: 1,
      status: Active,
      path: "/tmp/ws-1/.moonclaw/starter_attachments/file-1.txt.extracted.txt",
      content_type: "text/markdown",
      metadata: {
        "filename": "parcel.pdf",
        "saved_path": "/tmp/ws-1/.moonclaw/starter_attachments/file-1.parcel.pdf",
      },
      created_at: 120,
      archived_at: None,
      scope: ["starter_attachment", "file-1"],
    }
    let starter_manifest = ArtifactRecord::{
      id: "artifact-starter-manifest",
      run_id: "run-1",
      job_id: "job-1",
      artifact_type: "starter_attachment.manifest",
      logical_key: Some("starter-attachment:manifest:markdown"),
      version: 1,
      status: Active,
      path: "/tmp/ws-1/.moonclaw/starter_attachments/manifest.md",
      content_type: "text/markdown",
      metadata: {
        "kind": "markdown",
        "path": "/tmp/ws-1/.moonclaw/starter_attachments/manifest.md",
      },
      created_at: 121,
      archived_at: None,
      scope: ["starter_attachment", "manifest"],
    }
    let starter_summary = ArtifactRecord::{
      id: "artifact-starter-summary",
      run_id: "run-1",
      job_id: "job-1",
      artifact_type: "starter_attachment.summary",
      logical_key: Some("starter-attachment:file-1:summary"),
      version: 1,
      status: Active,
      path: "/tmp/ws-1/.moonclaw/starter_attachments/parcel.summary.md",
      content_type: "text/markdown",
      metadata: {
        "filename": "parcel.pdf",
        "saved_path": "/tmp/ws-1/.moonclaw/starter_attachments/file-1.parcel.pdf",
      },
      created_at: 122,
      archived_at: None,
      scope: ["starter_attachment", "file-1", "summary"],
    }
    let starter_digest = ArtifactRecord::{
      id: "artifact-starter-digest",
      run_id: "run-1",
      job_id: "job-1",
      artifact_type: "starter_attachment.digest",
      logical_key: Some("starter-attachment:digest"),
      version: 1,
      status: Active,
      path: "/tmp/ws-1/.moonclaw/starter_attachments/digest.md",
      content_type: "text/markdown",
      metadata: {
        "attachment_count": 1,
        "path": "/tmp/ws-1/.moonclaw/starter_attachments/digest.md",
      },
      created_at: 123,
      archived_at: None,
      scope: ["starter_attachment", "digest"],
    }
    store.save_definition(definition)
    store.save_workflow(workflow)
    store.save_run(run)
    store.save_artifact(starter_text)
    store.save_artifact(starter_manifest)
    store.save_artifact(starter_summary)
    store.save_artifact(starter_digest)

    let snapshot = build_job_ui_snapshot(store, "run-1").unwrap()
    let text_node = snapshot.nodes.filter(fn(node) {
        node.artifact_id == Some("artifact-starter-text")
      })[0]
    let manifest_node = snapshot.nodes.filter(fn(node) {
        node.artifact_id == Some("artifact-starter-manifest")
      })[0]
    let summary_node = snapshot.nodes.filter(fn(node) {
        node.artifact_id == Some("artifact-starter-summary")
      })[0]
    let digest_node = snapshot.nodes.filter(fn(node) {
        node.artifact_id == Some("artifact-starter-digest")
      })[0]
    json_inspect(text_node.title, content="Starter Attachment Text: parcel.pdf")
    json_inspect(
      text_node.detail.unwrap_or(""),
      content="starter document text",
    )
    json_inspect(
      text_node.summary.unwrap_or(""),
      content="/tmp/ws-1/.moonclaw/starter_attachments/file-1.parcel.pdf",
    )
    json_inspect(
      manifest_node.title,
      content="Starter Attachment Manifest: Markdown",
    )
    json_inspect(
      manifest_node.detail.unwrap_or(""),
      content="starter attachment manifest",
    )
    json_inspect(
      summary_node.title,
      content="Starter Attachment Summary: parcel.pdf",
    )
    json_inspect(
      summary_node.detail.unwrap_or(""),
      content="starter document summary",
    )
    json_inspect(digest_node.title, content="Starter Attachment Digest")
    json_inspect(
      digest_node.detail.unwrap_or(""),
      content="starter document digest",
    )
    json_inspect(
      digest_node.summary.unwrap_or(""),
      content="/tmp/ws-1/.moonclaw/starter_attachments/digest.md",
    )
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
      "expansion_kind": null,
    })
  })
}

///|
async test "build_job_ui_snapshot labels analysis-expanded child runs as subplans" {
  let store = SystemStore::new(root="unused")
  let definition = JobDefinition::{
    id: "job-parent",
    kind: "job.proposal",
    enabled: true,
    config: { "family": "generic" },
    schedule: None,
    retry_policy: None,
    workflow_id: Some("workflow-parent"),
    created_at: 100,
    updated_at: 100,
    tags: [],
  }
  let child_definition = JobDefinition::{
    id: "job-subplan",
    kind: "job.proposal",
    enabled: true,
    config: { "family": "generic" },
    schedule: None,
    retry_policy: None,
    workflow_id: None,
    created_at: 110,
    updated_at: 110,
    tags: [],
  }
  let workflow = WorkflowDefinition::{
    id: "workflow-parent",
    kind: "job.proposal",
    steps: [
      WorkflowStepDefinition::{
        id: "analyze",
        kind: "job.analysis",
        config: {},
        retry_policy: None,
      },
    ],
    output_bindings: ["analyze"],
  }
  let run = JobRun::{
    id: "run-parent",
    job_id: "job-parent",
    trigger: TriggerSource::Manual,
    parent_run_id: None,
    parent_step_id: None,
    depth: 0,
    workspace_dir: None,
    status: RunStatus::Running,
    attempt: 1,
    retry_of: None,
    started_at: Some(100),
    completed_at: None,
    summary: Some("Parent running"),
    error: None,
  }
  let child_run = JobRun::{
    id: "run-subplan",
    job_id: "job-subplan",
    trigger: TriggerSource::Custom("analysis-subplan"),
    parent_run_id: Some("run-parent"),
    parent_step_id: Some("analyze"),
    depth: 1,
    workspace_dir: None,
    status: RunStatus::Running,
    attempt: 1,
    retry_of: None,
    started_at: Some(120),
    completed_at: None,
    summary: Some("Expanded from analysis"),
    error: None,
  }
  store.save_definition(definition)
  store.save_definition(child_definition)
  store.save_workflow(workflow)
  store.save_run(run)
  store.save_run(child_run)

  let snapshot = build_job_ui_snapshot(store, "run-parent").unwrap()
  let node = snapshot.nodes.filter(fn(node) { node.id == "child:run-subplan" })[0]
  json_inspect(node.title, content="Expanded Subplan")
  json_inspect(node.summary.unwrap_or(""), content="Expanded from analysis")
  json_inspect(node.detail.unwrap_or(""), content="job-subplan")
  json_inspect(
    match node.metadata {
      { "expansion_kind": String(value), .. } => value
      _ => ""
    },
    content="analysis-subplan",
  )
}

///|
async test "build_job_ui_snapshot uses the proposal and workflow for the selected run instead of the latest proposal for the job" {
  @fsx.with_temporary_directory("job-ui-run-specific-proposal-XXXXXX", dir => {
    let store = SystemStore::new(root=dir)
    let definition = JobDefinition::{
      id: "job-1",
      kind: "job.proposal",
      enabled: true,
      config: { "family": "generic" },
      schedule: None,
      retry_policy: None,
      workflow_id: Some("wf-latest"),
      created_at: 10,
      updated_at: 20,
      tags: [],
    }
    let old_workflow = WorkflowDefinition::{
      id: "wf-old",
      kind: "job.proposal",
      steps: [
        WorkflowStepDefinition::{
          id: "old-step",
          kind: "job.analysis",
          config: {},
          retry_policy: None,
        },
      ],
      output_bindings: [],
    }
    let latest_workflow = WorkflowDefinition::{
      id: "wf-latest",
      kind: "job.proposal",
      steps: [
        WorkflowStepDefinition::{
          id: "latest-step",
          kind: "job.analysis",
          config: {},
          retry_policy: None,
        },
      ],
      output_bindings: [],
    }
    let old_run = JobRun::{
      id: "run-old",
      job_id: "job-1",
      trigger: Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: None,
      status: Succeeded,
      attempt: 1,
      retry_of: None,
      started_at: Some(100),
      completed_at: Some(140),
      summary: Some("old run"),
      error: None,
    }
    let latest_run = JobRun::{
      id: "run-latest",
      job_id: "job-1",
      trigger: Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: None,
      status: Running,
      attempt: 1,
      retry_of: None,
      started_at: Some(200),
      completed_at: None,
      summary: Some("latest run"),
      error: None,
    }
    let old_proposal = JobProposal::{
      id: "proposal-old",
      title: "Old plan",
      request_text: "old request",
      summary: "old summary",
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
      workflow_id: Some("wf-old"),
      last_run_id: Some("run-old"),
      created_at: 90,
      updated_at: 100,
    }
    let latest_proposal = JobProposal::{
      id: "proposal-latest",
      title: "Latest plan",
      request_text: "latest request",
      summary: "latest summary",
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
      workflow_id: Some("wf-latest"),
      last_run_id: Some("run-latest"),
      created_at: 190,
      updated_at: 200,
    }
    store.save_definition(definition)
    store.save_workflow(old_workflow)
    store.save_workflow(latest_workflow)
    store.save_run(old_run)
    store.save_run(latest_run)
    store.save_job_proposal(old_proposal)
    store.save_job_proposal(latest_proposal)

    let snapshot = build_job_ui_snapshot(store, "run-old").unwrap()
    json_inspect(
      snapshot.proposal.map(fn(proposal) { proposal.id }).unwrap_or(""),
      content="proposal-old",
    )
    json_inspect(
      snapshot.workflow.map(fn(workflow) { workflow.id }).unwrap_or(""),
      content="wf-old",
    )
    json_inspect(
      snapshot.nodes
      .filter(fn(node) { node.kind.to_json().stringify() == "\"Step\"" })
      .map(fn(node) { node.step_id.unwrap_or("") }),
      content=["old-step"],
    )
  })
}
