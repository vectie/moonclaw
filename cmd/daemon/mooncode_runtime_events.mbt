///|
async fn Daemon::mooncode_runtime_events_state(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let session_id = session_id.to_string()
  let book_root = self.mooncode_runtime_events_book_root(session_id, r, {})
  if book_root == "" {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": "MoonCode runtime events require book_root query or an existing live binding",
        "metadata": { "session_id": session_id },
      },
    })
  }
  let state = self.mooncode_runtime_events_state_payload(session_id, book_root)
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(state.stringify(indent=2))
}

///|
async fn Daemon::mooncode_runtime_events(
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
          "message": "Invalid JSON body for MoonCode runtime events",
        },
      })
  }
  let session_id = session_id.to_string()
  let book_root = self.mooncode_runtime_events_book_root(session_id, r, body)
  if book_root == "" {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": "MoonCode runtime events require book_root query, JSON field, or existing live binding",
        "metadata": { "session_id": session_id },
      },
    })
  }
  let events = mooncode_runtime_event_records(
    session_id,
    book_root,
    body,
    now=self.clock.now(),
  )
  if events.length() == 0 {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": "MoonCode runtime events payload did not contain any event object",
        "metadata": { "session_id": session_id, "book_root": book_root },
      },
    })
  }
  let binding = self.mooncode_binding_for_session(session_id)
  if binding.book_root == "" {
    binding.book_root = book_root
  }
  let mut latest_command_id = binding.last_command_id
  for event in events {
    let command_id = mooncode_json_string(event, "command_id", default="")
    if command_id != "" {
      latest_command_id = command_id
    }
    binding.events.put(event)
    self.mooncode_persist_event(binding, event)
  }
  binding.last_command_id = latest_command_id
  binding.last_updated = self.clock.now()
  self.mooncode_persist_session(binding)
  let state = self.mooncode_runtime_events_state_payload(session_id, book_root)
  w.header().set("Content-Type", "application/json")
  w.write_header(202, reason="Accepted")
  w.write(
    (
      {
        "accepted": true,
        "kind": "mooncode-runtime-events",
        "protocol": "mooncode.v1",
        "owner": "moonclaw",
        "session_id": session_id,
        "book_root": book_root,
        "event_count": events.length(),
        "events": Json::array(events),
        "state": state,
      } : Json).stringify(indent=2),
  )
}

///|
fn Daemon::mooncode_runtime_events_book_root(
  self : Daemon,
  session_id : String,
  r : @httpx.RequestReader,
  body : Json,
) -> String {
  let requested = mooncode_request_book_root(r)
  if requested != "" {
    return requested
  }
  let body_root = mooncode_json_string(body, "book_root", default="")
  if body_root != "" {
    return body_root
  }
  match self.mooncode_sessions.get(session_id) {
    Some(binding) => binding.book_root
    None => ""
  }
}

///|
async fn Daemon::mooncode_runtime_events_state_payload(
  self : Daemon,
  session_id : String,
  book_root : String,
) -> Json {
  let events_path = mooncode_events_path(book_root, session_id)
  let events = mooncode_read_jsonl(events_path)
  {
    "kind": "mooncode-runtime-events-state",
    "protocol": "mooncode.v1",
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "events_jsonl": events_path,
    "event_count": events.length(),
    "live_binding_ready": self.mooncode_sessions.get(session_id) is Some(_),
    "events": Json::array(events),
  }
}

///|
fn mooncode_runtime_event_records(
  session_id : String,
  book_root : String,
  body : Json,
  now~ : @clock.Timestamp,
) -> Array[Json] {
  let raw_events = mooncode_runtime_raw_events(body)
  let records : Array[Json] = []
  for index in 0..<raw_events.length() {
    records.push(
      mooncode_runtime_event_record(
        session_id,
        book_root,
        raw_events[index],
        index~,
        now~,
      ),
    )
  }
  records
}

///|
fn mooncode_runtime_raw_events(body : Json) -> Array[Json] {
  match body {
    Json::Object(object) =>
      match object.get("events") {
        Some(Json::Array(items)) => items
        _ => [body]
      }
    Json::Array(items) => items
    _ => []
  }
}

///|
fn mooncode_runtime_event_record(
  session_id : String,
  book_root : String,
  raw : Json,
  index~ : Int,
  now~ : @clock.Timestamp,
) -> Json {
  let raw_kind = mooncode_runtime_event_kind(raw)
  let kind = if raw_kind == "" { "runtime.event" } else { raw_kind }
  let lane = mooncode_runtime_event_lane(raw, kind)
  let command_id = mooncode_runtime_event_command_id(raw)
  let title = mooncode_runtime_event_title(raw, kind)
  let detail = mooncode_runtime_event_detail(raw, kind)
  let status = mooncode_runtime_event_status(raw, kind)
  {
    "id": mooncode_runtime_event_id(session_id, command_id, kind, index, now),
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "lane": lane,
    "kind": kind,
    "title": title,
    "status": status,
    "detail": detail,
    "created_at": now,
    "source": "moonclaw-native-runtime-events",
    "raw_event": raw,
  }
}

///|
fn mooncode_runtime_event_id(
  session_id : String,
  command_id : String,
  kind : String,
  index : Int,
  now : @clock.Timestamp,
) -> String {
  "moonclaw-\{mooncode_safe_session_id(session_id)}-\{if command_id == "" { "event" } else { command_id }}-\{kind.replace_all(old="/", new="_")}-\{index}-\{now}"
}

///|
fn mooncode_runtime_event_kind(raw : Json) -> String {
  let kind = mooncode_json_string(raw, "kind", default="")
  if kind != "" {
    return kind
  }
  let event = mooncode_json_string(raw, "event", default="")
  if event != "" {
    return event
  }
  mooncode_json_string(raw, "type", default="")
}

///|
fn mooncode_runtime_event_lane(raw : Json, kind : String) -> String {
  let lane = mooncode_json_string(raw, "lane", default="")
  if lane != "" {
    return lane
  }
  if kind.contains("assistant") || kind.contains("message") {
    "transcript"
  } else if kind.contains("tool") ||
    kind.contains("shell") ||
    kind.contains("read") ||
    kind.contains("write") ||
    kind.contains("edit") {
    "tool"
  } else if kind.contains("diff") || kind.contains("patch") {
    "diff"
  } else if kind.contains("test") || kind.contains("check") {
    "test"
  } else if kind.contains("package") ||
    kind.contains("artifact") ||
    kind.contains("finish") {
    "artifact"
  } else if kind.contains("review") ||
    kind.contains("accept") ||
    kind.contains("reject") {
    "review"
  } else {
    "runtime"
  }
}

///|
fn mooncode_runtime_event_command_id(raw : Json) -> String {
  let command_id = mooncode_json_string(raw, "command_id", default="")
  if command_id != "" {
    return command_id
  }
  let packet = mooncode_json_object_field_or_empty(raw, "command_packet")
  let packet_id = mooncode_json_string(packet, "command_id", default="")
  if packet_id != "" {
    return packet_id
  }
  let packet = mooncode_json_object_field_or_empty(raw, "packet")
  mooncode_json_string(packet, "command_id", default="")
}

///|
fn mooncode_runtime_event_title(raw : Json, kind : String) -> String {
  let title = mooncode_json_string(raw, "title", default="")
  if title != "" {
    title
  } else {
    "MoonCode runtime event `\{kind}`"
  }
}

///|
fn mooncode_runtime_event_detail(raw : Json, kind : String) -> String {
  for key in ["detail", "message", "content", "text"] {
    let value = mooncode_json_string(raw, key, default="")
    if value != "" {
      return value
    }
  }
  kind
}

///|
fn mooncode_runtime_event_status(raw : Json, kind : String) -> String {
  let status = mooncode_json_string(raw, "status", default="")
  if status != "" {
    return status
  }
  if kind.contains("delta") ||
    kind.contains("started") ||
    kind.contains("running") {
    "running"
  } else if kind.contains("failed") || kind.contains("error") {
    "failed"
  } else if kind.contains("cancel") {
    "cancelled"
  } else {
    "done"
  }
}

///|
test "mooncode runtime events normalize batch into durable lanes" {
  let records = mooncode_runtime_event_records(
    "session-demo",
    "/tmp/book",
    {
      "protocol": "mooncode.v1",
      "session_id": "session-demo",
      "book_root": "/tmp/book",
      "events": [
        {
          "kind": "assistant_delta",
          "command_id": "cmd-1",
          "content": "working",
        },
        {
          "kind": "moon_check.finished",
          "command_packet": { "command_id": "cmd-2" },
          "status": "passed",
          "detail": "27/27 tests passed",
        },
      ],
    },
    now=@clock.Timestamp::from_ms(42L),
  )
  assert_eq(records.length(), 2)
  assert_eq(mooncode_json_string(records[0], "lane", default=""), "transcript")
  assert_eq(mooncode_json_string(records[0], "status", default=""), "running")
  assert_eq(mooncode_json_string(records[0], "detail", default=""), "working")
  assert_eq(mooncode_json_string(records[1], "lane", default=""), "test")
  assert_eq(mooncode_json_string(records[1], "command_id", default=""), "cmd-2")
  assert_eq(mooncode_json_string(records[1], "status", default=""), "passed")
}

///|
test "mooncode runtime events accept single tool event payload" {
  let records = mooncode_runtime_event_records(
    "session-demo",
    "/tmp/book",
    {
      "event": "tool_result",
      "packet": { "command_id": "cmd-tool" },
      "message": "read completed",
    },
    now=@clock.Timestamp::from_ms(43L),
  )
  assert_eq(records.length(), 1)
  assert_eq(mooncode_json_string(records[0], "kind", default=""), "tool_result")
  assert_eq(mooncode_json_string(records[0], "lane", default=""), "tool")
  assert_eq(
    mooncode_json_string(records[0], "command_id", default=""),
    "cmd-tool",
  )
}
