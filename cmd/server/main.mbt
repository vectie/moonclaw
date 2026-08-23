///|
priv suberror HttpError {
  HttpError(code~ : Int, reason~ : String, body~ : String)
} derive(Debug, ToJson)

///|
fn json_error(code : Int, reason : String, body : Json) -> HttpError {
  HttpError(code~, reason~, body=body.stringify())
}

///|
fn text_error(code : Int, reason : String, body : String) -> HttpError {
  HttpError(code~, reason~, body~)
}

///|
/// Connection details used to register the local server with a daemon.
pub(all) struct RegisterInfo {
  host : String
  port : Int
  id : String
  instance_id : String
  token : String
}

///|
/// Loads the static HTML shell used by the playground UI and surfaces a
/// user-friendly 404 page when the asset is missing.
async fn html_read_file(path : String) -> String {
  @fsx.read_file(path) catch {
    @os_error.OSError(_) as os_error if os_error.is_ENOENT() =>
      raise text_error(404, "NotFound", "<h1>404 Not Found</h1>")
    error => raise error
  }
}

///|
/// CLI entry point. Parses flags, loads the requested model, and boots the
/// HTTP server with optional daemon registration.
pub async fn start(args : ArrayView[String]) -> Unit {
  let mut model = None
  let mut port = 0
  let mut serve = @os.cwd()
  let mut register_host = None
  let mut register_port = None
  let mut register_id = None
  let mut web_search = false
  let mut resume_id = None
  let mut name = None
  let mut source_kind = "user"
  let mut workspace_trust = "trusted"
  let mut remaining = args
  while true {
    match remaining {
      ["--name", n, .. rest] =>
        if n.has_prefix("-") {
          fail("Expected name after \{remaining[0]}")
        } else {
          name = Some(n)
          remaining = rest
        }
      ["-m" | "--model", m, .. rest] =>
        if m.has_prefix("-") {
          fail("Expected model name after \{remaining[0]}")
        } else {
          model = Some(m)
          remaining = rest
        }
      ["-p" | "--port", p, .. rest] => {
        port = @string.parse_int(p)
        remaining = rest
      }
      ["--register-host", d, .. rest] =>
        if d.has_prefix("-") {
          fail("Expected daemon host after \{remaining[0]}")
        } else {
          register_host = Some(d)
          remaining = rest
        }
      ["--register-port", dp, .. rest] => {
        register_port = Some(@string.parse_int(dp))
        remaining = rest
      }
      ["--register-id", du, .. rest] =>
        if du.has_prefix("-") {
          fail("Expected register id after \{remaining[0]}")
        } else {
          register_id = Some(du)
          remaining = rest
        }
      ["--serve", s, .. rest] =>
        if s.has_prefix("-") {
          fail("Expected serve path after \{remaining[0]}")
        } else {
          serve = s
          remaining = rest
        }
      ["--web-search", .. rest] => {
        web_search = true
        remaining = rest
      }
      ["--resume", rid, .. rest] => {
        resume_id = Some(@uuid.parse(rid))
        remaining = rest
      }
      ["--source-kind", value, .. rest] => {
        guard @conversation.source_kind_valid(value) else {
          fail("Invalid task source kind: \{value}")
        }
        source_kind = value
        remaining = rest
      }
      ["--workspace-trust", value, .. rest] => {
        guard @conversation.workspace_trust_valid(value) else {
          fail("Invalid workspace trust state: \{value}")
        }
        workspace_trust = value
        remaining = rest
      }
      [unknown, ..] => {
        let error : Json = {
          "error": { "code": -1, "message": "Unknown argument: \{unknown}" },
        }
        println(error.stringify())
        break
      }
      [] => break
    }
  }
  let register = match (register_host, register_port, register_id) {
    (Some(host), Some(port), Some(id)) => {
      let instance_id = @os.getenv("MOONCLAW_WORKER_REGISTRATION_INSTANCE").unwrap_or(
        "",
      )
      let token = @os.getenv("MOONCLAW_WORKER_REGISTRATION_TOKEN").unwrap_or("")
      guard instance_id == id && token.length() == 72 else {
        fail("worker registration capability is unavailable")
      }
      Some({ host, port, id, instance_id, token })
    }
    (None, None, None) => None
    _ =>
      fail(
        "--register-host, --register-port, and --register-id must be provided together",
      )
  }
  @moongate_startup.print_status()
  Server::new(
    name?,
    model?,
    register?,
    serve~,
    port~,
    resume_id?,
    web_search~,
    source_kind~,
    workspace_trust~,
  ).start()
}
