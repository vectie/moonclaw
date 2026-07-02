///|
priv struct DaemonInfo {
  version : @buildinfo.Version
  pid : Int
  port : Int
}

///|
impl ToJson for DaemonInfo with fn to_json(self) {
  { "version": self.version.to_string(), "pid": self.pid, "port": self.port }
}

///|
impl @json.FromJson for DaemonInfo with fn from_json(
  json : Json,
  json_path : @json.JsonPath,
) -> DaemonInfo raise {
  guard json is Object(object) else {
    raise JsonDecodeError((json_path, "Expected object for DaemonInfo"))
  }
  let version : String = match object.get("version") {
    Some(Null) | None => "0.0.0"
    Some(String(v)) => v
    Some(_) =>
      raise JsonDecodeError(
        (json_path.add_key("version"), "Expected string for 'version' field"),
      )
  }
  let version : @buildinfo.Version = @buildinfo.Version::parse(version) catch {
    error =>
      raise JsonDecodeError(
        (
          json_path.add_key("version"),
          "Invalid version string in 'version' field: " + "\{to_repr(error)}",
        ),
      )
  }
  let pid = match object.get("pid") {
    Some(v) => @json.from_json(v, path=json_path.add_key("pid"))
    None =>
      raise JsonDecodeError((json_path, "Missing field 'pid' in DaemonInfo"))
  }
  let port = match object.get("port") {
    Some(v) => @json.from_json(v, path=json_path.add_key("port"))
    None =>
      raise JsonDecodeError((json_path, "Missing field 'port' in DaemonInfo"))
  }
  { version, pid, port }
}

///|
fn moonclaw_daemon_home_for_serve(serve : StringView?) -> String {
  match serve {
    Some(serve) => serve.to_owned()
    None => @os.home() catch { _ => "." }
  }
}

///|
/// Spawns (and optionally detaches) a moonclaw daemon process and waits until
/// the child writes its MoonLib-derived MoonClaw daemon status file. Returns
/// the PID recorded in that file, which can belong to the new child or an
/// already running daemon.
pub async fn detach(
  exec_path? : String,
  port? : Int,
  serve? : StringView,
) -> Int {
  let home = moonclaw_daemon_home_for_serve(serve)
  let args = ["daemon"]
  if port is Some(port) {
    args.push("--port")
    args.push(port.to_string())
  }
  if serve is Some(serve) {
    args.push("--serve")
    args.push(serve.to_owned())
  }
  if exec_path is Some(exec_path) {
    args.push(exec_path)
  }
  let pid = @process.spawn_orphan(@os.executable(), args)
  @async.with_timeout(60_000, () => {
    let mut resolved_pid : Int? = None
    while resolved_pid is None {
      try {
        let info_file = @fs.open(moonclaw_daemon_info_path(home), mode=ReadOnly)
        defer info_file.close()
        if @fsx.get_lock_owner(info_file) is Some(owner) {
          if owner == pid {
            let text = info_file.read_all().text()
            let json = @json.parse(text)
            if json is { "pid": info_pid, .. } {
              let info_pid : Int = @json.from_json(info_pid)
              if info_pid == pid {
                resolved_pid = Some(pid)
              } else {
                resolved_pid = Some(info_pid)
              }
            }
            // There is no pid field; wait and retry.
          } else {
            resolved_pid = Some(owner)
          }
        }
        // The daemon info file is not yet locked by any process; wait and retry.
      } catch {
        error =>
          if @async.is_being_cancelled() {
            raise error
          } else {
            logger.error("Waiting for daemon to start: \{error}")
            @async.sleep(500)
            continue
          }
      }
    }
    match resolved_pid {
      Some(pid) => pid
      None => fail("unreachable")
    }
  }) catch {
    @async.TimeoutError as error => {
      logger.error("Timeout waiting for daemon to start.")
      raise error
    }
    error => raise error
  }
}

///|
/// CLI entry point used by `moon run cmd/main -- daemon`. Parses flags,
/// optionally detaches into a background process, and otherwise starts the
/// HTTP server in the foreground.
pub async fn start(args : ArrayView[String]) -> Unit {
  let mut port = 8090
  let mut serve = @os.cwd()
  let mut exec_path = None
  let mut to_detach = false
  let mut remaining = args
  while true {
    match remaining {
      ["-p" | "--port", p, .. rest] => {
        port = @string.parse_int(p)
        remaining = rest
      }
      ["-s" | "--serve", s, .. rest] => {
        serve = if @pathx.is_absolute(s) {
          s
        } else {
          @pathx.join(@os.cwd(), s)
        }
        remaining = rest
      }
      ["-d" | "--detach", .. rest] => {
        to_detach = true
        remaining = rest
      }
      [e, .. rest] => {
        exec_path = if @pathx.is_absolute(e) {
          Some(e)
        } else {
          Some(@pathx.join(@os.cwd(), e))
        }
        remaining = rest
      }
      [] => break
    }
  }
  guard @model.load(home=serve, cwd=serve) is Some(_) else { @os.exit(-1) }
  if to_detach {
    let pid = detach(exec_path?, port~, serve~)
    logger.info("Detached moonclaw daemon with PID \{pid}.")
  } else {
    let home = serve
    let exec_path = if exec_path is Some(exec_path) {
      exec_path
    } else {
      @os.executable()
    }
    guard Daemon::new(exec_path~, port~, serve~, home~) is Some(daemon) else {
      return
    }
    daemon.serve()
  }
}
