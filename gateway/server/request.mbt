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
      (Get, ["", "ui"]) => self.handle_operator_ui(r, w, [])
      (Get, ["", "ui", .. rest]) =>
        self.handle_operator_ui(r, w, rest.map(fn(part) { part.to_string() }))
      (Get, ["", "assets", .. rest]) =>
        self.handle_operator_ui(
          r,
          w,
          ["assets", ..rest.map(fn(part) { part.to_string() })],
        )
      (Get, ["", "health"]) => self.handle_health(r, w)
      (Get, ["", "v1", "events"]) => self.handle_events_stream(r, w)
      (Get, ["", "v1", "runs"]) => self.handle_list_runs(r, w)
      (Get, ["", "v1", "runs", _run_id]) => self.handle_get_run(r, w)
      (Get, ["", "v1", "jobs"]) => self.handle_list_jobs(r, w)
      (Get, ["", "v1", "jobs", "runs"]) => self.handle_list_job_runs(r, w)
      (Get, ["", "v1", "jobs", "runs", _run_id, "ui"]) =>
        self.handle_get_job_ui(r, w)
      (Get, ["", "v1", "jobs", "runs", _run_id, "events", "stream"]) =>
        self.handle_stream_job_ui_events(r, w)
      (Get, ["", "v1", "jobs", "runs", _run_id, "events"]) =>
        self.handle_get_job_ui_events(r, w)
      (Get, ["", "v1", "jobs", "runs", _run_id]) =>
        self.handle_get_job_run(r, w)
      (Get, ["", "v1", "jobs", _job_id]) => self.handle_get_job(r, w)
      (Post, ["", "v1", "jobs"]) => self.handle_create_job(r, w)
      (Post, ["", "v1", "jobs", job_id, "update"]) =>
        self.handle_update_job(r, w, job_id.to_string())
      (Post, ["", "v1", "jobs", job_id, "run"]) =>
        self.handle_run_job(r, w, job_id.to_string())
      (Post, ["", "v1", "jobs", job_id, "cancel"]) =>
        self.handle_cancel_job(r, w, job_id.to_string(), false)
      (Post, ["", "v1", "jobs", job_id, "force-cancel"]) =>
        self.handle_cancel_job(r, w, job_id.to_string(), true)
      (Get, ["", "v1", "artifacts"]) => self.handle_list_artifacts(r, w)
      (Get, ["", "v1", "artifacts", _artifact_id]) =>
        self.handle_get_artifact(r, w)
      (Get, ["", "v1", "workspace"]) => self.handle_get_workspace(r, w)
      (Get, ["", "v1", "plugins"]) => self.handle_list_plugins(r, w)
      (Get, ["", "v1", "plugins", _plugin_id]) => self.handle_get_plugin(r, w)
      (Get, ["", "v1", "acp", "targets"]) => self.handle_list_acp_targets(r, w)
      (Get, ["", "v1", "acp", "targets", _target_id]) =>
        self.handle_get_acp_target(r, w)
      (Get, ["", "v1", "acp", "sessions"]) =>
        self.handle_list_acp_sessions(r, w)
      (Get, ["", "v1", "acp", "sessions", _session_id]) =>
        self.handle_get_acp_session(r, w)
      (Get, ["", "v1", "acp", "runs"]) => self.handle_list_acp_runs(r, w)
      (Get, ["", "v1", "acp", "runs", _run_id]) => self.handle_get_acp_run(r, w)
      (Get, ["", "v1", "acp", "ui"]) => self.handle_get_acp_ui(r, w)
      (Get, ["", "v1", "acp", "events", "stream"]) =>
        self.handle_stream_acp_ui_events(r, w)
      (Get, ["", "v1", "acp", "events"]) => self.handle_get_acp_ui_events(r, w)
      (Post, ["", "v1", "acp", "runs", _run_id, "cancel"]) =>
        self.handle_cancel_acp_run(r, w)
      (Post, ["", "v1", "acp", "sessions"]) =>
        self.handle_create_acp_session(r, w)
      (Post, ["", "v1", "acp", "sessions", _session_id, "detach"]) =>
        self.handle_detach_acp_session(r, w)
      (Post, ["", "v1", "acp", "sessions", _session_id, "run"]) =>
        self.handle_run_acp_session(r, w)
      (Post, ["", "v1", "acp", "sessions", _session_id, "reset"]) =>
        self.handle_reset_acp_session(r, w)
      (Get, ["", "v1", "memories"]) => self.handle_list_memories(r, w)
      (Get, ["", "v1", "memories", _memory_id]) => self.handle_get_memory(r, w)
      (Post, ["", "v1", "memories"]) => self.handle_create_memory(r, w)
      (Post, ["", "v1", "memories", "search"]) =>
        self.handle_search_memories(r, w)
      (Post, ["", "v1", "jobs", "ask"]) => self.handle_job_ask(r, w)
      (Get, ["", "v1", "channels"]) => self.handle_list_channels(r, w)
      (Get, ["", "v1", "channels", _channel_id]) =>
        self.handle_get_channel(r, w)
      (Post, ["", "v1", "channels", channel_id, "configure"]) =>
        self.handle_configure_channel(r, w, channel_id.to_string())
      (Post, ["", "v1", "channels", channel_id, "start"]) =>
        self.handle_start_channel(r, w, channel_id.to_string())
      (Post, ["", "v1", "channels", channel_id, "stop"]) =>
        self.handle_stop_channel(r, w, channel_id.to_string())
      (Get, ["", "v1", "extensions"]) => self.handle_list_extensions(r, w)
      (Get, ["", "v1", "extensions", _extension_id]) =>
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
fn ui_not_built_html(ui_root : String, build_dir : String) -> String {
  "<!doctype html>\n" +
  "<html><head><meta charset=\"utf-8\" />" +
  "<title>MoonClaw UI Not Built</title>" +
  "<style>" +
  "body { font-family: serif; padding: 2rem; line-height: 1.5; background: #faf6ee; color: #2c2418; }" +
  "code, pre { background: rgba(0,0,0,0.05); padding: 0.15rem 0.35rem; border-radius: 6px; }" +
  "pre { padding: 1rem; overflow: auto; }" +
  "</style></head><body>" +
  "<h1>Operator UI bundle not found</h1>" +
  "<p>The gateway looked for a built Rabbita UI bundle under:</p>" +
  "<pre>" +
  ui_root +
  "</pre>" +
  "<p>Build it first:</p>" +
  "<pre>cd " +
  build_dir +
  "\nnpm install\nnpm run build</pre>" +
  "<p>Then open <code>/ui</code> again.</p>" +
  "</body></html>"
}

///|
fn gateway_operator_ui_dist_root(root : String) -> String {
  @path.Path(root)
  .join(@path.Path("ui"))
  .join(@path.Path("rabbita-job"))
  .join(@path.Path("dist"))
  .to_string()
}

///|
fn gateway_operator_ui_build_dir(root : String) -> String {
  @path.Path(root)
  .join(@path.Path("ui"))
  .join(@path.Path("rabbita-job"))
  .to_string()
}

///|
async fn Gateway::operator_ui_dist_root(self : Gateway) -> (String, String) {
  let cwd_root = self.cwd
  let cwd_ui_root = gateway_operator_ui_dist_root(cwd_root)
  let cwd_index = @path.Path(cwd_ui_root)
    .join(@path.Path("index.html"))
    .to_string()
  let cwd_exists = @fsx.exists_as_file(cwd_index) catch { _ => false }
  if cwd_exists {
    return (cwd_ui_root, gateway_operator_ui_build_dir(cwd_root))
  }
  let process_cwd = @os.cwd() catch { _ => cwd_root }
  let repo_root = @git.find_repo_root(process_cwd)
  match repo_root {
    Some(root) =>
      (gateway_operator_ui_dist_root(root), gateway_operator_ui_build_dir(root))
    None => (cwd_ui_root, gateway_operator_ui_build_dir(cwd_root))
  }
}

///|
fn operator_ui_content_type(path : String) -> String {
  if path.has_suffix(".js") {
    "application/javascript"
  } else if path.has_suffix(".css") {
    "text/css"
  } else if path.has_suffix(".html") {
    "text/html"
  } else if path.has_suffix(".json") {
    "application/json"
  } else if path.has_suffix(".svg") {
    "image/svg+xml"
  } else if path.has_suffix(".png") {
    "image/png"
  } else if path.has_suffix(".jpg") || path.has_suffix(".jpeg") {
    "image/jpeg"
  } else {
    "application/octet-stream"
  }
}

///|
async fn Gateway::handle_operator_ui(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  path_parts : Array[String],
) -> Unit {
  let (ui_root, build_dir) = self.operator_ui_dist_root()
  let relative_path = if path_parts.is_empty() {
    "index.html"
  } else {
    path_parts.join("/")
  }
  let is_spa_route = !path_parts.is_empty() && !relative_path.contains(".")
  let asset_path = if is_spa_route { "index.html" } else { relative_path }
  let full_path = @path.Path(ui_root).join(@path.Path(asset_path)).to_string()
  if !full_path.has_prefix(ui_root) {
    raise json_error(404, "NotFound", {
      "error": { "code": "ui_not_found", "message": "Unknown UI asset path" },
    })
  }
  let exists = @fsx.exists_as_file(full_path) catch { _ => false }
  if !exists {
    if path_parts.is_empty() || asset_path == "index.html" {
      w.header().set("Content-Type", "text/html")
      w.write_header(200)
      w.write(ui_not_built_html(ui_root, build_dir))
      return
    }
    raise json_error(404, "NotFound", {
      "error": {
        "code": "ui_asset_not_found",
        "message": "UI asset not found: \{relative_path}",
      },
    })
  }
  let content = @fsx.read_file(full_path) catch {
    error =>
      raise json_error(500, "InternalServerError", {
        "error": {
          "code": "ui_read_failed",
          "message": "Failed to read UI asset: \{error}",
        },
      })
  }
  w.header().set("Content-Type", operator_ui_content_type(full_path))
  w.write_header(200)
  w.write(content)
}

///|
async fn Gateway::handle_index(
  _self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  let info : Json = {
    "name": "MoonClaw Gateway",
    "version": @buildinfo.version.to_string(),
    "protocol_version": @protocol.PROTOCOL_VERSION,
    "operator_ui": "/ui",
    "endpoints": [
      "GET /health - Health check", "GET /v1/events - SSE event stream", "GET /v1/runs - List agent runs",
      "GET /ui - Serve Rabbita operator UI bundle", "GET /v1/runs/{id} - Get agent run status",
      "GET /v1/jobs - List job definitions", "GET /v1/jobs/{id} - Get job definition",
      "POST /v1/jobs - Create job definition", "POST /v1/jobs/{id}/update - Update job definition",
      "POST /v1/jobs/{id}/run - Trigger a job run", "POST /v1/jobs/{id}/cancel - Cancel the active job run",
      "POST /v1/jobs/{id}/force-cancel - Force-cancel the active job run", "GET /v1/acp/targets - List ACP targets",
      "GET /v1/acp/sessions - List ACP sessions", "GET /v1/acp/runs - List ACP runs",
      "GET /v1/acp/runs/{id} - Get ACP run", "GET /v1/acp/ui - Get ACP UI snapshot",
      "GET /v1/acp/events - Get ACP UI timeline", "POST /v1/acp/runs/{id}/cancel - Cancel ACP run",
      "POST /v1/acp/sessions/{id}/detach - Detach ACP session", "POST /v1/acp/sessions/{id}/run - Start an ACP-backed run",
      "GET /v1/jobs/runs - List job runs", "GET /v1/jobs/runs/{id} - Get job run status",
      "POST /v1/jobs/ask - Ask over job artifacts", "GET /v1/channels - List channels",
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
  _r : @httpx.RequestReader,
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
  _r : @httpx.RequestReader,
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
  _r : @httpx.RequestReader,
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
  _r : @httpx.RequestReader,
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
  _rest : ArrayView[StringView],
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
