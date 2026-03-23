///|

///|
let gateway_root_groups : Map[Int, @async.TaskGroup[Unit]] = {}

///|
fn Gateway::root_group(self : Gateway) -> @async.TaskGroup[Unit]? {
  gateway_root_groups.get(self.port)
}

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
fn gateway_child_run_session_key(child_run_id : String) -> String {
  "job-child:\{child_run_id}"
}

///|
fn gateway_child_acp_session_id(child_run_id : String) -> String {
  "acp-session-\{child_run_id}"
}

///|
fn gateway_child_acp_run_id(child_run_id : String) -> String {
  "acp-\{child_run_id}"
}

///|
fn acp_execution_requested(config : @job.SubjobStepConfig) -> Bool {
  match config.execution_mode {
    Some(mode) => mode.trim().to_string() == "acp"
    None => false
  }
}

///|
fn acp_analysis_execution_requested(request : @job.AnalysisRequest) -> Bool {
  match request.execution_mode {
    Some(mode) => mode.trim().to_string() == "acp"
    None => false
  }
}

///|
async fn Gateway::child_run_step_started(
  self : Gateway,
  child_run : @job.JobRun,
  step : @job.WorkflowStepDefinition,
  now_ms : Int,
) -> @job.JobStepRun {
  let step_run = @job.JobStepRun::{
    id: "\{child_run.id}:\{step.id}",
    run_id: child_run.id,
    step_id: step.id,
    status: @job.RunStatus::Running,
    started_at: Some(now_ms),
    completed_at: None,
    metrics: {},
    logs: [],
    retry_count: 0,
    summary: None,
    output: None,
    error: None,
  }
  self.job_runtime().store().save_step_run(step_run)
  step_run
}

///|
async fn Gateway::finish_child_run_step(
  self : Gateway,
  step_run : @job.JobStepRun,
  status : @job.RunStatus,
  now_ms : Int,
  output? : Json? = None,
  summary? : String? = None,
  error? : String? = None,
  logs? : Array[String] = [],
) -> Unit {
  self
  .job_runtime()
  .store()
  .save_step_run(@job.JobStepRun::{
    ..step_run,
    status,
    completed_at: Some(now_ms),
    output,
    summary,
    error,
    logs,
  })
}

///|
fn acp_child_run_message(request : @job.AnalysisRequest) -> String {
  [request.system_prompt, request.prompt]
  .filter(fn(section) { !section.trim().to_string().is_blank() })
  .join("\n\n")
}

///|
fn gateway_analysis_session_key(run_id : String, step_id : String) -> String {
  "job-analysis:\{run_id}:\{step_id}"
}

///|
fn gateway_analysis_acp_session_id(run_id : String, step_id : String) -> String {
  "acp-analysis-session-\{run_id}-\{step_id}"
}

///|
fn gateway_analysis_acp_run_id(run_id : String, step_id : String) -> String {
  "acp-analysis-\{run_id}-\{step_id}"
}

///|
async fn Gateway::execute_analysis_via_acp(
  self : Gateway,
  request : @job.AnalysisRequest,
) -> Result[@job.AnalysisExecution, String] {
  let target_id = match request.execution_target {
    Some(target_id) if !target_id.trim().to_string().is_blank() => target_id
    _ => return Err("ACP analysis execution requires execution_target")
  }
  let now_ms = current_time_ms()
  let session = match
    self
    .acp_runtime()
    .open_session(
      gateway_analysis_acp_session_id(request.run_id, request.step_id),
      target_id,
      gateway_analysis_session_key(request.run_id, request.step_id),
      now_ms,
      metadata={
        "job_id": request.job_id,
        "job_run_id": request.run_id,
        "job_step_id": request.step_id,
      },
    ) {
    Ok(session) => session
    Err(error) => return Err(error)
  }
  let target = match self.acp_runtime().get_target(target_id) {
    Some(target) => target
    None => return Err("Unknown ACP target: \{target_id}")
  }
  let metadata : Json = {
    "job_id": request.job_id,
    "job_run_id": request.run_id,
    "job_step_id": request.step_id,
    "execution_mode": request.execution_mode,
    "execution_target": request.execution_target,
  }
  let run_id = gateway_analysis_acp_run_id(request.run_id, request.step_id)
  let run_request = @acp.new_run_request(
    message=acp_child_run_message(request),
    run_id~,
    model?=if request.model_name == "default" {
      None
    } else {
      Some(request.model_name)
    },
    cwd=request.cwd,
    metadata~,
  )
  let launch = match @acp.prepare_launch_plan(target, session, run_request) {
    Ok(plan) => plan
    Err(error) => return Err(error)
  }
  ignore(
    self
    .acp_runtime()
    .start_run(
      run_id,
      session,
      target,
      run_request.to_json(),
      launch.to_json(),
      now_ms,
    ),
  )
  ignore(self.acp_runtime().set_session_status(session.id, "running", now_ms))
  let outcome = match
    self.execute_managed_acp_process(run_id, launch, run_request) {
    Ok(outcome) => outcome
    Err(error) => {
      let failed_at = current_time_ms()
      ignore(
        self
        .acp_runtime()
        .finish_run(run_id, "failed", failed_at, error=Some(error)),
      )
      self.finalize_acp_session_after_run(
        session.id,
        "failed",
        failed_at,
        error=Some(error),
      )
      return Err(error)
    }
  }
  let finished_at = current_time_ms()
  ignore(
    self
    .acp_runtime()
    .finish_run(
      run_id,
      outcome.status,
      finished_at,
      result=Some(outcome.result),
      error=outcome.error,
    ),
  )
  self.finalize_acp_session_after_run(
    session.id,
    outcome.status,
    finished_at,
    error=outcome.error,
  )
  if outcome.status != "completed" {
    return Err(outcome.error.unwrap_or("ACP analysis execution failed"))
  }
  let content = match outcome.result {
    { "content": String(content), .. } => content
    _ => outcome.result.stringify()
  }
  Ok(@job.AnalysisExecution::{
    model_name: if request.model_name == "default" {
      target.label.unwrap_or(target.id)
    } else {
      request.model_name
    },
    content,
    conversation_id: Some(run_id),
    usage: None,
    metadata: {
      "job_id": request.job_id,
      "run_id": request.run_id,
      "step_id": request.step_id,
      "execution_mode": "acp",
      "execution_target": target_id,
      "acp_run_id": run_id,
      "acp_session_id": session.id,
    },
  })
}

///|
async fn Gateway::execute_child_run_via_acp(
  self : Gateway,
  request : @job.ChildRunExecutionRequest,
) -> Result[@job.ChildRunExecutionResult, String] {
  let target_id = match request.config.execution_target {
    Some(target_id) if !target_id.trim().to_string().is_blank() => target_id
    _ => return Err("ACP child execution requires execution_target")
  }
  let workflow = request.compilation.workflow
  guard workflow.steps.length() == 1 else {
    return Err(
      "ACP child execution currently supports workflows with exactly one step",
    )
  }
  let step = workflow.steps[0]
  guard step.kind == "job.analysis" else {
    return Err(
      "ACP child execution currently supports only single-step job.analysis workflows",
    )
  }
  let config : @job.AnalysisStepConfig = @json.from_json(step.config) catch {
    error => return Err("Invalid ACP child analysis config: \{error}")
  }
  let now_ms = current_time_ms()
  let started_run = match
    self.job_runtime().mark_run_started(request.child_run.id, now_ms) {
    Some(run) => run
    None => return Err("Missing child run: \{request.child_run.id}")
  }
  let step_run = self.child_run_step_started(started_run, step, now_ms)
  let context = @job.WorkflowStepContext::new(
    run=started_run,
    step~,
    control=request.control,
  )
  let analysis_request = @job.build_analysis_request(
    self.job_runtime().store(),
    context,
    config,
  )
  let session = match
    self
    .acp_runtime()
    .open_session(
      gateway_child_acp_session_id(started_run.id),
      target_id,
      gateway_child_run_session_key(started_run.id),
      now_ms,
      metadata={
        "job_id": started_run.job_id,
        "job_run_id": started_run.id,
        "parent_run_id": request.parent_context.run.id,
        "parent_step_id": request.parent_context.step.id,
      },
    ) {
    Ok(session) => session
    Err(error) => {
      self.finish_child_run_step(
        step_run,
        @job.RunStatus::Failed,
        now_ms,
        summary=Some("ACP child execution failed"),
        error=Some(error),
      )
      ignore(
        self
        .job_runtime()
        .mark_run_failed(
          started_run.id,
          now_ms,
          error,
          summary=Some("ACP child execution failed"),
        ),
      )
      return Err(error)
    }
  }
  let target = match self.acp_runtime().get_target(target_id) {
    Some(target) => target
    None => return Err("Unknown ACP target: \{target_id}")
  }
  let metadata : Json = {
    "job_id": started_run.job_id,
    "job_run_id": started_run.id,
    "job_step_id": step.id,
    "parent_run_id": request.parent_context.run.id,
    "parent_step_id": request.parent_context.step.id,
    "execution_mode": request.config.execution_mode,
    "execution_target": request.config.execution_target,
  }
  let run_request = @acp.new_run_request(
    message=acp_child_run_message(analysis_request),
    run_id=gateway_child_acp_run_id(started_run.id),
    model?=if analysis_request.model_name == "default" {
      None
    } else {
      Some(analysis_request.model_name)
    },
    cwd=analysis_request.cwd,
    metadata~,
  )
  let launch = match @acp.prepare_launch_plan(target, session, run_request) {
    Ok(plan) => plan
    Err(error) => return Err(error)
  }
  ignore(
    self
    .acp_runtime()
    .start_run(
      gateway_child_acp_run_id(started_run.id),
      session,
      target,
      run_request.to_json(),
      launch.to_json(),
      now_ms,
    ),
  )
  ignore(self.acp_runtime().set_session_status(session.id, "running", now_ms))
  let outcome = match
    self.execute_managed_acp_process(
      gateway_child_acp_run_id(started_run.id),
      launch,
      run_request,
    ) {
    Ok(outcome) => outcome
    Err(error) => {
      let failed_at = current_time_ms()
      self.finish_child_run_step(
        step_run,
        @job.RunStatus::Failed,
        failed_at,
        summary=Some("ACP child execution failed"),
        error=Some(error),
      )
      ignore(
        self
        .job_runtime()
        .mark_run_failed(
          started_run.id,
          failed_at,
          error,
          summary=Some("ACP child execution failed"),
        ),
      )
      ignore(
        self
        .acp_runtime()
        .finish_run(
          gateway_child_acp_run_id(started_run.id),
          "failed",
          failed_at,
          error=Some(error),
        ),
      )
      self.finalize_acp_session_after_run(
        session.id,
        "failed",
        failed_at,
        error=Some(error),
      )
      return Err(error)
    }
  }
  let finished_at = current_time_ms()
  ignore(
    self
    .acp_runtime()
    .finish_run(
      gateway_child_acp_run_id(started_run.id),
      outcome.status,
      finished_at,
      result=Some(outcome.result),
      error=outcome.error,
    ),
  )
  self.finalize_acp_session_after_run(
    session.id,
    outcome.status,
    finished_at,
    error=outcome.error,
  )
  if outcome.status != "completed" {
    let error = outcome.error.unwrap_or("ACP child execution failed")
    self.finish_child_run_step(
      step_run,
      @job.RunStatus::Failed,
      finished_at,
      summary=Some("ACP child execution failed"),
      error=Some(error),
      logs=["execution mode: acp", "execution target: \{target_id}"],
    )
    ignore(
      self
      .job_runtime()
      .mark_run_failed(
        started_run.id,
        finished_at,
        error,
        summary=Some("ACP child execution failed"),
      ),
    )
    return Err(error)
  }
  let content = match outcome.result {
    { "content": String(content), .. } => content
    _ => outcome.result.stringify()
  }
  let output : Json = {
    "status": "completed",
    "model": analysis_request.model_name,
    "content": content,
    "execution_mode": "acp",
    "execution_target": target_id,
    "acp_run_id": gateway_child_acp_run_id(started_run.id),
    "acp_session_id": session.id,
  }
  self.finish_child_run_step(
    step_run,
    @job.RunStatus::Succeeded,
    finished_at,
    output=Some(output),
    summary=Some("ACP analysis completed"),
    logs=[
      "execution mode: acp",
      "execution target: \{target_id}",
      "acp run: \{gateway_child_acp_run_id(started_run.id)}",
    ],
  )
  ignore(
    self
    .job_runtime()
    .mark_run_succeeded(
      started_run.id,
      finished_at,
      summary=Some("ACP child execution completed"),
    ),
  )
  let outputs : Map[String, Json] = {}
  outputs.set(step.id, output)
  Ok(@job.ChildRunExecutionResult::{ outputs, })
}

///|
fn Gateway::job_child_run_executor(self : Gateway) -> @job.ChildRunExecutor {
  @job.ChildRunExecutor::new(run=async fn(request) {
    if !acp_execution_requested(request.config) {
      return Ok(None)
    }
    match self.execute_child_run_via_acp(request) {
      Ok(result) => Ok(Some(result))
      Err(error) => Err(error)
    }
  })
}

///|
fn Gateway::analysis_executor(self : Gateway) -> @job.AnalysisExecutor {
  let fallback_executor = @job.default_analysis_executor()
  @job.AnalysisExecutor::new(run=async fn(request) {
    if !acp_analysis_execution_requested(request) {
      return (fallback_executor.run)(request)
    }
    self.execute_analysis_via_acp(request)
  })
}

///|
fn Gateway::new_workflow_engine(self : Gateway) -> @job.WorkflowEngine {
  self.job_app.new_workflow_engine_with_executors(
    child_executor=Some(self.job_child_run_executor()),
    analysis_executor=Some(self.analysis_executor()),
  )
}

///|
async fn Gateway::refresh_proposal_definition_if_present(
  self : Gateway,
  job_id : String,
) -> Unit {
  for proposal in self.job_runtime().store().list_job_proposals() {
    if proposal.job_id == Some(job_id) &&
      proposal.status is @job.JobProposalStatus::Confirmed {
      let compilation = self.job_app.compile_proposal(proposal)
      self.job_runtime().register_definition(compilation.definition)
      self.job_runtime().register_workflow(compilation.workflow)
      for binding in compilation.bindings {
        self.job_runtime().store().save_chat_binding(binding)
      }
      break
    }
  }
}

///|
async fn Gateway::launch_job_run(self : Gateway, run_id : String) -> Unit {
  match self.root_group() {
    Some(group) =>
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        self.execute_job_run_async(run_id) catch {
          error =>
            self.logger.warn("Job run \{run_id} crashed after launch: \{error}")
        }
      })
    None =>
      self.logger.warn(
        "Skipped launching job run \{run_id}: gateway task group is not active",
      )
  }
}

///|
async fn Gateway::resume_pending_job_runs(self : Gateway) -> Unit {
  let pending_runs = self
    .job_runtime()
    .store()
    .list_runs()
    .filter(fn(run) { run.status is @job.RunStatus::Pending })
  for run in pending_runs {
    self.refresh_proposal_definition_if_present(run.job_id)
    self.launch_job_run(run.id)
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
  self.refresh_proposal_definition_if_present(job_id)
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
      @job.human_readable_run_id(current_time_ms(), self.uuid.v4().to_string()),
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
