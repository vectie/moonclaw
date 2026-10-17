///|
// Read-only operator discovery reuses the exact accepted-memory reader. The
// workspace is resolved from an existing session, never from a supplied path.
async fn Gateway::handle_cowork_procedures(
  self : Gateway,
  w : @httpx.ResponseWriter,
  encoded_session_key : String,
) -> Unit {
  guard self.auth.token is Some(token) && !token.is_blank() else {
    raise json_error(401, "Unauthorized", {
      "error": {
        "message": "Configure gateway authentication before opening private Book procedures",
      },
    })
  }
  guard artifact_route_id(encoded_session_key) is Some(session_key) else {
    raise json_error(400, "BadRequest", {
      "error": { "message": "Choose an existing work thread" },
    })
  }
  let session = match self.sessions.get(session_key) {
    Some(value) => value
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "message": "Select an existing work thread before loading procedures",
        },
      })
  }
  let cwd = cowork_effective_cwd(session, self.cwd)
  // These are local source-binding labels, not an asserted portable Book ID.
  // No selected-book hydration, worker snapshot, or Book file is modified.
  let binding : @book_learning.Binding = {
    workspace_id: session_key,
    book_id: "cowork-selected-workspace",
    source_root: cwd,
    request_digest: @book_learning.digest(
      @encoding/utf8.encode(
        Json::array([session_key.to_json(), cwd.to_json()]).stringify(),
      ),
    ),
  }
  let snapshot = @book_learning.capture(binding, current_time_ms())
  let projection = cowork_procedure_projection(session_key, cwd, snapshot)
  w.header().set("Content-Type", "application/json")
  w.header().set("Cache-Control", "no-store")
  w.header().set("X-Content-Type-Options", "nosniff")
  w.write_header(200)
  w.write(projection.stringify())
}

///|
fn cowork_procedure_projection(
  session_key : String,
  cwd : String,
  snapshot : @book_learning.Snapshot,
) -> Json {
  {
    "contract_version": "moonclaw.cowork-procedures.v1",
    "session_key": session_key,
    "cwd": cwd,
    "status": snapshot.status,
    "content_digest": snapshot.content_digest,
    "records": snapshot.records.filter(record => {
      record.category == "procedure" &&
      record.path.has_prefix("memory/procedures/")
    }),
    "reasons": snapshot.reasons,
    "source_scope": "selected_work_thread_folder",
    "authority_granted": false,
  }
}
