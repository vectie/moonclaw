///|
fn is_controller_definition(definition : JobDefinition) -> Bool {
  if definition.kind == "job.controller" {
    return true
  }
  match definition.config {
    { "role": String(role), .. } => role == "controller"
    _ => false
  }
}

///|
fn controller_root_iteration_id(run_id : String) -> String {
  "\{run_id}:iter:root"
}

///|
fn controller_step_iteration_id(run_id : String, step_id : String) -> String {
  "\{run_id}:iter:\{step_id}"
}

///|
fn append_unique(values : Array[String], value : String) -> Array[String] {
  if values.contains(value) {
    values
  } else {
    [..values, value]
  }
}

///|
fn without_value(values : Array[String], value : String) -> Array[String] {
  values.filter(fn(existing) { existing != value })
}

///|
fn controller_edge_exists(
  store : SystemStore,
  controller_job_id : String,
  edge_id : String,
) -> Bool {
  store
  .list_controller_lineage_edges(controller_job_id=Some(controller_job_id))
  .any(fn(edge) { edge.id == edge_id })
}

///|
fn controller_family(definition : JobDefinition) -> String {
  match definition.config {
    { "family": String(family), .. } => family
    _ => "generic"
  }
}

///|
fn controller_profile_id(definition : JobDefinition) -> String? {
  match definition.config {
    { "profile_id": String(profile_id), .. } => Some(profile_id)
    _ => None
  }
}

///|
fn controller_profile_metadata(definition : JobDefinition) -> Json {
  match definition.config {
    { "profile_metadata": metadata, .. } => metadata
    _ => {}
  }
}

///|
fn controller_objective(
  store : SystemStore,
  definition : JobDefinition,
) -> String {
  match definition.config {
    { "proposal_id": String(proposal_id), .. } =>
      match store.get_job_proposal(proposal_id) {
        Some(proposal) => proposal.request_text
        None => definition.id
      }
    _ => definition.id
  }
}

///|
fn controller_step_title(step : WorkflowStepDefinition) -> String {
  match step.config {
    { "metadata": { "proposal_step_title": String(title), .. }, .. } => title
    { "request_text": String(request_text), .. } =>
      request_text.split("\n").head().unwrap_or(step.id).trim().to_string()
    { "prompt": String(prompt), .. } =>
      prompt.split("\n").head().unwrap_or(step.id).trim().to_string()
    _ => step.id
  }
}

///|
fn controller_step_hypothesis(
  step : WorkflowStepDefinition,
  title : String,
) -> String {
  match step.config {
    { "request_text": String(request_text), .. } => request_text
    { "prompt": String(prompt), .. } => prompt
    _ => title
  }
}

///|
pub async fn ensure_controller_records_for_run(
  store : SystemStore,
  definition : JobDefinition,
  run : JobRun,
  now_ms : Int,
) -> Unit {
  guard is_controller_definition(definition) else { return () }
  guard store.get_controller_state(run.id) is None else { return () }
  let root_iteration_id = controller_root_iteration_id(run.id)
  let state = JobControllerState::{
    controller_job_id: definition.id,
    controller_run_id: run.id,
    family: controller_family(definition),
    profile_id: controller_profile_id(definition),
    objective: controller_objective(store, definition),
    active_iteration_ids: [root_iteration_id],
    accepted_iteration_ids: [],
    rejected_iteration_ids: [],
    best_iteration_id: None,
    frontier: [root_iteration_id],
    metadata: controller_profile_metadata(definition),
    created_at: now_ms,
    updated_at: now_ms,
  }
  let iteration = JobControllerIteration::{
    id: root_iteration_id,
    controller_job_id: definition.id,
    controller_run_id: run.id,
    parent_iteration_id: None,
    title: "Root iteration",
    hypothesis: state.objective,
    status: "active",
    decision: None,
    child_job_ids: [],
    child_run_ids: [],
    metadata: { "kind": "root", "trigger": run.trigger.to_json() },
    created_at: now_ms,
    updated_at: now_ms,
  }
  store.save_controller_state(state)
  store.save_controller_iteration(iteration)
}

///|
pub async fn ensure_controller_iteration_for_step(
  store : SystemStore,
  run : JobRun,
  step : WorkflowStepDefinition,
  now_ms : Int,
) -> Unit {
  let state = match store.get_controller_state(run.id) {
    Some(state) => state
    None => return ()
  }
  let root_iteration_id = controller_root_iteration_id(run.id)
  let iteration_id = controller_step_iteration_id(run.id, step.id)
  if store.get_controller_iteration(iteration_id) is None {
    let title = controller_step_title(step)
    let iteration = JobControllerIteration::{
      id: iteration_id,
      controller_job_id: state.controller_job_id,
      controller_run_id: run.id,
      parent_iteration_id: Some(root_iteration_id),
      title,
      hypothesis: controller_step_hypothesis(step, title),
      status: "active",
      decision: None,
      child_job_ids: [],
      child_run_ids: [],
      metadata: { "step_id": step.id, "step_kind": step.kind },
      created_at: now_ms,
      updated_at: now_ms,
    }
    store.save_controller_iteration(iteration)
  }
  let edge_id = "\{run.id}:edge:root:\{step.id}"
  if !controller_edge_exists(store, state.controller_job_id, edge_id) {
    store.save_controller_lineage_edge(JobControllerLineageEdge::{
      id: edge_id,
      controller_job_id: state.controller_job_id,
      from_iteration_id: root_iteration_id,
      to_iteration_id: iteration_id,
      edge_kind: "step",
      metadata: { "step_id": step.id, "step_kind": step.kind },
      created_at: now_ms,
    })
  }
  store.save_controller_state(JobControllerState::{
    ..state,
    active_iteration_ids: append_unique(
      state.active_iteration_ids,
      iteration_id,
    ),
    frontier: append_unique(state.frontier, iteration_id),
    updated_at: now_ms,
  })
}

///|
pub async fn record_controller_child_run(
  store : SystemStore,
  parent_run : JobRun,
  step : WorkflowStepDefinition,
  child_job_id : String,
  child_run_id : String,
  child_family : String,
  now_ms : Int,
) -> Unit {
  guard store.get_controller_state(parent_run.id) is Some(_) else { return () }
  ensure_controller_iteration_for_step(store, parent_run, step, now_ms)
  let iteration_id = controller_step_iteration_id(parent_run.id, step.id)
  let iteration = match store.get_controller_iteration(iteration_id) {
    Some(iteration) => iteration
    None => return ()
  }
  store.save_controller_iteration(JobControllerIteration::{
    ..iteration,
    child_job_ids: append_unique(iteration.child_job_ids, child_job_id),
    child_run_ids: append_unique(iteration.child_run_ids, child_run_id),
    metadata: {
      "step_id": step.id,
      "step_kind": step.kind,
      "child_family": child_family,
    },
    updated_at: now_ms,
  })
}

///|
fn completed_iteration_status(status : RunStatus) -> String {
  match status {
    RunStatus::Succeeded => "completed"
    RunStatus::Failed => "failed"
    RunStatus::Cancelled => "cancelled"
    RunStatus::Pending => "pending"
    RunStatus::Running => "active"
  }
}

///|
fn completed_iteration_decision(status : RunStatus) -> String? {
  match status {
    RunStatus::Succeeded => Some("accepted")
    RunStatus::Failed => Some("rejected")
    RunStatus::Cancelled => Some("cancelled")
    RunStatus::Pending | RunStatus::Running => None
  }
}

///|
pub async fn complete_controller_iteration_for_step(
  store : SystemStore,
  run : JobRun,
  step : WorkflowStepDefinition,
  status : RunStatus,
  now_ms : Int,
) -> Unit {
  let state = match store.get_controller_state(run.id) {
    Some(state) => state
    None => return ()
  }
  ensure_controller_iteration_for_step(store, run, step, now_ms)
  let iteration_id = controller_step_iteration_id(run.id, step.id)
  let iteration = match store.get_controller_iteration(iteration_id) {
    Some(iteration) => iteration
    None => return ()
  }
  store.save_controller_iteration(JobControllerIteration::{
    ..iteration,
    status: completed_iteration_status(status),
    decision: completed_iteration_decision(status),
    updated_at: now_ms,
  })
  let accepted = if status is RunStatus::Succeeded {
    append_unique(state.accepted_iteration_ids, iteration_id)
  } else {
    state.accepted_iteration_ids
  }
  let rejected = if status is RunStatus::Failed {
    append_unique(state.rejected_iteration_ids, iteration_id)
  } else {
    state.rejected_iteration_ids
  }
  store.save_controller_state(JobControllerState::{
    ..state,
    active_iteration_ids: without_value(
      state.active_iteration_ids,
      iteration_id,
    ),
    accepted_iteration_ids: accepted,
    rejected_iteration_ids: rejected,
    best_iteration_id: if status is RunStatus::Succeeded {
      Some(iteration_id)
    } else {
      state.best_iteration_id
    },
    frontier: without_value(state.frontier, iteration_id),
    updated_at: now_ms,
  })
}

///|
pub async fn complete_controller_run(
  store : SystemStore,
  run : JobRun,
  status : RunStatus,
  now_ms : Int,
) -> Unit {
  let state = match store.get_controller_state(run.id) {
    Some(state) => state
    None => return ()
  }
  let root_iteration_id = controller_root_iteration_id(run.id)
  let root_iteration = match store.get_controller_iteration(root_iteration_id) {
    Some(iteration) => iteration
    None => return ()
  }
  store.save_controller_iteration(JobControllerIteration::{
    ..root_iteration,
    status: completed_iteration_status(status),
    decision: completed_iteration_decision(status),
    updated_at: now_ms,
  })
  store.save_controller_state(JobControllerState::{
    ..state,
    active_iteration_ids: without_value(
      state.active_iteration_ids,
      root_iteration_id,
    ),
    updated_at: now_ms,
  })
}
