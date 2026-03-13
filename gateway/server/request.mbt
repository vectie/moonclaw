///|
pub async fn Gateway::handle_request(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  self.logger.info("Received request: \{r.method_} \{r.path}")
  try {
    match (r.method_, paths) {
      (Options, _) => w.write_header(204)
      (Get, ["", ""]) => self.handle_index(r, w)
      (Get, ["", "health"]) => self.handle_health(r, w)
      (Get, ["", "v1", "events"]) => self.handle_events_stream(r, w)
      (Get, ["", "v1", "runs"]) => self.handle_list_runs(r, w)
      (Get, ["", "v1", "runs", run_id]) => self.handle_get_run(r, w)
      (Get, ["", "v1", "artifacts"]) => self.handle_list_artifacts(r, w)
      (Get, ["", "v1", "artifacts", artifact_id]) =>
        self.handle_get_artifact(r, w)
      (Get, ["", "v1", "channels"]) => self.handle_list_channels(r, w)
      (Get, ["", "v1", "channels", channel_id]) => self.handle_get_channel(r, w)
      (Post, ["", "v1", "channels", channel_id, "configure"]) =>
        self.handle_configure_channel(r, w, channel_id.to_string())
      (Post, ["", "v1", "channels", channel_id, "start"]) =>
        self.handle_start_channel(r, w, channel_id.to_string())
      (Post, ["", "v1", "channels", channel_id, "stop"]) =>
        self.handle_stop_channel(r, w, channel_id.to_string())
      (Get, ["", "v1", "extensions"]) => self.handle_list_extensions(r, w)
      (Get, ["", "v1", "extensions", extension_id]) =>
        self.handle_get_extension(r, w)
      (Post, ["", "v1", "agent"]) => self.handle_agent(r, w)
      (Post, ["", "v1", "agent", "message"]) => self.handle_agent_message(r, w)
      (Get, ["", "v1", "agent", agent_id, "messages"]) =>
        self.handle_get_messages(r, w, agent_id)
      (Post, ["", "v1", "mailbox"]) => self.handle_create_mailbox(r, w)
      (Delete, ["", "v1", "mailbox", mailbox_id]) =>
        self.handle_delete_mailbox(r, w, mailbox_id)
      (Get, ["", "v1", "mailboxes"]) => self.handle_list_mailboxes(r, w)
      (Post, ["", "v1", "coordination"]) =>
        self.handle_create_coordination(r, w)
      (Get, ["", "v1", "coordination"]) => self.handle_list_coordinations(r, w)
      (Get, ["", "v1", "coordination", coordination_id]) =>
        self.handle_get_coordination(r, w, coordination_id)
      (Post, ["", "v1", "coordination", coordination_id, "start"]) =>
        self.handle_start_coordination(r, w, coordination_id)
      (Post, ["", "v1", "coordination", coordination_id, "cancel"]) =>
        self.handle_cancel_coordination(r, w, coordination_id)
      (Post, ["", "v1", "coordination", coordination_id, "subtask", task_id]) =>
        self.handle_update_subtask(r, w, coordination_id, task_id)
      (Get, ["", "v1", "coordination", coordination_id, "results"]) =>
        self.handle_coordination_results(r, w, coordination_id)
      (Post, ["", "v1", "pipeline"]) => self.handle_create_pipeline(r, w)
      (Get, ["", "v1", "pipeline"]) => self.handle_list_pipelines(r, w)
      (Get, ["", "v1", "pipeline", pipeline_id]) =>
        self.handle_get_pipeline(r, w, pipeline_id)
      (Post, ["", "v1", "pipeline", pipeline_id, "start"]) =>
        self.handle_start_pipeline(r, w, pipeline_id)
      (Post, ["", "v1", "pipeline", pipeline_id, "cancel"]) =>
        self.handle_cancel_pipeline(r, w, pipeline_id)
      (Post, ["", "v1", "pipeline", pipeline_id, "advance"]) =>
        self.handle_advance_pipeline_stage(r, w, pipeline_id)
      (Post, ["", "v1", "pipeline", pipeline_id, "fail"]) =>
        self.handle_fail_pipeline_stage(r, w, pipeline_id)
      (Get, ["", "v1", "pipeline", pipeline_id, "next"]) =>
        self.handle_pipeline_next_task(r, w, pipeline_id)
      (Post, ["", "v1", "rpc"]) => self.handle_rpc(r, w)
      (Post, ["", "v1", "shutdown"]) => self.handle_shutdown_request(r, w)
      // Webhook routes for channel extensions
      (Post | Get, ["", "webhook", channel_id, .. rest]) =>
        self.handle_webhook(r, w, channel_id, rest)
      _ =>
        raise json_error(404, "NotFound", {
          "error": {
            "code": "not_found",
            "message": "Endpoint not found: \{r.path}",
          },
        })
    }
  } catch {
    HttpError(code~, reason~, body~) => {
      w.header().set("Content-Type", "application/json")
      w.write_header(code, reason~)
      w.write(body)
    }
    error => raise error
  }
}

///|
async fn Gateway::handle_index(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  let info : Json = {
    "name": "MoonClaw Gateway",
    "version": @buildinfo.version.to_string(),
    "protocol_version": @protocol.PROTOCOL_VERSION,
    "endpoints": [
      "GET /health - Health check", "GET /v1/events - SSE event stream", "GET /v1/runs - List agent runs",
      "GET /v1/runs/{id} - Get agent run status", "GET /v1/channels - List channels",
      "GET /v1/channels/{id} - Get channel info", "POST /v1/channels/{id}/configure - Configure channel accounts",
      "POST /v1/channels/{id}/start - Start a channel account", "POST /v1/channels/{id}/stop - Stop a channel account",
      "POST /v1/agent - Submit agent task", "POST /v1/rpc - RPC endpoint", "POST /v1/shutdown - Graceful shutdown",
    ],
  }
  w.write(info.stringify())
}

///|
async fn Gateway::handle_health(
  self : Gateway,
  r : @httpx.RequestReader,
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
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(health.to_json().stringify())
}

///|
async fn Gateway::handle_shutdown_request(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  let result : Json = { "shutting_down": true }
  w.write(result.stringify())
  w.flush()
  w.close()
  self.request_shutdown()
}

///|
async fn Gateway::handle_list_channels(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let channels = self.channel_manager.list_channels()
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  let result : Json = { "channels": channels.map(ch => ch.to_json()) }
  w.write(result.stringify())
}

///|
async fn Gateway::handle_get_channel(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let channel_id = match paths {
    ["", "v1", "channels", id] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_channel_id",
          "message": "Missing channel_id in path",
        },
      })
  }
  match self.channel_manager.get_channel_dock(channel_id) {
    Some(dock) => {
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      let result : Json = { "channel": dock.to_json() }
      w.write(result.stringify())
    }
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "channel_not_found",
          "message": "Channel not found: \{channel_id}",
        },
      })
  }
}

///|
async fn Gateway::handle_list_extensions(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let extensions = self.extension_registry.list_extensions()
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  let result : Json = {
    "extensions": extensions
    .map(ext => {
      "channel_id": ext.channel_id().to_json(),
      "webhook_path": ext.webhook_path().to_json(),
      "supports_websocket": ext.supports_websocket().to_json(),
      "allowed_methods": ext
      .allowed_methods()
      .map(fn(s) { s.to_json() })
      .to_json(),
    })
    .to_json(),
  }
  w.write(result.stringify())
}

///|
async fn Gateway::handle_get_extension(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let extension_id = match paths {
    ["", "v1", "extensions", id] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_extension_id",
          "message": "Missing extension_id in path",
        },
      })
  }
  match self.extension_registry.get(extension_id) {
    Some(extension) => {
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      let info : Json = {
        "channel_id": extension.id().to_json(),
        "webhook_path": extension.webhook_path().to_json(),
        "supports_websocket": extension.supports_websocket().to_json(),
        "allowed_methods": extension
        .allowed_methods()
        .map(fn(s) { s.to_json() })
        .to_json(),
      }
      let result : Json = { "extension": info }
      w.write(result.stringify())
    }
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "extension_not_found",
          "message": "Extension not found: \{extension_id}",
        },
      })
  }
}

///|
async fn Gateway::handle_webhook(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  channel_id : StringView,
  rest : ArrayView[StringView],
) -> Unit {
  let webhook_path = "/webhook/" + channel_id.to_string()
  if !self.extension_registry.has_path(webhook_path) {
    raise json_error(404, "NotFound", {
      "error": {
        "code": "webhook_not_found",
        "message": "No webhook registered for channel: \{channel_id}",
      },
    })
  }

  // Build extension request
  let body = r.body.read_all().binary()
  let headers : Map[String, String] = {}
  let query_params : Map[String, String] = {}

  let request = @channel.ExtensionRequest::new(
    http_method=r.method_.to_string(),
    path=r.path.to_string(),
    headers~,
    body~,
    query_params~,
  )

  // Handle webhook
  try {
    let response = self.extension_registry.handle_webhook(webhook_path, request)
    w.header().set("Content-Type", "application/json")
    for name, value in response.headers() {
      w.header().set(name, value)
    }
    w.write_header(response.status_code())
    w.write(response.body())
    w.flush()
  } catch {
    e => {
      let error_body : Json = {
        "error": { "code": "webhook_error", "message": e.to_string() },
      }
      raise json_error(500, "Internal Server Error", error_body)
    }
  }
}
