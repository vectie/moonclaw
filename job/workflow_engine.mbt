///|
pub(all) struct WorkflowExecutionControl {
  should_cancel : () -> Bool
  should_force_stop : () -> Bool
}

///|
pub fn WorkflowExecutionControl::new(
  should_cancel? : () -> Bool = fn() { false },
  should_force_stop? : () -> Bool = fn() { false },
) -> WorkflowExecutionControl {
  WorkflowExecutionControl::{ should_cancel, should_force_stop }
}

///|
pub(all) struct WorkflowStepContext {
  run : JobRun
  step : WorkflowStepDefinition
  initial_input : Json?
  outputs : Map[String, Json]
  control : WorkflowExecutionControl
}

///|
pub fn WorkflowStepContext::new(
  run~ : JobRun,
  step~ : WorkflowStepDefinition,
  initial_input? : Json? = None,
  outputs? : Map[String, Json] = {},
  control? : WorkflowExecutionControl = WorkflowExecutionControl::new(),
) -> WorkflowStepContext {
  WorkflowStepContext::{ run, step, initial_input, outputs, control }
}

///|
pub fn WorkflowStepContext::output(
  self : WorkflowStepContext,
  step_id : String,
) -> Json? {
  self.outputs.get(step_id)
}

///|
pub(all) struct WorkflowStepResult {
  output : Json
  summary : String?
  metrics : Json
  logs : Array[String]
}

///|
pub fn WorkflowStepResult::new(
  output~ : Json,
  summary? : String? = None,
  metrics? : Json = {},
  logs? : Array[String] = [],
) -> WorkflowStepResult {
  WorkflowStepResult::{ output, summary, metrics, logs }
}

///|
pub(all) struct WorkflowStepHandler {
  kind : String
  run : async (WorkflowStepContext) -> Result[WorkflowStepResult, String]
}

///|
pub fn WorkflowStepHandler::new(
  kind~ : String,
  run~ : async (WorkflowStepContext) -> Result[WorkflowStepResult, String],
) -> WorkflowStepHandler {
  WorkflowStepHandler::{ kind, run }
}

///|
pub(all) struct WorkflowExecutionResult {
  run : JobRun
  workflow : WorkflowDefinition
  outputs : Map[String, Json]
  steps : Array[JobStepRun]
}

///|
pub struct WorkflowEngine {
  runtime : RuntimeManager
  handlers : Map[String, WorkflowStepHandler]
}

///|
pub fn WorkflowEngine::new(runtime~ : RuntimeManager) -> WorkflowEngine {
  WorkflowEngine::{ runtime, handlers: {} }
}

///|
pub fn WorkflowEngine::register_handler(
  self : WorkflowEngine,
  handler : WorkflowStepHandler,
) -> Unit {
  self.handlers.set(handler.kind, handler)
}

///|
async fn WorkflowEngine::log_run_event(
  self : WorkflowEngine,
  run : JobRun,
  event_type : String,
  now_ms : Int,
  message : String,
  step_id? : String? = None,
  status? : RunStatus? = None,
  data? : Json = {},
) -> Unit {
  self.runtime
  .store()
  .append_run_event(JobRunEvent::{
    run_id: run.id,
    job_id: run.job_id,
    event_type,
    timestamp: now_ms,
    step_id,
    status,
    message,
    data,
  })
}

///|
fn WorkflowEngine::handler_for_step(
  self : WorkflowEngine,
  step : WorkflowStepDefinition,
) -> WorkflowStepHandler? {
  self.handlers.get(step.kind)
}

///|
fn WorkflowEngine::step_retry_policy(
  step : WorkflowStepDefinition,
) -> RetryPolicy {
  step.retry_policy.unwrap_or(RetryPolicy::{ max_attempts: 1, backoff_ms: None })
}

///|
fn WorkflowEngine::step_run_record(
  run_id : String,
  step : WorkflowStepDefinition,
  status : RunStatus,
  started_at : Int?,
  finished_at : Int?,
  retry_count : Int,
  logs : Array[String],
  metrics? : Json = {},
  summary? : String? = None,
  output? : Json? = None,
  error? : String? = None,
) -> JobStepRun {
  JobStepRun::{
    id: "\{run_id}:\{step.id}",
    run_id,
    step_id: step.id,
    status,
    started_at,
    finished_at,
    metrics,
    logs,
    retry_count,
    summary,
    output,
    error,
  }
}

///|
fn WorkflowEngine::control_message(
  control : WorkflowExecutionControl,
) -> String? {
  if (control.should_force_stop)() {
    Some("Workflow force-stopped")
  } else if (control.should_cancel)() {
    Some("Workflow cancelled")
  } else {
    None
  }
}

///|
fn waiting_for_input_message(error : String) -> String? {
  let prefix = "Analysis requires input: "
  if error.has_prefix(prefix) {
    Some(error[prefix.length():].trim().to_string())
  } else {
    None
  }
}

///|
fn disable_waiting_for_input_in_job_config(job_config : Json) -> Bool? {
  match waiting_for_input_disabled_from_metadata(job_config) {
    Some(value) => Some(value)
    None =>
      match job_config {
        Object(obj) =>
          match obj.get("profile_metadata") {
            Some(profile_metadata) =>
              waiting_for_input_disabled_from_metadata(profile_metadata)
            None => None
          }
        _ => None
      }
  }
}

///|
fn workflow_disable_waiting_for_input(
  step : WorkflowStepDefinition,
  definition : JobDefinition,
) -> Bool {
  match waiting_for_input_disabled_from_metadata(step.config) {
    Some(value) => value
    None =>
      disable_waiting_for_input_in_job_config(definition.config).unwrap_or(
        false,
      )
  }
}

///|
fn best_effort_on_missing_input_in_job_config(job_config : Json) -> Bool? {
  match best_effort_on_missing_input_from_metadata(job_config) {
    Some(value) => Some(value)
    None =>
      match job_config {
        Object(obj) =>
          match obj.get("profile_metadata") {
            Some(profile_metadata) =>
              best_effort_on_missing_input_from_metadata(profile_metadata)
            None => None
          }
        _ => None
      }
  }
}

///|
fn workflow_best_effort_on_missing_input(
  step : WorkflowStepDefinition,
  definition : JobDefinition,
) -> Bool {
  match best_effort_on_missing_input_from_metadata(step.config) {
    Some(value) => value
    None =>
      match best_effort_on_missing_input_in_job_config(definition.config) {
        Some(value) => value
        None =>
          definition.kind == "job.controller" &&
          (step.id.contains("locate") || step.id.contains("search"))
      }
  }
}

///|
fn waiting_message_items(message : String) -> Array[String] {
  let items : Array[String] = []
  for raw in message.split(";") {
    let trimmed = raw.trim().to_string()
    if !trimmed.is_blank() {
      items.push(trimmed)
    }
  }
  items
}

///|
fn best_effort_waiting_output(
  step : WorkflowStepDefinition,
  message : String,
) -> Json {
  {
    "status": "best_effort_missing_input",
    "step_id": step.id,
    "message": message,
    "missing_inputs": waiting_message_items(message),
    "review_queued": true,
  }
}

///|
pub async fn WorkflowEngine::execute_run(
  self : WorkflowEngine,
  run_id : String,
  now : () -> Int,
  initial_input? : Json? = None,
  control? : WorkflowExecutionControl = WorkflowExecutionControl::new(),
) -> Result[WorkflowExecutionResult, String] {
  let store = self.runtime.store()
  let initial_run = match store.get_run(run_id) {
    Some(run) => run
    None => return Err("Unknown job run: \{run_id}")
  }
  let definition = match store.get_definition(initial_run.job_id) {
    Some(definition) => definition
    None => return Err("Unknown job definition: \{initial_run.job_id}")
  }
  let workflow_id = match definition.workflow_id {
    Some(workflow_id) => workflow_id
    None => return Err("Job \{definition.id} has no workflow_id")
  }
  let workflow = match store.get_workflow(workflow_id) {
    Some(workflow) => workflow
    None => return Err("Unknown workflow definition: \{workflow_id}")
  }
  let resuming_from_waiting = initial_run.status is WaitingForInput
  let started_run = if resuming_from_waiting {
    match self.runtime.mark_run_resumed(run_id, now()) {
      Some(run) => run
      None => return Err("Unable to mark run \{run_id} as resumed")
    }
  } else {
    match self.runtime.mark_run_started(run_id, now()) {
      Some(run) => run
      None => return Err("Unable to mark run \{run_id} as started")
    }
  }
  self.log_run_event(
    started_run,
    if resuming_from_waiting {
      "job.resumed"
    } else {
      "job.started"
    },
    now(),
    if resuming_from_waiting {
      "Workflow run resumed"
    } else {
      "Workflow run started"
    },
    status=Some(Running),
    data={ "workflow_id": workflow.id, "workflow_kind": workflow.kind },
  )

  let outputs : Map[String, Json] = {}
  let steps : Array[JobStepRun] = []
  let prior_steps : Map[String, JobStepRun] = {}
  if resuming_from_waiting {
    for prior_step in store.list_step_runs(run_id) {
      prior_steps.set(prior_step.step_id, prior_step)
      if prior_step.status is Succeeded {
        steps.push(prior_step)
        match prior_step.output {
          Some(output) => outputs.set(prior_step.step_id, output)
          None => ()
        }
      }
    }
  }

  for step in workflow.steps {
    if resuming_from_waiting {
      match prior_steps.get(step.id) {
        Some(previous) if previous.status is Succeeded => continue
        _ => ()
      }
    }
    match WorkflowEngine::control_message(control) {
      Some(message) => {
        self.log_run_event(
          started_run,
          "job.cancelled",
          now(),
          message,
          status=Some(Cancelled),
        )
        ignore(self.runtime.cancel_run(run_id, now(), summary=Some(message)))
        return Err(message)
      }
      None => ()
    }

    let handler = match self.handler_for_step(step) {
      Some(handler) => handler
      None => {
        let error = "No workflow step handler registered for kind \{step.kind}"
        self.log_run_event(
          started_run,
          "job.failed",
          now(),
          error,
          step_id=Some(step.id),
          status=Some(Failed),
          data={ "step_kind": step.kind },
        )
        ignore(self.runtime.mark_run_failed(run_id, now(), error))
        return Err(error)
      }
    }

    let retry_policy = WorkflowEngine::step_retry_policy(step)
    let max_attempts = if retry_policy.max_attempts > 0 {
      retry_policy.max_attempts
    } else {
      1
    }
    let mut attempt = 1
    let mut step_logs : Array[String] = []
    let mut final_step : JobStepRun? = None

    while attempt <= max_attempts {
      match WorkflowEngine::control_message(control) {
        Some(message) => {
          let cancelled_step = WorkflowEngine::step_run_record(
            run_id,
            step,
            RunStatus::Cancelled,
            Some(now()),
            Some(now()),
            attempt - 1,
            step_logs,
            summary=Some(message),
            error=Some(message),
          )
          store.save_step_run(cancelled_step)
          ignore(
            checkpoint_run_workspace(
              store,
              run_id,
              "moonclaw: step \{step.id} cancelled",
            ),
          )
          self.log_run_event(
            started_run,
            "step.cancelled",
            now(),
            message,
            step_id=Some(step.id),
            status=Some(Cancelled),
            data={ "attempt": attempt },
          )
          steps.push(cancelled_step)
          self.log_run_event(
            started_run,
            "job.cancelled",
            now(),
            message,
            status=Some(Cancelled),
          )
          ignore(self.runtime.cancel_run(run_id, now(), summary=Some(message)))
          return Err(message)
        }
        None => ()
      }

      let start_ts = now()
      let running_step = WorkflowEngine::step_run_record(
        run_id,
        step,
        RunStatus::Running,
        Some(start_ts),
        None,
        attempt - 1,
        [..step_logs, "attempt \{attempt} started"],
      )
      store.save_step_run(running_step)
      self.log_run_event(
        started_run,
        "step.started",
        start_ts,
        "Step \{step.id} started",
        step_id=Some(step.id),
        status=Some(Running),
        data={ "step_kind": step.kind, "attempt": attempt },
      )
      ensure_controller_iteration_for_step(store, started_run, step, start_ts)

      let context = WorkflowStepContext::new(
        run=started_run,
        step~,
        initial_input~,
        outputs~,
        control~,
      )
      match (handler.run)(context) {
        Ok(result) => {
          let completed_logs = [
            ..step_logs,
            "attempt \{attempt} started",
            ..result.logs,
          ]
          let completed_step = WorkflowEngine::step_run_record(
            run_id,
            step,
            RunStatus::Succeeded,
            Some(start_ts),
            Some(now()),
            attempt - 1,
            completed_logs,
            metrics=result.metrics,
            summary=result.summary,
            output=Some(result.output),
          )
          store.save_step_run(completed_step)
          ignore(
            checkpoint_run_workspace(
              store,
              run_id,
              "moonclaw: step \{step.id} succeeded",
            ),
          )
          self.log_run_event(
            started_run,
            "step.succeeded",
            now(),
            completed_step.summary.unwrap_or("Step \{step.id} succeeded"),
            step_id=Some(step.id),
            status=Some(Succeeded),
            data={ "attempt": attempt, "metrics": result.metrics },
          )
          record_controller_decision_from_output(
            store,
            definition,
            started_run,
            step,
            result.output,
            now(),
          )
          complete_controller_iteration_for_step(
            store,
            started_run,
            step,
            RunStatus::Succeeded,
            now(),
          )
          outputs.set(step.id, result.output)
          final_step = Some(completed_step)
          break
        }
        Err(error) => {
          if waiting_for_input_message(error) is Some(message) {
            if workflow_best_effort_on_missing_input(step, definition) {
              let continued_logs = [
                ..step_logs,
                "attempt \{attempt} started",
                "attempt \{attempt} continued best-effort after missing input: \{message}",
              ]
              let continued_output = best_effort_waiting_output(step, message)
              let continued_step = WorkflowEngine::step_run_record(
                run_id,
                step,
                RunStatus::Succeeded,
                Some(start_ts),
                Some(now()),
                attempt - 1,
                continued_logs,
                summary=Some(
                  "Best-effort continuation after missing input: \{message}",
                ),
                output=Some(continued_output),
              )
              store.save_step_run(continued_step)
              ignore(
                checkpoint_run_workspace(
                  store,
                  run_id,
                  "moonclaw: step \{step.id} continued best-effort after missing input",
                ),
              )
              self.log_run_event(
                started_run,
                "step.succeeded",
                now(),
                continued_step.summary.unwrap_or("Step \{step.id} succeeded"),
                step_id=Some(step.id),
                status=Some(Succeeded),
                data={ "attempt": attempt, "best_effort_missing_input": true },
              )
              complete_controller_iteration_for_step(
                store,
                started_run,
                step,
                RunStatus::Succeeded,
                now(),
              )
              outputs.set(step.id, continued_output)
              final_step = Some(continued_step)
              break
            }
            if !workflow_disable_waiting_for_input(step, definition) {
              let waiting_logs = [
                ..step_logs,
                "attempt \{attempt} started",
                "attempt \{attempt} waiting for input: \{message}",
              ]
              let waiting_step = WorkflowEngine::step_run_record(
                run_id,
                step,
                RunStatus::WaitingForInput,
                Some(start_ts),
                Some(now()),
                attempt - 1,
                waiting_logs,
                summary=Some(message),
                error=Some(error),
              )
              store.save_step_run(waiting_step)
              ignore(
                checkpoint_run_workspace(
                  store,
                  run_id,
                  "moonclaw: step \{step.id} waiting for input",
                ),
              )
              self.log_run_event(
                started_run,
                "step.waiting_for_input",
                now(),
                message,
                step_id=Some(step.id),
                status=Some(WaitingForInput),
                data={ "attempt": attempt },
              )
              complete_controller_iteration_for_step(
                store,
                started_run,
                step,
                RunStatus::WaitingForInput,
                now(),
              )
              steps.push(waiting_step)
              self.log_run_event(
                started_run,
                "job.waiting_for_input",
                now(),
                message,
                step_id=Some(step.id),
                status=Some(WaitingForInput),
              )
              let waiting_run = match
                self.runtime.mark_run_waiting_for_input(
                  run_id,
                  now(),
                  summary=Some(
                    "Waiting for input on step \{step.id}: \{message}",
                  ),
                ) {
                Some(run) => run
                None =>
                  return Err(
                    "Unable to mark run \{run_id} as waiting for input",
                  )
              }
              complete_controller_run(
                store,
                waiting_run,
                RunStatus::WaitingForInput,
                now(),
              )
              return Ok(WorkflowExecutionResult::{
                run: waiting_run,
                workflow,
                outputs,
                steps,
              })
            }
          }
          let failed_logs = [
            ..step_logs,
            "attempt \{attempt} started",
            "attempt \{attempt} failed: \{error}",
          ]
          let failed_step = WorkflowEngine::step_run_record(
            run_id,
            step,
            RunStatus::Failed,
            Some(start_ts),
            Some(now()),
            attempt,
            failed_logs,
            summary=Some(error),
            error=Some(error),
          )
          store.save_step_run(failed_step)
          ignore(
            checkpoint_run_workspace(
              store,
              run_id,
              "moonclaw: step \{step.id} failed",
            ),
          )
          self.log_run_event(
            started_run,
            "step.failed",
            now(),
            error,
            step_id=Some(step.id),
            status=Some(Failed),
            data={ "attempt": attempt },
          )
          step_logs = failed_logs
          final_step = Some(failed_step)
          if attempt >= max_attempts {
            complete_controller_iteration_for_step(
              store,
              started_run,
              step,
              RunStatus::Failed,
              now(),
            )
            self.log_run_event(
              started_run,
              "job.failed",
              now(),
              error,
              step_id=Some(step.id),
              status=Some(Failed),
            )
            ignore(
              self.runtime.mark_run_failed(
                run_id,
                now(),
                error,
                summary=Some("Workflow step \{step.id} failed"),
              ),
            )
            complete_controller_run(
              store,
              started_run,
              RunStatus::Failed,
              now(),
            )
            return Err(error)
          }
          let backoff_ms = retry_policy.backoff_ms.unwrap_or(0)
          if backoff_ms > 0 {
            @async.sleep(backoff_ms)
          }
          attempt = attempt + 1
        }
      }
    }

    match final_step {
      Some(step_run) => steps.push(step_run)
      None => ()
    }
  }

  let completed_run = match
    self.runtime.mark_run_succeeded(
      run_id,
      now(),
      summary=Some("Workflow completed"),
    ) {
    Some(run) => run
    None => return Err("Unable to mark run \{run_id} as succeeded")
  }
  self.log_run_event(
    completed_run,
    "job.completed",
    now(),
    "Workflow completed",
    status=Some(Succeeded),
    data={ "step_count": steps.length() },
  )
  complete_controller_run(store, completed_run, RunStatus::Succeeded, now())
  Ok(WorkflowExecutionResult::{ run: completed_run, workflow, outputs, steps })
}
