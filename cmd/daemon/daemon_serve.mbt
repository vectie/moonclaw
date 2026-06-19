///|
/// Runs the daemon event loop: starts the task manager, serves HTTP requests
/// (behind the shared CORS middleware), and blocks until cancelled.
///
/// Routes:
///
/// - GET  /              → serve UI `index.html`
/// - GET  /v1/events     → `get_events`
/// - GET  /v1/models     → `list_models`
/// - POST /v1/task/register → `register_task`
/// - GET  /v1/tasks      → `list_tasks`
/// - POST /v1/task       → `create_task`
/// - GET  /v1/task/{id}  → `get_task`
/// - ANY  /v1/task/{id}/... → `forward_to_task`
/// - GET  /v1/code/capabilities → `mooncode_capabilities`
/// - GET  /v1/code/sessions?book_root={path} → `mooncode_list_sessions`
/// - GET  /v1/code/sessions/{id}?book_root={path} → `mooncode_get_session`
/// - POST /v1/code/sessions/{id}/commands → `mooncode_accept_command`
/// - GET  /v1/code/sessions/{id}/serve-scheduler?book_root={path} → `mooncode_serve_scheduler`
/// - GET  /v1/code/sessions/{id}/runtime-claim?book_root={path} → `mooncode_runtime_claim_state`
/// - POST /v1/code/sessions/{id}/runtime-claim?book_root={path} → `mooncode_runtime_claim`
/// - POST /v1/code/sessions/{id}/runtime-dispatch?book_root={path} → `mooncode_runtime_dispatch`
/// - POST /v1/code/sessions/{id}/runtime-turn?book_root={path} → `mooncode_runtime_turn`
/// - POST /v1/code/sessions/{id}/runtime-loop?book_root={path} → `mooncode_runtime_loop`
/// - POST /v1/code/sessions/{id}/runtime-service?book_root={path} → `mooncode_runtime_service`
/// - GET  /v1/code/sessions/{id}/runtime-events?book_root={path} → `mooncode_runtime_events_state`
/// - POST /v1/code/sessions/{id}/runtime-events?book_root={path} → `mooncode_runtime_events`
/// - POST /v1/code/sessions/{id}/tool-exec?book_root={path} → `mooncode_tool_execute`
/// - GET  /v1/code/sessions/{id}/stream → `mooncode_stream`
/// - GET  /v1/code/sessions/{id}/eval-report → `mooncode_eval_report`
/// - POST /v1/code/sessions/{id}/package-result?book_root={path} → `mooncode_package_result`
/// - GET  /v1/auth/status → `get_auth_status`
/// - POST /v1/auth/codex/start → `start_codex_auth` (callback on port 1455)
/// - POST /v1/auth/codex/logout → `logout_codex`
/// - POST /v1/auth/copilot/start → `start_copilot_auth`
/// - POST /v1/auth/copilot/logout → `logout_copilot`
/// - POST /v1/shutdown   → graceful shutdown response then stop server
/// - POST /v1/moonbit/publish → `publish_moonbit_module`
/// - GET  /{file}        → `serve_static_file`
pub async fn Daemon::serve(self : Daemon) -> Unit {
  @async.with_task_group(group => {
    group.spawn_bg(() => self.process.start())
    self.httpx.serve(
      @httpx.cors((r, w) => {
        let route_path = r.path.split("?").head().unwrap_or(r.path)
        let paths = route_path.split("/").collect()
        logger.info("Received request: \{r.method_} \{r.path}")
        logger.info("Handling request paths: \{to_repr(paths)}")
        try {
          match (r.method_, paths) {
            (Options, _) => w.write_header(204)
            // GET /
            (Get, ["", ""]) => {
              let index_html = html_read_file(
                @pathx.join(self.serve, "index.html"),
              )
              w.header().set("Content-Type", "text/html")
              w.write_header(200)
              w.write(index_html)
            }
            (Get, ["", "v1", "events"]) => self.get_events(w)
            (Get, ["", "v1", "models"]) => self.list_models(w)
            (Post, ["", "v1", "task", "register"]) => self.register_task(r, w)
            (Get, ["", "v1", "tasks"]) => self.list_tasks(w)
            (Post, ["", "v1", "task"]) => self.create_task(group~, r, w)
            (Get, ["", "v1", "task", id]) => self.get_task(id, w)
            (Get, ["", "v1", "task", id, "events"]) =>
              self.get_task_events(id~, w)
            (Get, ["", "v1", "code", "capabilities"]) =>
              self.mooncode_capabilities(w)
            (Get, ["", "v1", "code", "sessions"]) =>
              self.mooncode_list_sessions(r, w)
            (Get, ["", "v1", "code", "sessions", session_id]) =>
              self.mooncode_get_session(session_id~, r, w)
            (Post, ["", "v1", "code", "sessions", session_id, "commands"]) =>
              self.mooncode_accept_command(group~, session_id~, r, w)
            (Get, ["", "v1", "code", "sessions", session_id, "serve-scheduler"]) =>
              self.mooncode_serve_scheduler(session_id~, r, w)
            (Get, ["", "v1", "code", "sessions", session_id, "runtime-claim"]) =>
              self.mooncode_runtime_claim_state(session_id~, r, w)
            (Post, ["", "v1", "code", "sessions", session_id, "runtime-claim"]) =>
              self.mooncode_runtime_claim(session_id~, r, w)
            (
              Post,
              ["", "v1", "code", "sessions", session_id, "runtime-dispatch"],
            ) => self.mooncode_runtime_dispatch(group~, session_id~, r, w)
            (Post, ["", "v1", "code", "sessions", session_id, "runtime-turn"]) =>
              self.mooncode_runtime_turn(session_id~, r, w)
            (Post, ["", "v1", "code", "sessions", session_id, "runtime-loop"]) =>
              self.mooncode_runtime_loop(session_id~, r, w)
            (Post, ["", "v1", "code", "sessions", session_id, "runtime-service"]
            ) => self.mooncode_runtime_service(group~, session_id~, r, w)
            (Get, ["", "v1", "code", "sessions", session_id, "runtime-events"]) =>
              self.mooncode_runtime_events_state(session_id~, r, w)
            (Post, ["", "v1", "code", "sessions", session_id, "runtime-events"]) =>
              self.mooncode_runtime_events(session_id~, r, w)
            (Post, ["", "v1", "code", "sessions", session_id, "tool-exec"]) =>
              self.mooncode_tool_execute(session_id~, r, w)
            (Get, ["", "v1", "code", "sessions", session_id, "stream"]) =>
              self.mooncode_stream(session_id~, r, w)
            (Get, ["", "v1", "code", "sessions", session_id, "eval-report"]) =>
              self.mooncode_eval_report(session_id~, r, w)
            (Post, ["", "v1", "code", "sessions", session_id, "package-result"]) =>
              self.mooncode_package_result(session_id~, r, w)
            (method_, ["", "v1", "task", id, .. paths]) =>
              self.forward_to_task(method_~, group~, id~, paths~, r, w)
            // Auth endpoints
            (Get, ["", "v1", "auth", "status"]) => self.get_auth_status(w)
            (Post, ["", "v1", "auth", "codex", "start"]) =>
              self.start_codex_auth(group~, r, w)
            (Post, ["", "v1", "auth", "codex", "logout"]) =>
              self.logout_codex(w)
            (Post, ["", "v1", "auth", "copilot", "start"]) =>
              self.start_copilot_auth(group~, r, w)
            (Post, ["", "v1", "auth", "copilot", "logout"]) =>
              self.logout_copilot(w)
            (Post, ["", "v1", "shutdown"]) => {
              w.header().set("Content-Type", "application/json")
              w.write_header(200)
              let response : Json = {}
              w.write(response.stringify())
              w.flush()
              // We need to close the writer before shutting down to ensure the
              w.close()
              group.return_immediately(())
            }
            (Get, ["", .. file]) =>
              serve_static_file(w, serve=self.serve, path=file.join("/"))
            _ =>
              raise json_error(404, "NotFound", {
                "error": {
                  "code": -1,
                  "message": "Unknown endpoint: \{r.path}",
                  "metadata": {
                    "method": r.method_.to_string(),
                    "path": r.path,
                  },
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
      }),
    )
  })
}
