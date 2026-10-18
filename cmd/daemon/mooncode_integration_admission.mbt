///|
fn mooncode_integration_session_id_valid(value : String) -> Bool {
  value.length() >= 1 &&
  value.length() <= 128 &&
  value.all(c => {
    c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '-' || c == '_'
  })
}

///|
async fn Daemon::mooncode_bind_integration_session(
  self : Daemon,
  book_root : String,
  session_id : String,
) -> Unit {
  if self.mooncode_sessions.get(session_id) is Some(binding) &&
    binding.book_root != "" &&
    binding.book_root != book_root {
    raise json_error(409, "Conflict", {
      "error": { "message": "Session is bound to a different Book" },
    })
  }
  let lock = mooncode_integration_file(
    mooncode_session_lock_path(book_root, session_id),
    create=true,
  ).unwrap()
  defer lock.close()
  lock.lock(Exclusive)
  defer lock.unlock()
  let marker = mooncode_session_state_path(book_root, session_id)
  let state_file = mooncode_integration_file(marker)
  let stored_state = match state_file {
    None => ""
    Some(file) => {
      defer file.close()
      file.lock(Shared)
      defer file.unlock()
      mooncode_session_stored_state_file(file)
    }
  }
  let active_path = mooncode_session_dir_by_safe_id(book_root, session_id)
  let archived_path = mooncode_session_dir_by_safe_id(
    book_root,
    session_id,
    archived=true,
  )
  let active = @fsx.exists(active_path)
  let archived = @fsx.exists(archived_path)
  let snapshot_path = mooncode_session_snapshot_path_by_safe_id(
    book_root,
    session_id,
    archived~,
  )
  let snapshot_text = @book_runtime.read_resource(snapshot_path)
  let snapshot = match snapshot_text {
    None => Json::empty_object()
    Some(text) => @json.parse(text)
  }
  if snapshot_text is Some(_) {
    guard mooncode_json_string(snapshot, "session_id", default="") == session_id else {
      raise json_error(409, "Conflict", {
        "error": { "message": "Session snapshot identity does not match" },
      })
    }
    ignore(mooncode_snapshot_journal_sequence(snapshot))
  }
  let state = mooncode_session_state_from_parts(
    book_root, session_id, stored_state, active, archived, snapshot,
  )
  if state != "new" && state != "active" {
    raise json_error(409, "Conflict", {
      "error": { "message": "Session is foreign or is not active" },
    })
  }
  let journal_path = mooncode_session_journal_path(book_root, session_id)
  let journal_file = mooncode_integration_file(
    journal_path,
    create=state == "new",
  )
  let journal = match journal_file {
    None => []
    Some(file) => {
      defer file.close()
      file.lock(Exclusive)
      defer file.unlock()
      mooncode_repair_journal_tail(file)
      mooncode_parse_journal_file(file, journal_path, session_id)
    }
  }
  let accepted_owner = mooncode_journal_model_workspace(journal)
  let snapshot_owner = mooncode_json_string(
    snapshot,
    "model_workspace",
    default="",
  )
  if accepted_owner is Some(owner) &&
    snapshot_owner != "" &&
    snapshot_owner != owner {
    raise json_error(409, "Conflict", {
      "error": {
        "message": "Session model workspace conflicts with its journal",
      },
    })
  }
  guard mooncode_model_workspace_is_canonical(
    accepted_owner.unwrap_or(snapshot_owner),
  ) else {
    raise json_error(409, "Conflict", {
      "error": { "message": "Session model workspace is not canonical" },
    })
  }
  if state == "active" && snapshot_text is None {
    raise json_error(409, "Conflict", {
      "error": { "message": "Session has no matching durable Book binding" },
    })
  }
  let was_present = self.mooncode_sessions.contains(session_id)
  let binding = self.mooncode_binding_for_session(session_id)
  let previous_root = binding.book_root
  errdefer {
    binding.book_root = previous_root
    if !was_present {
      self.mooncode_sessions.remove(session_id)
    }
  }
  guard binding.bind_book_root(book_root) else {
    raise json_error(409, "Conflict", {
      "error": { "message": "Session is bound to a different Book" },
    })
  }
  if state == "new" {
    mooncode_integration_write_new(
      mooncode_session_snapshot_path(book_root, session_id),
      mooncode_session_snapshot(binding).stringify(indent=2),
    )
    mooncode_integration_write_new(marker, "active\n")
  } else {
    binding.restore_session_metadata_parts(snapshot, journal)
  }
}

///|
async fn mooncode_integration_file(
  path : String,
  create~ : Bool = false,
) -> @fs.File? {
  @book_runtime.storage_file(path, create~) catch {
    _ =>
      raise json_error(403, "Forbidden", {
        "error": { "message": "Session storage is not canonical or available" },
      })
  }
}

///|
async fn mooncode_integration_write_new(
  path : String,
  content : String,
) -> Unit {
  let file = mooncode_integration_file(path, create=true).unwrap()
  defer file.close()
  file.lock(Exclusive)
  defer file.unlock()
  guard file.size() == 0L else {
    raise json_error(409, "Conflict", {
      "error": { "message": "Session storage changed during admission" },
    })
  }
  file.write(content)
  file.sync()
}

///|
async fn Daemon::with_mooncode_integration_request(
  self : Daemon,
  config : @moondesk_sandbox_config.Config,
  r : @httpx.RequestReader,
  run : async (Json, String) -> Unit,
) -> Unit {
  let body : Json = @httpx.JsonRequestReader::new(r).read() catch {
    _ =>
      raise json_error(400, "Bad Request", {
        "error": { "message": "Invalid integration JSON" },
      })
  }
  guard body is Object(fields) else {
    raise json_error(400, "Bad Request", {
      "error": { "message": "Integration request must be an object" },
    })
  }
  let book_root = mooncode_json_string(body, "book_root", default="")
  guard config.allows_book_root(book_root) else {
    raise json_error(403, "Forbidden", {
      "error": {
        "message": "Book is not explicitly trusted by this control instance",
      },
    })
  }
  for key in ["trusted_book_roots", "workspace_trust", "model_workspace"] {
    if fields.contains(key) {
      raise json_error(400, "Bad Request", {
        "error": {
          "message": "Request cannot supply trust or model workspace authority",
        },
      })
    }
  }
  let session_id = match fields.get("session_id") {
    None => {
      run(body, book_root)
      return
    }
    Some(String(value)) => value
    _ =>
      raise json_error(400, "Bad Request", {
        "error": { "message": "Invalid session identity" },
      })
  }
  guard mooncode_integration_session_id_valid(session_id) else {
    raise json_error(400, "Bad Request", {
      "error": { "message": "Invalid session identity" },
    })
  }
  // Deny unrecorded caller identities before creating even the admission lock.
  mooncode_integration_check_binding(config, session_id, book_root) catch {
    HttpError(..) as error => raise error
    _ =>
      raise json_error(403, "Forbidden", {
        "error": { "message": "Session binding storage is unavailable" },
      })
  }
  let binding_lock = mooncode_integration_file(
    mooncode_integration_binding_path(config, session_id, ".lock"),
    create=true,
  ).unwrap()
  defer binding_lock.close()
  binding_lock.lock(Exclusive)
  let binding_locked = Ref(true)
  defer (if binding_locked.val { binding_lock.unlock() })
  mooncode_integration_check_binding(config, session_id, book_root) catch {
    HttpError(..) as error => raise error
    _ =>
      raise json_error(403, "Forbidden", {
        "error": { "message": "Session binding storage is unavailable" },
      })
  }
  let gate = mooncode_integration_file(
    mooncode_session_lifecycle_gate_path(book_root, session_id),
    create=true,
  ).unwrap()
  defer gate.close()
  gate.lock(Shared)
  defer gate.unlock()
  self.mooncode_bind_integration_session(book_root, session_id) catch {
    HttpError(..) as error => raise error
    _ =>
      raise json_error(409, "Conflict", {
        "error": { "message": "Session identity or storage is invalid" },
      })
  }
  binding_lock.unlock()
  binding_locked.val = false
  // Keep lifecycle ownership through metadata reads and the provider operation.
  run(body, book_root)
}
