///|
/// Return MoonClaw's own PID for daemon status bookkeeping.
pub fn current_process_id() -> Int {
  trusted_getpid()
}

///|
/// Suspend MoonClaw's immediate parent after the interactive readline user
/// explicitly enters Ctrl-Z. This is intentionally not a general signal API.
pub fn suspend_parent_process() -> Unit raise TrustedHostProcessError {
  let parent = trusted_getppid()
  if parent <= 1 {
    raise InvalidParameter("refusing to suspend an invalid parent pid")
  }
  let status = trusted_kill(parent, @signal.sigtstp)
  if status != 0 {
    raise InvalidParameter("failed to suspend parent process (errno=\{status})")
  }
}

///|
/// Force-stop a stale MoonClaw daemon after the versioned shutdown handshake
/// has failed. This is intentionally not a generic signal API.
pub fn terminate_stale_daemon(pid : Int) -> Unit raise TrustedHostProcessError {
  if pid <= 1 {
    raise InvalidParameter("refusing to signal an invalid daemon pid")
  }
  let status = trusted_kill(pid, @signal.sigkill)
  if status != 0 {
    raise InvalidParameter("failed to terminate stale daemon (errno=\{status})")
  }
}

///|
/// Start MoonClaw's own detached daemon entrypoint. The executable and first
/// subcommand are fixed; callers can only provide typed daemon configuration.
pub async fn spawn_detached_daemon(
  server_exec_path? : String,
  port? : Int,
  serve? : String,
) -> Int {
  if port is Some(port) && (port < 0 || port > 65535) {
    raise InvalidParameter("invalid detached daemon port")
  }
  let executable = @fs.realpath(@os.executable()) catch {
    _ => raise HostToolUnavailable("MoonClaw executable does not resolve")
  }
  let args = ["daemon"]
  if port is Some(port) {
    args.push("--port")
    args.push(port.to_string())
  }
  if serve is Some(serve) {
    validate_daemon_data("serve path", serve, 4096)
    args.push("--serve")
    args.push(serve)
  }
  if server_exec_path is Some(server_exec_path) {
    let server_exec_path = canonical_daemon_path(
      "server executable", server_exec_path,
    )
    args.push(server_exec_path)
  }
  @process.spawn_orphan(executable, args)
}

///|
/// Start MoonClaw's own detached `proposal run` entrypoint. There is no
/// caller-selected executable or arbitrary argument vector.
pub async fn spawn_detached_proposal_run(
  run_id~ : String,
  home~ : String,
  cwd~ : String,
  initial_input_path? : String,
) -> Int {
  validate_daemon_data("proposal run id", run_id, 256)
  let home = canonical_daemon_path("proposal home", home)
  let cwd = canonical_daemon_path("proposal working directory", cwd)
  let executable = @fs.realpath(@os.executable()) catch {
    _ => raise HostToolUnavailable("MoonClaw executable does not resolve")
  }
  let args = ["proposal", "run", run_id, "--home", home, "--cwd", cwd]
  if initial_input_path is Some(initial_input_path) {
    let initial_input_path = canonical_daemon_path(
      "proposal initial input", initial_input_path,
    )
    if !initial_input_path.has_prefix("\{home}/") {
      raise InvalidParameter("proposal initial input must stay under home")
    }
    args.push("--initial-input-file")
    args.push(initial_input_path)
  }
  @process.spawn_orphan(executable, args)
}
