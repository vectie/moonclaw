///|
pub fn render_unknown_job_or_run_message(job_or_run_id : String) -> String {
  "Unknown job or run id: \{job_or_run_id}"
}

///|
pub fn render_job_stop_usage(force : Bool) -> String {
  if force {
    "Usage: /job-force-stop <job_id|run_id>"
  } else {
    "Usage: /job-stop <job_id|run_id>"
  }
}

///|
pub fn render_job_stop_requested(
  definition_id : String,
  run_id : String,
  force : Bool,
) -> String {
  if force {
    "Force-stop requested for `\{definition_id}` (`\{run_id}`)."
  } else {
    "Stop requested for `\{definition_id}` (`\{run_id}`)."
  }
}

///|
pub fn render_jobs_command_reply(
  store : SystemStore,
  runs : Array[JobRun],
) -> String {
  render_active_runs(store, runs)
}

///|
pub async fn render_job_status_command_reply(
  store : SystemStore,
  job_or_run_id : String,
  now_ms : Int,
  prefix : String,
  active_run_id? : String? = None,
) -> String? {
  match resolve_status_target(store, job_or_run_id, active_run_id~) {
    Some((definition, run)) =>
      Some(render_status_text(store, definition, run, prefix, now_ms))
    None => None
  }
}

///|
pub async fn render_job_workspace_command_reply(
  store : SystemStore,
  job_or_run_id : String,
  active_run_id? : String? = None,
) -> String? {
  match resolve_status_target(store, job_or_run_id, active_run_id~) {
    Some((definition, run)) =>
      Some(render_run_workspace_status(store, definition, run))
    None => None
  }
}

///|
pub async fn request_job_stop(
  store : SystemStore,
  job_or_run_id : String,
  cancel : async (String, Bool) -> Result[JobRun, String],
  force? : Bool = false,
  active_run_id? : String? = None,
) -> Result[String, String] {
  let trimmed = job_or_run_id.trim().to_string()
  let (definition, _run) = match
    resolve_status_target(store, trimmed, active_run_id~) {
    Some(resolved) => resolved
    None => return Err(render_unknown_job_or_run_message(trimmed))
  }
  match cancel(definition.id, force) {
    Ok(run) => Ok(render_job_stop_requested(definition.id, run.id, force))
    Err(error) => Err(error)
  }
}
