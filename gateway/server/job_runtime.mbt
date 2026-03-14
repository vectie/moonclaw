///|
fn Gateway::job_should_cancel(self : Gateway, run_id : String) -> Bool {
  self.job_cancel_requests.get(run_id).unwrap_or(false)
}

///|
fn Gateway::job_should_force_stop(self : Gateway, run_id : String) -> Bool {
  self.job_force_stop_requests.get(run_id).unwrap_or(false)
}

///|
fn Gateway::clear_job_control_requests(self : Gateway, run_id : String) -> Unit {
  self.job_cancel_requests.remove(run_id) |> ignore()
  self.job_force_stop_requests.remove(run_id) |> ignore()
}

///|
fn Gateway::new_workflow_engine(self : Gateway) -> @job.WorkflowEngine {
  let engine = @job.WorkflowEngine::new(runtime=self.jobs)
  engine.register_handler(@job.analysis_step_handler(runtime=self.jobs))
  engine.register_handler(
    @job.subjob_step_handler(
      runtime=self.jobs,
      planner=@job.ProposalPlanner::new(run=async fn(request_text, cwd, home) {
        @job.plan_job_proposal(
          self.uuid.v4().to_string(),
          request_text,
          current_time_ms(),
          cwd~,
          home~,
        )
      }),
      compiler=@job.ProposalCompiler::new(run=fn(proposal, now_ms, cwd, home) {
        @job.compile_job_proposal(proposal, now_ms, cwd, home)
      }),
      engine_factory=fn() { self.new_workflow_engine() },
      next_run_id=fn() { self.uuid.v4().to_string() },
    ),
  )
  engine.register_handler(
    @job.research_topic_sync_step_handler(runtime=self.jobs),
  )
  engine.register_handler(
    @job.research_paper_fetch_step_handler(runtime=self.jobs),
  )
  engine.register_handler(
    @job.research_paper_parse_step_handler(runtime=self.jobs),
  )
  engine.register_handler(
    @job.research_paper_analyze_step_handler(runtime=self.jobs),
  )
  engine
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
  let run = match self.jobs.store().get_run(run_id) {
    Some(run) => run
    None => {
      self.logger.warn("Skipping unknown job run: \{run_id}")
      return
    }
  }
  let definition = match self.jobs.store().get_definition(run.job_id) {
    Some(definition) => definition
    None => {
      self.logger.warn(
        "Skipping job run \{run_id}; missing definition \{run.job_id}",
      )
      ignore(
        self.jobs.mark_run_failed(
          run_id,
          current_time_ms(),
          "Missing job definition: \{run.job_id}",
          summary=Some("Job execution failed"),
        ),
      )
      return
    }
  }
  if definition.workflow_id is None {
    self.logger.warn("Skipping job run \{run_id}; no workflow configured")
    ignore(
      self.jobs.mark_run_failed(
        run_id,
        current_time_ms(),
        "Job \{definition.id} has no workflow_id",
        summary=Some("Job execution failed"),
      ),
    )
    return
  }
  self.logger.info("Starting job run \{definition.id} -> \{run_id}")
  self.clear_job_control_requests(run_id)
  self.notify_job_run_started(definition, run)
  let engine = self.new_workflow_engine()
  let control = @job.WorkflowExecutionControl::new(
    should_cancel=fn() { self.job_should_cancel(run_id) },
    should_force_stop=fn() { self.job_should_force_stop(run_id) },
  )
  let result = engine.execute_run(run_id, current_time_ms, control~) catch {
    error => {
      let message = "Job run \{run_id} crashed before completion: \{error}"
      self.logger.warn(message)
      ignore(
        self.jobs.mark_run_failed(
          run_id,
          current_time_ms(),
          message,
          summary=Some("Job execution crashed"),
        ),
      )
      match self.jobs.store().get_run(run_id) {
        Some(updated_run) =>
          self.notify_job_run_finished(definition, updated_run)
        None => ()
      }
      self.clear_job_control_requests(run_id)
      return
    }
  }
  match result {
    Ok(result) => {
      self.logger.info(
        "Completed job run \{result.run.job_id} -> \{result.run.id} with \{result.steps.length()} step(s)",
      )
      self.notify_job_run_finished(definition, result.run)
    }
    Err(error) => {
      self.logger.warn("Job run \{run_id} finished with error: \{error}")
      match self.jobs.store().get_run(run_id) {
        Some(updated_run) =>
          self.notify_job_run_finished(definition, updated_run)
        None => ()
      }
    }
  }
  self.clear_job_control_requests(run_id)
}

///|
fn Gateway::job_run_for_definition(
  self : Gateway,
  job_id : String,
) -> @job.JobRun? {
  match self.jobs.active_run_id(job_id) {
    Some(run_id) => self.jobs.store().get_run(run_id)
    None => {
      let candidates = self.jobs
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
  let definition = match self.jobs.store().get_definition(job_id) {
    Some(definition) => definition
    None => return Err("Unknown job definition: \{job_id}")
  }
  if definition.workflow_id is None {
    return Err("Job \{job_id} has no workflow_id")
  }
  let run = match
    self.jobs.trigger_definition(
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
        self.jobs.cancel_run(
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
      self.job_cancel_requests.set(run.id, true)
      if force {
        self.job_force_stop_requests.set(run.id, true)
      }
      Ok(run)
    }
    _ => Err("Job run \{run.id} is already terminal")
  }
}
