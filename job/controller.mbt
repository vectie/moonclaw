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
fn controller_policy_metadata(definition : JobDefinition) -> Json? {
  match definition.config {
    { "controller_policy": metadata, .. } => Some(metadata)
    _ =>
      match controller_profile_metadata(definition) {
        { "controller_policy": metadata, .. } => Some(metadata)
        _ => None
      }
  }
}

///|
fn controller_acceptance_source(definition : JobDefinition) -> String? {
  match controller_policy_metadata(definition) {
    Some({ "acceptance_source": String(source), .. }) => Some(source)
    _ => None
  }
}

///|
fn controller_result_schema(definition : JobDefinition) -> String? {
  match controller_policy_metadata(definition) {
    Some({ "result_schema": String(schema), .. }) => Some(schema)
    _ => None
  }
}

///|
fn controller_next_iteration_field(
  definition : JobDefinition,
  key : String,
  fallback : String,
) -> String {
  match controller_policy_metadata(definition) {
    Some({ "next_iteration_fields": Object(fields), .. }) =>
      match fields.get(key) {
        Some(String(field)) if !field.trim().to_string().is_blank() =>
          field.trim().to_string()
        _ => fallback
      }
    _ => fallback
  }
}

///|
fn controller_allowed_verdicts(definition : JobDefinition) -> Array[String] {
  match controller_policy_metadata(definition) {
    Some({ "allowed_verdicts": Array(verdicts), .. }) => {
      let allowed : Array[String] = []
      for verdict in verdicts {
        match verdict {
          String(value) => allowed.push(value.trim().to_string().to_lower())
          _ => ()
        }
      }
      allowed
    }
    _ => []
  }
}

///|
fn controller_verdict_aliases(
  definition : JobDefinition,
) -> Map[String, String] {
  match controller_policy_metadata(definition) {
    Some({ "verdict_aliases": Object(aliases), .. }) => {
      let normalized : Map[String, String] = {}
      for key, value in aliases {
        match value {
          String(target) =>
            normalized.set(
              key.trim().to_string().to_lower(),
              target.trim().to_string().to_lower(),
            )
          _ => ()
        }
      }
      normalized
    }
    _ => {}
  }
}

///|
fn controller_accepts_step_output(definition : JobDefinition) -> Bool {
  match controller_acceptance_source(definition) {
    Some("child_output") => false
    Some("manual") => false
    Some("disabled") => false
    Some("none") => false
    Some("step_output") | None => true
    Some(_) => true
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
fn controller_decision_id(run_id : String, step_id : String) -> String {
  "\{run_id}:decision:\{step_id}"
}

///|
fn controller_next_iteration_id(
  run_id : String,
  step_id : String,
  provided? : String? = None,
) -> String {
  match provided {
    Some(id) if !id.trim().to_string().is_blank() => id.trim().to_string()
    _ => "\{run_id}:iter:\{step_id}:next"
  }
}

///|
fn decision_metadata_with_schema(
  metadata : Json,
  result_schema : String?,
) -> Json {
  match result_schema {
    Some(schema) => { "result_schema": schema, "payload": metadata }
    None => metadata
  }
}

///|
fn decision_metadata_with_warning(metadata : Json, warning : String?) -> Json {
  match warning {
    Some(warning) => { "warning": warning, "payload": metadata }
    None => metadata
  }
}

///|
fn decision_payload_from_output(output : Json) -> Json? {
  match output {
    { "controller_decision": decision, .. } => Some(decision)
    { "verdict": String(_), .. } => Some(output)
    { "decision": String(_), .. } => Some(output)
    { "status": String(_), .. } => Some(output)
    { "action": String(_), .. } => Some(output)
    _ => None
  }
}

///|
fn decision_verdict(decision : Json) -> String? {
  match decision {
    { "verdict": String(verdict), .. } => Some(verdict)
    { "decision": String(verdict), .. } => Some(verdict)
    { "status": String(verdict), .. } => Some(verdict)
    { "action": String(verdict), .. } => Some(verdict)
    _ => None
  }
}

///|
fn normalized_verdict(
  definition : JobDefinition,
  verdict : String,
) -> (String, String?) {
  let raw = verdict.trim().to_string()
  let normalized = raw.to_lower()
  let aliases = controller_verdict_aliases(definition)
  let canonical = aliases.get(normalized).unwrap_or(normalized)
  let allowed = controller_allowed_verdicts(definition)
  if allowed.is_empty() || allowed.contains(canonical) {
    (canonical, None)
  } else {
    let allowed_text = allowed.join(",")
    (
      canonical,
      Some(
        "Verdict `\{raw}` is outside configured allowed_verdicts: \{allowed_text}",
      ),
    )
  }
}

///|
fn decision_reason(decision : Json) -> String? {
  match decision {
    { "reason": String(reason), .. } => Some(reason)
    { "rationale": String(reason), .. } => Some(reason)
    { "summary": String(reason), .. } => Some(reason)
    _ => None
  }
}

///|
fn decision_next_action(decision : Json) -> String? {
  match decision {
    { "next_action": String(next_action), .. } => Some(next_action)
    { "next": String(next_action), .. } => Some(next_action)
    _ => None
  }
}

///|
fn decision_next_iteration(decision : Json) -> Json? {
  match decision {
    { "next_iteration": next_iteration, .. } => Some(next_iteration)
    { "next": next_iteration, .. } =>
      match next_iteration {
        Object(_) => Some(next_iteration)
        _ => None
      }
    _ => None
  }
}

///|
fn mapped_object_string(
  object : Json,
  primary : String,
  secondary? : String? = None,
) -> String? {
  match object {
    Object(fields) =>
      match fields.get(primary) {
        Some(String(value)) if !value.trim().to_string().is_blank() =>
          Some(value)
        _ =>
          match secondary {
            Some(secondary) =>
              match fields.get(secondary) {
                Some(String(value)) if !value.trim().to_string().is_blank() =>
                  Some(value)
                _ => None
              }
            None => None
          }
      }
    _ => None
  }
}

///|
pub async fn record_controller_decision_from_output(
  store : SystemStore,
  definition : JobDefinition,
  run : JobRun,
  step : WorkflowStepDefinition,
  output : Json,
  now_ms : Int,
) -> Unit {
  guard store.get_controller_state(run.id) is Some(state) else { return () }
  guard controller_accepts_step_output(definition) else { return () }
  ensure_controller_iteration_for_step(store, run, step, now_ms)
  let iteration_id = controller_step_iteration_id(run.id, step.id)
  let result_schema = controller_result_schema(definition)
  match decision_payload_from_output(output) {
    Some(decision) =>
      match decision_verdict(decision) {
        Some(verdict) => {
          let (verdict, verdict_warning) = normalized_verdict(
            definition, verdict,
          )
          let reason = decision_reason(decision)
          let next_action = decision_next_action(decision)
          store.save_controller_decision(JobControllerDecision::{
            id: controller_decision_id(run.id, step.id),
            controller_job_id: state.controller_job_id,
            controller_run_id: run.id,
            iteration_id,
            step_id: step.id,
            verdict,
            reason,
            next_action,
            metadata: decision_metadata_with_warning(
              decision_metadata_with_schema(decision, result_schema),
              verdict_warning,
            ),
            created_at: now_ms,
            updated_at: now_ms,
          })
          match decision_next_iteration(decision) {
            Some(next_iteration) => {
              let title_field = controller_next_iteration_field(
                definition, "title", "title",
              )
              let hypothesis_field = controller_next_iteration_field(
                definition, "hypothesis", "hypothesis",
              )
              let objective_field = controller_next_iteration_field(
                definition, "objective", "objective",
              )
              let id_field = controller_next_iteration_field(
                definition, "id", "id",
              )
              let edge_kind_field = controller_next_iteration_field(
                definition, "edge_kind", "edge_kind",
              )
              let metadata_field = controller_next_iteration_field(
                definition, "metadata", "metadata",
              )
              match mapped_object_string(next_iteration, title_field) {
                Some(title) => {
                  let hypothesis = mapped_object_string(
                    next_iteration,
                    hypothesis_field,
                    secondary=Some(objective_field),
                  ).unwrap_or(title)
                  let next_iteration_id = controller_next_iteration_id(
                    run.id,
                    step.id,
                    provided=mapped_object_string(next_iteration, id_field),
                  )
                  let edge_kind = mapped_object_string(
                    next_iteration, edge_kind_field,
                  ).unwrap_or("branches")
                  let next_metadata = match next_iteration {
                    Object(fields) =>
                      match fields.get(metadata_field) {
                        Some(metadata) => metadata
                        None => {}
                      }
                    _ => {}
                  }
                  if store.get_controller_iteration(next_iteration_id) is None {
                    store.save_controller_iteration(JobControllerIteration::{
                      id: next_iteration_id,
                      controller_job_id: state.controller_job_id,
                      controller_run_id: run.id,
                      parent_iteration_id: Some(iteration_id),
                      title,
                      hypothesis,
                      status: "pending",
                      decision: None,
                      child_job_ids: [],
                      child_run_ids: [],
                      metadata: next_metadata,
                      created_at: now_ms,
                      updated_at: now_ms,
                    })
                  }
                  let edge_id = "\{run.id}:edge:\{step.id}:\{next_iteration_id}"
                  if !controller_edge_exists(
                      store,
                      state.controller_job_id,
                      edge_id,
                    ) {
                    store.save_controller_lineage_edge(JobControllerLineageEdge::{
                      id: edge_id,
                      controller_job_id: state.controller_job_id,
                      from_iteration_id: iteration_id,
                      to_iteration_id: next_iteration_id,
                      edge_kind,
                      metadata: next_metadata,
                      created_at: now_ms,
                    })
                  }
                  store.save_controller_state(JobControllerState::{
                    ..state,
                    frontier: append_unique(state.frontier, next_iteration_id),
                    updated_at: now_ms,
                  })
                }
                None => ()
              }
            }
            _ => ()
          }
        }
        None => ()
      }
    _ => ()
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
