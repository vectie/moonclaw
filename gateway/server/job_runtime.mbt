///|
fn Gateway::job_should_cancel(self : Gateway, run_id : String) -> Bool {
  self.job_app.state().should_cancel(run_id)
}

///|
fn Gateway::job_should_force_stop(self : Gateway, run_id : String) -> Bool {
  self.job_app.state().should_force_stop(run_id)
}

///|
fn Gateway::clear_job_control_requests(self : Gateway, run_id : String) -> Unit {
  self.job_app.state().clear_control_requests(run_id)
}

///|
fn Gateway::new_workflow_engine(self : Gateway) -> @job.WorkflowEngine {
  self.job_app.new_workflow_engine()
}

///|
async fn Gateway::launch_job_run(self : Gateway, run_id : String) -> Unit {
  @async.with_task_group(group => {
    group.spawn_bg(() => self.execute_job_run_async(run_id), no_wait=true)
  }) catch {
    error => self.logger.warn("Failed to launch job run \{run_id}: \{error}")
  }
}

///|
async fn Gateway::execute_job_run_async(
  self : Gateway,
  run_id : String,
) -> Unit {
  self.clear_job_control_requests(run_id)
  @job.execute_run_lifecycle(
    self.job_runtime(),
    run_id,
    current_time_ms,
    fn() { self.new_workflow_engine() },
    control=@job.WorkflowExecutionControl::new(
      should_cancel=fn() { self.job_should_cancel(run_id) },
      should_force_stop=fn() { self.job_should_force_stop(run_id) },
    ),
    hooks=@job.execution_notification_hooks(
      self.job_app.state(),
      current_time_ms,
      async fn(target, content) { self.send_job_notification(target, content) },
      on_info=async fn(message) { self.logger.info(message) },
      on_warn=async fn(message) { self.logger.warn(message) },
    ),
  )
  self.clear_job_control_requests(run_id)
}

///|
fn Gateway::job_run_for_definition(
  self : Gateway,
  job_id : String,
) -> @job.JobRun? {
  match self.job_runtime().active_run_id(job_id) {
    Some(run_id) => self.job_runtime().store().get_run(run_id)
    None => {
      let candidates = self
        .job_runtime()
        .store()
        .list_runs()
        .filter(fn(run) {
          run.job_id == job_id &&
          (
            run.status is @job.RunStatus::Pending ||
            run.status is @job.RunStatus::Running
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
        Some(candidates[0])
      }
    }
  }
}

///|
async fn Gateway::trigger_job_definition(
  self : Gateway,
  job_id : String,
  trigger? : @job.TriggerSource = @job.TriggerSource::Manual,
) -> Result[@job.JobRun, String] {
  let definition = match self.job_runtime().store().get_definition(job_id) {
    Some(definition) => definition
    None => return Err("Unknown job definition: \{job_id}")
  }
  if definition.workflow_id is None {
    return Err("Job \{job_id} has no workflow_id")
  }
  let run = match
    self
    .job_runtime()
    .trigger_definition(
      self.uuid.v4().to_string(),
      job_id,
      trigger,
      current_time_ms(),
    ) {
    Ok(run) => run
    Err(error) => return Err(error)
  }
  self.launch_job_run(run.id)
  Ok(run)
}

///|
async fn Gateway::cancel_job_definition_run(
  self : Gateway,
  job_id : String,
  force? : Bool = false,
) -> Result[@job.JobRun, String] {
  let run = match self.job_run_for_definition(job_id) {
    Some(run) => run
    None => return Err("No pending or running job found for \{job_id}")
  }
  match run.status {
    @job.RunStatus::Pending => {
      let cancelled = match
        self
        .job_runtime()
        .cancel_run(
          run.id,
          current_time_ms(),
          summary=Some(
            if force {
              "Force-cancelled before start"
            } else {
              "Cancelled before start"
            },
          ),
        ) {
        Some(cancelled) => cancelled
        None => return Err("Failed to cancel pending run: \{run.id}")
      }
      self.clear_job_control_requests(run.id)
      Ok(cancelled)
    }
    @job.RunStatus::Running => {
      self.job_app.state().request_stop(run.id, force~)
      Ok(run)
    }
    _ => Err("Job run \{run.id} is already terminal")
  }
}
