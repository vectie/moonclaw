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
  let path = mooncode_session_snapshot_path_by_safe_id(
    book_root, safe_session_id,
  )
  if book_root == "" || !(@fsx.exists(path) catch { _ => false }) {
    return mooncode_missing_session_snapshot(
      book_root,
      safe_session_id,
      path,
      load_status="missing",
    )
  }
  @json.parse(@fsx.read_file(path)) catch {
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
      "commands_jsonl": mooncode_commands_path_by_safe_id(
        book_root, safe_session_id,
      ),
      "runtime_receipts_jsonl": mooncode_runtime_receipts_path_by_safe_id(
        book_root, safe_session_id,
      ),
      "events_jsonl": mooncode_events_path_by_safe_id(
        book_root, safe_session_id,
      ),
      "package_results_jsonl": mooncode_package_results_path_by_safe_id(
        book_root, safe_session_id,
      ),
      "book_results_jsonl": mooncode_book_results_path_by_safe_id(
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
  let commands_path = mooncode_commands_path_by_safe_id(
    book_root, safe_session_id,
  )
  let events_path = mooncode_events_path_by_safe_id(book_root, safe_session_id)
  let runtime_receipts_path = mooncode_runtime_receipts_path_by_safe_id(
    book_root, safe_session_id,
  )
  let package_results_path = mooncode_package_results_path_by_safe_id(
    book_root, safe_session_id,
  )
  let book_results_path = mooncode_book_results_path_by_safe_id(
    book_root, safe_session_id,
  )
  let commands = mooncode_read_jsonl(commands_path)
  let runtime_receipts = mooncode_read_jsonl(runtime_receipts_path)
  let events = mooncode_read_jsonl(events_path)
  let package_results = mooncode_read_jsonl(package_results_path)
  let book_results = mooncode_read_jsonl(book_results_path)
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
    "live_binding_ready": live_binding is Some(_),
    "binding": match live_binding {
      Some(binding) => binding.to_json()
      None => null
    },
    "snapshot": resolved_snapshot,
    "storage": {
      "session_json": mooncode_session_snapshot_path_by_safe_id(
        book_root, safe_session_id,
      ),
      "commands_jsonl": commands_path,
      "runtime_receipts_jsonl": runtime_receipts_path,
      "events_jsonl": events_path,
      "package_results_jsonl": package_results_path,
      "book_results_jsonl": book_results_path,
    },
    "command_log_count": commands.length(),
    "runtime_receipt_log_count": runtime_receipts.length(),
    "event_log_count": events.length(),
    "package_result_log_count": package_results.length(),
    "book_result_log_count": book_results.length(),
    "resume_state": resume_state,
  }
  mooncode_json_object_with_field(
    record_without_lifecycle,
    "executable_book_lifecycle",
    mooncode_executable_book_lifecycle_report(
      record_without_lifecycle, commands, runtime_receipts, events, package_results,
      book_results,
    ),
  )
}

///|
async fn mooncode_read_jsonl(path : String) -> Array[Json] {
  let records : Array[Json] = []
  if path == "" || !(@fsx.exists(path) catch { _ => false }) {
    return records
  }
  let text = @fsx.read_file(path) catch { _ => return records }
  for line in text.split("\n") {
    let line = line.trim()
    if line.is_empty() {
      continue
    }
    let parsed = @json.parse(line.to_owned()) catch { _ => continue }
    records.push(parsed)
  }
  records
}

///|
async fn mooncode_append_jsonl(path : String, entry : Json) -> Unit {
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  let existing = if @fsx.exists(path) { @fsx.read_file(path) } else { "" }
  let line = entry.stringify()
  let content = if existing.is_blank() { line } else { "\{existing}\n\{line}" }
  @fsx.write_to_file(path, content)
}

///|
fn mooncode_session_snapshot(binding : MoonCodeSessionBinding) -> Json {
  {
    "kind": "mooncode-session-snapshot",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": binding.session_id,
    "book_root": binding.book_root,
    "command_count": binding.command_count,
    "first_user_prompt": binding.first_user_prompt,
    "last_command_id": binding.last_command_id,
    "last_updated": binding.last_updated,
    "storage": {
      "session_json": mooncode_session_snapshot_path(
        binding.book_root,
        binding.session_id,
      ),
      "commands_jsonl": mooncode_commands_path(
        binding.book_root,
        binding.session_id,
      ),
      "runtime_receipts_jsonl": mooncode_runtime_receipts_path(
        binding.book_root,
        binding.session_id,
      ),
      "events_jsonl": mooncode_events_path(
        binding.book_root,
        binding.session_id,
      ),
      "package_results_jsonl": mooncode_package_results_path(
        binding.book_root,
        binding.session_id,
      ),
      "book_results_jsonl": mooncode_book_results_path(
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
fn mooncode_product_home(book_root : String) -> String {
  book_root
  |> @pathx.join(".moonsuite")
  |> @pathx.join("products")
  |> @pathx.join("moonclaw")
}

///|
fn mooncode_sessions_root(book_root : String) -> String {
  mooncode_product_home(book_root)
  |> @pathx.join("mooncode")
  |> @pathx.join("sessions")
}

///|
fn mooncode_session_dir_by_safe_id(
  book_root : String,
  safe_session_id : String,
) -> String {
  mooncode_sessions_root(book_root) |> @pathx.join(safe_session_id)
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
) -> String {
  mooncode_session_dir_by_safe_id(book_root, safe_session_id)
  |> @pathx.join("session.json")
}

///|
fn mooncode_commands_path(book_root : String, session_id : String) -> String {
  mooncode_session_dir(book_root, session_id) |> @pathx.join("commands.jsonl")
}

///|
fn mooncode_commands_path_by_safe_id(
  book_root : String,
  safe_session_id : String,
) -> String {
  mooncode_session_dir_by_safe_id(book_root, safe_session_id)
  |> @pathx.join("commands.jsonl")
}

///|
fn mooncode_runtime_receipts_path(
  book_root : String,
  session_id : String,
) -> String {
  mooncode_session_dir(book_root, session_id)
  |> @pathx.join("runtime-receipts.jsonl")
}

///|
fn mooncode_runtime_receipts_path_by_safe_id(
  book_root : String,
  safe_session_id : String,
) -> String {
  mooncode_session_dir_by_safe_id(book_root, safe_session_id)
  |> @pathx.join("runtime-receipts.jsonl")
}

///|
fn mooncode_events_path(book_root : String, session_id : String) -> String {
  mooncode_session_dir(book_root, session_id) |> @pathx.join("events.jsonl")
}

///|
fn mooncode_events_path_by_safe_id(
  book_root : String,
  safe_session_id : String,
) -> String {
  mooncode_session_dir_by_safe_id(book_root, safe_session_id)
  |> @pathx.join("events.jsonl")
}

///|
fn mooncode_package_results_path(
  book_root : String,
  session_id : String,
) -> String {
  mooncode_session_dir(book_root, session_id)
  |> @pathx.join("package-results.jsonl")
}

///|
fn mooncode_package_results_path_by_safe_id(
  book_root : String,
  safe_session_id : String,
) -> String {
  mooncode_session_dir_by_safe_id(book_root, safe_session_id)
  |> @pathx.join("package-results.jsonl")
}

///|
fn mooncode_book_results_path(
  book_root : String,
  session_id : String,
) -> String {
  mooncode_session_dir(book_root, session_id)
  |> @pathx.join("book-results.jsonl")
}

///|
fn mooncode_book_results_path_by_safe_id(
  book_root : String,
  safe_session_id : String,
) -> String {
  mooncode_session_dir_by_safe_id(book_root, safe_session_id)
  |> @pathx.join("book-results.jsonl")
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
