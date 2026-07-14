///|
async fn Daemon::mooncode_list_sessions(
  self : Daemon,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let book_root = mooncode_request_book_root(r)
  let format = mooncode_request_string(r, "format", default="")
  let records = if format == "json" || format == "listing" {
    self.mooncode_session_listing_records(book_root)
  } else {
    self.mooncode_session_records(book_root)
  }
  w.header().set("Content-Type", "application/json")
  match mooncode_session_list_format_error(format) {
    Some(payload) => raise json_error(400, "Bad Request", payload)
    None => ()
  }
  w.write_header(200)
  if format == "json" {
    let rows = records.map(record => {
      mooncode_compact_session_listing_row(record)
    })
    rows.sort_by(mooncode_compare_session_listing_rows)
    w.write(Json::array(rows).stringify(indent=2))
    return
  }
  if format == "listing" {
    let rows = records.map(record => mooncode_session_listing_row(record))
    rows.sort_by(mooncode_compare_session_listing_rows)
    w.write(
      (
        {
          "kind": "mooncode-session-listing",
          "protocol": mooncode_protocol_version(),
          "owner": "moonclaw",
          "book_root": book_root,
          "durable_store": mooncode_sessions_root(book_root),
          "durable_store_loaded": book_root != "",
          "session_count": records.length(),
          "sessions": Json::array(rows),
        } : Json).stringify(indent=2),
    )
    return
  }
  w.write(
    (
      {
        "kind": "mooncode-session-list",
        "protocol": mooncode_protocol_version(),
        "owner": "moonclaw",
        "book_root": book_root,
        "durable_store": mooncode_sessions_root(book_root),
        "durable_store_loaded": book_root != "",
        "session_count": records.length(),
        "sessions": Json::array(records),
      } : Json).stringify(indent=2),
  )
}

///|
fn mooncode_session_list_format_error(format : String) -> Json? {
  if format == "" || format == "json" || format == "listing" {
    return None
  }
  Some({
    "error": "unsupported MoonCode session list format",
    "format": format,
    "allowed_formats": ["json", "listing"],
  })
}

///|
fn mooncode_compact_session_listing_row(record : Json) -> Json {
  {
    "id": mooncode_json_string(record, "session_id", default=""),
    "title": mooncode_compact_session_listing_title(record),
    "updated_at_ms": mooncode_session_listing_updated_at_ms(record),
  }
}

///|
fn mooncode_compact_session_listing_title(record : Json) -> String {
  let trimmed = mooncode_session_listing_first_user_prompt(record).trim()
  let out = StringBuilder()
  for ch in trimmed {
    if ch is ('\n' | '\r') {
      break
    }
    out.write_char(ch)
  }
  out.to_string().trim().to_owned()
}

///|
fn mooncode_session_listing_row(record : Json) -> Json {
  let session_id = mooncode_json_string(record, "session_id", default="")
  let book_root = mooncode_json_string(record, "book_root", default="")
  let source = mooncode_json_string(record, "source", default="")
  let last_command_id = mooncode_session_listing_last_command_id(record)
  let command_count = mooncode_json_int(record, "command_log_count", default=0)
  let event_count = mooncode_json_int(record, "event_log_count", default=0)
  let package_result_count = mooncode_json_int(
    record,
    "package_result_log_count",
    default=0,
  )
  let lifecycle = mooncode_json_object_field_or_empty(
    record, "executable_book_lifecycle",
  )
  let conversation = mooncode_json_object_field_or_empty(
    record, "mooncode_conversation",
  )
  let workspace_id = mooncode_json_string(
    conversation,
    "workspace_id",
    default="",
  )
  let workspace_name = mooncode_json_string(
    conversation,
    "workspace_name",
    default="",
  )
  let status = if mooncode_json_bool(
      record,
      "live_binding_ready",
      default=false,
    ) {
    "live"
  } else if mooncode_json_string(record, "resume_state", default="") ==
    "durable" {
    "durable"
  } else {
    "unknown"
  }
  {
    "id": session_id,
    "title": mooncode_session_listing_title(record),
    "updated_at": mooncode_session_listing_updated_at(record),
    "updated_at_ms": mooncode_session_listing_updated_at_ms(record),
    "workspace_id": workspace_id,
    "workspace_name": if workspace_name == "" {
      mooncode_session_listing_workspace_name(book_root)
    } else {
      workspace_name
    },
    "workspace_root": book_root,
    "book_root": book_root,
    "status": status,
    "model": mooncode_json_string(record, "model", default=""),
    "last_message": mooncode_session_listing_last_message(record),
    "last_command_id": last_command_id,
    "command_count": command_count,
    "event_count": event_count,
    "package_result_count": package_result_count,
    "lifecycle_status": mooncode_json_string(lifecycle, "status", default=""),
    "lifecycle_ready": mooncode_json_bool(lifecycle, "ready", default=false),
    "lifecycle_completed_step_count": mooncode_json_int(
      lifecycle,
      "completed_step_count",
      default=0,
    ),
    "lifecycle_step_count": mooncode_json_int(
      lifecycle,
      "step_count",
      default=0,
    ),
    "lifecycle_first_blocker_id": mooncode_json_string(
      lifecycle,
      "first_blocker_id",
      default="",
    ),
    "session_url": "/v1/code/sessions/\{session_id}?book_root=<path>",
    "stream_url": "/v1/code/sessions/\{session_id}/stream?book_root=<path>&format=jsonl",
    "source": if source == "" {
      "moonclaw"
    } else {
      source
    },
    "protocol": mooncode_protocol_version(),
    "component": "mooncode",
  }
}

///|
fn mooncode_compare_session_listing_rows(left : Json, right : Json) -> Int {
  match
    (
      mooncode_json_int64_field(left, "updated_at_ms"),
      mooncode_json_int64_field(right, "updated_at_ms"),
    ) {
    (Some(left_ms), Some(right_ms)) =>
      if left_ms > right_ms {
        -1
      } else if left_ms < right_ms {
        1
      } else {
        mooncode_compare_session_listing_labels(left, right)
      }
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (None, None) => mooncode_compare_session_listing_labels(left, right)
  }
}

///|
fn mooncode_compare_session_listing_labels(left : Json, right : Json) -> Int {
  let title_order = mooncode_json_string(left, "title", default="").compare(
    mooncode_json_string(right, "title", default=""),
  )
  if title_order != 0 {
    return title_order
  }
  mooncode_json_string(left, "id", default="").compare(
    mooncode_json_string(right, "id", default=""),
  )
}

///|
fn mooncode_session_listing_title(record : Json) -> String {
  let first_prompt = mooncode_session_listing_first_user_prompt(record)
  if first_prompt != "" {
    return mooncode_session_listing_trim_title(first_prompt)
  }
  let last_message = mooncode_session_listing_last_message(record)
  if last_message != "" {
    return mooncode_session_listing_trim_title(last_message)
  }
  let last_command_id = mooncode_session_listing_last_command_id(record)
  if last_command_id != "" {
    return last_command_id
  }
  let session_id = mooncode_json_string(record, "session_id", default="")
  if session_id == "" {
    "Untitled MoonCode Session"
  } else {
    session_id
  }
}

///|
fn mooncode_session_listing_first_user_prompt(record : Json) -> String {
  let snapshot = mooncode_json_object_field_or_empty(record, "snapshot")
  for key in ["first_user_prompt", "first_prompt"] {
    let value = mooncode_json_string(snapshot, key, default="")
    if value != "" {
      return value
    }
  }
  let binding = mooncode_json_object_field_or_empty(record, "binding")
  for key in ["first_user_prompt", "first_prompt"] {
    let value = mooncode_json_string(binding, key, default="")
    if value != "" {
      return value
    }
  }
  for message in mooncode_json_array_items(snapshot, "transcript") {
    if mooncode_json_string(message, "role", default="") == "user" {
      let content = mooncode_json_string(message, "content", default="")
      if content != "" {
        return content
      }
    }
  }
  ""
}

///|
fn mooncode_session_listing_last_message(record : Json) -> String {
  let snapshot = mooncode_json_object_field_or_empty(record, "snapshot")
  let text = mooncode_json_string(snapshot, "last_text", default="")
  if text != "" {
    return text
  }
  let command = mooncode_json_object_field_or_empty(snapshot, "last_command")
  let command_text = mooncode_json_string(command, "text", default="")
  if command_text != "" {
    return command_text
  }
  mooncode_session_listing_last_command_id(record)
}

///|
fn mooncode_session_listing_last_command_id(record : Json) -> String {
  let value = mooncode_json_string(record, "last_command_id", default="")
  if value != "" {
    return value
  }
  let snapshot = mooncode_json_object_field_or_empty(record, "snapshot")
  mooncode_json_string(snapshot, "last_command_id", default="")
}

///|
fn mooncode_session_listing_updated_at(record : Json) -> Json {
  match record {
    Object(object) =>
      match object.get("last_updated") {
        Some(value) => value
        None => {
          let snapshot = mooncode_json_object_field_or_empty(record, "snapshot")
          match snapshot {
            Object(snapshot_object) =>
              snapshot_object.get("last_updated").unwrap_or(null)
            _ => null
          }
        }
      }
    _ => null
  }
}

///|
fn mooncode_session_listing_updated_at_ms(record : Json) -> Json {
  match mooncode_session_listing_updated_at_millis(record) {
    Some(ms) => Json::number(ms.to_double(), repr=ms.to_string())
    None => null
  }
}

///|
fn mooncode_session_listing_updated_at_millis(record : Json) -> Int64? {
  let explicit = mooncode_json_int64_value(
    mooncode_session_listing_updated_at(record),
  )
  let storage = mooncode_session_listing_latest_storage_mtime(record)
  match (explicit, storage) {
    (Some(left), Some(right)) =>
      if right > left {
        Some(right)
      } else {
        Some(left)
      }
    (Some(value), None) | (None, Some(value)) => Some(value)
    (None, None) => None
  }
}

///|
fn mooncode_session_listing_latest_storage_mtime(record : Json) -> Int64? {
  let storage = mooncode_json_object_field_or_empty(record, "storage")
  let mut latest : Int64? = None
  for
    key in [
      "events_jsonl", "commands_jsonl", "package_results_jsonl", "runtime_receipts_jsonl",
      "session_json",
    ] {
    let mtime = mooncode_file_mtime_ms(
      mooncode_json_string(storage, key, default=""),
    )
    match mtime {
      Some(value) =>
        latest = match latest {
          Some(current) if current >= value => Some(current)
          _ => Some(value)
        }
      None => ()
    }
  }
  latest
}

///|
fn mooncode_file_mtime_ms(path : String) -> Int64? {
  if path == "" {
    return None
  }
  Some(@fsx.stat(path).mtime()) catch {
    _ => None
  }
}

///|
fn mooncode_json_int64_value(value : Json) -> Int64? {
  match value {
    Number(number, repr=None) => Some(number.to_int64())
    Number(_, repr=Some(raw)) | String(raw) =>
      try @string.parse_int64(raw) catch {
        _ => None
      } noraise {
        value => Some(value)
      }
    _ => None
  }
}

///|
fn mooncode_json_int64_field(json : Json, key : String) -> Int64? {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(value) => mooncode_json_int64_value(value)
        None => None
      }
    _ => None
  }
}

///|
fn mooncode_session_listing_workspace_name(book_root : String) -> String {
  if book_root == "" {
    return ""
  }
  let name = @pathx.basename(book_root)
  if name == "" || name == "/" {
    book_root
  } else {
    name.to_owned()
  }
}

///|
fn mooncode_session_listing_trim_title(text : String) -> String {
  let trimmed = text.trim()
  let out = StringBuilder()
  let mut count = 0
  for ch in trimmed {
    if ch is ('\n' | '\r') {
      break
    }
    if count >= 80 {
      out.write_string("...")
      break
    }
    out.write_char(ch)
    count += 1
  }
  out.to_string()
}
