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
fn timeline_from_events(
  events : Array[JobRunEvent],
) -> Array[JobUiTimelineEntry] {
  let sorted = events.copy()
  sorted.sort_by(fn(left, right) { left.timestamp.compare(right.timestamp) })
  let timeline : Array[JobUiTimelineEntry] = []
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
fn step_node(
  run : JobRun,
  step_definition : WorkflowStepDefinition,
  step_run : JobStepRun?,
) -> JobUiNode {
  let status = match step_run {
    Some(step_run) => ui_status_text(step_run.status)
    None => "\"Pending\""
  }
  JobUiNode::{
    id: "step:\{run.id}:\{step_definition.id}",
    parent_id: Some(workflow_node_id(run.id)),
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
fn child_run_node(parent_run_id : String, run : JobRun) -> JobUiNode {
  let parent_id = match run.parent_step_id {
    Some(step_id) => Some("step:\{parent_run_id}:\{step_id}")
    None => Some(workflow_node_id(parent_run_id))
  }
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
      "parent_run_id": run.parent_run_id,
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
        metadata: {
          "suggested_family": proposal.suggested_family,
          "suggested_template": proposal.suggested_template,
          "required_capabilities": proposal.required_capabilities,
          "missing_capabilities": proposal.missing_capabilities,
          "compiler_notes": proposal.compiler_notes,
        },
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
  match workflow {
    Some(workflow) =>
      for step_definition in workflow.steps {
        nodes.push(
          step_node(
            run,
            step_definition,
            store.get_step_run(run.id, step_definition.id),
          ),
        )
      }
    None => ()
  }
  for child_run in child_runs {
    nodes.push(child_run_node(run.id, child_run))
  }
  for artifact in artifacts {
    nodes.push(artifact_node(run, artifact))
  }
  for memory in memories {
    nodes.push(memory_node(run, memory))
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
    nodes,
    timeline: timeline_from_events(store.list_run_events(run.id)),
  })
}
