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
    spawn_queue: Queue(kind=Unbounded),
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
/// Serialize model selection separately from the isolated execution directory.
pub fn daemon_child_model_arguments(
  model_selector : String?,
  model_workspace : String?,
) -> Array[String] raise TrustedHostProcessError {
  let args : Array[String] = []
  if model_selector is Some(selector) {
    validate_daemon_data("model selector", selector, 256)
    args.append(["--model", selector])
  }
  if model_workspace is Some(workspace) {
    validate_daemon_data("model workspace", workspace, 4096)
    if !@pathx.is_absolute(workspace) || workspace == "/" {
      raise InvalidParameter(
        "model workspace must be an absolute non-root path",
      )
    }
    args.append(["--model-workspace", workspace])
  }
  args
}

///|
fn daemon_child_environment_from_values(
  home : String,
  register_id : String,
  register_token : String,
  moonfort_config? : String,
  moonfort_promotion_config? : String,
) -> Map[String, String] {
  let environment : Map[String, String] = {
    "HOME": home,
    "PATH": "/usr/bin:/bin",
    "LANG": "C",
    "LC_ALL": "C",
    "TMPDIR": "/tmp",
    "MOONCLAW_WORKER_REGISTRATION_INSTANCE": register_id,
    "MOONCLAW_WORKER_REGISTRATION_TOKEN": register_token,
  }
  // Only the two operator-owned references cross this boundary. Keep invalid
  // configured values present so the existing MoonFort loaders fail closed.
  if moonfort_config is Some(reference) {
    environment["MOONCLAW_MOONFORT_CONFIG"] = reference
  }
  if moonfort_promotion_config is Some(reference) {
    environment["MOONCLAW_MOONFORT_PROMOTION_CONFIG"] = reference
  }
  environment
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
  model_workspace? : String,
  web_search? : Bool = false,
  resume_id? : String,
  register_id~ : String,
  register_port~ : Int,
  register_token~ : String,
  source_kind? : String = "user",
  workspace_trust? : String = "trusted",
) -> DaemonChildProcess {
  guard self.executable is Some(executable) else {
    raise HostToolUnavailable(
      "MoonClaw daemon child executable is not configured",
    )
  }
  let executable = canonical_daemon_path("executable", executable)
  let cwd = canonical_daemon_path("working directory", cwd)
  let home = canonical_daemon_path("home", self.home)
  // This is a read-only discovery context, not the child execution directory.
  // Preserve the explicit owning Book path (including a suite-local symlink),
  // because resolving the link can incorrectly move discovery to another suite.
  validate_daemon_data("register id", register_id, 128)
  validate_daemon_data("registration token", register_token, 128)
  if register_token.length() != 72 {
    raise InvalidParameter("invalid daemon child registration token")
  }
  if register_port < 1 || register_port > 65535 {
    raise InvalidParameter("invalid daemon child register port")
  }
  validate_daemon_data("source kind", source_kind, 64)
  validate_daemon_data("workspace trust", workspace_trust, 16)
  let args = ["server"]
  args.append(daemon_child_model_arguments(model_selector, model_workspace))
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
  args.push("--source-kind")
  args.push(source_kind)
  args.push("--workspace-trust")
  args.push(workspace_trust)
  if resume_id is Some(resume_id) {
    validate_daemon_data("resume id", resume_id, 128)
    args.push("--resume")
    args.push(resume_id)
  }
  if web_search {
    args.push("--web-search")
  }
  let response : @aqueue.Queue[Result[DaemonChildProcess, Error]] = Queue(
    kind=Unbounded,
  )
  self.spawn_queue.put({
    executable,
    arguments: args,
    cwd,
    environment: daemon_child_environment_from_values(
      home,
      register_id,
      register_token,
      moonfort_config?=@os.getenv("MOONCLAW_MOONFORT_CONFIG"),
      moonfort_promotion_config?=@os.getenv(
        "MOONCLAW_MOONFORT_PROMOTION_CONFIG",
      ),
    ),
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
