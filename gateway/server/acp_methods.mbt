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
  metadata : Json?
} derive(FromJson, ToJson, Show)

///|
fn acp_session_run_payload_with_session_id(
  payload : Json,
  session_id : String,
) -> Json {
  let obj = match payload {
    Object(obj) => obj
    _ => {}
  }
  obj["session_id"] = Json::string(session_id)
  Json::object(obj)
}

///|
priv struct AcpProcessOutcome {
  status : String
  result : Json
  error : String?
}

///|
fn acp_run_error_shape(code : String, message : String) -> @protocol.ErrorShape {
  @protocol.ErrorShape::{
    code,
    message,
    details: None,
    retryable: None,
    retry_after_ms: None,
  }
}

///|
fn stdio_content_preview(stdio : Json) -> String? {
  match stdio {
    { "stdout": String(stdout), .. } if !stdout.trim().is_blank() =>
      Some(stdout.trim().to_string())
    { "stderr": String(stderr), .. } if !stderr.trim().is_blank() =>
      Some(stderr.trim().to_string())
    _ => None
  }
}

///|
fn metadata_with_live_stdio(metadata : Json, stdio : Json) -> Json {
  let obj = match metadata {
    Object(obj) => obj
    _ => {}
  }
  obj["stdout_stderr"] = stdio
  obj["live"] = Json::boolean(true)
  Json::object(obj)
}

///|
fn live_acp_run_node(node : @acp.AcpUiNode, stdio : Json) -> @acp.AcpUiNode {
  @acp.AcpUiNode::{
    ..node,
    summary: stdio_content_preview(stdio),
    metadata: metadata_with_live_stdio(node.metadata, stdio),
  }
}

///|
fn live_acp_session_node(
  node : @acp.AcpUiNode,
  stdio : Json,
  run_id : String,
) -> @acp.AcpUiNode {
  @acp.AcpUiNode::{
    ..node,
    status: "running",
    summary: stdio_content_preview(stdio),
    run_id: Some(run_id),
    metadata: metadata_with_live_stdio(node.metadata, stdio),
  }
}

///|
fn live_acp_output_timeline_entry(
  run : @acp.AcpRun,
  stdio : Json,
  timestamp : Int,
) -> @acp.AcpUiTimelineEntry? {
  let preview = match stdio_content_preview(stdio) {
    Some(preview) => preview
    None => return None
  }
  let stdout_len = match stdio {
    { "stdout": String(stdout), .. } => stdout.length()
    _ => 0
  }
  let stderr_len = match stdio {
    { "stderr": String(stderr), .. } => stderr.length()
    _ => 0
  }
  let linkage = match run.request {
    { "metadata": metadata, .. } => metadata
    _ => {}
  }
  Some(@acp.AcpUiTimelineEntry::{
    id: "run-output:\{run.id}:\{stdout_len}:\{stderr_len}",
    event_type: "run.output",
    title: "Run output streaming",
    detail: preview,
    timestamp,
    target_id: Some(run.target_id),
    session_id: Some(run.session_id),
    run_id: Some(run.id),
    status: Some(run.status),
    data: { "stdout_stderr": stdio, "linkage": linkage, "live": true },
  })
}

///|
fn Gateway::build_live_acp_ui_snapshot(self : Gateway) -> @acp.AcpUiSnapshot {
  let snapshot = @acp.build_acp_ui_snapshot(self.acp_runtime())
  let now = current_time_ms()
  for run in snapshot.runs {
    match self.active_acp_stdio(run.id) {
      Some(stdio) => {
        for i = 0; i < snapshot.nodes.length(); i = i + 1 {
          let node = snapshot.nodes[i]
          if node.run_id == Some(run.id) {
            snapshot.nodes[i] = live_acp_run_node(node, stdio)
          } else {
            match node.kind {
              Session if node.session_id == Some(run.session_id) =>
                snapshot.nodes[i] = live_acp_session_node(node, stdio, run.id)
              _ => ()
            }
          }
        }
        match live_acp_output_timeline_entry(run, stdio, now) {
          Some(entry) => snapshot.timeline.push(entry)
          None => ()
        }
      }
      None => ()
    }
  }
  snapshot.timeline.sort_by(fn(left, right) {
    right.timestamp.compare(left.timestamp)
  })
  snapshot
}

///|
fn Gateway::acp_ui_is_live(
  _self : Gateway,
  snapshot : @acp.AcpUiSnapshot,
) -> Bool {
  snapshot.nodes.any(fn(node) {
    let status = node.status.trim().to_lower()
    status.contains("running") ||
    status.contains("pending") ||
    status.contains("cancelling") ||
    status.contains("resetting") ||
    status.contains("detaching")
  })
}

///|
fn array_contains_id(ids : Array[String], target : String) -> Bool {
  for id in ids {
    if id == target {
      return true
    }
  }
  false
}

///|
async fn Gateway::finalize_acp_session_after_run(
  self : Gateway,
  session_id : String,
  outcome_status : String,
  now : Int,
  error? : String?,
) -> Unit {
  let session = match self.acp_runtime().get_session(session_id) {
    Some(session) => session
    None => return
  }
  match session.status {
    "detaching" => ignore(self.acp_runtime().delete_session(session_id))
    "resetting" => ignore(self.acp_runtime().reset_session(session_id, now))
    _ =>
      if outcome_status == "failed" {
        ignore(
          self
          .acp_runtime()
          .set_session_status(session_id, "failed", now, last_error?=error),
        )
      } else {
        ignore(
          self.acp_runtime().set_session_status(session_id, "attached", now),
        )
      }
  }
}

///|
async fn Gateway::request_acp_session_reset(
  self : Gateway,
  session : @acp.AcpSession,
) -> Result[@acp.AcpSession, String] {
  let now = current_time_ms()
  match self.active_acp_run_for_session(session.id) {
    Some(run) =>
      match self.cancel_active_acp_run(run.id) {
        Err(error) => Err(error)
        Ok(false) =>
          Err("ACP run is not active in this gateway process: \{run.id}")
        Ok(true) => {
          let updated = match
            self
            .acp_runtime()
            .set_session_status(
              session.id,
              "resetting",
              now,
              last_error=Some("ACP session reset requested."),
            ) {
            Ok(updated) => updated
            Err(_) => session
          }
          ignore(
            self
            .acp_runtime()
            .finish_run(
              run.id,
              "cancelling",
              now,
              error=Some("ACP session reset requested."),
            ),
          )
          Ok(updated)
        }
      }
    None => self.acp_runtime().reset_session(session.id, now)
  }
}

///|
async fn Gateway::execute_managed_acp_process(
  self : Gateway,
  run_id : String,
  launch : @acp.AcpLaunchPlan,
  request : @acp.AcpRunRequest,
) -> Result[AcpProcessOutcome, String] {
  if launch.backend == "codex" &&
    launch.command == Some("codex") &&
    !@codex.credentials_exist() {
    return Err(
      "Codex credentials are not available. Authenticate first with the Codex OAuth flow.",
    )
  }
  let command = match @acp.prepare_launch_command(launch, request) {
    Ok(command) => command
    Err(error) => return Err(error)
  }
  let stdout = @spawn.Buffer::new()
  let stderr = @spawn.Buffer::new()
  let process = self.acp_process_manager.spawn(
    command.command,
    command.args,
    stdout=@spawn.Capture(stdout),
    stderr=@spawn.Capture(stderr),
    cwd=launch.cwd,
    env=command.env,
  ) catch {
    error => return Err("Failed to start ACP backend: \{error}")
  }
  self.register_active_acp_run(run_id, process, stdout, stderr)
  let status = process.wait()
  self.clear_active_acp_run(run_id)
  let stdout_text = stdout.to_string()
  let stderr_text = stderr.to_string()
  let cancelled = self.consume_acp_run_cancel_requested(run_id)
  let outcome_status = if cancelled {
    "cancelled"
  } else if status == 0 {
    "completed"
  } else {
    "failed"
  }
  let summary = @acp.process_output_summary(stdout_text, stderr_text, status)
  let result : Json = {
    "backend": launch.backend,
    "target_id": launch.target_id,
    "session_id": launch.session_id,
    "session_key": launch.session_key,
    "cwd": launch.cwd,
    "workspace": launch.workspace,
    "command": command.command,
    "args": command.args,
    "status": outcome_status,
    "exit_status": status,
    "stdout": stdout_text,
    "stderr": stderr_text,
    "content": if outcome_status == "cancelled" {
      "ACP run cancelled."
    } else {
      summary
    },
  }
  Ok(AcpProcessOutcome::{
    status: outcome_status,
    result,
    error: if outcome_status == "completed" {
      None
    } else if outcome_status == "cancelled" {
      Some("ACP run cancelled.")
    } else {
      Some(summary)
    },
  })
}

///|
async fn Gateway::execute_acp_agent_async(
  self : Gateway,
  run_id : String,
  session_id : String,
  launch : @acp.AcpLaunchPlan,
  request : @acp.AcpRunRequest,
  idempotency_key : String,
) -> Unit {
  let result = self.execute_managed_acp_process(run_id, launch, request)
  match result {
    Ok(outcome) => {
      let now = current_time_ms()
      let output = outcome.result
      if outcome.status == "completed" {
        self.dedupe.set(idempotency_key, DedupeEntry::{
          ts: now,
          ok: true,
          payload: Some(output),
          error: None,
        })
        self.finalize_acp_session_after_run(session_id, "completed", now)
        ignore(
          self
          .acp_runtime()
          .finish_run(run_id, "completed", now, result=Some(output)),
        )
        return
      }
      let (code, message) = if outcome.status == "cancelled" {
        ("acp_run_cancelled", outcome.error.unwrap_or("ACP run cancelled."))
      } else {
        ("acp_backend_failed", outcome.error.unwrap_or("ACP backend failed"))
      }
      let error_shape = acp_run_error_shape(code, message)
      self.dedupe.set(idempotency_key, DedupeEntry::{
        ts: now,
        ok: false,
        payload: Some(output),
        error: Some(error_shape),
      })
      match outcome.error {
        Some(error) =>
          self.finalize_acp_session_after_run(
            session_id,
            outcome.status,
            now,
            error=Some(error),
          )
        None =>
          self.finalize_acp_session_after_run(session_id, outcome.status, now)
      }
      ignore(
        self
        .acp_runtime()
        .finish_run(
          run_id,
          outcome.status,
          now,
          result=Some(output),
          error=outcome.error,
        ),
      )
    }
    Err(error) => {
      let error_shape = acp_run_error_shape("acp_backend_failed", error)
      self.dedupe.set(idempotency_key, DedupeEntry::{
        ts: current_time_ms(),
        ok: false,
        payload: None,
        error: Some(error_shape),
      })
      self.finalize_acp_session_after_run(
        session_id,
        "failed",
        current_time_ms(),
        error=Some(error),
      )
      ignore(
        self
        .acp_runtime()
        .finish_run(run_id, "failed", current_time_ms(), error=Some(error)),
      )
    }
  }
}

///|
pub(all) struct AcpRunCancelParams {
  run_id : String
} derive(FromJson, ToJson, Show)

///|
async fn Gateway::handle_acp_runs_cancel_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params : AcpRunCancelParams = match request.params {
    Some(params) =>
      @json.from_json(params) catch {
        error =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(
              acp_run_error_shape(
                "invalid_params",
                "Invalid ACP run cancel params: \{error}",
              ),
            ),
          })
      }
    None =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(
          acp_run_error_shape("missing_params", "Missing ACP run cancel params"),
        ),
      })
  }
  let run = match self.acp_runtime().get_run(params.run_id) {
    Some(run) => run
    None =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(
          acp_run_error_shape(
            "run_not_found",
            "ACP run not found: \{params.run_id}",
          ),
        ),
      })
  }
  if run.status != "running" && run.status != "cancelling" {
    return self.send_response(w, @protocol.Response::{
      id: request.id,
      ok: false,
      payload: None,
      error: Some(
        acp_run_error_shape(
          "run_not_active",
          "ACP run is not active: \{run.id}",
        ),
      ),
    })
  }
  match self.cancel_active_acp_run(run.id) {
    Err(error) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(acp_run_error_shape("cancel_failed", error)),
      })
    Ok(false) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(
          acp_run_error_shape(
            "run_not_local",
            "ACP run is not active in this gateway process: \{run.id}",
          ),
        ),
      })
    Ok(true) => {
      let updated = match
        self
        .acp_runtime()
        .finish_run(
          run.id,
          "cancelling",
          current_time_ms(),
          error=Some("ACP run cancellation requested."),
        ) {
        Ok(updated) => updated
        Err(_) => run
      }
      ignore(
        self
        .acp_runtime()
        .set_session_status(
          run.session_id,
          "cancelling",
          current_time_ms(),
          last_error=Some("ACP run cancellation requested."),
        ),
      )
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({ "status": "cancelling", "run": updated.to_json() }),
        error: None,
      })
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
async fn Gateway::handle_acp_runs_list_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let runs = self.acp_runtime().list_runs()
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({ "runs": runs.map(fn(run) { run.to_json() }) }),
    error: None,
  })
}

///|
async fn Gateway::handle_acp_ui_get_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let snapshot = self.build_live_acp_ui_snapshot()
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({ "snapshot": snapshot.to_json() }),
    error: None,
  })
}

///|
async fn Gateway::handle_acp_ui_events_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let timeline = self.build_live_acp_ui_snapshot().timeline
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({ "timeline": timeline.map(fn(entry) { entry.to_json() }) }),
    error: None,
  })
}

///|
async fn Gateway::handle_acp_runs_get_method(
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
          message: "Invalid ACP run lookup parameters",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  match self.acp_runtime().get_run(run_id) {
    Some(run) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({ "run": run.to_json() }),
        error: None,
      })
    None =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "run_not_found",
          message: "ACP run not found: \{run_id}",
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
  let session = match self.acp_runtime().get_session(session_id) {
    Some(session) => session
    None =>
      return self.send_response(w, @protocol.Response::{
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
  match self.request_acp_session_reset(session) {
    Ok(session) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({
          "status": if session.status == "resetting" {
            "resetting"
          } else {
            "reset"
          },
          "session": session.to_json(),
        }),
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
  let metadata = merged_acp_run_metadata(session, params.metadata)
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
        metadata?,
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
  let run_request = @acp.new_run_request(
    message=params.message,
    run_id~,
    model?=params.model,
    cwd?=params.cwd,
    idempotency_key~,
    metadata?,
  )
  let acp_run = self
    .acp_runtime()
    .start_run(
      run_id,
      session,
      target,
      run_request.to_json(),
      launch.to_json(),
      current_time_ms(),
    )
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
      "run": acp_run.to_json(),
      "accepted": accepted.to_json(),
      "target": target.to_json(),
      "plan": launch.to_json(),
    }),
    error: None,
  })
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      self.execute_acp_agent_async(
        run_id,
        session.id,
        launch,
        run_request,
        idempotency_key,
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
async fn Gateway::handle_list_acp_runs(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let runs = self.acp_runtime().list_runs()
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(({ "runs": runs.map(fn(run) { run.to_json() }) } : Json).stringify())
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
async fn Gateway::handle_get_acp_run(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let run_id = match paths {
    ["", "v1", "acp", "runs", id] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_run_id",
          "message": "Missing ACP run id in path",
        },
      })
  }
  match self.acp_runtime().get_run(run_id) {
    Some(run) => {
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      w.write(({ "run": run.to_json() } : Json).stringify())
    }
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "run_not_found",
          "message": "ACP run not found: \{run_id}",
        },
      })
  }
}

///|
async fn Gateway::handle_get_acp_ui(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let snapshot = self.build_live_acp_ui_snapshot()
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(({ "snapshot": snapshot.to_json() } : Json).stringify())
}

///|
async fn Gateway::handle_get_acp_ui_events(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let timeline = self.build_live_acp_ui_snapshot().timeline
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(
    ({ "timeline": timeline.map(fn(entry) { entry.to_json() }) } : Json).stringify(),
  )
}

///|
async fn Gateway::handle_stream_acp_ui_events(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let sse = @httpx.EventStreamWriter::new(w)
  sse.write_header(200)
  sse.write_event(
    event="connected",
    data=@encoding/utf8.encode(({ "stream": "acp_ui" } : Json).stringify()),
  )
  let sent : Array[String] = []
  while true {
    let snapshot = self.build_live_acp_ui_snapshot()
    for entry in snapshot.timeline {
      if !array_contains_id(sent, entry.id) {
        sse.write_event(
          id=entry.id,
          event="acp_ui_event",
          data=@encoding/utf8.encode(entry.to_json().stringify()),
        )
        sent.push(entry.id)
      }
    }
    if !self.acp_ui_is_live(snapshot) {
      sse.write_event(
        event="acp_ui_complete",
        data=@encoding/utf8.encode(({ "status": "static" } : Json).stringify()),
      )
      break
    }
    @async.sleep(500)
  }
}

///|
async fn Gateway::handle_cancel_acp_run(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let run_id = match paths {
    ["", "v1", "acp", "runs", id, "cancel"] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_run_id",
          "message": "Missing ACP run id in path",
        },
      })
  }
  self.handle_acp_runs_cancel_method(
    @protocol.Request::{
      id: self.uuid.v4().to_string(),
      rpc_method: "acp.runs.cancel",
      params: Some(AcpRunCancelParams::{ run_id, }.to_json()),
    },
    w,
  )
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
  let session = match self.acp_runtime().get_session(session_id) {
    Some(session) => session
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "session_not_found",
          "message": "ACP session not found: \{session_id}",
        },
      })
  }
  match self.request_acp_session_reset(session) {
    Ok(session) => {
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      w.write(
        (
          {
            "status": if session.status == "resetting" {
              "resetting"
            } else {
              "reset"
            },
            "session": session.to_json(),
          } : Json).stringify(),
      )
    }
    Err(error) =>
      raise json_error(400, "BadRequest", {
        "error": { "code": "session_reset_failed", "message": error },
      })
  }
}

///|
async fn Gateway::handle_detach_acp_session(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let session_id = match paths {
    ["", "v1", "acp", "sessions", id, "detach"] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_session_id",
          "message": "Missing ACP session id in path",
        },
      })
  }
  let session = match self.acp_runtime().get_session(session_id) {
    Some(session) => session
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "session_not_found",
          "message": "ACP session not found: \{session_id}",
        },
      })
  }
  match self.active_acp_run_for_session(session.id) {
    Some(run) =>
      match self.cancel_active_acp_run(run.id) {
        Err(error) =>
          raise json_error(400, "BadRequest", {
            "error": { "code": "detach_failed", "message": error },
          })
        Ok(false) =>
          raise json_error(400, "BadRequest", {
            "error": {
              "code": "run_not_local",
              "message": "ACP run is not active in this gateway process: \{run.id}",
            },
          })
        Ok(true) => {
          let updated = match
            self
            .acp_runtime()
            .set_session_status(
              session.id,
              "detaching",
              current_time_ms(),
              last_error=Some("ACP session detach requested."),
            ) {
            Ok(updated) => updated
            Err(_) => session
          }
          ignore(
            self
            .acp_runtime()
            .finish_run(
              run.id,
              "cancelling",
              current_time_ms(),
              error=Some("ACP session detach requested."),
            ),
          )
          w.header().set("Content-Type", "application/json")
          w.write_header(200)
          w.write(
            (
              {
                "status": "detaching",
                "session": updated.to_json(),
                "run": run.to_json(),
              } : Json).stringify(),
          )
        }
      }
    None =>
      match self.acp_runtime().delete_session(session.id) {
        Some(removed) => {
          w.header().set("Content-Type", "application/json")
          w.write_header(200)
          w.write(
            ({ "status": "detached", "session": removed.to_json() } : Json).stringify(),
          )
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
  let params : AcpSessionRunParams = @json.from_json(
    acp_session_run_payload_with_session_id(payload, session_id),
  ) catch {
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
