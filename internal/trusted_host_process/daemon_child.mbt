///|
/// A closed process manager for MoonClaw's own `server` child lifecycle. The
/// caller cannot select an executable, subcommand, arbitrary argument vector,
/// shell, or environment at spawn time.
pub struct DaemonChildManager {
  executable : String?
  home : String
  cwd : String
  priv spawn_queue : @aqueue.Queue[DaemonChildSpawn]
}

///|
pub struct DaemonChildProcess {
  priv task : @async.Task[Int]
}

///|
priv struct DaemonChildSpawn {
  executable : String
  arguments : Array[String]
  cwd : String
  environment : Map[String, String]
  response : @aqueue.Queue[Result[DaemonChildProcess, Error]]
}

///|
pub fn DaemonChildManager::new(
  cwd~ : String,
  executable? : String,
  home? : String,
) -> DaemonChildManager {
  {
    executable,
    home: home.unwrap_or(cwd),
    cwd,
    spawn_queue: @aqueue.Queue::new(kind=Unbounded),
  }
}

///|
pub async fn DaemonChildManager::start(self : DaemonChildManager) -> Unit {
  @async.with_task_group(group => {
    while true {
      let request = self.spawn_queue.get()
      let task = group.spawn(() => {
        @process.run(
          request.executable,
          request.arguments,
          cwd=request.cwd,
          extra_env=request.environment,
          inherit_env=false,
          cancel_handler=@process.graceful_cancel(timeout=1000),
        )
      })
      request.response.put(Ok({ task, }))
    }
  }) catch {
    error => {
      while self.spawn_queue.try_get() is Some(request) {
        request.response.put(Err(error))
      }
      raise error
    }
  }
}

///|
fn validate_daemon_data(
  label : String,
  value : String,
  max_length : Int,
) -> Unit raise TrustedHostProcessError {
  if value.is_blank() || value.length() > max_length || contains_nul(value) {
    raise InvalidParameter("invalid daemon child \{label}")
  }
}

///|
async fn canonical_daemon_path(label : String, path : String) -> String {
  if !@pathx.is_absolute(path) || path == "/" || contains_nul(path) {
    raise InvalidParameter(
      "daemon child \{label} must be an absolute non-root path",
    )
  }
  let canonical = @fs.realpath(path) catch {
    _ => raise InvalidParameter("daemon child \{label} does not resolve")
  }
  if canonical != path {
    raise InvalidParameter("daemon child \{label} must already be canonical")
  }
  canonical
}

///|
/// Spawn the fixed MoonClaw `server` subcommand with typed data arguments. The
/// environment is replaced rather than inherited, preventing ambient daemon
/// secrets from leaking into the child process.
pub async fn DaemonChildManager::spawn_server(
  self : DaemonChildManager,
  cwd~ : String,
  name? : String,
  model_selector? : String,
  web_search? : Bool = false,
  resume_id? : String,
  register_id~ : String,
  register_port~ : Int,
  register_token~ : String,
) -> DaemonChildProcess {
  guard self.executable is Some(executable) else {
    raise HostToolUnavailable(
      "MoonClaw daemon child executable is not configured",
    )
  }
  let executable = canonical_daemon_path("executable", executable)
  let cwd = canonical_daemon_path("working directory", cwd)
  let home = canonical_daemon_path("home", self.home)
  validate_daemon_data("register id", register_id, 128)
  validate_daemon_data("registration token", register_token, 128)
  if register_token.length() != 72 {
    raise InvalidParameter("invalid daemon child registration token")
  }
  if register_port < 1 || register_port > 65535 {
    raise InvalidParameter("invalid daemon child register port")
  }
  let args = ["server"]
  if model_selector is Some(model_selector) {
    validate_daemon_data("model selector", model_selector, 256)
    args.push("--model")
    args.push(model_selector)
  }
  if name is Some(name) {
    validate_daemon_data("name", name, 1024)
    args.push("--name")
    args.push(name)
  }
  args.append([
    "--port",
    "0",
    "--register-id",
    register_id,
    "--register-host",
    "127.0.0.1",
    "--register-port",
    register_port.to_string(),
  ])
  if resume_id is Some(resume_id) {
    validate_daemon_data("resume id", resume_id, 128)
    args.push("--resume")
    args.push(resume_id)
  }
  if web_search {
    args.push("--web-search")
  }
  let response = @aqueue.Queue::new(kind=Unbounded)
  self.spawn_queue.put({
    executable,
    arguments: args,
    cwd,
    environment: {
      "HOME": home,
      "PATH": "/usr/bin:/bin",
      "LANG": "C",
      "LC_ALL": "C",
      "TMPDIR": "/tmp",
      "MOONCLAW_WORKER_REGISTRATION_INSTANCE": register_id,
      "MOONCLAW_WORKER_REGISTRATION_TOKEN": register_token,
    },
    response,
  })
  response.get().unwrap_or_error()
}

///|
pub fn DaemonChildProcess::pid_string(self : DaemonChildProcess) -> String {
  ignore(self)
  "managed"
}

///|
pub async fn DaemonChildProcess::wait(self : DaemonChildProcess) -> Int {
  self.task.wait()
}
