///|
fn mooncode_session_rename_event_kind() -> String {
  "session.renamed"
}

///|
async fn Daemon::mooncode_manage_session(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
  let body : Json = reader.read() catch {
    _ =>
      raise json_error(400, "Bad Request", {
        "error": {
          "code": -1,
          "message": "Invalid JSON body for MoonCode session lifecycle",
        },
      })
  }
  let response = self.mooncode_manage_session_response(
    session_id.to_owned(),
    body,
  )
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(response.stringify(indent=2))
}

///|
async fn Daemon::mooncode_manage_session_response(
  self : Daemon,
  session_id : String,
  body : Json,
) -> Json {
  let action = mooncode_json_string(body, "action", default="")
  let book_root = mooncode_json_string(body, "book_root", default="")
  if session_id.trim().is_empty() || book_root.trim().is_empty() {
    raise mooncode_session_management_error(
      400, "Bad Request", "session_id and book_root are required", session_id,
    )
  }
  match action {
    "rename" => {
      let title = mooncode_json_string(body, "title", default="")
        .trim()
        .to_owned()
      if title.is_empty() {
        raise mooncode_session_management_error(
          400, "Bad Request", "A non-empty session title is required", session_id,
        )
      }
      if title.length() > 160 {
        raise mooncode_session_management_error(
          400, "Bad Request", "Session titles may not exceed 160 characters", session_id,
        )
      }
      self.mooncode_rename_session(session_id, book_root, title)
    }
    "archive" => self.mooncode_archive_session(session_id, book_root)
    "restore" => self.mooncode_restore_session(session_id, book_root)
    "delete" => self.mooncode_delete_session(session_id, book_root)
    _ =>
      raise mooncode_session_management_error(
        400, "Bad Request", "Unsupported MoonCode session lifecycle action", session_id,
      )
  }
}

///|
async fn Daemon::mooncode_rename_session(
  self : Daemon,
  session_id : String,
  book_root : String,
  title : String,
) -> Json {
  let safe_session_id = mooncode_require_session_record(
    book_root,
    session_id,
    archived=false,
  )
  let now = self.clock.now()
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_event(),
    {
      "id": "mooncode-session-rename-\{self.uuid.v4()}",
      "kind": mooncode_session_rename_event_kind(),
      "event": mooncode_session_rename_event_kind(),
      "lane": "session",
      "status": "done",
      "session_id": session_id,
      "command_id": "",
      "client_turn_id": "",
      "created_at": now,
      "title": "Session renamed",
      "detail": title,
    },
  )
  match self.mooncode_sessions.get(session_id) {
    Some(binding) => binding.custom_title = title
    None => ()
  }
  let snapshot = mooncode_load_session_snapshot_by_safe_id(
    book_root, safe_session_id,
  )
  let journal = mooncode_read_session_journal_path(
    mooncode_session_journal_path_by_safe_id(book_root, safe_session_id),
  )
  let updated = snapshot
    |> mooncode_json_object_with_field("custom_title", title.to_json())
    |> mooncode_json_object_with_field(
      "journal_sequence",
      mooncode_journal_last_sequence(journal).to_json(),
    )
  mooncode_write_locked_file(
    mooncode_session_snapshot_path_by_safe_id(book_root, safe_session_id),
    updated.stringify(indent=2),
  )
  mooncode_session_management_result(
    "rename",
    session_id,
    title~,
    archived=false,
    deleted=false,
  )
}

///|
async fn Daemon::mooncode_archive_session(
  self : Daemon,
  session_id : String,
  book_root : String,
) -> Json {
  self.mooncode_require_idle_session(session_id)
  let safe_session_id = mooncode_require_session_record(
    book_root,
    session_id,
    archived=false,
  )
  mooncode_move_session_record(book_root, safe_session_id, from_archived=false)
  self.mooncode_sessions.remove(session_id)
  mooncode_session_management_result(
    "archive",
    session_id,
    title="",
    archived=true,
    deleted=false,
  )
}

///|
async fn Daemon::mooncode_restore_session(
  self : Daemon,
  session_id : String,
  book_root : String,
) -> Json {
  ignore(self)
  let safe_session_id = mooncode_require_session_record(
    book_root,
    session_id,
    archived=true,
  )
  mooncode_move_session_record(book_root, safe_session_id, from_archived=true)
  mooncode_session_management_result(
    "restore",
    session_id,
    title="",
    archived=false,
    deleted=false,
  )
}

///|
async fn Daemon::mooncode_delete_session(
  self : Daemon,
  session_id : String,
  book_root : String,
) -> Json {
  self.mooncode_require_idle_session(session_id)
  let safe_session_id = mooncode_safe_session_id(session_id)
  let active = mooncode_session_record_matches(
    book_root,
    session_id,
    safe_session_id,
    archived=false,
  )
  let archived = mooncode_session_record_matches(
    book_root,
    session_id,
    safe_session_id,
    archived=true,
  )
  if !active && !archived {
    raise mooncode_session_management_error(
      404, "Not Found", "MoonCode session not found", session_id,
    )
  }
  let path = mooncode_session_dir_by_safe_id(
    book_root,
    safe_session_id,
    archived=!active,
  )
  @fs.rmdir(path, recursive=true)
  self.mooncode_sessions.remove(session_id)
  mooncode_session_management_result(
    "delete",
    session_id,
    title="",
    archived=!active,
    deleted=true,
  )
}

///|
fn Daemon::mooncode_require_idle_session(
  self : Daemon,
  session_id : String,
) -> Unit raise {
  match self.mooncode_sessions.get(session_id) {
    Some(binding) if binding.runtime_service_running ||
      binding.active_command_id != "" =>
      raise mooncode_session_management_error(
        409, "Conflict", "This MoonCode session is still running; stop it before changing its storage",
        session_id,
      )
    _ => ()
  }
}

///|
async fn mooncode_require_session_record(
  book_root : String,
  session_id : String,
  archived~ : Bool,
) -> String {
  let safe_session_id = mooncode_safe_session_id(session_id)
  if !mooncode_session_record_matches(
      book_root,
      session_id,
      safe_session_id,
      archived~,
    ) {
    raise mooncode_session_management_error(
      404, "Not Found", "MoonCode session not found", session_id,
    )
  }
  safe_session_id
}

///|
async fn mooncode_session_record_matches(
  book_root : String,
  session_id : String,
  safe_session_id : String,
  archived~ : Bool,
) -> Bool {
  let path = mooncode_session_dir_by_safe_id(
    book_root,
    safe_session_id,
    archived~,
  )
  if !(@fsx.exists(path) catch { _ => false }) {
    return false
  }
  let snapshot = mooncode_load_session_snapshot_from_store(
    book_root,
    safe_session_id,
    archived~,
  )
  mooncode_json_string(snapshot, "session_id", default="") == session_id
}

///|
async fn mooncode_move_session_record(
  book_root : String,
  safe_session_id : String,
  from_archived~ : Bool,
) -> Unit {
  let source = mooncode_session_dir_by_safe_id(
    book_root,
    safe_session_id,
    archived=from_archived,
  )
  let destination = mooncode_session_dir_by_safe_id(
    book_root,
    safe_session_id,
    archived=!from_archived,
  )
  if (@fsx.exists(destination) catch { _ => false }) {
    raise mooncode_session_management_error(
      409, "Conflict", "A MoonCode session record already exists at the destination",
      safe_session_id,
    )
  }
  @fsx.make_directory(
    @pathx.dirname(destination),
    recursive=true,
    exists_ok=true,
  )
  @moonclaw_fsx.rename(source, destination)
}

///|
fn mooncode_session_management_result(
  action : String,
  session_id : String,
  title~ : String,
  archived~ : Bool,
  deleted~ : Bool,
) -> Json {
  {
    "kind": "mooncode-session-lifecycle-result",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "action": action,
    "session_id": session_id,
    "title": title,
    "archived": archived,
    "deleted": deleted,
  }
}

///|
fn mooncode_session_management_error(
  code : Int,
  reason : String,
  message : String,
  session_id : String,
) -> HttpError {
  json_error(code, reason, {
    "error": {
      "code": -1,
      "message": message,
      "metadata": { "session_id": session_id },
    },
  })
}

///|
fn mooncode_session_custom_title(
  record : Json,
  journal : Array[Json],
) -> String raise MoonCodeGoalRuntimeStoreError {
  let snapshot = mooncode_json_object_field_or_empty(record, "snapshot")
  let binding = mooncode_json_object_field_or_empty(record, "binding")
  let mut title = mooncode_json_string(
      snapshot,
      "custom_title",
      default=mooncode_json_string(binding, "custom_title", default=""),
    )
    .trim()
    .to_owned()
  for entry in mooncode_journal_entries(journal, mooncode_journal_event()) {
    if mooncode_json_string(entry, "kind", default="") ==
      mooncode_session_rename_event_kind() {
      let next = mooncode_json_string(entry, "detail", default="")
        .trim()
        .to_owned()
      if next != "" {
        title = next
      }
    }
  }
  title
}
