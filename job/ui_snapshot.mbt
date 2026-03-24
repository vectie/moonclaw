///|
fn ui_status_text(status : RunStatus) -> String {
  status.to_json().stringify()
}

///|
fn workflow_node_id(run_id : String) -> String {
  "workflow:\{run_id}"
}

///|
fn proposal_for_run(
  store : SystemStore,
  run : JobRun,
  definition : JobDefinition,
) -> JobProposal? {
  for proposal in store.list_job_proposals() {
    if proposal.last_run_id == Some(run.id) ||
      proposal.job_id == Some(definition.id) {
      return Some(proposal)
    }
  }
  None
}

///|
fn timeline_entry_id(run_id : String, index : Int) -> String {
  "\{run_id}:event:\{index}"
}

///|
fn timeline_title(event : JobRunEvent) -> String {
  match event.step_id {
    Some(step_id) => "\{event.event_type} (\{step_id})"
    None => event.event_type
  }
}

///|
fn remote_link_timestamp(link : JobUiRemoteLink) -> Int {
  match link.metadata {
    { "updated_at": Number(ts, ..), .. } => ts.to_int()
    { "created_at": Number(ts, ..), .. } => ts.to_int()
    _ => 0
  }
}

///|
fn remote_handoff_timeline(
  run : JobRun,
  handoffs : Array[JobUiHandoff],
) -> Array[JobUiTimelineEntry] {
  let timeline : Array[JobUiTimelineEntry] = []
  let mut index = 0
  for handoff in handoffs {
    for remote in handoff.remote {
      let timestamp = remote_link_timestamp(remote)
      timeline.push(JobUiTimelineEntry::{
        id: "\{run.id}:handoff:\{index}",
        run_id: run.id,
        event_type: "remote.handoff",
        title: match handoff.step_id {
          Some(step_id) => "remote.handoff (\{step_id})"
          None => "remote.handoff"
        },
        detail: "Linked \{remote.kind} \{remote.title} (\{remote.status})",
        timestamp,
        step_id: handoff.step_id,
        status: Some(remote.status),
        data: {
          "node_id": handoff.node_id,
          "remote_id": remote.id,
          "remote_kind": remote.kind,
          "remote_title": remote.title,
        },
      })
      index = index + 1
    }
  }
  timeline
}

///|
fn timeline_from_events(
  events : Array[JobRunEvent],
  synthetic? : Array[JobUiTimelineEntry] = [],
) -> Array[JobUiTimelineEntry] {
  let sorted = events.copy()
  sorted.sort_by(fn(left, right) { left.timestamp.compare(right.timestamp) })
  let timeline : Array[JobUiTimelineEntry] = synthetic.copy()
  for index in 0..<sorted.length() {
    let event = sorted[index]
    timeline.push(JobUiTimelineEntry::{
      id: timeline_entry_id(event.run_id, index),
      run_id: event.run_id,
      event_type: event.event_type,
      title: timeline_title(event),
      detail: event.message,
      timestamp: event.timestamp,
      step_id: event.step_id,
      status: event.status.map(ui_status_text),
      data: event.data,
    })
  }
  timeline.sort_by(fn(left, right) { left.timestamp.compare(right.timestamp) })
  timeline
}

///|
fn node_updated_at(started_at : Int?, completed_at : Int?) -> Int? {
  match completed_at {
    Some(value) => Some(value)
    None => started_at
  }
}

///|
fn snapshot_json_string_field(value : Json, key : String) -> String? {
  match value {
    Object(obj) =>
      match obj.get(key) {
        Some(String(text)) => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
fn split_node_id(run_id : String) -> String {
  "split:\{run_id}"
}

///|
fn merge_node_id(run_id : String) -> String {
  "merge:\{run_id}"
}

///|
fn controller_split_status(run : JobRun, child_runs : Array[JobRun]) -> String {
  if child_runs.any(fn(child) {
      child.status is RunStatus::Running || child.status is RunStatus::Pending
    }) {
    return ui_status_text(RunStatus::Running)
  }
  if child_runs.any(fn(child) { child.status is RunStatus::Failed }) {
    return ui_status_text(RunStatus::Failed)
  }
  if !child_runs.is_empty() {
    return ui_status_text(RunStatus::Succeeded)
  }
  ui_status_text(run.status)
}

///|
fn controller_split_summary(
  workflow : WorkflowDefinition?,
  child_runs : Array[JobRun],
) -> String? {
  let delegated_steps = match workflow {
    Some(workflow) =>
      workflow.steps.filter(fn(step) { step.kind == "job.delegate" }).length()
    None => 0
  }
  let running = child_runs
    .filter(fn(child) {
      child.status is RunStatus::Running || child.status is RunStatus::Pending
    })
    .length()
  let failed = child_runs
    .filter(fn(child) { child.status is RunStatus::Failed })
    .length()
  let completed = child_runs
    .filter(fn(child) { child.status is RunStatus::Succeeded })
    .length()
  let parts : Array[String] = []
  if delegated_steps > 0 {
    parts.push("\{delegated_steps} delegated steps")
  }
  if !child_runs.is_empty() {
    parts.push("\{child_runs.length()} worker runs")
    if completed > 0 {
      parts.push("\{completed} completed")
    }
    if running > 0 {
      parts.push("\{running} active")
    }
    if failed > 0 {
      parts.push("\{failed} failed")
    }
  }
  if parts.is_empty() {
    None
  } else {
    Some(parts.join(" · "))
  }
}

///|
fn controller_merge_summary(
  run : JobRun,
  state : JobControllerState,
  decisions : Array[JobControllerDecision],
  artifacts : Array[ArtifactRecord],
  memories : Array[MemoryRecord],
) -> String? {
  let accepted = state.accepted_iteration_ids.length()
  let rejected = state.rejected_iteration_ids.length()
  let parts : Array[String] = []
  if accepted > 0 {
    parts.push("\{accepted} accepted")
  }
  if rejected > 0 {
    parts.push("\{rejected} rejected")
  }
  if !decisions.is_empty() {
    parts.push("\{decisions.length()} decisions")
  }
  if !artifacts.is_empty() {
    parts.push("\{artifacts.length()} artifacts")
  }
  if !memories.is_empty() {
    parts.push("\{memories.length()} memories")
  }
  match run.summary {
    Some(summary) if !summary.is_blank() => parts.push(summary)
    _ => ()
  }
  if parts.is_empty() {
    None
  } else {
    Some(parts.join(" · "))
  }
}

///|
fn controller_split_node(
  run : JobRun,
  workflow : WorkflowDefinition?,
  child_runs : Array[JobRun],
  state : JobControllerState,
) -> JobUiNode {
  JobUiNode::{
    id: split_node_id(run.id),
    parent_id: Some(workflow_node_id(run.id)),
    kind: Split,
    title: "Split Work",
    status: controller_split_status(run, child_runs),
    summary: controller_split_summary(workflow, child_runs),
    detail: Some("Controller dispatches delegated worker branches here."),
    run_id: Some(run.id),
    step_id: None,
    artifact_id: None,
    memory_id: None,
    created_at: run.started_at,
    updated_at: Some(state.updated_at),
    provisional: false,
    metadata: {
      "family": state.family,
      "frontier": Json::array(state.frontier.map(fn(id) { Json::string(id) })),
      "active_iteration_ids": Json::array(
        state.active_iteration_ids.map(fn(id) { Json::string(id) }),
      ),
    },
  }
}

///|
fn controller_merge_node(
  run : JobRun,
  state : JobControllerState,
  decisions : Array[JobControllerDecision],
  artifacts : Array[ArtifactRecord],
  memories : Array[MemoryRecord],
) -> JobUiNode {
  JobUiNode::{
    id: merge_node_id(run.id),
    parent_id: Some(workflow_node_id(run.id)),
    kind: Merge,
    title: "Merge Results",
    status: ui_status_text(run.status),
    summary: controller_merge_summary(
      run, state, decisions, artifacts, memories,
    ),
    detail: Some(
      run.error.unwrap_or(
        "Controller collects branch outputs and final result here.",
      ),
    ),
    run_id: Some(run.id),
    step_id: None,
    artifact_id: None,
    memory_id: None,
    created_at: Some(state.created_at),
    updated_at: Some(state.updated_at),
    provisional: run.status is RunStatus::Pending,
    metadata: {
      "best_iteration_id": state.best_iteration_id,
      "accepted_iteration_ids": Json::array(
        state.accepted_iteration_ids.map(fn(id) { Json::string(id) }),
      ),
      "rejected_iteration_ids": Json::array(
        state.rejected_iteration_ids.map(fn(id) { Json::string(id) }),
      ),
      "decision_count": decisions.length(),
    },
  }
}

///|
fn step_node(
  run : JobRun,
  step_definition : WorkflowStepDefinition,
  step_run : JobStepRun?,
  parent_id? : String? = Some(workflow_node_id(run.id)),
) -> JobUiNode {
  let status = match step_run {
    Some(step_run) => ui_status_text(step_run.status)
    None => "\"Pending\""
  }
  JobUiNode::{
    id: "step:\{run.id}:\{step_definition.id}",
    parent_id,
    kind: Step,
    title: step_definition.id,
    status,
    summary: step_run.bind(fn(step) { step.summary }),
    detail: Some(step_definition.kind),
    run_id: Some(run.id),
    step_id: Some(step_definition.id),
    artifact_id: None,
    memory_id: None,
    created_at: step_run.bind(fn(step) { step.started_at }),
    updated_at: step_run.bind(fn(step) {
      node_updated_at(step.started_at, step.completed_at)
    }),
    provisional: step_run is None,
    metadata: step_definition.config,
  }
}

///|
fn child_run_node(
  store : SystemStore,
  parent_run_id : String,
  run : JobRun,
) -> JobUiNode {
  let parent_id = match run.parent_step_id {
    Some(step_id) => Some("step:\{parent_run_id}:\{step_id}")
    None => Some(workflow_node_id(parent_run_id))
  }
  let child_definition = store.get_definition(run.job_id)
  let family = child_definition.bind(fn(definition) {
    snapshot_json_string_field(definition.config, "family")
  })
  let role = child_definition.bind(fn(definition) {
    snapshot_json_string_field(definition.config, "role")
  })
  let worker_role = child_definition.bind(fn(definition) {
    match definition.config {
      { "profile_metadata": profile_metadata, .. } =>
        snapshot_json_string_field(profile_metadata, "worker_role")
      _ => None
    }
  })
  JobUiNode::{
    id: "child:\{run.id}",
    parent_id,
    kind: ChildRun,
    title: run.job_id,
    status: ui_status_text(run.status),
    summary: run.summary,
    detail: run.error,
    run_id: Some(run.id),
    step_id: run.parent_step_id,
    artifact_id: None,
    memory_id: None,
    created_at: run.started_at,
    updated_at: node_updated_at(run.started_at, run.completed_at),
    provisional: false,
    metadata: {
      "depth": run.depth,
      "job_id": run.job_id,
      "parent_run_id": match run.parent_run_id {
        Some(value) => Json::string(value)
        None => null
      },
      "family": match family {
        Some(value) => Json::string(value)
        None => null
      },
      "role": match role {
        Some(value) => Json::string(value)
        None => null
      },
      "worker_role": match worker_role {
        Some(value) => Json::string(value)
        None => null
      },
    },
  }
}

///|
fn artifact_node(run : JobRun, artifact : ArtifactRecord) -> JobUiNode {
  JobUiNode::{
    id: "artifact:\{artifact.id}",
    parent_id: Some(workflow_node_id(run.id)),
    kind: Artifact,
    title: artifact.logical_key.unwrap_or(artifact.artifact_type),
    status: artifact.status.to_json().stringify(),
    summary: Some(artifact.path),
    detail: Some(artifact.artifact_type),
    run_id: Some(run.id),
    step_id: None,
    artifact_id: Some(artifact.id),
    memory_id: None,
    created_at: Some(artifact.created_at),
    updated_at: Some(artifact.archived_at.unwrap_or(artifact.created_at)),
    provisional: false,
    metadata: artifact.metadata,
  }
}

///|
fn artifact_node_with_parent(
  run : JobRun,
  artifact : ArtifactRecord,
  parent_id : String?,
) -> JobUiNode {
  { ..artifact_node(run, artifact), parent_id, }
}

///|
fn memory_node(run : JobRun, memory : MemoryRecord) -> JobUiNode {
  JobUiNode::{
    id: "memory:\{memory.id}",
    parent_id: Some(workflow_node_id(run.id)),
    kind: Memory,
    title: memory.title.unwrap_or(memory.kind),
    status: memory.status.to_json().stringify(),
    summary: Some(memory.content),
    detail: Some(memory.kind),
    run_id: Some(run.id),
    step_id: None,
    artifact_id: memory.source_artifact_id,
    memory_id: Some(memory.id),
    created_at: Some(memory.created_at),
    updated_at: Some(memory.updated_at),
    provisional: false,
    metadata: memory.metadata,
  }
}

///|
fn memory_node_with_parent(
  run : JobRun,
  memory : MemoryRecord,
  parent_id : String?,
) -> JobUiNode {
  { ..memory_node(run, memory), parent_id, }
}

///|
pub fn current_step_id_for_ui(
  store : SystemStore,
  run : JobRun,
  workflow : WorkflowDefinition?,
) -> String? {
  let steps = store.list_step_runs(run.id)
  let running = steps.filter(fn(step) { step.status is RunStatus::Running })
  if !running.is_empty() {
    return Some(running[0].step_id)
  }
  match workflow {
    Some(workflow) =>
      if steps.is_empty() {
        workflow.steps.get(0).map(fn(step) { step.id })
      } else {
        let sorted = steps.copy()
        sorted.sort_by(fn(left, right) {
          let left_ts = left.completed_at.unwrap_or(
            left.started_at.unwrap_or(0),
          )
          let right_ts = right.completed_at.unwrap_or(
            right.started_at.unwrap_or(0),
          )
          right_ts.compare(left_ts)
        })
        sorted.get(0).map(fn(step) { step.step_id })
      }
    None => None
  }
}

///|
pub async fn build_job_ui_snapshot(
  store : SystemStore,
  run_id : String,
  linked_remote? : Array[JobUiRemoteLink] = [],
  handoffs? : Array[JobUiHandoff] = [],
) -> JobUiSnapshot? {
  let run = match store.get_run(run_id) {
    Some(run) => run
    None => return None
  }
  let definition = match store.get_definition(run.job_id) {
    Some(definition) => definition
    None => return None
  }
  let workflow = definition.workflow_id.bind(fn(workflow_id) {
    store.get_workflow(workflow_id)
  })
  let proposal = proposal_for_run(store, run, definition)
  let controller_state = store.get_controller_state(run.id)
  let controller_decisions = store.list_controller_decisions(
    controller_run_id=Some(run.id),
  )
  let child_runs = store
    .list_runs()
    .filter(fn(candidate) { candidate.parent_run_id == Some(run.id) })
  let artifacts = store.list_artifacts(run_id=run.id)
  let memories = store
    .list_memories()
    .filter(fn(memory) {
      if memory.workspace == run.workspace_dir {
        return true
      }
      match memory.source_artifact_id {
        Some(source_id) =>
          artifacts.any(fn(artifact) { artifact.id == source_id })
        None => false
      }
    })
  let nodes : Array[JobUiNode] = []
  match proposal {
    Some(proposal) =>
      nodes.push(JobUiNode::{
        id: "proposal:\{proposal.id}",
        parent_id: None,
        kind: Proposal,
        title: proposal.title,
        status: proposal.status.to_json().stringify(),
        summary: Some(proposal.summary),
        detail: Some(proposal.request_text),
        run_id: proposal.last_run_id,
        step_id: None,
        artifact_id: None,
        memory_id: None,
        created_at: Some(proposal.created_at),
        updated_at: Some(proposal.updated_at),
        provisional: proposal.status is Draft,
        metadata: { "suggested_family": proposal.suggested_family },
      })
    None => ()
  }
  nodes.push(JobUiNode::{
    id: workflow_node_id(run.id),
    parent_id: proposal.map(fn(p) { "proposal:\{p.id}" }),
    kind: Workflow,
    title: workflow.map(fn(item) { item.kind }).unwrap_or(definition.kind),
    status: ui_status_text(run.status),
    summary: run.summary,
    detail: run.error,
    run_id: Some(run.id),
    step_id: None,
    artifact_id: None,
    memory_id: None,
    created_at: run.started_at,
    updated_at: node_updated_at(run.started_at, run.completed_at),
    provisional: false,
    metadata: {
      "job_id": definition.id,
      "workflow_id": definition.workflow_id,
      "workspace_dir": run.workspace_dir,
    },
  })
  match controller_state {
    Some(state) =>
      nodes.push(controller_split_node(run, workflow, child_runs, state))
    None => ()
  }
  match workflow {
    Some(workflow) =>
      for step_definition in workflow.steps {
        nodes.push(
          step_node(
            run,
            step_definition,
            store.get_step_run(run.id, step_definition.id),
            parent_id=match controller_state {
              Some(_) => Some(split_node_id(run.id))
              None => Some(workflow_node_id(run.id))
            },
          ),
        )
      }
    None => ()
  }
  for child_run in child_runs {
    nodes.push(child_run_node(store, run.id, child_run))
  }
  match controller_state {
    Some(state) =>
      nodes.push(
        controller_merge_node(
          run, state, controller_decisions, artifacts, memories,
        ),
      )
    None => ()
  }
  for artifact in artifacts {
    nodes.push(
      artifact_node_with_parent(
        run,
        artifact,
        match controller_state {
          Some(_) => Some(merge_node_id(run.id))
          None => Some(workflow_node_id(run.id))
        },
      ),
    )
  }
  for memory in memories {
    nodes.push(
      memory_node_with_parent(
        run,
        memory,
        match controller_state {
          Some(_) => Some(merge_node_id(run.id))
          None => Some(workflow_node_id(run.id))
        },
      ),
    )
  }
  Some(JobUiSnapshot::{
    run,
    definition,
    workflow,
    proposal,
    workspace_dir: run.workspace_dir,
    current_step_id: current_step_id_for_ui(store, run, workflow),
    child_runs,
    artifacts,
    memories,
    linked_remote,
    handoffs,
    nodes,
    timeline: timeline_from_events(
      store.list_run_events(run.id),
      synthetic=remote_handoff_timeline(run, handoffs),
    ),
  })
}
