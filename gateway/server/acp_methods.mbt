///|
pub(all) struct AcpSessionCreateParams {
  target_id : String
  session_key : String
  session_id : String?
  metadata : Json?
} derive(FromJson, Show)

///|
pub(all) struct AcpSessionRunParams {
  session_id : String
  message : String
  run_id : String?
  model : String?
  cwd : String?
  idempotency_key : String?
} derive(FromJson, ToJson, Show)

///|
async fn Gateway::execute_acp_agent_async(
  self : Gateway,
  session_id : String,
  run_id : String,
  idempotency_key : String,
  params : @protocol.AgentParams,
) -> Unit {
  let result = self.execute_agent(run_id~, params)
  match result {
    Ok(output) => {
      self.dedupe.set(idempotency_key, DedupeEntry::{
        ts: current_time_ms(),
        ok: true,
        payload: Some(output),
        error: None,
      })
      ignore(
        self
        .acp_runtime()
        .set_session_status(session_id, "attached", current_time_ms()),
      )
    }
    Err(error) => {
      self.dedupe.set(idempotency_key, DedupeEntry::{
        ts: current_time_ms(),
        ok: false,
        payload: None,
        error: Some(error),
      })
      ignore(
        self
        .acp_runtime()
        .set_session_status(
          session_id,
          "failed",
          current_time_ms(),
          last_error=Some(error.message),
        ),
      )
    }
  }
}

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
async fn Gateway::handle_acp_sessions_run_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params : AcpSessionRunParams = match request.params {
    Some(params) =>
      @json.from_json(params) catch {
        error =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "invalid_params",
              message: "Invalid ACP run params: \{error}",
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
          message: "Missing ACP run params",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let session = match self.acp_runtime().get_session(params.session_id) {
    Some(session) => session
    None =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "session_not_found",
          message: "ACP session not found: \{params.session_id}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let target = match self.acp_runtime().get_target(session.target_id) {
    Some(target) => target
    None =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "target_not_found",
          message: "ACP target not found: \{session.target_id}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let run_id = match params.run_id {
    Some(run_id) => run_id
    None => self.uuid.v4().to_string()
  }
  let idempotency_key = match params.idempotency_key {
    Some(key) => key
    None => run_id
  }
  match self.dedupe.get(idempotency_key) {
    Some(entry) => {
      let response = if entry.ok {
        @protocol.Response::{
          id: request.id,
          ok: true,
          payload: entry.payload,
          error: None,
        }
      } else {
        @protocol.Response::{
          id: request.id,
          ok: false,
          payload: None,
          error: entry.error,
        }
      }
      return self.send_response(w, response)
    }
    None => ()
  }
  let launch = match
    @acp.prepare_launch_plan(
      target,
      session,
      @acp.new_run_request(
        message=params.message,
        run_id?=params.run_id,
        model?=params.model,
        cwd?=params.cwd,
        idempotency_key?=params.idempotency_key,
      ),
    ) {
    Ok(plan) => plan
    Err(error) =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "launch_plan_failed",
          message: error,
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let agent_params = @protocol.AgentParams::{
    message: params.message,
    session_key: Some(session.session_key),
    cwd: Some(launch.cwd),
    model: launch.model,
    provider: None,
    run_id: Some(run_id),
    idempotency_key: Some(idempotency_key),
  }
  let updated_session = match
    self
    .acp_runtime()
    .set_session_status(session.id, "running", current_time_ms()) {
    Ok(updated) => updated
    Err(_) => session
  }
  let accepted = @protocol.AgentAcceptedPayload::{
    run_id,
    status: "accepted",
    accepted_at: current_time_ms(),
  }
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({
      "status": "accepted",
      "session": updated_session.to_json(),
      "accepted": accepted.to_json(),
      "target": target.to_json(),
      "plan": launch.to_json(),
    }),
    error: None,
  })
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      self.execute_acp_agent_async(
        session.id,
        run_id,
        idempotency_key,
        agent_params,
      )
    })
  })
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

///|
async fn Gateway::handle_run_acp_session(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let session_id = match paths {
    ["", "v1", "acp", "sessions", id, "run"] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_session_id",
          "message": "Missing ACP session id in path",
        },
      })
  }
  let payload = self.read_json_body(r, "Invalid ACP run payload")
  let params : AcpSessionRunParams = @json.from_json(payload) catch {
    error =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_params",
          "message": "Invalid ACP run params: \{error}",
        },
      })
  }
  self.handle_acp_sessions_run_method(
    @protocol.Request::{
      id: self.uuid.v4().to_string(),
      rpc_method: "acp.sessions.run",
      params: Some(AcpSessionRunParams::{ ..params, session_id, }.to_json()),
    },
    w,
  )
}
