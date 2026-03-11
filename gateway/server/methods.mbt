///|
fn supported_rpc_methods() -> Array[String] {
  [
    "connect", "agent", "agent.wait", "sessions.list", "sessions.reset", "config.get",
    "config.set", "health", "runs.list", "runs.get", "channels.list", "channels.get",
    "channels.configure", "channels.start", "channels.stop",
  ]
}

///|
async fn Gateway::handle_connect_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params : @protocol.ConnectParams = match request.params {
    Some(params) =>
      match @json.from_json(params) {
        Ok(p) => p
        Err(e) =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "invalid_params",
              message: "Invalid connect params: \{e}",
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
          message: "Missing connect params",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }

  if params.min_protocol > @protocol.PROTOCOL_VERSION ||
    params.max_protocol < @protocol.PROTOCOL_VERSION {
    return self.send_response(w, @protocol.Response::{
      id: request.id,
      ok: false,
      payload: None,
      error: Some(@protocol.ErrorShape::{
        code: "protocol_version_mismatch",
        message: "Protocol version mismatch. Server supports \{@protocol.PROTOCOL_VERSION}",
        details: Some({
          "min_client": params.min_protocol,
          "max_client": params.max_protocol,
          "server": @protocol.PROTOCOL_VERSION,
        }),
        retryable: None,
        retry_after_ms: None,
      }),
    })
  }

  if self.auth.token is Some(expected_token) {
    match params.auth.token {
      Some(token) =>
        if token != expected_token {
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "unauthorized",
              message: "Invalid auth token",
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
            code: "unauthorized",
            message: "Auth token required",
            details: None,
            retryable: None,
            retry_after_ms: None,
          }),
        })
    }
  }

  let hello = @protocol.HelloOk::{
    protocol: @protocol.PROTOCOL_VERSION,
    server: @protocol.ServerInfo::{
      version: @buildinfo.version.to_string(),
      commit: None,
      host: None,
      conn_id: self.uuid.v4().to_string(),
    },
    features: @protocol.Features::{
      methods: supported_rpc_methods(),
      events: ["tick", "session_changed", "agent_started", "agent_completed"],
    },
    snapshot: @protocol.Snapshot::{
      presence: None,
      health: None,
      state_version: None,
    },
    policy: @protocol.Policy::{
      max_payload: @protocol.MAX_PAYLOAD_BYTES,
      max_buffered_bytes: @protocol.MAX_BUFFERED_BYTES,
      tick_interval_ms: @protocol.TICK_INTERVAL_MS,
    },
  }

  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some(hello.to_json()),
    error: None,
  })
}

///|
async fn Gateway::handle_runs_list_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let runs = self.agent_runs.values().to_array()
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({ "runs": runs.map(run => run.to_json()) }),
    error: None,
  })
}

///|
async fn Gateway::handle_runs_get_method(
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
          message: "Missing run_id parameter",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let run_id = match params {
    String(id) => id
    Object(obj) =>
      match obj.get("run_id") {
        Some(String(id)) => id
        _ =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "missing_run_id",
              message: "Missing run_id in params",
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
          message: "Invalid run lookup parameters",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  match self.agent_runs.get(run_id) {
    Some(run) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some(run.to_json()),
        error: None,
      })
    None =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "run_not_found",
          message: "Run not found: \{run_id}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_agent_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params : @protocol.AgentParams = match request.params {
    Some(params) =>
      match @json.from_json(params) {
        Ok(p) => p
        Err(e) =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "invalid_params",
              message: "Invalid agent params: \{e}",
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
          message: "Missing agent params",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let run_id = match params.run_id {
    Some(id) => id
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
  let accepted = @protocol.AgentAcceptedPayload::{
    run_id,
    status: "accepted",
    accepted_at: current_time_ms(),
  }
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some(accepted.to_json()),
    error: None,
  })
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      self.execute_agent_async(run_id~, idempotency_key~, params)
    })
  })
}

///|
async fn Gateway::handle_agent_wait(
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
          message: "Missing run_id",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let params_obj = match params {
    Object(obj) => obj
    _ =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "invalid_params",
          message: "Params must be an object",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let run_id = match params_obj.get("run_id") {
    Some(String(s)) => s
    _ =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_run_id",
          message: "Missing run_id",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let timeout_ms = match params_obj.get("timeout_ms") {
    Some(Number(n, ..)) => n.to_int()
    _ => 60000
  }
  let start = current_time_ms()
  for ;; {
    match self.dedupe.get(run_id) {
      Some(entry) =>
        return self.send_response(w, @protocol.Response::{
          id: request.id,
          ok: entry.ok,
          payload: entry.payload,
          error: entry.error,
        })
      None => {
        if current_time_ms() - start > timeout_ms {
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "timeout",
              message: "Timeout waiting for agent run",
              details: Some({ "run_id": run_id, "timeout_ms": timeout_ms }),
              retryable: Some(true),
              retry_after_ms: Some(1000),
            }),
          })
        }
        @async.sleep(100)
      }
    }
  }
}

///|
async fn Gateway::handle_sessions_list_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let sessions = self.sessions.list()
  let payload = @protocol.SessionsListPayload::{
    sessions: sessions.map(s => @protocol.SessionInfo::{
      session_id: s.session_id,
      updated_at: s.updated_at,
      channel: s.channel,
      model_override: s.model_override,
      provider_override: s.provider_override,
    }),
  }
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some(payload.to_json()),
    error: None,
  })
}

///|
async fn Gateway::handle_sessions_reset_method(
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
          message: "Missing session_id",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let session_id = match params {
    Object(obj) =>
      match obj.get("session_id") {
        Some(String(s)) => s
        _ =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "missing_session_id",
              message: "Missing session_id",
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
          message: "Params must be an object",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let removed = self.sessions.reset_and_save(session_id)
  let result : Json = { "reset": removed }
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some(result),
    error: None,
  })
}

///|
async fn Gateway::handle_config_get_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let config : Json = { "home": self.home, "cwd": self.cwd, "port": self.port }
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some(config),
    error: None,
  })
}

///|
async fn Gateway::handle_config_set_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let result : Json = { "updated": true }
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some(result),
    error: None,
  })
}

///|
async fn Gateway::handle_health_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let uptime = if self.started_at > 0 {
    current_time_ms() - self.started_at
  } else {
    0
  }
  let health = @protocol.HealthPayload::{
    status: "ok",
    uptime_ms: uptime,
    active_sessions: self.sessions.count(),
    pending_requests: self.pending_requests,
  }
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some(health.to_json()),
    error: None,
  })
}
