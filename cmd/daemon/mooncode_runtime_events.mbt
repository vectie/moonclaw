///|
async fn Daemon::mooncode_runtime_events_state(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let session_id = session_id.to_owned()
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
  let session_id = session_id.to_owned()
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
        "protocol": mooncode_protocol_version(),
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
  let journal_path = mooncode_session_journal_path(book_root, session_id)
  let journal = mooncode_read_session_journal(book_root, session_id)
  let events = mooncode_journal_entries(journal, mooncode_journal_event())
  let watcher_state = mooncode_moon_check_read_state(book_root)
  let watcher_update = mooncode_moon_check_runtime_update_event(
    session_id,
    book_root,
    watcher_state,
    now=self.clock.now(),
  )
  let projected_events = events.copy()
  if watcher_update is Some(event) {
    projected_events.push(event)
  }
  {
    "kind": "mooncode-runtime-events-state",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "journal_jsonl": journal_path,
    "event_count": projected_events.length(),
    "durable_event_count": events.length(),
    "watcher_update_ready": watcher_update is Some(_),
    "moon_check_watcher": watcher_state,
    "live_binding_ready": self.mooncode_sessions.get(session_id) is Some(_),
    "events": Json::array(projected_events),
  }
}

///|
fn mooncode_moon_check_runtime_update_event(
  session_id : String,
  book_root : String,
  watcher_state : Json,
  now~ : @clock.Timestamp,
) -> Json? {
  if mooncode_json_string(watcher_state, "kind", default="") !=
    "mooncode-moon-check-watcher" {
    return None
  }
  let status = mooncode_json_string(watcher_state, "status", default="stopped")
  let event_status = if status == "running" { "running" } else { "done" }
  Some({
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-moon-check-update-\{mooncode_json_int(watcher_state, "seq", default=0)}-\{now}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command_id": "",
    "lane": "test",
    "kind": "runtime_update",
    "event": "runtime_update",
    "title": "MoonCode moon_check update",
    "status": event_status,
    "detail": mooncode_moon_check_update_text(watcher_state),
    "content": mooncode_moon_check_update_text(watcher_state),
    "created_at": now,
    "source": "moonclaw-native-moon-check-watcher",
    "moon_check_watcher": watcher_state,
  })
}

///|
fn mooncode_moon_check_update_text(watcher_state : Json) -> String {
  let output = mooncode_json_string(watcher_state, "output", default="")
  let output = if output == "" { "(no output yet)" } else { output }
  let exit = if mooncode_json_string(watcher_state, "status", default="") ==
    "running" {
    ""
  } else {
    "\nexit=\{mooncode_json_int(watcher_state, "exit_status", default=-1)}"
  }
  let truncated = if mooncode_json_bool(
      watcher_state,
      "truncated",
      default=false,
    ) {
    "\ntruncated=true\nmax_output_chars=\{mooncode_json_int(watcher_state, "max_output_chars", default=MOONCODE_DEFAULT_TOOL_OUTPUT_CHARS)}"
  } else {
    ""
  }
  let restart_count = mooncode_json_int(
    watcher_state,
    "restart_count",
    default=0,
  )
  let restart = if restart_count > 0 {
    "\nrestart_count=\{restart_count}\nrestart_limit=\{mooncode_json_int(watcher_state, "restart_limit", default=3)}"
  } else {
    ""
  }
  "[moon_check update]\nevents=1\nid=\{mooncode_json_string(watcher_state, "id", default="moon-check")}\ncwd=.\ncommand=\{mooncode_json_string(watcher_state, "command", default="moon check --watch --diagnostic-limit 10")}\nstatus=\{mooncode_json_string(watcher_state, "status", default="stopped")}\nseq=\{mooncode_json_int(watcher_state, "seq", default=0)}\{exit}\{truncated}\{restart}\n\{output}"
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
    Object(object) =>
      match object.get("events") {
        Some(Array(items)) => items
        _ => [body]
      }
    Array(items) => items
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
    "protocol": mooncode_protocol_version(),
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
      "protocol": mooncode_protocol_version(),
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

///|
test "mooncode runtime events synthesize moon_check watcher update" {
  let watcher : Json = {
    "kind": "mooncode-moon-check-watcher",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "book_root": "/tmp/book",
    "target": "",
    "key": "moon-check:/tmp/book",
    "id": "moon-check-123",
    "command": "moon check --watch --diagnostic-limit 10",
    "watcher": "reused",
    "status": "running",
    "seq": 7,
    "exit_status": 0,
    "elapsed_ms": 42,
    "restart_count": 1,
    "restart_limit": 3,
    "truncated": false,
    "max_output_chars": 12000,
    "output": "Success, waiting for filesystem changes...",
  }
  guard mooncode_moon_check_runtime_update_event(
      "session-demo",
      "/tmp/book",
      watcher,
      now=@clock.Timestamp::from_ms(77L),
    )
    is Some(event) else {
    fail("expected moon_check watcher event")
  }
  assert_eq(mooncode_json_string(event, "kind", default=""), "runtime_update")
  assert_eq(mooncode_json_string(event, "lane", default=""), "test")
  assert_eq(mooncode_json_string(event, "status", default=""), "running")
  let content = mooncode_json_string(event, "content", default="")
  assert_true(content.contains("[moon_check update]"))
  assert_true(content.contains("id=moon-check-123"))
  assert_true(content.contains("watch --diagnostic-limit 10"))
  assert_true(content.contains("restart_count=1"))
  assert_true(content.contains("Success"))
}
