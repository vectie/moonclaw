///|
fn supported_rpc_methods() -> Array[String] {
  [
    "connect", "agent", "agent.wait", "sessions.list", "sessions.reset", "config.get",
    "config.set", "health", "runs.list", "runs.get", "artifacts.list", "artifacts.get",
    "workspace.get", "plugins.list", "plugins.get", "memories.list", "memories.get",
    "memories.create", "memories.search", "jobs.list", "jobs.get", "jobs.create",
    "jobs.update", "jobs.run", "jobs.cancel", "jobs.force_cancel", "jobs.runs.list",
    "jobs.runs.get", "jobs.ui.get", "jobs.ui.events", "jobs.ask", "channels.list",
    "channels.get", "channels.configure", "channels.start", "channels.stop", "acp.targets.list",
    "acp.targets.get", "acp.sessions.list", "acp.sessions.get", "acp.sessions.create",
    "acp.sessions.reset", "acp.sessions.run", "acp.runs.list", "acp.runs.get", "acp.runs.cancel",
    "acp.ui.get", "acp.ui.events",
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
      @json.from_json(params) catch {
        e =>
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
async fn Gateway::handle_artifacts_list_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let query = match request.params {
    Some(params) =>
      @json.from_json(params) catch {
        _ => @job.ArtifactQuery::new()
      }
    None => @job.ArtifactQuery::new()
  }
  let artifacts = @job.ArtifactStore::new(store=self.job_runtime().store()).list(
    query~,
  )
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({ "artifacts": artifacts.map(artifact => artifact.to_json()) }),
    error: None,
  })
}

///|
async fn Gateway::handle_artifacts_get_method(
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
          message: "Missing artifact lookup parameters",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let artifact_id = match params {
    String(id) => id
    Object(obj) =>
      match obj.get("artifact_id") {
        Some(String(id)) => id
        _ =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "missing_artifact_id",
              message: "Missing artifact_id in params",
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
          message: "Invalid artifact lookup parameters",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let artifacts = @job.ArtifactStore::new(store=self.job_runtime().store())
  match artifacts.get(artifact_id) {
    Some(artifact) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({
          "artifact": artifact.to_json(),
          "content": artifacts.read_text(artifact_id),
        }),
        error: None,
      })
    None =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "artifact_not_found",
          message: "Artifact not found: \{artifact_id}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_memories_list_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let query = match request.params {
    Some(params) =>
      @json.from_json(params) catch {
        _ => @job.MemoryQuery::new()
      }
    None => @job.MemoryQuery::new()
  }
  let memories = @job.MemoryService::new(store=self.job_runtime().store()).list(
    query~,
  )
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({ "memories": memories.map(fn(memory) { memory.to_json() }) }),
    error: None,
  })
}

///|
async fn Gateway::handle_workspace_get_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some(self.workspace_runtime().snapshot().to_json()),
    error: None,
  })
}

///|
async fn Gateway::handle_plugins_list_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({
      "plugins": self
      .plugin_runtime()
      .list()
      .map(fn(plugin) { plugin.to_json() }),
    }),
    error: None,
  })
}

///|
async fn Gateway::handle_plugins_get_method(
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
          message: "Missing plugin lookup parameters",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let plugin_id = match params {
    String(id) => id
    Object(obj) =>
      match obj.get("plugin_id") {
        Some(String(id)) => id
        _ =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "missing_plugin_id",
              message: "Missing plugin_id in params",
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
          message: "Invalid plugin lookup parameters",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  match self.plugin_runtime().get(plugin_id) {
    Some(plugin) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some(plugin.to_json()),
        error: None,
      })
    None =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "plugin_not_found",
          message: "Plugin not found: \{plugin_id}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_memories_get_method(
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
          message: "Missing memory lookup parameters",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let memory_id = match params {
    String(id) => id
    Object(obj) =>
      match obj.get("memory_id") {
        Some(String(id)) => id
        _ =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "missing_memory_id",
              message: "Missing memory_id in params",
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
          message: "Invalid memory lookup parameters",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  match
    @job.MemoryService::new(store=self.job_runtime().store()).get(memory_id) {
    Some(memory) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some(memory.to_json()),
        error: None,
      })
    None =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "memory_not_found",
          message: "Memory not found: \{memory_id}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_memories_create_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params : @job.MemoryWriteRequest = match request.params {
    Some(params) =>
      @json.from_json(params) catch {
        error =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "invalid_params",
              message: "Invalid memory create params: \{error}",
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
          message: "Missing memory create params",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let memory = @job.MemoryService::new(store=self.job_runtime().store()).remember(
    params,
    self.uuid.v4().to_string(),
    current_time_ms(),
  )
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({ "status": "created", "memory": memory.to_json() }),
    error: None,
  })
}

///|
async fn Gateway::handle_memories_search_method(
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
          message: "Missing memory search params",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let obj = match params {
    Object(obj) => obj
    _ =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "invalid_params",
          message: "Memory search params must be an object",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let question = match obj.get("question") {
    Some(String(question)) => question
    _ =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_question",
          message: "Missing memory search question",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  let query = match obj.get("query") {
    Some(query_json) =>
      @json.from_json(query_json) catch {
        _ => @job.MemoryQuery::new()
      }
    None => @job.MemoryQuery::new()
  }
  let max_hits = match obj.get("max_hits") {
    Some(Number(value, ..)) => value.to_int()
    _ => 5
  }
  let hits = @job.MemoryService::new(store=self.job_runtime().store()).search(
    question,
    query~,
    max_hits~,
  )
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({ "hits": hits.map(fn(hit) { hit.to_json() }) }),
    error: None,
  })
}

///|
async fn Gateway::handle_jobs_ask_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params : @job.JobAskParams = match request.params {
    Some(params) =>
      @json.from_json(params) catch {
        error =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "invalid_params",
              message: "Invalid job ask params: \{error}",
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
          message: "Missing job ask params",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  match @job.ChatService::new(store=self.job_runtime().store()).ask(params) {
    Ok(answer) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some(answer.to_json()),
        error: None,
      })
    Err(error) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "job_ask_failed",
          message: error,
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
      @json.from_json(params) catch {
        e =>
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
