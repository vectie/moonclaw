///|
/// Spawns a new task process and waits for it to register with the daemon.
///
/// Parameters:
///
/// * `self` : The daemon instance that will manage the spawned task.
/// * `group` : The task group used to manage background operations for process
///   monitoring and status listening.
/// * `name` : Optional name for the spawned task.
/// * `model` : Optional model configuration to be passed to the task.
/// * `web_search` : Whether to enable web search functionality for the task
///   (defaults to false).
/// * `resume_id` : Optional ID of a previous task to resume from.
/// * `cwd` : The working directory where the task process will be spawned.
///
/// Returns a `Running` task instance representing the successfully spawned and
/// registered task.
///
/// Throws a JSON error with status code 500 if the process fails to spawn or if
/// the task fails to register within the 5-minute timeout period.
///
/// Note: This function DOES NOT register the spawned task in the daemon's task
/// lists. The caller is responsible for adding the returned `Running` task to
/// the appropriate data structures.
async fn Daemon::spawn_task(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  name? : String,
  model? : @model.Model,
  web_search? : Bool = false,
  resume_id? : @uuid.Uuid,
  cwd~ : String,
  broadcast? : @broadcast.Broadcast[@server.ServerStreamEvent] = @broadcast.Broadcast::new(),
) -> Running {
  let id = self.uuid.v4()
  let registration_token = self.uuid.v4().to_string() +
    self.uuid.v4().to_string()
  let registration_expires_at_ms = self.clock.now().ms() + 300_000L
  let rq = @aqueue.Queue(kind=Unbounded)
  self.rqs[id.to_string()] = {
    queue: rq,
    instance_id: id.to_string(),
    token: registration_token,
    expires_at_ms: registration_expires_at_ms,
  }
  defer self.rqs.remove(id.to_string())
  logger.info(
    "Spawning governed MoonClaw server child at \{cwd.to_json().stringify(indent=2)}",
  )
  let process = self.process.spawn_server(
    cwd~,
    name?,
    model_selector?=model.map(model => model.selector()),
    web_search~,
    resume_id?=resume_id.map(id => id.to_string()),
    register_id=id.to_string(),
    register_port=self.port,
    register_token=registration_token,
  ) catch {
    error =>
      raise json_error(500, "Internal Server Error", {
        "error": {
          "code": -1,
          "message": "Failed to spawn task process: \{error}",
          "metadata": { "cwd": cwd },
        },
      })
  }
  logger.info(
    "Spawned task process with PID \{process.pid_string()} and ID \{id} at '\{cwd}'",
  )
  let reg : @server.RegisterRequest = @async.with_timeout(300_000, () => {
    rq.get()
  }) catch {
    @async.TimeoutError => {
      logger.error("Timed out waiting for task to register after 5 minutes")
      raise json_error(500, "Internal Server Error", {
        "error": {
          "code": -1,
          "message": "Timed out waiting for task to register",
        },
      })
    }
    error => raise error
  }
  logger.info(
    "Received registration from task '\{reg.new_id}' ('\{reg.id}') on port \{reg.port}",
  )
  let created : @clock.Timestamp = self.clock.now()
  let task : Running = Running::new(
    name?,
    id=reg.new_id,
    cwd=reg.cwd,
    port=reg.port,
    created~,
    web_search=reg.web_search,
    model=reg.model,
    broadcast~,
  )
  // FIXME: The daemon does not ends anyway, so this cleanup code is never run.
  group.spawn_bg(() => {
    defer self.by_cwd.remove(cwd)
    defer self.by_id.remove(task.id)
    let exit_code = process.wait()
    if exit_code != 0 {
      logger.error("server process exited with code \{exit_code}")
    }
  })
  self.by_id[task.id] = Running(task)
  // FIXME: The daemon does not ends anyway, so the `no_wait` option is
  // unnecessary.
  group.spawn_bg(() => self.listen_for_status_change(task), no_wait=true)
  task
}
