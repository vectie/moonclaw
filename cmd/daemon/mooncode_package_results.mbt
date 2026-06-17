///|
async fn Daemon::mooncode_package_result(
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
          "message": "Invalid JSON body for MoonCode package result",
        },
      })
  }
  let session_id = session_id.to_owned()
  let report = mooncode_validate_package_result_body(session_id, body)
  if !mooncode_json_bool(report, "ok", default=false) {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": mooncode_json_string(
          report,
          "message",
          default="Invalid MoonCode package result",
        ),
        "metadata": report,
      },
    })
  }
  let command_id = mooncode_package_result_command_id(body)
  let event_name = mooncode_package_result_event(body)
  let now = self.clock.now()
  let binding = self.mooncode_binding_for_session(session_id)
  binding.command_count += 1
  binding.last_command_id = command_id
  binding.last_updated = now
  let event = mooncode_package_result_event_record(
    session_id~,
    command_id~,
    body,
    now~,
  )
  binding.events.put(event)
  let book_root = mooncode_package_result_book_root(
    requested_book_root=mooncode_request_book_root(r),
    body,
    binding_book_root=binding.book_root,
  )
  if binding.book_root == "" && book_root != "" {
    binding.book_root = book_root
  }
  self.mooncode_persist_package_result(body, binding, event)
  w.header().set("Content-Type", "application/json")
  w.write_header(202, reason="Accepted")
  w.write(
    (
      {
        "accepted": true,
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "command_id": command_id,
        "event": event_name,
        "status": mooncode_package_result_status(event_name),
        "message": "MoonClaw recorded MoonCode package result `\{event_name}`",
        "binding": binding.to_json(),
        "package_result": mooncode_package_result_payload(body),
        "events": Json::array([event]),
      } : Json).stringify(indent=2),
  )
}

///|
fn mooncode_validate_package_result_body(
  session_id : String,
  body : Json,
) -> Json {
  let protocol = mooncode_json_string(body, "protocol", default="")
  let body_session = mooncode_json_string(body, "session_id", default="")
  let command_id = mooncode_package_result_command_id(body)
  let event = mooncode_package_result_event(body)
  let path = mooncode_package_result_path(body)
  let missing : Array[Json] = []
  if protocol != mooncode_protocol_version() {
    missing.push("protocol".to_json())
  }
  if body_session != session_id {
    missing.push("session_id".to_json())
  }
  if command_id == "" {
    missing.push("command_id".to_json())
  }
  if event != mooncode_event_package_built() &&
    event != mooncode_event_package_verified() {
    missing.push("event".to_json())
  }
  if path == "" {
    missing.push("path".to_json())
  }
  {
    "ok": missing.length() == 0,
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "event": event,
    "path": path,
    "missing": Json::array(missing),
    "message": if missing.length() == 0 {
      "MoonCode package result is valid"
    } else {
      "MoonCode package result is missing required fields: \{missing.map(item => item.stringify()).join(", ")}"
    },
  }
}

///|
fn mooncode_package_result_command_id(body : Json) -> String {
  let command_id = mooncode_json_string(body, "command_id", default="")
  if command_id != "" {
    return command_id
  }
  let packet = mooncode_json_object_field_or_empty(body, "command_packet")
  mooncode_json_string(packet, "command_id", default="")
}

///|
fn mooncode_package_result_event(body : Json) -> String {
  let event = mooncode_json_string(body, "event", default="")
  if event != "" {
    return event
  }
  mooncode_json_string(body, "kind", default="")
}

///|
fn mooncode_package_result_path(body : Json) -> String {
  let path = mooncode_json_string(body, "path", default="")
  if path != "" {
    return path
  }
  mooncode_json_string(body, "artifact_path", default="")
}

///|
fn mooncode_package_result_status(event : String) -> String {
  match event {
    "package_verified" => "verified"
    "package_built" => "built"
    _ => "recorded"
  }
}

///|
fn mooncode_package_result_payload(body : Json) -> Json {
  {
    "event": mooncode_package_result_event(body),
    "status": mooncode_package_result_status(
      mooncode_package_result_event(body),
    ),
    "path": mooncode_package_result_path(body),
    "detail": mooncode_json_string(body, "detail", default=""),
    "package_manifest": mooncode_json_object_field_or_empty(
      body, "package_manifest",
    ),
    "package_index": mooncode_json_object_field_or_empty(body, "package_index"),
    "command_packet": mooncode_json_object_field_or_empty(
      body, "command_packet",
    ),
  }
}

///|
fn mooncode_package_result_book_root(
  requested_book_root~ : String,
  body : Json,
  binding_book_root~ : String,
) -> String {
  if requested_book_root != "" {
    return requested_book_root
  }
  let body_book_root = mooncode_book_root(body)
  if body_book_root != "" {
    return body_book_root
  }
  binding_book_root
}

///|
fn mooncode_package_result_event_record(
  session_id~ : String,
  command_id~ : String,
  body : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let event = mooncode_package_result_event(body)
  let path = mooncode_package_result_path(body)
  let detail = mooncode_json_string(body, "detail", default="")
  {
    "id": "moonclaw-\{session_id}-\{command_id}-\{event}-\{now}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "lane": "artifact",
    "kind": "runtime.\{event}",
    "event": event,
    "title": if event == mooncode_event_package_verified() {
      "MoonCode package verified"
    } else {
      "MoonCode package built"
    },
    "status": mooncode_package_result_status(event),
    "detail": if detail == "" {
      "MoonClaw recorded package result at \{path}"
    } else {
      detail
    },
    "path": path,
    "package_result": mooncode_package_result_payload(body),
    "created_at": now,
    "source": "moonclaw-native-mooncode",
  }
}

///|
async fn Daemon::mooncode_persist_package_result(
  self : Daemon,
  body : Json,
  binding : MoonCodeSessionBinding,
  event : Json,
) -> Unit {
  if binding.book_root == "" {
    return
  }
  self.mooncode_persist_session(binding)
  mooncode_append_jsonl(
    mooncode_package_results_path(binding.book_root, binding.session_id),
    {
      "kind": "mooncode-package-result",
      "protocol": mooncode_protocol_version(),
      "session_id": binding.session_id,
      "command_id": mooncode_package_result_command_id(body),
      "created_at": self.clock.now(),
      "package_result": mooncode_package_result_payload(body),
    },
  )
  self.mooncode_persist_event(binding, event)
}
