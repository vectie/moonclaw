///|
fn moondesk_control_route_requires_auth(
  method_ : @httpx.Method,
  paths : Array[StringView],
) -> Bool {
  match (method_, paths) {
    (Get, ["", "v1", "events"]) => true
    (Get, ["", "v1", "models"]) => true
    (Get, ["", "v1", "tasks"]) => true
    // Provider workers register back into the daemon on this process-internal
    // endpoint. It is not part of the MoonDesk control plane and remains
    // separate until worker registration has its own launch-bound credential.
    (_, ["", "v1", "task", "register"]) => false
    (Post, ["", "v1", "task"]) => true
    (_, ["", "v1", "task", _, ..]) => true
    (_, ["", "v1", "code", ..]) => true
    (_, ["", "v1", "supervisors", ..]) => true
    (Get, ["", "v1", "auth", "status"]) => true
    (Post, ["", "v1", "auth", "codex", "start"]) => true
    (Post, ["", "v1", "auth", "codex", "logout"]) => true
    (Post, ["", "v1", "auth", "copilot", "start"]) => true
    (Post, ["", "v1", "auth", "copilot", "logout"]) => true
    (Post, ["", "v1", "shutdown"]) => true
    (Post, ["", "v1", "moonbit", "publish"]) => true
    // Health, static assets, OAuth callbacks, and the two execution-sandbox
    // routes are not classified here. The sandbox routes retain their typed
    // request-bound authentication in their owning handlers.
    _ => false
  }
}

///|
fn moondesk_control_headers_authorized(
  headers : Map[String, String],
  config : @moondesk_sandbox_config.Config,
) -> Bool {
  let token = headers.get("x-moonclaw-execution-token").unwrap_or("")
  let instance_id = headers.get("x-moonclaw-instance-id").unwrap_or("")
  // Evaluate both comparisons so an instance mismatch cannot bypass the
  // constant-time token comparison.
  let token_matches = moondesk_sandbox_constant_time_equal(
    token,
    config.auth_token,
  )
  let instance_matches = moondesk_sandbox_constant_time_equal(
    instance_id,
    config.instance_id,
  )
  token_matches && instance_matches
}

///|
async fn Daemon::require_moondesk_control_auth(
  self : Daemon,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  ignore(self)
  let config = @moondesk_sandbox_config.load() catch {
    _ =>
      raise json_error(503, "ServiceUnavailable", {
        "error": {
          "code": "control_unavailable",
          "message": "MoonClaw control authentication is unavailable",
        },
      })
  }
  guard config is Some(config) else {
    raise json_error(503, "ServiceUnavailable", {
      "error": {
        "code": "control_unavailable",
        "message": "MoonClaw control authentication is unavailable",
      },
    })
  }
  guard moondesk_control_headers_authorized(r.headers, config) else {
    raise json_error(401, "Unauthorized", {
      "error": {
        "code": "unauthorized",
        "message": "MoonClaw control authentication failed",
      },
    })
  }
  // Bind every successful protected response to the operator-owned instance.
  // The credential itself is never copied into response state.
  w.header().set("X-MoonClaw-Instance-ID", config.instance_id)
  w.header().set("Cache-Control", "no-store")
}
