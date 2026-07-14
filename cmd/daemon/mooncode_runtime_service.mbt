///|
async fn Daemon::mooncode_runtime_service_state(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let session_id = session_id.to_owned()
  let book_root = mooncode_request_book_root(r)
  if book_root == "" {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": "MoonCode runtime service state requires book_root query",
        "metadata": { "session_id": session_id },
      },
    })
  }
  let events = self.mooncode_runtime_service_events(session_id, book_root)
  let service_id = mooncode_request_string(r, "service_id", default="")
  let state = mooncode_runtime_service_state_payload(
    session_id,
    book_root,
    events,
    service_id~,
  )
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(state.stringify(indent=2))
}

///|
async fn Daemon::mooncode_runtime_service(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
  let body : Json = reader.read() catch { _ => Json::object({}) }
  let session_id = session_id.to_owned()
  let requested_book_root = mooncode_request_book_root(r)
  let book_root = if requested_book_root == "" {
    mooncode_json_string(body, "book_root", default="")
  } else {
    requested_book_root
  }
  if book_root == "" {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": "MoonCode runtime service requires book_root query or JSON field",
        "metadata": { "session_id": session_id },
      },
    })
  }
  let binding = self.mooncode_binding_for_session(session_id)
  if !binding.bind_book_root(book_root) {
    raise json_error(409, "Conflict", {
      "error": {
        "code": -1,
        "message": "MoonCode session is bound to a different MoonBook root",
        "metadata": {
          "session_id": session_id,
          "book_root": binding.book_root,
          "requested_book_root": book_root,
        },
      },
    })
  }
  let book_root = binding.book_root
  let started = self.mooncode_runtime_service_started_event(
    session_id, book_root, body,
  )
  mooncode_append_jsonl(mooncode_events_path(book_root, session_id), started)
  group.spawn_bg(
    () => {
      let _ = self.mooncode_runtime_service_execute(session_id, book_root, body) catch {
        error => {
          logger.error("MoonCode runtime service failed: \{error}")
          self.mooncode_runtime_service_persist_failed(
            session_id,
            book_root,
            body,
            "\{error}",
          )
          Json::object({})
        }
      }
    },
    no_wait=true,
  )
  w.header().set("Content-Type", "application/json")
  w.write_header(202, reason="Accepted")
  w.write(
    (
      {
        "kind": "mooncode-runtime-service",
        "protocol": mooncode_protocol_version(),
        "owner": "moonclaw",
        "accepted": true,
        "session_id": session_id,
        "book_root": book_root,
        "service_id": mooncode_runtime_service_id(session_id, body),
        "status": "started",
        "message": "MoonClaw native runtime service started in the daemon task group.",
        "started_event": started,
        "loop_options": mooncode_runtime_service_loop_payload(session_id, body),
      } : Json).stringify(indent=2),
  )
}

///|
async fn Daemon::mooncode_runtime_service_events(
  self : Daemon,
  session_id : String,
  book_root : String,
) -> Array[Json] {
  ignore(self)
  let events = mooncode_read_jsonl(mooncode_events_path(book_root, session_id))
  let result : Array[Json] = []
  for event in events {
    let kind = mooncode_json_string(event, "kind", default="")
    if kind == "runtime.service_started" ||
      kind == "runtime.service_finished" ||
      kind == "runtime.service_failed" {
      result.push(event)
    }
  }
  result
}

///|
fn mooncode_runtime_service_state_payload(
  session_id : String,
  book_root : String,
  events : Array[Json],
  service_id~ : String,
) -> Json {
  let filtered : Array[Json] = []
  for event in events {
    if service_id == "" ||
      mooncode_json_string(event, "service_id", default="") == service_id {
      filtered.push(event)
    }
  }
  let latest = if filtered.length() > 0 {
    filtered[filtered.length() - 1]
  } else {
    Json::object({})
  }
  let latest_kind = mooncode_json_string(latest, "kind", default="")
  let status = if filtered.length() == 0 {
    "idle"
  } else if latest_kind == "runtime.service_started" {
    "running"
  } else {
    mooncode_json_string(latest, "status", default="unknown")
  }
  {
    "kind": "mooncode-runtime-service-state",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "service_id": if service_id != "" {
      service_id
    } else {
      mooncode_json_string(latest, "service_id", default="")
    },
    "status": status,
    "running": status == "running",
    "event_count": filtered.length(),
    "events_jsonl": mooncode_events_path(book_root, session_id),
    "latest_event": latest,
    "events": Json::array(filtered),
  }
}

///|
async fn Daemon::mooncode_runtime_service_execute(
  self : Daemon,
  session_id : String,
  book_root : String,
  payload : Json,
) -> Json {
  let loop_payload = mooncode_runtime_service_loop_payload(session_id, payload)
  let result = self.mooncode_runtime_loop_execute(
    session_id, book_root, loop_payload,
  )
  let finished = self.mooncode_runtime_service_finished_event(
    session_id, book_root, payload, result,
  )
  mooncode_append_jsonl(mooncode_events_path(book_root, session_id), finished)
  {
    "kind": "mooncode-runtime-service-result",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "accepted": mooncode_json_bool(result, "accepted", default=false),
    "session_id": session_id,
    "book_root": book_root,
    "service_id": mooncode_runtime_service_id(session_id, payload),
    "status": mooncode_json_string(finished, "status", default="done"),
    "runtime_loop": result,
    "finished_event": finished,
  }
}

///|
fn Daemon::mooncode_runtime_service_started_event(
  self : Daemon,
  session_id : String,
  book_root : String,
  payload : Json,
) -> Json {
  let now = self.clock.now()
  let service_id = mooncode_runtime_service_id(session_id, payload)
  let event = mooncode_event(
    session_id~,
    command_id=service_id,
    lane="runtime",
    kind="runtime.service_started",
    title="Runtime service started",
    status="running",
    detail="MoonClaw native runtime service is supervising queued MoonCode commands.",
    now~,
  )
  mooncode_runtime_service_attach(event, book_root, payload)
}

///|
fn Daemon::mooncode_runtime_service_finished_event(
  self : Daemon,
  session_id : String,
  book_root : String,
  payload : Json,
  result : Json,
) -> Json {
  let now = self.clock.now()
  let status = mooncode_runtime_service_status(result)
  let service_id = mooncode_runtime_service_id(session_id, payload)
  let event = mooncode_event(
    session_id~,
    command_id=service_id,
    lane="runtime",
    kind="runtime.service_finished",
    title="Runtime service finished",
    status~,
    detail=mooncode_json_string(
      result,
      "message",
      default="MoonClaw native runtime service finished.",
    ),
    now~,
  )
  mooncode_runtime_service_finish_event(event, book_root, payload, result)
}

///|
async fn Daemon::mooncode_runtime_service_persist_failed(
  self : Daemon,
  session_id : String,
  book_root : String,
  payload : Json,
  error : String,
) -> Unit {
  let now = self.clock.now()
  let service_id = mooncode_runtime_service_id(session_id, payload)
  let event = mooncode_event(
    session_id~,
    command_id=service_id,
    lane="runtime",
    kind="runtime.service_failed",
    title="Runtime service failed",
    status="failed",
    detail=error,
    now~,
  )
  mooncode_append_jsonl(
    mooncode_events_path(book_root, session_id),
    mooncode_runtime_service_attach(event, book_root, payload),
  )
}

///|
fn mooncode_runtime_service_attach(
  event : Json,
  book_root : String,
  payload : Json,
) -> Json {
  let session_id = mooncode_json_string(event, "session_id", default="")
  let loop_payload = mooncode_runtime_service_loop_payload(session_id, payload)
  let object : Map[String, Json] = {
    "id": mooncode_json_string(event, "id", default=""),
    "protocol": mooncode_json_string(event, "protocol", default=""),
    "session_id": session_id,
    "command_id": mooncode_json_string(event, "command_id", default=""),
    "lane": mooncode_json_string(event, "lane", default="runtime"),
    "kind": mooncode_json_string(event, "kind", default=""),
    "title": mooncode_json_string(event, "title", default="Runtime service"),
    "status": mooncode_json_string(event, "status", default="running"),
    "detail": mooncode_json_string(event, "detail", default=""),
    "source": mooncode_json_string(
      event,
      "source",
      default="moonclaw-native-mooncode",
    ),
    "book_root": book_root,
    "service_id": mooncode_runtime_service_id(session_id, payload),
    "runtime_service": true,
    "consumer_id": mooncode_runtime_service_consumer_id(payload),
    "max_turns": mooncode_runtime_loop_max_turns(loop_payload),
    "live_wait_ms": mooncode_runtime_loop_live_wait_ms(loop_payload),
    "poll_ms": mooncode_runtime_loop_poll_ms(loop_payload),
  }
  match event {
    Object(event_object) =>
      match event_object.get("created_at") {
        Some(value) => object["created_at"] = value
        None => ()
      }
    _ => ()
  }
  Json::object(object)
}

///|
fn mooncode_runtime_service_finish_event(
  event : Json,
  book_root : String,
  payload : Json,
  result : Json,
) -> Json {
  let base = mooncode_runtime_service_attach(event, book_root, payload)
  match base {
    Object(object) => {
      object["ran_turn_count"] = mooncode_json_int(
        result,
        "ran_turn_count",
        default=0,
      ).to_json()
      object["failed_turn_count"] = mooncode_json_int(
        result,
        "failed_turn_count",
        default=0,
      ).to_json()
      object["stopped_by"] = mooncode_json_string(
        result,
        "stopped_by",
        default="",
      ).to_json()
      Json::object(object)
    }
    _ => base
  }
}

///|
fn mooncode_runtime_service_loop_payload(
  session_id : String,
  payload : Json,
) -> Json {
  {
    "consumer_id": mooncode_runtime_service_consumer_id(payload),
    "max_turns": mooncode_runtime_loop_max_turns(payload),
    "live_wait_ms": mooncode_runtime_service_live_wait_ms(payload),
    "poll_ms": mooncode_runtime_loop_poll_ms(payload),
    "runtime_service": true,
    "service_id": mooncode_runtime_service_id(session_id, payload),
  }
}

///|
fn mooncode_runtime_service_consumer_id(payload : Json) -> String {
  mooncode_json_string(
    payload,
    "consumer_id",
    default="moonclaw-native-runtime-service",
  )
}

///|
fn mooncode_runtime_service_live_wait_ms(payload : Json) -> Int {
  let requested = mooncode_json_int(payload, "live_wait_ms", default=5000)
  if requested < 0 {
    0
  } else if requested > 30000 {
    30000
  } else {
    requested
  }
}

///|
fn mooncode_runtime_service_id(session_id : String, payload : Json) -> String {
  let explicit = mooncode_json_string(payload, "service_id", default="")
  if explicit != "" {
    explicit
  } else {
    "mooncode-service-\{session_id}"
  }
}

///|
fn mooncode_runtime_service_status(result : Json) -> String {
  if mooncode_json_int(result, "failed_turn_count", default=0) > 0 {
    "failed"
  } else {
    match mooncode_json_string(result, "stopped_by", default="") {
      "cancelled" => "cancelled"
      _ => "done"
    }
  }
}

///|
async test "mooncode runtime service records lifecycle events" (t : @test.Test) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-service-XXXXXX"),
  )
  let session_id = "session-runtime-service"
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": "cmd-service-1",
    "created_at": @clock.Timestamp::from_ms(10L),
    "command": {
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command": "prompt",
      "packet": { "command_id": "cmd-service-1" },
      "runtime_tool_calls": [
        {
          "tool": "write",
          "arguments": {
            "path": "tools/service-proof/one.txt",
            "content": "service",
          },
        },
        { "tool": "finish", "arguments": { "answer": "service done" } },
      ],
    },
  })
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @spawn.Manager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
    exec_path: @pathx.join(book_root, "moonclaw"),
    httpx: @httpx.Server::new("[::1]", 0, reuse_addr=true),
    port: 0,
    events: @broadcast.Broadcast::new(),
    serve: book_root,
    conversations: @conversation.Manager::new(
      home=book_root,
      uuid=@uuid.generator(@rand.chacha8()),
    ),
    home: book_root,
    pending_codex_auth: {},
    mooncode_sessions: {},
  }
  let started = daemon.mooncode_runtime_service_started_event(
    session_id,
    book_root,
    { "service_id": "svc-test", "max_turns": 2, "live_wait_ms": 0 },
  )
  mooncode_append_jsonl(mooncode_events_path(book_root, session_id), started)
  let result = daemon.mooncode_runtime_service_execute(session_id, book_root, {
    "service_id": "svc-test",
    "max_turns": 2,
    "live_wait_ms": 0,
  })
  assert_true(mooncode_json_bool(result, "accepted", default=false))
  assert_eq(mooncode_json_string(result, "status", default=""), "done")
  assert_true(
    @fsx.exists(@pathx.join(book_root, "tools/service-proof/one.txt")),
  )
  let events = @fsx.read_file(mooncode_events_path(book_root, session_id))
  assert_true(events.contains("runtime.service_started"))
  assert_true(events.contains("runtime.service_finished"))
  assert_true(events.contains("svc-test"))
}

///|
async test "mooncode runtime service state projects latest lifecycle event" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-service-state-XXXXXX"),
  )
  let session_id = "session-runtime-service-state"
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @spawn.Manager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
    exec_path: @pathx.join(book_root, "moonclaw"),
    httpx: @httpx.Server::new("[::1]", 0, reuse_addr=true),
    port: 0,
    events: @broadcast.Broadcast::new(),
    serve: book_root,
    conversations: @conversation.Manager::new(
      home=book_root,
      uuid=@uuid.generator(@rand.chacha8()),
    ),
    home: book_root,
    pending_codex_auth: {},
    mooncode_sessions: {},
  }
  let idle = mooncode_runtime_service_state_payload(
    session_id,
    book_root,
    [],
    service_id="svc-state",
  )
  assert_eq(mooncode_json_string(idle, "status", default=""), "idle")
  assert_false(mooncode_json_bool(idle, "running", default=true))
  let started = daemon.mooncode_runtime_service_started_event(
    session_id,
    book_root,
    { "service_id": "svc-state", "max_turns": 1, "live_wait_ms": 0 },
  )
  mooncode_append_jsonl(mooncode_events_path(book_root, session_id), started)
  let running = mooncode_runtime_service_state_payload(
    session_id,
    book_root,
    daemon.mooncode_runtime_service_events(session_id, book_root),
    service_id="svc-state",
  )
  assert_eq(mooncode_json_string(running, "status", default=""), "running")
  assert_true(mooncode_json_bool(running, "running", default=false))
  let finished = daemon.mooncode_runtime_service_finished_event(
    session_id,
    book_root,
    { "service_id": "svc-state", "max_turns": 1, "live_wait_ms": 0 },
    {
      "kind": "mooncode-runtime-loop",
      "accepted": true,
      "ran_turn_count": 0,
      "failed_turn_count": 0,
      "stopped_by": "idle",
      "message": "idle",
    },
  )
  assert_false(finished.stringify().contains("\"runtime_loop\""))
  assert_true(finished.stringify().length() < 2048)
  mooncode_append_jsonl(mooncode_events_path(book_root, session_id), finished)
  let done = mooncode_runtime_service_state_payload(
    session_id,
    book_root,
    daemon.mooncode_runtime_service_events(session_id, book_root),
    service_id="svc-state",
  )
  assert_eq(mooncode_json_string(done, "status", default=""), "done")
  assert_false(mooncode_json_bool(done, "running", default=true))
  assert_eq(mooncode_json_int(done, "event_count", default=0), 2)
}
