///|
fn Gateway::can_run_subtask(
  self : Gateway,
  coordination_id : String,
  task_id : String,
) -> Bool {
  match self.coordinator.get(coordination_id) {
    Some(task) if task.status is Running =>
      task.subtasks
      .iter()
      .any(fn(subtask) {
        if subtask.task_id != task_id {
          false
        } else {
          match subtask.status {
            Pending => true
            Running => true
            _ => false
          }
        }
      })
    _ => false
  }
}

///|
fn Gateway::can_update_pipeline_stage(
  self : Gateway,
  pipeline_id : String,
  stage_name : String,
) -> Bool {
  match self.pipeline_manager.get(pipeline_id) {
    Some(pipeline) if pipeline.status is Running =>
      pipeline.has_current_stage(stage_name)
    _ => false
  }
}

///|
fn Gateway::subtask_agent_params(
  self : Gateway,
  coordination_id : String,
  task : SubTask,
) -> @protocol.AgentParams {
  @protocol.AgentParams::{
    message: task.message,
    session_key: Some(coordination_session_key(coordination_id, task.task_id)),
    cwd: task.cwd,
    model: task.model,
    provider: None,
    run_id: Some(self.uuid.v4().to_string()),
    idempotency_key: None,
  }
}

///|
fn Gateway::pipeline_stage_agent_params(
  self : Gateway,
  pipeline_id : String,
  stage_name : String,
  input : String,
  model : String?,
  cwd : String?,
) -> @protocol.AgentParams {
  @protocol.AgentParams::{
    message: input,
    session_key: Some(pipeline_stage_session_key(pipeline_id, stage_name)),
    cwd,
    model,
    provider: None,
    run_id: Some(self.uuid.v4().to_string()),
    idempotency_key: None,
  }
}

///|
async fn Gateway::run_coordination(
  self : Gateway,
  coordination_id : String,
) -> Unit {
  let pending = self.coordinator.get_pending_subtasks(coordination_id)
  @async.with_task_group(group => {
    for task in pending {
      group.spawn_bg(() => {
        guard self.can_run_subtask(coordination_id, task.task_id) else {
          return
        }
        let _ = self.coordinator.update_subtask_status(
          coordination_id,
          task.task_id,
          Running,
        )
        let params = self.subtask_agent_params(coordination_id, task)
        let result = self.execute_agent(
          run_id=self.uuid.v4().to_string(),
          params,
        )
        match result {
          Ok(output) if self.can_run_subtask(coordination_id, task.task_id) =>
            ignore(
              self.coordinator.update_subtask_status(
                coordination_id,
                task.task_id,
                Completed,
                result=Some(output),
              ),
            )
          Err(error) if self.can_run_subtask(coordination_id, task.task_id) =>
            ignore(
              self.coordinator.update_subtask_status(
                coordination_id,
                task.task_id,
                Failed,
                error=Some(error.message),
              ),
            )
          _ => ()
        }
      })
    }
  })
}

///|
async fn Gateway::run_pipeline(self : Gateway, pipeline_id : String) -> Unit {
  let mut done = false
  while !done {
    let pipeline = match self.pipeline_manager.get(pipeline_id) {
      Some(pipeline) => pipeline
      None => break
    }
    match pipeline.status {
      Running => ()
      Completed | Failed | Cancelled => break
      Pending => {
        @async.sleep(10)
        continue
      }
    }
    match pipeline.current_stage_info() {
      Some(stage) => {
        let input = stage.resolve_input(pipeline.results)
        let params = self.pipeline_stage_agent_params(
          pipeline_id,
          stage.name,
          input,
          stage.model,
          stage.cwd,
        )
        let result = self.execute_agent(
          run_id=self.uuid.v4().to_string(),
          params,
        )
        match result {
          Ok(output) if self.can_update_pipeline_stage(pipeline_id, stage.name) =>
            ignore(
              self.pipeline_manager.advance_stage(
                pipeline_id,
                stage.name,
                output,
              ),
            )
          Err(error) if self.can_update_pipeline_stage(pipeline_id, stage.name) => {
            ignore(
              self.pipeline_manager.fail_stage(
                pipeline_id,
                stage.name,
                error.message,
              ),
            )
            done = true
          }
          _ => ()
        }
      }
      None => done = true
    }
    let latest = self.pipeline_manager.get(pipeline_id)
    match latest {
      Some(p) => done = p.is_done()
      None => done = true
    }
  }
}
