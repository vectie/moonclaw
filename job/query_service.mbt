///|
fn run_elapsed_ms(run : JobRun, now_ms : Int) -> Int {
  match run.started_at {
    Some(started_at) => now_ms - started_at
    None => 0
  }
}

///|
pub fn current_step_label(
  store : SystemStore,
  definition : JobDefinition,
  run_id : String,
) -> String {
  let steps = store.list_step_runs(run_id)
  let running = steps.filter(fn(step) { step.status is RunStatus::Running })
  if !running.is_empty() {
    return running[0].step_id
  }
  if steps.is_empty() {
    match definition.workflow_id {
      Some(workflow_id) =>
        match store.get_workflow(workflow_id) {
          Some(workflow) =>
            workflow.steps.get(0).map(fn(step) { step.id }).unwrap_or("pending")
          None => "pending"
        }
      None => "pending"
    }
  } else {
    steps.sort_by(fn(left, right) {
      let left_ts = left.completed_at.unwrap_or(left.started_at.unwrap_or(0))
      let right_ts = right.completed_at.unwrap_or(right.started_at.unwrap_or(0))
      right_ts.compare(left_ts)
    })
    steps[0].step_id
  }
}

///|
fn definition_created_at_label(definition : JobDefinition) -> String {
  format_job_timestamp(definition.created_at)
}

///|
pub fn child_runs_for(store : SystemStore, run_id : String) -> Array[JobRun] {
  store.list_runs().filter(fn(run) { run.parent_run_id == Some(run_id) })
}

///|
pub async fn render_status_text(
  store : SystemStore,
  definition : JobDefinition,
  run : JobRun,
  prefix : String,
  now_ms : Int,
) -> String {
  let steps = store.list_step_runs(run.id)
  let total_steps = match definition.workflow_id {
    Some(workflow_id) =>
      store
      .get_workflow(workflow_id)
      .map(fn(workflow) { workflow.steps.length() })
      .unwrap_or(steps.length())
    None => steps.length()
  }
  let done_steps = steps
    .filter(fn(step) { step.status is RunStatus::Succeeded })
    .length()
  let current_step = current_step_label(store, definition, run.id)
  let elapsed_ms = run_elapsed_ms(run, now_ms)
  let lineage_line = match (run.parent_run_id, run.parent_step_id) {
    (Some(parent_run_id), Some(parent_step_id)) =>
      Some(
        "Lineage: child of run \{parent_run_id} via step \{parent_step_id} (depth \{run.depth})",
      )
    (Some(parent_run_id), None) =>
      Some("Lineage: child of run \{parent_run_id} (depth \{run.depth})")
    _ => if run.depth > 0 { Some("Lineage: depth \{run.depth}") } else { None }
  }
  let family = match definition.config {
    { "family": String(family), .. } => family
    _ => "unknown"
  }
  let run_events = store.list_run_events(run.id)
  let latest_event = if run_events.is_empty() {
    None
  } else {
    run_events.get(run_events.length() - 1)
  }
  let latest_event_line = match latest_event {
    Some(event) => "Latest event: \{event.event_type} - \{event.message}"
    None => "Latest event: none"
  }
  let child_runs = child_runs_for(store, run.id).map(fn(child) {
    ChildRunStatus::{
      run_id: child.id,
      status: child.status.to_json().stringify(),
    }
  })
  render_job_status(
    JobStatusSnapshot::{
      definition_id: definition.id,
      definition_title: definition_display_title(definition),
      created_at_label: definition_created_at_label(definition),
      run_id: run.id,
      status: run.status.to_json().stringify(),
      family,
      current_step,
      done_steps,
      total_steps,
      elapsed_ms,
      lineage_line,
      summary: run.summary,
      error: run.error,
      child_runs,
      latest_event_line,
    },
    prefix,
  )
}

///|
pub fn render_active_runs(store : SystemStore, runs : Array[JobRun]) -> String {
  let summaries : Array[ActiveJobSnapshot] = []
  for run in runs {
    match store.get_definition(run.job_id) {
      Some(definition) => {
        let family = match definition.config {
          { "family": String(family), .. } => family
          _ => "unknown"
        }
        summaries.push(ActiveJobSnapshot::{
          definition_id: definition.id,
          definition_title: definition_display_title(definition),
          created_at_label: definition_created_at_label(definition),
          run_id: run.id,
          status: run.status.to_json().stringify(),
          family,
          depth: run.depth,
          current_step: current_step_label(store, definition, run.id),
        })
      }
      None => ()
    }
  }
  render_active_jobs(summaries)
}

///|
pub fn resolve_status_target(
  store : SystemStore,
  job_or_run_id : String,
  active_run_id? : String? = None,
) -> (JobDefinition, JobRun)? {
  let trimmed = job_or_run_id.trim().to_string()
  match store.get_definition(trimmed) {
    Some(definition) =>
      match active_run_id {
        Some(run_id) =>
          match store.get_run(run_id) {
            Some(run) => Some((definition, run))
            None => None
          }
        None => {
          let candidates = store
            .list_runs()
            .filter(fn(run) {
              run.job_id == trimmed &&
              (
                run.status is RunStatus::Pending ||
                run.status is RunStatus::Running
              )
            })
          if candidates.is_empty() {
            None
          } else {
            candidates.sort_by(fn(left, right) {
              let left_ts = left.started_at.unwrap_or(0)
              let right_ts = right.started_at.unwrap_or(0)
              right_ts.compare(left_ts)
            })
            Some((definition, candidates[0]))
          }
        }
      }
    None =>
      match store.get_run(trimmed) {
        Some(run) =>
          match store.get_definition(run.job_id) {
            Some(definition) => Some((definition, run))
            None => None
          }
        None => None
      }
  }
}
