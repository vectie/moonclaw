///|
fn Running::to_stopped(self : Running) -> Stopped {
  {
    name: self.name,
    id: self.id,
    cwd: self.cwd,
    created: self.created,
    updated: self.updated,
    web_search: self.web_search,
    broadcast: self.broadcast,
    source_kind: self.source_kind,
    workspace_trust: self.workspace_trust,
  }
}

///|
/// Called while holding the cwd spawn mutex. The child performs the final
/// idle check atomically with closing message ingress; cached SSE status alone
/// cannot authorize retiring a process that may have just accepted input.
async fn Daemon::retire_idle_task(self : Daemon, lock : TaskLock) -> Unit {
  guard lock.running is Some(task) else { return }
  let (response, body) = @httpx.post_json(
    "http://127.0.0.1:\{task.port}/v1/retire",
    Json::empty_object(),
  )
  guard response.code == 200 else {
    raise json_error(409, "Conflict", {
      "error": {
        "code": -1,
        "message": "A task is still generating or accepting input for cwd: \{task.cwd}",
        "metadata": {
          "cwd": task.cwd,
          "task_id": task.id,
          "status": response.code,
        },
      },
    })
  }
  ignore(body)
  self.by_id[task.id] = Stopped(task.to_stopped())
  lock.running = None
  logger.info(
    "Retired idle task \{task.id}; saved conversation remains available",
  )
}
