///|
fn parse_frame(json : Json) -> Result[@protocol.Frame, String] {
  match json {
    Object(obj) => {
      let type_val = obj.get("type")
      match type_val {
        Some(String("req")) => {
          let id = match obj.get("id") {
            Some(String(s)) => s
            _ => return Err("Missing or invalid id")
          }
          let rpc_method = match obj.get("method") {
            Some(String(s)) => s
            _ => return Err("Missing or invalid method")
          }
          let params = obj.get("params")
          Ok(
            @protocol.Frame::Req(@protocol.Request::{ id, rpc_method, params }),
          )
        }
        Some(String("res")) => {
          let id = match obj.get("id") {
            Some(String(s)) => s
            _ => return Err("Missing or invalid id")
          }
          let ok = match obj.get("ok") {
            Some(True) => true
            Some(False) => false
            _ => return Err("Missing or invalid ok")
          }
          let payload = obj.get("payload")
          let error = match obj.get("error") {
            Some(error_json) =>
              match error_json {
                Object(_) => {
                  let error_result : Result[@protocol.ErrorShape, Error] = try? @json.from_json(
                    error_json,
                  )
                  match error_result {
                    Ok(e) => Some(e)
                    Err(_) => None
                  }
                }
                _ => None
              }
            None => None
          }
          Ok(
            @protocol.Frame::Res(@protocol.Response::{ id, ok, payload, error }),
          )
        }
        Some(String("evt")) => {
          let event = match obj.get("event") {
            Some(String(s)) => s
            _ => return Err("Missing or invalid event")
          }
          let payload = obj.get("payload")
          Ok(
            @protocol.Frame::Event(@protocol.EventFrame::{
              event,
              payload,
              seq: None,
              state_version: None,
            }),
          )
        }
        _ => Err("Invalid frame type")
      }
    }
    _ => Err("Invalid frame format")
  }
}

///|
async fn Gateway::handle_rpc(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let body = r.body.read_all().binary()
  let text : String = @encoding/utf8.decode(body) catch {
    _error =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_utf8",
          "message": "Invalid UTF-8 in request body",
        },
      })
  }
  let json = @json.parse(text) catch {
    e =>
      raise json_error(400, "BadRequest", {
        "error": { "code": "parse_error", "message": "Invalid JSON: \{e}" },
      })
  }
  let frame = match parse_frame(json) {
    Ok(frame) => frame
    Err(e) =>
      raise json_error(400, "BadRequest", {
        "error": { "code": "invalid_frame", "message": e },
      })
  }
  match frame {
    @protocol.Frame::Req(request) => self.handle_request_frame(request, w)
    @protocol.Frame::Res(_) =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "unexpected_frame",
          "message": "Expected request frame",
        },
      })
    @protocol.Frame::Event(_) =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "unexpected_frame",
          "message": "Expected request frame",
        },
      })
  }
}

///|
async fn Gateway::handle_request_frame(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  match request.rpc_method {
    "connect" => self.handle_connect_method(request, w)
    "agent" | "agent.run" => self.handle_agent_method(request, w)
    "agent.wait" => self.handle_agent_wait(request, w)
    "sessions.list" => self.handle_sessions_list_method(request, w)
    "sessions.reset" => self.handle_sessions_reset_method(request, w)
    "config.get" => self.handle_config_get_method(request, w)
    "config.set" => self.handle_config_set_method(request, w)
    "health" => self.handle_health_method(request, w)
    "runs.list" => self.handle_runs_list_method(request, w)
    "runs.get" => self.handle_runs_get_method(request, w)
    "artifacts.list" => self.handle_artifacts_list_method(request, w)
    "artifacts.get" => self.handle_artifacts_get_method(request, w)
    "workspace.get" => self.handle_workspace_get_method(request, w)
    "plugins.list" => self.handle_plugins_list_method(request, w)
    "plugins.get" => self.handle_plugins_get_method(request, w)
    "memories.list" => self.handle_memories_list_method(request, w)
    "memories.get" => self.handle_memories_get_method(request, w)
    "memories.create" => self.handle_memories_create_method(request, w)
    "memories.search" => self.handle_memories_search_method(request, w)
    "jobs.list" => self.handle_jobs_list_method(request, w)
    "jobs.get" => self.handle_jobs_get_method(request, w)
    "jobs.create" => self.handle_jobs_create_method(request, w)
    "jobs.update" => self.handle_jobs_update_method(request, w)
    "jobs.run" => self.handle_jobs_run_method(request, w)
    "jobs.cancel" => self.handle_jobs_cancel_method(request, w)
    "jobs.force_cancel" => self.handle_jobs_force_cancel_method(request, w)
    "jobs.runs.list" => self.handle_job_runs_list_method(request, w)
    "jobs.runs.get" => self.handle_job_runs_get_method(request, w)
    "jobs.ui.get" => self.handle_job_ui_get_method(request, w)
    "jobs.ui.events" => self.handle_job_ui_events_method(request, w)
    "jobs.ask" => self.handle_jobs_ask_method(request, w)
    "channels.list" => self.handle_channels_list(request, w)
    "channels.get" => self.handle_channels_get(request, w)
    "channels.configure" => self.handle_channels_configure(request, w)
    "channels.start" => self.handle_channels_start(request, w)
    "channels.stop" => self.handle_channels_stop(request, w)
    "acp.targets.list" => self.handle_acp_targets_list_method(request, w)
    "acp.targets.get" => self.handle_acp_targets_get_method(request, w)
    "acp.sessions.list" => self.handle_acp_sessions_list_method(request, w)
    "acp.sessions.get" => self.handle_acp_sessions_get_method(request, w)
    "acp.sessions.create" => self.handle_acp_sessions_create_method(request, w)
    "acp.sessions.reset" => self.handle_acp_sessions_reset_method(request, w)
    "acp.sessions.run" => self.handle_acp_sessions_run_method(request, w)
    "acp.runs.list" => self.handle_acp_runs_list_method(request, w)
    "acp.runs.get" => self.handle_acp_runs_get_method(request, w)
    "acp.runs.cancel" => self.handle_acp_runs_cancel_method(request, w)
    "acp.ui.get" => self.handle_acp_ui_get_method(request, w)
    "acp.ui.events" => self.handle_acp_ui_events_method(request, w)
    _ =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "method_not_found",
          message: "Method not found: \{request.rpc_method}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::send_response(
  _self : Gateway,
  w : @httpx.ResponseWriter,
  response : @protocol.Response,
) -> Unit {
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  let frame : Json = {
    "type": "res",
    "id": response.id,
    "ok": response.ok,
    "payload": response.payload,
    "error": (
      match response.error {
        Some(e) => Some(e.to_json())
        None => None
      } : Json?),
  }
  w.write(frame.stringify())
}
