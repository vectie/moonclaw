///|
pub(all) struct RunExecutionHooks {
  on_started : async (JobDefinition, JobRun) -> Unit
  on_finished : async (JobDefinition, JobRun) -> Unit
  on_info : async (String) -> Unit
  on_warn : async (String) -> Unit
}

///|
pub fn RunExecutionHooks::new(
  on_started? : async (JobDefinition, JobRun) -> Unit = (_, _) => (),
  on_finished? : async (JobDefinition, JobRun) -> Unit = (_, _) => (),
  on_info? : async (String) -> Unit = _ => (),
  on_warn? : async (String) -> Unit = _ => (),
) -> RunExecutionHooks {
  RunExecutionHooks::{ on_started, on_finished, on_info, on_warn }
}

///|
async fn notify_run_started(
  state : GatewayJobState,
  definition : JobDefinition,
  run : JobRun,
  now_ms : Int,
  send : async (JobNotifyTarget, String) -> Unit,
) -> Unit {
  let target = match
    resolve_job_notify_target(state.runtime().store(), definition) {
    Some(target) => target
    None => return
  }
  if target.verbosity is NotificationVerbosity::Off {
    return
  }
  send(
    target,
    render_status_text(
      state.runtime().store(),
      definition,
      run,
      "Job started",
      now_ms,
    ),
  )
  state.set_notification_runtime_state(
    run.id,
    initial_notification_runtime_state(now_ms),
  )
}

///|
async fn notify_run_finished(
  state : GatewayJobState,
  definition : JobDefinition,
  run : JobRun,
  now_ms : Int,
  send : async (JobNotifyTarget, String) -> Unit,
) -> Unit {
  ignore(
    capture_successful_run_memories(
      state.runtime().store(),
      definition,
      run,
      now_ms,
    ),
  )
  refresh_run_workspace_memory(state.runtime().store(), definition, run)
  let target = match
    resolve_job_notify_target(state.runtime().store(), definition) {
    Some(target) => target
    None => return
  }
  if !(target.verbosity is NotificationVerbosity::Off) {
    send(
      target,
      render_status_text(
        state.runtime().store(),
        definition,
        run,
        finished_status_prefix(run.status),
        now_ms,
      ),
    )
  }
  state.clear_notification_runtime_state(run.id)
}

///|
pub fn execution_notification_hooks(
  state : GatewayJobState,
  now : () -> Int,
  send : async (JobNotifyTarget, String) -> Unit,
  on_info? : async (String) -> Unit = _ => (),
  on_warn? : async (String) -> Unit = _ => (),
) -> RunExecutionHooks {
  RunExecutionHooks::new(
    on_started=async fn(definition, run) {
      notify_run_started(state, definition, run, now(), send)
    },
    on_finished=async fn(definition, run) {
      notify_run_finished(state, definition, run, now(), send)
    },
    on_info~,
    on_warn~,
  )
}

///|
pub async fn execute_run_lifecycle(
  runtime : RuntimeManager,
  run_id : String,
  now : () -> Int,
  engine_factory : () -> WorkflowEngine,
  control? : WorkflowExecutionControl = WorkflowExecutionControl::new(),
  hooks? : RunExecutionHooks = RunExecutionHooks::new(),
) -> Unit {
  let run = match runtime.store().get_run(run_id) {
    Some(run) => run
    None => {
      (hooks.on_warn)("Skipping unknown job run: \{run_id}")
      return
    }
  }
  let definition = match runtime.store().get_definition(run.job_id) {
    Some(definition) => definition
    None => {
      let message = "Skipping job run \{run_id}; missing definition \{run.job_id}"
      (hooks.on_warn)(message)
      ignore(
        runtime.mark_run_failed(
          run_id,
          now(),
          "Missing job definition: \{run.job_id}",
          summary=Some("Job execution failed"),
        ),
      )
      return
    }
  }
  let prepared_run = prepare_run_workspace(runtime.store(), definition, run)
  let workspace_dir = prepared_run.workspace_dir.unwrap_or(".")
  if definition.workflow_id is None {
    let message = "Skipping job run \{run_id}; no workflow configured"
    (hooks.on_warn)(message)
    ignore(
      runtime.mark_run_failed(
        run_id,
        now(),
        "Job \{definition.id} has no workflow_id",
        summary=Some("Job execution failed"),
      ),
    )
    return
  }
  (hooks.on_info)(
    "Starting job run \{definition.id} -> \{run_id} in \{workspace_dir}",
  )
  (hooks.on_started)(definition, prepared_run)
  let engine = engine_factory()
  let result = engine.execute_run(run_id, now, control~) catch {
    error => {
      let message = "Job run \{run_id} crashed before completion: \{error}"
      (hooks.on_warn)(message)
      ignore(
        runtime.mark_run_failed(
          run_id,
          now(),
          message,
          summary=Some("Job execution crashed"),
        ),
      )
      ignore(
        checkpoint_run_workspace(
          runtime.store(),
          run_id,
          "moonclaw: job crashed",
        ),
      )
      match runtime.store().get_run(run_id) {
        Some(updated_run) => (hooks.on_finished)(definition, updated_run)
        None => ()
      }
      return
    }
  }
  match result {
    Ok(result) => {
      ignore(
        checkpoint_run_workspace(
          runtime.store(),
          run_id,
          "moonclaw: run finished \{result.run.status.to_json().stringify()}",
        ),
      )
      (hooks.on_info)(
        "Completed job run \{result.run.job_id} -> \{result.run.id} with \{result.steps.length()} step(s)",
      )
      (hooks.on_finished)(definition, result.run)
    }
    Err(error) => {
      ignore(
        checkpoint_run_workspace(
          runtime.store(),
          run_id,
          "moonclaw: run ended with error",
        ),
      )
      (hooks.on_warn)("Job run \{run_id} finished with error: \{error}")
      match runtime.store().get_run(run_id) {
        Some(updated_run) => (hooks.on_finished)(definition, updated_run)
        None => ()
      }
    }
  }
}
