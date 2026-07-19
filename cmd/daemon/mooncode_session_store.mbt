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
      let snapshot = mooncode_load_session_snapshot_by_safe_id(
        book_root,
        entry.name,
      )
      let session_id = mooncode_json_string(
        snapshot,
        "session_id",
        default=entry.name,
      )
      records.push(
        mooncode_session_record_from_parts(
          session_id,
          book_root,
          None,
          Some(snapshot),
          source="sidecar",
        ),
      )
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
      let snapshot = mooncode_load_session_snapshot_from_store(
        book_root,
        entry.name,
        archived~,
      )
      let session_id = mooncode_json_string(
        snapshot,
        "session_id",
        default=entry.name,
      )
      let session_book_root = mooncode_json_string(
        snapshot,
        "book_root",
        default=book_root,
      )
      records.push(
        mooncode_session_listing_record_from_parts(
          session_id,
          session_book_root,
          None,
          snapshot,
          source="sidecar",
          include_log_counts~,
          archived~,
        ),
      )
    }
  }
  records
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
  let safe_session_id = mooncode_safe_session_id(session_id)
  let journal_path = mooncode_session_journal_path_by_safe_id(
    book_root,
    safe_session_id,
    archived~,
  )
  let journal = if include_log_counts {
    mooncode_read_session_journal_path(journal_path)
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
      mooncode_journal_last_sequence(journal)
    } else {
      mooncode_json_int(snapshot, "journal_sequence", default=0)
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
  @json.parse(mooncode_read_locked_file(path)) catch {
    _ =>
      mooncode_missing_session_snapshot(
        book_root,
        safe_session_id,
        path,
        load_status="invalid-json",
      )
  }
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
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": safe_session_id,
    "book_root": book_root,
    "load_status": load_status,
    "storage": {
      "session_json": path,
      "journal_jsonl": mooncode_session_journal_path_by_safe_id(
        book_root, safe_session_id,
      ),
    },
  }
}

///|
async fn mooncode_session_record_from_parts(
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
  let journal = mooncode_read_session_journal_path(journal_path)
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
    "journal_sequence": mooncode_journal_last_sequence(journal),
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
      journal_sequence=mooncode_journal_last_sequence(journal),
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
fn mooncode_session_snapshot(
  binding : MoonCodeSessionBinding,
  journal_sequence? : Int = 0,
) -> Json {
  {
    "kind": "mooncode-session-snapshot",
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
    "journal_sequence": journal_sequence,
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
