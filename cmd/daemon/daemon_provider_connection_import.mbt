///|
/// Control authentication precedes bounded parsing in the real dispatcher.
/// The registered workspace snapshot selects MoonGate; the body cannot choose
/// a service or workspace. Candidate credentials are never logged or returned.
async fn Daemon::import_provider_connection(
  self : Daemon,
  config : @moondesk_sandbox_config.Config,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  ignore(self)
  let bytes = @buffer.Buffer(size_hint=1024)
  for ;; {
    guard r.body.read_some(max_len=(8193 - bytes.length()).min(1024))
      is Some(chunk) else {
      break
    }
    bytes.write_bytes(chunk)
    if bytes.length() > 8192 {
      raise json_error(413, "Payload Too Large", {
        "error": {
          "code": "connection_too_large",
          "message": "Connection descriptor exceeds its limit",
        },
      })
    }
  }
  let descriptor = @json.parse(@encoding/utf8.decode(bytes.to_bytes())) catch {
    _ =>
      raise json_error(400, "Bad Request", {
        "error": {
          "code": "invalid_connection",
          "message": "Invalid OpenAI connection settings",
        },
      })
  }
  let response = match
    @provider_connection.import_connection(config.workspace_root, descriptor) {
    Ok(value) => value
    Err(InvalidDescriptor) =>
      raise json_error(400, "Bad Request", {
        "error": {
          "code": "invalid_connection",
          "message": "Invalid OpenAI connection settings",
        },
      })
    Err(GateUnavailable) =>
      raise json_error(503, "Service Unavailable", {
        "error": {
          "code": "moongate_unavailable",
          "message": "MoonGate service is not configured",
        },
      })
    Err(Failed(stage)) =>
      raise json_error(502, "Bad Gateway", {
        "error": {
          "code": "connection_import_failed",
          "message": "Could not complete " +
          stage +
          ". Check service readiness and connection access.",
        },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(response.stringify())
}
