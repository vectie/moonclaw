///|
const TASK_STREAM_CONTRACT : String = "moonclaw-task-stream.v2"

///|
const TASK_STREAM_START_CURSOR : String = "start"

///|
const TASK_STREAM_DEFAULT_REPLAY_EVENTS : Int = 128

///|
const TASK_STREAM_MAX_REPLAY_EVENTS : Int = 512

///|
const TASK_STREAM_CURSOR_MAX_CHARS : Int = 256

///|
const TASK_STREAM_CONTENT_MAX_BYTES : Int = 200000

///|
let task_stream_cursor_secrets : Map[String, String] = Map([])

///|
fn task_stream_install_cursor_secret(home : String, secret : String) -> Unit {
  task_stream_cursor_secrets[home] = secret
}

///|
fn Daemon::task_stream_cursor_secret(self : Daemon) -> String {
  task_stream_cursor_secrets
  .get(self.home)
  .unwrap_or_else(() => {
    // Directly constructed white-box fixtures do not pass through
    // `Daemon::new`. They never expose an HTTP stream, but a deterministic
    // fallback keeps those fixture records source-compatible.
    mooncode_goal_runtime_sha256_hex(TASK_STREAM_CONTRACT + "\n" + self.home)
  })
}

///|
fn task_stream_constant_time_equal(left : String, right : String) -> Bool {
  let left = @encoding/utf8.encode(left)
  let right = @encoding/utf8.encode(right)
  if left.length() != right.length() {
    return false
  }
  let mut difference = 0
  for index in 0..<left.length() {
    difference = difference | (left[index].to_int() ^ right[index].to_int())
  }
  difference == 0
}

///|
fn Daemon::task_stream_cursor_mac(
  self : Daemon,
  task_id : String,
  raw_sequence : Int,
) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @encoding/utf8.encode(self.task_stream_cursor_secret()),
      @encoding/utf8.encode(
        TASK_STREAM_CONTRACT + "\n" + task_id + "\n" + raw_sequence.to_string(),
      ),
    ),
  )
}

///|
fn Daemon::task_stream_cursor(
  self : Daemon,
  task_id : String,
  raw_sequence : Int,
) -> String {
  "mct2." +
  raw_sequence.to_string() +
  "." +
  self.task_stream_cursor_mac(task_id, raw_sequence)
}

///|
fn Daemon::task_stream_parse_cursor(
  self : Daemon,
  task_id : String,
  cursor : String,
) -> Int? {
  if cursor == TASK_STREAM_START_CURSOR {
    return Some(0)
  }
  if cursor == "" || cursor.length() > TASK_STREAM_CURSOR_MAX_CHARS {
    return None
  }
  let parts = cursor.split(".").to_array()
  guard parts.length() == 3 && parts[0] == "mct2" else { return None }
  let sequence = @string.parse_int(parts[1]) catch { _ => return None }
  if sequence < 0 {
    return None
  }
  let expected = self.task_stream_cursor_mac(task_id, sequence)
  if !task_stream_constant_time_equal(parts[2].to_owned(), expected) {
    return None
  }
  Some(sequence)
}

///|
fn task_stream_content(text : String) -> String {
  if @encoding/utf8.encode(text).length() <= TASK_STREAM_CONTENT_MAX_BYTES {
    text
  } else {
    mooncode_utf8_prefix_within(text, TASK_STREAM_CONTENT_MAX_BYTES) +
    "\n...[answer projection truncated by moonclaw-task-stream.v2 policy]"
  }
}

///|
fn task_stream_project(event : @server.ServerStreamEvent) -> Json? {
  guard event is Moonclaw(event) else { return None }
  guard event.to_json() is { "created": created, "desc": Object(desc), .. } else {
    return None
  }
  match desc.get("msg") {
    Some(String("PreConversation")) =>
      Some({
        "contract": TASK_STREAM_CONTRACT,
        "kind": "lifecycle",
        "state": "working",
        "created": created,
      })
    Some(String("AssistantMessageDelta")) =>
      match desc.get("content") {
        Some(String(content)) =>
          Some({
            "contract": TASK_STREAM_CONTRACT,
            "kind": "answer_delta",
            "content": task_stream_content(content),
            "created": created,
          })
        _ => None
      }
    Some(String("AssistantMessage")) =>
      match desc.get("content") {
        Some(String(content)) =>
          Some({
            "contract": TASK_STREAM_CONTRACT,
            "kind": "answer",
            "content": task_stream_content(content),
            "created": created,
          })
        _ => None
      }
    Some(String("PostConversation")) =>
      Some({
        "contract": TASK_STREAM_CONTRACT,
        "kind": "terminal",
        "state": "complete",
        "created": created,
      })
    Some(String("Cancelled")) =>
      Some({
        "contract": TASK_STREAM_CONTRACT,
        "kind": "terminal",
        "state": "cancelled",
        "created": created,
      })
    Some(String("Failed")) =>
      Some({
        "contract": TASK_STREAM_CONTRACT,
        "kind": "warning",
        "state": "failed",
        "message": "The general agent could not complete this turn. You can retry without losing the document context.",
        "created": created,
      })
    _ => None
  }
}

///|
fn task_stream_latest_snapshot(
  values : ArrayView[@server.ServerStreamEvent],
) -> Json {
  let mut answer = ""
  let mut state = "idle"
  for event in values {
    match task_stream_project(event) {
      Some({ "kind": "answer", "content": String(content), .. }) => {
        answer = content
        state = "working"
      }
      Some({ "kind": "lifecycle", "state": String(next), .. }) => state = next
      Some({ "kind": "terminal", "state": String(next), .. }) => state = next
      Some({ "kind": "warning", .. }) => state = "failed"
      _ => ()
    }
  }
  {
    "contract": TASK_STREAM_CONTRACT,
    "kind": "snapshot",
    "answer": answer,
    "state": state,
  }
}

///|
async fn Daemon::task_stream_write(
  self : Daemon,
  writer : @httpx.EventStreamWriter,
  task_id : String,
  raw_sequence : Int,
  event : Json,
) -> Unit {
  let cursor = self.task_stream_cursor(task_id, raw_sequence)
  let payload : Json = match event {
    Object(fields) => {
      let copy = fields.copy()
      copy["cursor"] = cursor.to_json()
      Json::object(copy)
    }
    _ => event
  }
  writer.write_event(id=cursor, event=TASK_STREAM_CONTRACT, data=payload)
}

///|
async fn Daemon::task_stream_resume(
  self : Daemon,
  task_id~ : String,
  broadcast~ : @broadcast.Broadcast[@server.ServerStreamEvent],
  live~ : Bool,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let requested_cursor = mooncode_request_string(
    r,
    "cursor",
    default=TASK_STREAM_START_CURSOR,
  )
  let requested_limit = mooncode_request_int(
    r,
    "replay_limit",
    default=TASK_STREAM_DEFAULT_REPLAY_EVENTS,
  )
  let replay_limit = if requested_limit <= 0 {
    TASK_STREAM_DEFAULT_REPLAY_EVENTS
  } else {
    requested_limit.min(TASK_STREAM_MAX_REPLAY_EVENTS)
  }
  let values = broadcast.values()
  let head = values.length()
  let parsed = self.task_stream_parse_cursor(task_id, requested_cursor)
  let mut boundary = parsed.unwrap_or(head)
  let mut recovery = if parsed is None { "invalid_cursor" } else { "" }
  if boundary > head {
    boundary = head
    recovery = "future_cursor"
  }
  let writer = @httpx.EventStreamWriter::new(w)
  writer.write_header(200)
  let meta : Json = {
    "contract": TASK_STREAM_CONTRACT,
    "kind": "meta",
    "cursor": self.task_stream_cursor(task_id, boundary),
    "replay_limit": replay_limit,
    "live": live,
  }
  writer.write_event(
    id=self.task_stream_cursor(task_id, boundary),
    event=TASK_STREAM_CONTRACT,
    data=meta,
  )
  let mut visible = 0
  if recovery == "" {
    for index = boundary; index < head; index = index + 1 {
      if task_stream_project(values[index]) is Some(_) {
        visible += 1
      }
    }
  }
  if recovery != "" || visible > replay_limit {
    let snapshot = task_stream_latest_snapshot(values)
    let snapshot : Json = match snapshot {
      Object(fields) => {
        let copy = fields.copy()
        copy["recovery"] = (if recovery == "" {
          "replay_limit"
        } else {
          recovery
        }).to_json()
        Json::object(copy)
      }
      _ => snapshot
    }
    self.task_stream_write(writer, task_id, head, snapshot)
    boundary = head
  } else {
    for index = boundary; index < head; index = index + 1 {
      if task_stream_project(values[index]) is Some(projected) {
        self.task_stream_write(writer, task_id, index + 1, projected)
      }
    }
    boundary = head
  }
  if !live {
    return
  }
  let mut live_sequence = boundary
  broadcast.listen_from(boundary, event => {
    live_sequence += 1
    if task_stream_project(event) is Some(projected) {
      self.task_stream_write(writer, task_id, live_sequence, projected)
    }
  })
}
