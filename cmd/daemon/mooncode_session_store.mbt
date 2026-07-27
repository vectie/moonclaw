///|
async fn mooncode_durable_session_records(book_root : String) -> Array[Json] {
  let records = []
  let root = mooncode_sessions_root(book_root)
  if !(@fsx.exists(root) catch { _ => false }) {
    return records
  }
  let entries = @fsx.list_directory(root) catch { _ => return records }
  for entry in entries {
    if entry.kind is Directory {
      match mooncode_durable_session_record_by_safe_id(book_root, entry.name) {
        Some(record) => records.push(record)
        None => ()
      }
    }
  }
  records
}

///|
async fn mooncode_durable_session_listing_records(
  book_root : String,
  include_log_counts? : Bool = true,
) -> Array[Json] {
  mooncode_durable_session_listing_records_at(
    book_root,
    archived=false,
    include_log_counts~,
  )
}

///|
async fn mooncode_durable_archived_session_listing_records(
  book_root : String,
  include_log_counts? : Bool = true,
) -> Array[Json] {
  mooncode_durable_session_listing_records_at(
    book_root,
    archived=true,
    include_log_counts~,
  )
}

///|
async fn mooncode_durable_session_listing_records_at(
  book_root : String,
  archived~ : Bool,
  include_log_counts~ : Bool,
) -> Array[Json] {
  let records = []
  let root = mooncode_session_store_root(book_root, archived~)
  if !(@fsx.exists(root) catch { _ => false }) {
    return records
  }
  let entries = @fsx.list_directory(root) catch { _ => return records }
  for entry in entries {
    if entry.kind is Directory {
      match
        mooncode_durable_session_listing_record_by_safe_id(
          book_root,
          entry.name,
          archived~,
          include_log_counts~,
        ) {
        Some(record) => records.push(record)
        None => ()
      }
    }
  }
  records
}

///|
/// Readers call this only while holding the stable session lock.
async fn mooncode_session_location_matches_locked(
  book_root : String,
  session_id : String,
  archived~ : Bool,
) -> Bool {
  let expected = if archived { "archived" } else { "active" }
  if mooncode_session_state_locked(book_root, session_id) != expected {
    return false
  }
  @fsx.exists(
    mooncode_session_dir_by_safe_id(
      book_root,
      mooncode_safe_session_id(session_id),
      archived~,
    ),
  ) catch {
    _ => false
  }
}

///|
async fn mooncode_durable_session_record_by_safe_id(
  book_root : String,
  safe_session_id : String,
) -> Json? {
  let session_lock = mooncode_open_session_lock(book_root, safe_session_id)
  defer session_lock.close()
  session_lock.lock(Shared)
  defer session_lock.unlock()
  if !mooncode_session_location_matches_locked(
      book_root,
      safe_session_id,
      archived=false,
    ) {
    return None
  }
  let snapshot = mooncode_load_session_snapshot_from_store(
    book_root,
    safe_session_id,
    archived=false,
  )
  let session_id = mooncode_json_string(
    snapshot,
    "session_id",
    default=safe_session_id,
  )
  if mooncode_safe_session_id(session_id) != safe_session_id {
    raise InvalidJournal(
      "MoonCode session snapshot identity does not match its storage directory",
    )
  }
  Some(
    mooncode_session_record_from_parts_locked(
      session_id,
      book_root,
      None,
      Some(snapshot),
      source="sidecar",
    ),
  )
}

///|
async fn mooncode_durable_session_listing_record_by_safe_id(
  book_root : String,
  safe_session_id : String,
  archived~ : Bool,
  include_log_counts~ : Bool,
) -> Json? {
  let session_lock = mooncode_open_session_lock(book_root, safe_session_id)
  defer session_lock.close()
  session_lock.lock(Shared)
  defer session_lock.unlock()
  if !mooncode_session_location_matches_locked(
      book_root,
      safe_session_id,
      archived~,
    ) {
    return None
  }
  let snapshot = mooncode_load_session_snapshot_from_store(
    book_root,
    safe_session_id,
    archived~,
  )
  let session_id = mooncode_json_string(
    snapshot,
    "session_id",
    default=safe_session_id,
  )
  if mooncode_safe_session_id(session_id) != safe_session_id {
    raise InvalidJournal(
      "MoonCode session snapshot identity does not match its storage directory",
    )
  }
  Some(
    mooncode_session_listing_record_from_parts_locked(
      session_id,
      book_root,
      None,
      snapshot,
      source="sidecar",
      include_log_counts~,
      archived~,
    ),
  )
}

///|
async fn mooncode_active_session_record_projection(
  session_id : String,
  book_root : String,
  live_binding : MoonCodeSessionBinding?,
  source~ : String,
) -> Json? {
  if book_root == "" {
    guard live_binding is Some(binding) else { return None }
    return Some(
      mooncode_session_record_from_parts_locked(
        session_id,
        book_root,
        live_binding,
        Some(mooncode_session_snapshot(binding)),
        source~,
      ),
    )
  }
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Shared)
  defer session_lock.unlock()
  let state = mooncode_session_state_locked(book_root, session_id)
  let snapshot = if state == "active" &&
    mooncode_session_location_matches_locked(
      book_root,
      session_id,
      archived=false,
    ) {
    let loaded = mooncode_load_session_snapshot(book_root, session_id)
    if mooncode_json_string(loaded, "load_status", default="") == "missing" &&
      live_binding is None {
      return None
    }
    loaded
  } else if state == "new" {
    guard live_binding is Some(binding) else { return None }
    mooncode_session_snapshot(binding)
  } else {
    return None
  }
  let projection_binding = if state == "new" { live_binding } else { None }
  Some(
    mooncode_session_record_from_parts_locked(
      session_id,
      book_root,
      projection_binding,
      Some(snapshot),
      source~,
    ),
  )
}

///|
async fn mooncode_active_session_listing_projection(
  session_id : String,
  book_root : String,
  live_binding : MoonCodeSessionBinding?,
  source~ : String,
  include_log_counts~ : Bool,
) -> Json? {
  if book_root == "" {
    guard live_binding is Some(binding) else { return None }
    return Some(
      mooncode_session_listing_record_from_parts_locked(
        session_id,
        book_root,
        live_binding,
        mooncode_session_snapshot(binding),
        source~,
        include_log_counts~,
      ),
    )
  }
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Shared)
  defer session_lock.unlock()
  let state = mooncode_session_state_locked(book_root, session_id)
  let snapshot = if state == "active" &&
    mooncode_session_location_matches_locked(
      book_root,
      session_id,
      archived=false,
    ) {
    let loaded = mooncode_load_session_snapshot(book_root, session_id)
    if mooncode_json_string(loaded, "load_status", default="") == "missing" &&
      live_binding is None {
      return None
    }
    loaded
  } else if state == "new" {
    guard live_binding is Some(binding) else { return None }
    mooncode_session_snapshot(binding)
  } else {
    return None
  }
  let projection_binding = if state == "new" { live_binding } else { None }
  Some(
    mooncode_session_listing_record_from_parts_locked(
      session_id,
      book_root,
      projection_binding,
      snapshot,
      source~,
      include_log_counts~,
    ),
  )
}

///|
fn mooncode_snapshot_journal_sequence(
  snapshot : Json,
) -> MoonCodeJournalSequence raise MoonCodeJournalError {
  guard snapshot is Object(fields) else {
    raise InvalidJournal("session snapshot is not an object")
  }
  let contract_id = match fields.get("contract_id") {
    None => ""
    Some(String(value)) => value
    Some(_) =>
      raise InvalidJournal("session snapshot contract_id must be a string")
  }
  if contract_id != "" &&
    contract_id != "mooncode-session-snapshot.v1" &&
    contract_id != @mooncode_core.session_snapshot_contract_id() {
    raise InvalidJournal(
      "Unsupported MoonCode session snapshot contract `\{contract_id}`",
    )
  }
  match fields.get("journal_sequence") {
    None => {
      if contract_id == @mooncode_core.session_snapshot_contract_id() {
        raise InvalidJournal(
          "MoonCode session snapshot v2 requires journal_sequence",
        )
      }
      MoonCodeJournalSequence::zero()
    }
    Some(value) => {
      if contract_id == @mooncode_core.session_snapshot_contract_id() &&
        !(value is String(_)) {
        raise InvalidJournal(
          "MoonCode session snapshot v2 requires a canonical decimal string journal_sequence",
        )
      }
      mooncode_journal_cursor_from_json(value) catch {
        MoonCodeGoalRuntimeStoreError::CorruptStore(message) =>
          raise InvalidJournal(
            "Invalid session snapshot journal_sequence: \{message}",
          )
        MoonCodeGoalRuntimeStoreError::IdentityConflict(_, _, _) =>
          raise InvalidJournal(
            "Invalid session snapshot journal_sequence: unexpected identity conflict",
          )
      }
    }
  }
}

///|
async fn mooncode_session_listing_record_from_parts_locked(
  session_id : String,
  book_root : String,
  live_binding : MoonCodeSessionBinding?,
  snapshot : Json,
  source~ : String,
  include_log_counts? : Bool = true,
  archived? : Bool = false,
) -> Json {
  let safe_session_id = mooncode_safe_session_id(session_id)
  let journal_path = mooncode_session_journal_path_by_safe_id(
    book_root,
    safe_session_id,
    archived~,
  )
  let journal = if include_log_counts {
    mooncode_read_session_journal_path(journal_path, session_id)
  } else {
    []
  }
  let metadata_source : Json = {
    "snapshot": snapshot,
    "binding": match live_binding {
      Some(binding) => binding.to_json()
      None => null
    },
  }
  {
    "kind": "mooncode-session-listing-record",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "source": source,
    "archived": archived,
    "session_id": session_id,
    "safe_session_id": safe_session_id,
    "book_root": book_root,
    "model": mooncode_json_string(snapshot, "model", default=""),
    "live_binding_ready": live_binding is Some(_),
    "binding": match live_binding {
      Some(binding) => binding.to_json()
      None => null
    },
    "snapshot": snapshot,
    "custom_title": mooncode_session_custom_title(metadata_source, journal),
    "storage": {
      "session_json": mooncode_session_snapshot_path_by_safe_id(
        book_root,
        safe_session_id,
        archived~,
      ),
      "journal_jsonl": journal_path,
    },
    "journal_record_count": journal.length(),
    "journal_sequence": if include_log_counts {
      mooncode_journal_last_sequence_exact(journal).text()
    } else {
      mooncode_snapshot_journal_sequence(snapshot).text()
    },
    "command_log_count": if include_log_counts {
      mooncode_journal_record_count(journal, mooncode_journal_command())
    } else {
      mooncode_json_int(snapshot, "command_count", default=0)
    },
    "runtime_receipt_log_count": if include_log_counts {
      mooncode_journal_record_count(journal, mooncode_journal_runtime_receipt())
    } else {
      0
    },
    "event_log_count": if include_log_counts {
      mooncode_journal_record_count(journal, mooncode_journal_event())
    } else {
      0
    },
    "package_result_log_count": if include_log_counts {
      mooncode_journal_record_count(journal, mooncode_journal_package_result())
    } else {
      0
    },
    "book_result_log_count": if include_log_counts {
      mooncode_journal_record_count(journal, mooncode_journal_book_result())
    } else {
      0
    },
    "resume_state": if live_binding is Some(_) {
      "live"
    } else {
      "durable"
    },
  }
}

///|
async fn mooncode_session_listing_record_from_parts(
  session_id : String,
  book_root : String,
  live_binding : MoonCodeSessionBinding?,
  snapshot : Json,
  source~ : String,
  include_log_counts? : Bool = true,
  archived? : Bool = false,
) -> Json {
  if book_root == "" {
    return mooncode_session_listing_record_from_parts_locked(
      session_id,
      book_root,
      live_binding,
      snapshot,
      source~,
      include_log_counts~,
      archived~,
    )
  }
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Shared)
  defer session_lock.unlock()
  mooncode_session_listing_record_from_parts_locked(
    session_id,
    book_root,
    live_binding,
    snapshot,
    source~,
    include_log_counts~,
    archived~,
  )
}

///|
async fn mooncode_load_session_snapshot(
  book_root : String,
  session_id : String,
) -> Json {
  mooncode_load_session_snapshot_by_safe_id(
    book_root,
    mooncode_safe_session_id(session_id),
  )
}

///|
async fn mooncode_load_session_snapshot_by_safe_id(
  book_root : String,
  safe_session_id : String,
) -> Json {
  mooncode_load_session_snapshot_from_store(
    book_root,
    safe_session_id,
    archived=false,
  )
}

///|
async fn mooncode_load_session_snapshot_from_store(
  book_root : String,
  safe_session_id : String,
  archived~ : Bool,
) -> Json {
  let path = mooncode_session_snapshot_path_by_safe_id(
    book_root,
    safe_session_id,
    archived~,
  )
  if book_root == "" || !(@fsx.exists(path) catch { _ => false }) {
    return mooncode_missing_session_snapshot(
      book_root,
      safe_session_id,
      path,
      load_status="missing",
    )
  }
  let snapshot = @json.parse(mooncode_read_locked_file(path)) catch {
    _ =>
      return mooncode_missing_session_snapshot(
        book_root,
        safe_session_id,
        path,
        load_status="invalid-json",
      )
  }
  ignore(mooncode_snapshot_journal_sequence(snapshot))
  snapshot
}

///|
fn mooncode_missing_session_snapshot(
  book_root : String,
  safe_session_id : String,
  path : String,
  load_status~ : String,
) -> Json {
  {
    "kind": "mooncode-session-snapshot",
    "contract_id": @mooncode_core.session_snapshot_contract_id(),
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": safe_session_id,
    "book_root": book_root,
    "load_status": load_status,
    "journal_sequence": "0",
    "storage": {
      "session_json": path,
      "journal_jsonl": mooncode_session_journal_path_by_safe_id(
        book_root, safe_session_id,
      ),
    },
  }
}

///|
async fn mooncode_session_record_from_parts_locked(
  session_id : String,
  book_root : String,
  live_binding : MoonCodeSessionBinding?,
  snapshot : Json?,
  source~ : String,
) -> Json {
  let safe_session_id = mooncode_safe_session_id(session_id)
  let resolved_snapshot = match snapshot {
    Some(value) => value
    None =>
      match live_binding {
        Some(binding) => mooncode_session_snapshot(binding)
        None =>
          mooncode_missing_session_snapshot(
            book_root,
            safe_session_id,
            mooncode_session_snapshot_path_by_safe_id(
              book_root, safe_session_id,
            ),
            load_status="not-loaded",
          )
      }
  }
  let journal_path = mooncode_session_journal_path_by_safe_id(
    book_root, safe_session_id,
  )
  let journal = mooncode_read_session_journal_path(journal_path, session_id)
  let commands = mooncode_journal_entries(journal, mooncode_journal_command())
  let runtime_receipts = mooncode_journal_entries(
    journal,
    mooncode_journal_runtime_receipt(),
  )
  let events = mooncode_journal_entries(journal, mooncode_journal_event())
  let package_results = mooncode_journal_entries(
    journal,
    mooncode_journal_package_result(),
  )
  let book_results = mooncode_journal_entries(
    journal,
    mooncode_journal_book_result(),
  )
  let resume_state = if live_binding is Some(_) {
    "live"
  } else if mooncode_json_string(
      resolved_snapshot,
      "load_status",
      default="loaded",
    ) ==
    "missing" {
    "missing"
  } else {
    "durable"
  }
  let record_without_lifecycle : Json = {
    "kind": "mooncode-session-record",
    "contract_id": @mooncode_core.session_record_contract_id(),
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "source": source,
    "session_id": mooncode_json_string(
      resolved_snapshot,
      "session_id",
      default=session_id,
    ),
    "safe_session_id": safe_session_id,
    "book_root": book_root,
    "model": mooncode_json_string(resolved_snapshot, "model", default=""),
    "live_binding_ready": live_binding is Some(_),
    "binding": match live_binding {
      Some(binding) => binding.to_json()
      None => null
    },
    "snapshot": resolved_snapshot,
    "custom_title": mooncode_session_custom_title(
      {
        "snapshot": resolved_snapshot,
        "binding": match live_binding {
          Some(binding) => binding.to_json()
          None => null
        },
      },
      journal,
    ),
    "storage": {
      "session_json": mooncode_session_snapshot_path_by_safe_id(
        book_root, safe_session_id,
      ),
      "journal_jsonl": journal_path,
    },
    "journal_record_count": journal.length(),
    "journal_sequence": mooncode_journal_last_sequence_exact(journal).text(),
    "command_log_count": commands.length(),
    "runtime_receipt_log_count": runtime_receipts.length(),
    "event_log_count": events.length(),
    "package_result_log_count": package_results.length(),
    "book_result_log_count": book_results.length(),
    "resume_state": resume_state,
  }
  let record_with_conversation = mooncode_json_object_with_field(
    record_without_lifecycle,
    "mooncode_conversation",
    mooncode_session_conversation(
      record_without_lifecycle,
      commands,
      runtime_receipts,
      events,
      journal_sequence=mooncode_journal_last_sequence_exact(journal),
    ),
  )
  mooncode_json_object_with_field(
    record_with_conversation,
    "executable_book_lifecycle",
    mooncode_executable_book_lifecycle_report(
      record_without_lifecycle, commands, runtime_receipts, events, package_results,
      book_results,
    ),
  )
}

///|
async fn mooncode_session_record_from_parts(
  session_id : String,
  book_root : String,
  live_binding : MoonCodeSessionBinding?,
  snapshot : Json?,
  source~ : String,
) -> Json {
  if book_root == "" {
    return mooncode_session_record_from_parts_locked(
      session_id,
      book_root,
      live_binding,
      snapshot,
      source~,
    )
  }
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Shared)
  defer session_lock.unlock()
  mooncode_session_record_from_parts_locked(
    session_id,
    book_root,
    live_binding,
    snapshot,
    source~,
  )
}

///|
fn mooncode_session_snapshot(
  binding : MoonCodeSessionBinding,
  journal_sequence? : MoonCodeJournalSequence = MoonCodeJournalSequence::zero(),
) -> Json {
  {
    "kind": "mooncode-session-snapshot",
    "contract_id": @mooncode_core.session_snapshot_contract_id(),
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": binding.session_id,
    "book_root": binding.book_root,
    "workspace_id": binding.workspace_id,
    "workspace_name": binding.workspace_name,
    "model": binding.model,
    "command_count": binding.command_count,
    "first_user_prompt": binding.first_user_prompt,
    "custom_title": binding.custom_title,
    "last_command_id": binding.last_command_id,
    "last_updated": binding.last_updated,
    "journal_sequence": journal_sequence.text(),
    "storage": {
      "session_json": mooncode_session_snapshot_path(
        binding.book_root,
        binding.session_id,
      ),
      "journal_jsonl": mooncode_session_journal_path(
        binding.book_root,
        binding.session_id,
      ),
    },
  }
}

///|
fn mooncode_session_dir(book_root : String, session_id : String) -> String {
  mooncode_session_dir_by_safe_id(
    book_root,
    mooncode_safe_session_id(session_id),
  )
}

///|
fn mooncode_sessions_root(book_root : String) -> String {
  @moonsuite.product_artifact_for_workspace_root(
    book_root, "moonclaw", "mooncode/sessions",
  )
}

///|
fn mooncode_archived_sessions_root(book_root : String) -> String {
  @moonsuite.product_artifact_for_workspace_root(
    book_root, "moonclaw", "mooncode/archived/sessions",
  )
}

///|
/// Cross-process coordination lives outside both movable session trees so an
/// archive, restore, or delete cannot replace the inode used by appenders.
fn mooncode_session_lock_path(
  book_root : String,
  session_id : String,
) -> String {
  @moonsuite.product_artifact_for_workspace_root(
    book_root,
    "moonclaw",
    "mooncode/session-locks/\{mooncode_safe_session_id(session_id)}.lock",
  )
}

///|
async fn mooncode_open_session_lock(
  book_root : String,
  session_id : String,
) -> @fs.File {
  let path = mooncode_session_lock_path(book_root, session_id)
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  @fs.open(path, mode=ReadWrite, create=0o644, truncate=false)
}

///|
/// Runtime work holds this gate shared for its execution lifetime; storage
/// lifecycle transitions take it exclusive before checking or moving state.
fn mooncode_session_lifecycle_gate_path(
  book_root : String,
  session_id : String,
) -> String {
  @moonsuite.product_artifact_for_workspace_root(
    book_root,
    "moonclaw",
    "mooncode/session-locks/\{mooncode_safe_session_id(session_id)}.runtime-gate",
  )
}

///|
async fn mooncode_open_session_lifecycle_gate(
  book_root : String,
  session_id : String,
) -> @fs.File {
  let path = mooncode_session_lifecycle_gate_path(book_root, session_id)
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  @fs.open(path, mode=ReadWrite, create=0o644, truncate=false)
}

///|
/// Cross-process execution ownership is separate from the lifecycle gate. A
/// runtime first holds the lifecycle gate Shared, then this lease Exclusive, so
/// lifecycle transitions can wait without allowing two queue consumers.
fn mooncode_session_execution_lease_path(
  book_root : String,
  session_id : String,
) -> String {
  @moonsuite.product_artifact_for_workspace_root(
    book_root,
    "moonclaw",
    "mooncode/session-locks/\{mooncode_safe_session_id(session_id)}.execution-lease",
  )
}

///|
async fn mooncode_open_session_execution_lease(
  book_root : String,
  session_id : String,
) -> @fs.File {
  let path = mooncode_session_execution_lease_path(book_root, session_id)
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  @fs.open(path, mode=ReadWrite, create=0o644, truncate=false)
}

///|
fn mooncode_session_state_path(
  book_root : String,
  session_id : String,
) -> String {
  @moonsuite.product_artifact_for_workspace_root(
    book_root,
    "moonclaw",
    "mooncode/session-locks/\{mooncode_safe_session_id(session_id)}.state",
  )
}

///|
/// Read the last newline-committed lifecycle state. A crash may leave a partial
/// final suffix; it is ignored just like a torn journal tail.
async fn mooncode_session_stored_state_locked(marker : String) -> String {
  if !(@fsx.exists(marker) catch { _ => false }) {
    return ""
  }
  let file = @fs.open(marker, mode=ReadOnly)
  defer file.close()
  file.lock(Shared)
  defer file.unlock()
  let committed_size = mooncode_newline_committed_size(file)
  let mut consumed = 0L
  let mut latest = ""
  while consumed < committed_size {
    match file.read_until("\n") {
      Some(line) => {
        consumed += @encoding/utf8.encode(line).length().to_int64() + 1L
        if consumed > committed_size {
          raise InvalidJournal(
            "MoonCode session lifecycle marker crossed its committed boundary",
          )
        }
        let state = line.trim().to_owned()
        if ![
            "active", "archiving", "archived", "restoring", "deleting", "deleted",
          ].contains(state) {
          raise InvalidJournal(
            "Invalid MoonCode session lifecycle marker entry `\{state}`",
          )
        }
        latest = state
      }
      None =>
        raise InvalidJournal(
          "MoonCode session lifecycle marker ended before its committed boundary",
        )
    }
  }
  latest
}

///|
/// Resolve lifecycle state only while the stable session lock is held. Legacy
/// sessions without a committed marker are inferred from their active/archived
/// location; interrupted transition intent is reconciled with that location.
async fn mooncode_session_state_locked(
  book_root : String,
  session_id : String,
) -> String {
  let marker = mooncode_session_state_path(book_root, session_id)
  let stored_state = mooncode_session_stored_state_locked(marker)
  let safe_session_id = mooncode_safe_session_id(session_id)
  let active = @fsx.exists(
    mooncode_session_dir_by_safe_id(book_root, safe_session_id, archived=false),
  ) catch {
    _ => false
  }
  let archived = @fsx.exists(
    mooncode_session_dir_by_safe_id(book_root, safe_session_id, archived=true),
  ) catch {
    _ => false
  }
  if active && archived {
    raise InvalidJournal(
      "MoonCode session `\{session_id}` exists in both active and archived storage",
    )
  }
  match stored_state {
    "" => if archived { "archived" } else if active { "active" } else { "new" }
    "archiving" =>
      if archived {
        "archived"
      } else if active {
        "active"
      } else {
        "archiving"
      }
    "restoring" =>
      if active {
        "active"
      } else if archived {
        "archived"
      } else {
        "restoring"
      }
    "deleting" =>
      if active {
        "active"
      } else if archived {
        "archived"
      } else {
        "deleted"
      }
    state => state
  }
}

///|
/// Persist lifecycle intent and result under the stable session lock. The state
/// file is synced before its complete parent chain on supported platforms.
async fn mooncode_write_session_state_locked(
  book_root : String,
  session_id : String,
  state : String,
) -> Unit {
  let marker = mooncode_session_state_path(book_root, session_id)
  @fsx.make_directory(@pathx.dirname(marker), recursive=true, exists_ok=true)
  let file = @fs.open(
    marker,
    mode=ReadWrite,
    append=false,
    create=0o644,
    truncate=false,
  )
  defer file.close()
  file.lock(Exclusive)
  defer file.unlock()
  mooncode_repair_journal_tail(file)
  let position = file.size()
  file.write_at(@encoding/utf8.encode(state + "\n"), position~)
  file.sync()
  mooncode_sync_journal_directories(mooncode_journal_commit_directories(marker))
}

///|
async fn mooncode_require_active_session_state_locked(
  book_root : String,
  session_id : String,
  allow_create? : Bool = false,
) -> Unit {
  let state = mooncode_session_state_locked(book_root, session_id)
  if state == "active" {
    let marker = mooncode_session_state_path(book_root, session_id)
    let marker_is_active = mooncode_session_stored_state_locked(marker) ==
      "active"
    if !marker_is_active {
      mooncode_write_session_state_locked(book_root, session_id, "active")
    }
    return
  }
  if state == "new" && allow_create {
    mooncode_write_session_state_locked(book_root, session_id, "active")
    return
  }
  raise InvalidJournal(
    "MoonCode session `\{session_id}` is not active (lifecycle state `\{state}`)",
  )
}

///|
fn mooncode_session_store_root(book_root : String, archived~ : Bool) -> String {
  if archived {
    mooncode_archived_sessions_root(book_root)
  } else {
    mooncode_sessions_root(book_root)
  }
}

///|
fn mooncode_session_dir_by_safe_id(
  book_root : String,
  safe_session_id : String,
  archived? : Bool = false,
) -> String {
  mooncode_session_store_root(book_root, archived~)
  |> @pathx.join(safe_session_id)
}

///|
fn mooncode_session_snapshot_path(
  book_root : String,
  session_id : String,
) -> String {
  mooncode_session_dir(book_root, session_id) |> @pathx.join("session.json")
}

///|
fn mooncode_session_snapshot_path_by_safe_id(
  book_root : String,
  safe_session_id : String,
  archived? : Bool = false,
) -> String {
  mooncode_session_dir_by_safe_id(book_root, safe_session_id, archived~)
  |> @pathx.join("session.json")
}

///|
fn mooncode_safe_session_id(session_id : String) -> String {
  let safe = session_id
    .replace_all(old="/", new="_")
    .replace_all(old="\\", new="_")
    .replace_all(old=":", new="_")
    .replace_all(old="..", new="_")
    .trim()
    .to_owned()
  if safe == "" {
    "session"
  } else {
    safe
  }
}
