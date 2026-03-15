///|
pub(all) struct AcpSessionCreateParams {
  target_id : String
  session_key : String
  session_id : String?
  metadata : Json?
} derive(FromJson, Show)

///|
async fn Gateway::handle_acp_targets_list_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let targets = self.acp_runtime().list_targets()
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({ "targets": targets.map(fn(target) { target.to_json() }) }),
    error: None,
  })
}

///|
async fn Gateway::handle_acp_targets_get_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params = match request.params {
    Some(params) => params
    None =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_params",
          message: "Missing target_id parameter",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let target_id = match params {
    String(id) => id
    Object(obj) =>
      match obj.get("target_id") {
        Some(String(id)) => id
        _ =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "missing_target_id",
              message: "Missing target_id in params",
              details: None,
              retryable: None,
              retry_after_ms: None,
            }),
          })
      }
    _ =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "invalid_params",
          message: "Invalid ACP target lookup parameters",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  match self.acp_runtime().get_target(target_id) {
    Some(target) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({ "target": target.to_json() }),
        error: None,
      })
    None =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "target_not_found",
          message: "ACP target not found: \{target_id}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_acp_sessions_list_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let sessions = self.acp_runtime().list_sessions()
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({
      "sessions": sessions.map(fn(session) { session.to_json() }),
    }),
    error: None,
  })
}

///|
async fn Gateway::handle_acp_sessions_get_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params = match request.params {
    Some(params) => params
    None =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_params",
          message: "Missing session_id parameter",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let session_id = match params {
    String(id) => id
    Object(obj) =>
      match obj.get("session_id") {
        Some(String(id)) => id
        _ =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "missing_session_id",
              message: "Missing session_id in params",
              details: None,
              retryable: None,
              retry_after_ms: None,
            }),
          })
      }
    _ =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "invalid_params",
          message: "Invalid ACP session lookup parameters",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  match self.acp_runtime().get_session(session_id) {
    Some(session) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({ "session": session.to_json() }),
        error: None,
      })
    None =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "session_not_found",
          message: "ACP session not found: \{session_id}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_acp_sessions_create_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params : AcpSessionCreateParams = match request.params {
    Some(params) =>
      @json.from_json(params) catch {
        error =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "invalid_params",
              message: "Invalid ACP session params: \{error}",
              details: None,
              retryable: None,
              retry_after_ms: None,
            }),
          })
      }
    None =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_params",
          message: "Missing ACP session params",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let session_id = match params.session_id {
    Some(session_id) => session_id
    None => self.uuid.v4().to_string()
  }
  match
    self
    .acp_runtime()
    .open_session(
      session_id,
      params.target_id,
      params.session_key,
      current_time_ms(),
      metadata=params.metadata.unwrap_or({}),
    ) {
    Ok(session) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({ "status": "attached", "session": session.to_json() }),
        error: None,
      })
    Err(error) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "session_create_failed",
          message: error,
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_acp_sessions_reset_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params = match request.params {
    Some(params) => params
    None =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_params",
          message: "Missing session_id parameter",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let session_id = match params {
    String(id) => id
    Object(obj) =>
      match obj.get("session_id") {
        Some(String(id)) => id
        _ =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "missing_session_id",
              message: "Missing session_id in params",
              details: None,
              retryable: None,
              retry_after_ms: None,
            }),
          })
      }
    _ =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "invalid_params",
          message: "Invalid ACP session reset parameters",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  match self.acp_runtime().reset_session(session_id, current_time_ms()) {
    Ok(session) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({ "status": "reset", "session": session.to_json() }),
        error: None,
      })
    Err(error) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "session_reset_failed",
          message: error,
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_list_acp_targets(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let targets = self.acp_runtime().list_targets()
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(
    ({ "targets": targets.map(fn(target) { target.to_json() }) } : Json).stringify(),
  )
}

///|
async fn Gateway::handle_get_acp_target(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let target_id = match paths {
    ["", "v1", "acp", "targets", id] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_target_id",
          "message": "Missing ACP target id in path",
        },
      })
  }
  match self.acp_runtime().get_target(target_id) {
    Some(target) => {
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      w.write(({ "target": target.to_json() } : Json).stringify())
    }
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "target_not_found",
          "message": "ACP target not found: \{target_id}",
        },
      })
  }
}

///|
async fn Gateway::handle_list_acp_sessions(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let sessions = self.acp_runtime().list_sessions()
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(
    ({ "sessions": sessions.map(fn(session) { session.to_json() }) } : Json).stringify(),
  )
}

///|
async fn Gateway::handle_get_acp_session(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let session_id = match paths {
    ["", "v1", "acp", "sessions", id] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_session_id",
          "message": "Missing ACP session id in path",
        },
      })
  }
  match self.acp_runtime().get_session(session_id) {
    Some(session) => {
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      w.write(({ "session": session.to_json() } : Json).stringify())
    }
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "session_not_found",
          "message": "ACP session not found: \{session_id}",
        },
      })
  }
}

///|
async fn Gateway::handle_create_acp_session(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let payload = self.read_json_body(r, "Invalid ACP session payload")
  let params : AcpSessionCreateParams = @json.from_json(payload) catch {
    error =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_params",
          "message": "Invalid ACP session params: \{error}",
        },
      })
  }
  let session_id = match params.session_id {
    Some(session_id) => session_id
    None => self.uuid.v4().to_string()
  }
  match
    self
    .acp_runtime()
    .open_session(
      session_id,
      params.target_id,
      params.session_key,
      current_time_ms(),
      metadata=params.metadata.unwrap_or({}),
    ) {
    Ok(session) => {
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      w.write(
        ({ "status": "attached", "session": session.to_json() } : Json).stringify(),
      )
    }
    Err(error) =>
      raise json_error(400, "BadRequest", {
        "error": { "code": "session_create_failed", "message": error },
      })
  }
}

///|
async fn Gateway::handle_reset_acp_session(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let session_id = match paths {
    ["", "v1", "acp", "sessions", id, "reset"] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_session_id",
          "message": "Missing ACP session id in path",
        },
      })
  }
  match self.acp_runtime().reset_session(session_id, current_time_ms()) {
    Ok(session) => {
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      w.write(
        ({ "status": "reset", "session": session.to_json() } : Json).stringify(),
      )
    }
    Err(error) =>
      raise json_error(400, "BadRequest", {
        "error": { "code": "session_reset_failed", "message": error },
      })
  }
}
