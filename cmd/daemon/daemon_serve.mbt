///|
/// Runs the daemon event loop: starts the task manager, serves HTTP requests
/// (behind the shared CORS middleware), and blocks until cancelled.
///
/// Routes:
///
/// - GET  /              → serve UI `index.html`
/// - GET  /v1/health     → lightweight daemon health
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
/// - POST /v1/code/sessions/{id}/turns → `mooncode_submit_turn`
/// - GET/PUT /v1/code/sessions/{id}/goal-runtime?book_root={path} → unbounded goal runtime genesis/status
/// - POST /v1/code/sessions/{id}/lifecycle → `mooncode_manage_session`
/// - GET  /v1/code/sessions/{id}/runtime-control?book_root={path} → `mooncode_runtime_control`
/// - GET  /v1/code/sessions/{id}/runtime-claim?book_root={path} → `mooncode_runtime_claim_state`
/// - POST /v1/code/sessions/{id}/runtime-claim?book_root={path} → `mooncode_runtime_claim`
/// - POST /v1/code/sessions/{id}/runtime-turn?book_root={path} → `mooncode_runtime_turn`
/// - POST /v1/code/sessions/{id}/runtime-loop?book_root={path} → `mooncode_runtime_loop`
/// - GET  /v1/code/sessions/{id}/runtime-service?book_root={path} → `mooncode_runtime_service_state`
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
/// - POST /v1/supervisors/activate → activate an external product profile
/// - POST /v1/supervisors/{id}/commands/{command} → governed supervisor command
/// - GET  /v1/supervisors/{id}/status → durable status projection
/// - GET  /v1/supervisors/{id}/events → cursor replay
/// - POST /v1/moonbit/publish → `publish_moonbit_module`
/// - GET  /{file}        → `serve_static_file`
pub async fn Daemon::serve(self : Daemon) -> Unit {
  @async.with_task_group(group => {
    group.spawn_bg(() => self.process.start())
    // Recovery can spawn provider processes that register through this daemon's
    // own HTTP endpoint. Run it concurrently with `serve` so startup never
    // waits for a registration request before the listener can accept it.
    group.spawn_bg(
      () => {
        // Let the foreground enter `httpx.serve` and register its accept event
        // before a recovered child posts `/v1/task/register` back to us.
        @async.sleep(1)
        self.restore_supervisors(group~)
        self.restore_supervisor_workers(group~)
      },
      no_wait=true,
    )
    self.httpx.serve(
      @httpx.cors((r, w) => {
        let route_path = r.path.split("?").head().unwrap_or(r.path)
        let paths = route_path.split("/").collect()
        logger.info("Received request: \{r.method_} \{r.path}")
        logger.info("Handling request paths: \{to_repr(paths)}")
        try {
          if moondesk_control_route_requires_auth(r.method_, paths) {
            self.require_moondesk_control_auth(r, w)
          }
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
            (Get, ["", "v1", "health"]) => self.health(w)
            (Get, ["", "v1", "events"]) => self.get_events(w)
            (Get, ["", "v1", "models"]) => self.list_models(w)
            (Post, ["", "v1", "supervisors", "activate"]) =>
              self.supervisor_activate(group~, r, w)
            (Post, ["", "v1", "supervisors", id, "commands", "message"]) =>
              self.supervisor_send_message(id.to_owned(), r, w)
            (Post, ["", "v1", "supervisors", id, "commands", "delegate"]) =>
              self.supervisor_delegate_intent(group~, id.to_owned(), r, w)
            (Post, ["", "v1", "supervisors", id, "commands", "worker-steer"]) =>
              self.supervisor_worker_command(
                group~,
                id.to_owned(),
                "worker-steer",
                r,
                w,
              )
            (Post, ["", "v1", "supervisors", id, "commands", "worker-stop"]) =>
              self.supervisor_worker_command(
                group~,
                id.to_owned(),
                "worker-stop",
                r,
                w,
              )
            (
              Post,
              ["", "v1", "supervisors", id, "commands", "worker-retry-resume"],
            ) =>
              self.supervisor_worker_command(
                group~,
                id.to_owned(),
                "worker-retry-resume",
                r,
                w,
              )
            (Post, ["", "v1", "supervisors", id, "commands", command]) =>
              self.supervisor_command(
                group~,
                id.to_owned(),
                command.to_owned(),
                r,
                w,
              )
            (Get, ["", "v1", "supervisors", id, "status"]) =>
              self.supervisor_status(id.to_owned(), w)
            (Get, ["", "v1", "supervisors", id, "events"]) =>
              self.supervisor_replay(id.to_owned(), r, w)
            (Post, ["", "v1", "task", "register"]) => self.register_task(r, w)
            (Get, ["", "v1", "tasks"]) => self.list_tasks(w)
            (Post, ["", "v1", "task"]) => self.create_task(group~, r, w)
            (Get, ["", "v1", "task", id]) => self.get_task(id, w)
            (Get, ["", "v1", "task", id, "events"]) =>
              self.get_task_events(id~, w)
            (Get, ["", "v1", "code", "capabilities"]) =>
              self.mooncode_capabilities(w)
            (Post, ["", "v1", "execution-sandbox", "moon-diagnostics"]) =>
              self.moondesk_moon_diagnostics(r, w)
            (Post, ["", "v1", "execution-sandbox", "promote"]) =>
              self.moondesk_promote_retention(r, w)
            (Get, ["", "v1", "code", "sessions"]) =>
              self.mooncode_list_sessions(r, w)
            (Get, ["", "v1", "code", "sessions", session_id]) =>
              self.mooncode_get_session(session_id~, r, w)
            (Post, ["", "v1", "code", "sessions", session_id, "commands"]) =>
              self.mooncode_accept_command(session_id~, r, w)
            (Post, ["", "v1", "code", "sessions", session_id, "turns"]) =>
              self.mooncode_submit_turn(group~, session_id~, r, w)
            (Get, ["", "v1", "code", "sessions", session_id, "goal-runtime"]) =>
              self.mooncode_goal_runtime_get(session_id~, r, w)
            (Put, ["", "v1", "code", "sessions", session_id, "goal-runtime"]) =>
              self.mooncode_goal_runtime_put(session_id~, r, w)
            (_, ["", "v1", "code", "sessions", _, "goal-runtime"]) =>
              self.mooncode_goal_runtime_method_not_allowed(w)
            (Post, ["", "v1", "code", "sessions", session_id, "lifecycle"]) =>
              self.mooncode_manage_session(session_id~, r, w)
            (Get, ["", "v1", "code", "sessions", session_id, "runtime-control"]) =>
              self.mooncode_runtime_control(session_id~, r, w)
            (Get, ["", "v1", "code", "sessions", session_id, "runtime-claim"]) =>
              self.mooncode_runtime_claim_state(session_id~, r, w)
            (Post, ["", "v1", "code", "sessions", session_id, "runtime-claim"]) =>
              self.mooncode_runtime_claim(session_id~, r, w)
            (Post, ["", "v1", "code", "sessions", session_id, "runtime-turn"]) =>
              self.mooncode_runtime_turn(session_id~, r, w)
            (Post, ["", "v1", "code", "sessions", session_id, "runtime-loop"]) =>
              self.mooncode_runtime_loop(session_id~, r, w)
            (Get, ["", "v1", "code", "sessions", session_id, "runtime-service"]) =>
              self.mooncode_runtime_service_state(session_id~, r, w)
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
