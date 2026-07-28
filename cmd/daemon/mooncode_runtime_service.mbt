///|
/// Release a transferred lifecycle gate even when unlock fails or cancellation
/// is already pending.
fn mooncode_runtime_service_release_lifecycle_gate(
  lifecycle_gate : @fs.File,
) -> Unit {
  defer lifecycle_gate.close()
  lifecycle_gate.unlock()
}

///|
/// Release execution ownership before lifecycle membership, the reverse of the
/// acquisition order. Protection from cancellation is supplied by the caller.
fn mooncode_runtime_service_release_gates(
  lifecycle_gate : @fs.File,
  execution_lease : @fs.File,
) -> Unit {
  execution_lease.unlock()
  execution_lease.close()
  lifecycle_gate.unlock()
  lifecycle_gate.close()
}

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
  let response = self.mooncode_start_runtime_service(
    group~,
    session_id,
    book_root,
    body,
  )
  w.header().set("Content-Type", "application/json")
  let busy = mooncode_json_string(response, "status", default="") == "busy"
  w.write_header(
    if busy {
      409
    } else {
      202
    },
    reason=if busy { "Conflict" } else { "Accepted" },
  )
  w.write(response.stringify(indent=2))
}

///|
async fn Daemon::mooncode_start_runtime_service(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  session_id : String,
  requested_book_root : String,
  payload : Json,
) -> Json {
  let binding = self.mooncode_binding_for_session(session_id)
  if !binding.bind_book_root(requested_book_root) {
    raise json_error(409, "Conflict", {
      "error": {
        "code": -1,
        "message": "MoonCode session is bound to a different MoonBook root",
        "metadata": {
          "session_id": session_id,
          "book_root": binding.book_root,
          "requested_book_root": requested_book_root,
        },
      },
    })
  }
  let book_root = binding.book_root
  if binding.runtime_service_running {
    return {
      "kind": "mooncode-runtime-service",
      "protocol": mooncode_protocol_version(),
      "owner": "moonclaw",
      "accepted": true,
      "session_id": session_id,
      "book_root": book_root,
      "service_id": mooncode_runtime_service_id(session_id, payload),
      "status": "running",
      "started": false,
      "message": "MoonClaw native runtime service is already running for this session.",
      "started_event": null,
      "loop_options": mooncode_runtime_service_loop_payload(session_id, payload),
    }
  }
  let lifecycle_gate = mooncode_open_session_lifecycle_gate(
    book_root, session_id,
  )
  ignore(lifecycle_gate.lock(Shared)) catch {
    error => {
      @async.protect_from_cancel(
        () => lifecycle_gate.close(),
        resume_on_cancel=true,
      )
      raise error
    }
  }
  mooncode_require_active_session_state_locked(
    book_root,
    session_id,
    allow_create=true,
  ) catch {
    error => {
      @async.protect_from_cancel(
        () => mooncode_runtime_service_release_lifecycle_gate(lifecycle_gate),
        resume_on_cancel=true,
      )
      raise error
    }
  }
  let execution_lease = mooncode_open_session_execution_lease(
    book_root, session_id,
  ) catch {
    error => {
      @async.protect_from_cancel(
        () => mooncode_runtime_service_release_lifecycle_gate(lifecycle_gate),
        resume_on_cancel=true,
      )
      raise error
    }
  }
  let owns_execution = execution_lease.try_lock(Exclusive) catch {
    error => {
      execution_lease.close()
      @async.protect_from_cancel(
        () => mooncode_runtime_service_release_lifecycle_gate(lifecycle_gate),
        resume_on_cancel=true,
      )
      raise error
    }
  }
  if !owns_execution {
    let observed = mooncode_runtime_service_state_payload(
      session_id,
      book_root,
      self.mooncode_runtime_service_events(session_id, book_root),
      service_id="",
    )
    let service_running = mooncode_json_bool(observed, "running", default=false)
    execution_lease.close()
    @async.protect_from_cancel(
      () => mooncode_runtime_service_release_lifecycle_gate(lifecycle_gate),
      resume_on_cancel=true,
    )
    return {
      "kind": "mooncode-runtime-service",
      "protocol": mooncode_protocol_version(),
      "owner": "moonclaw",
      "accepted": service_running,
      "session_id": session_id,
      "book_root": book_root,
      "service_id": if service_running {
        mooncode_json_string(observed, "service_id", default="")
      } else {
        ""
      },
      "status": if service_running {
        "running"
      } else {
        "busy"
      },
      "started": false,
      "busy_reason": "execution-lease-held",
      "message": if service_running {
        "Another MoonCode runtime service already owns this session's cross-process execution lease."
      } else {
        "Another MoonCode runtime operation owns this session's cross-process execution lease."
      },
      "started_event": null,
      "loop_options": mooncode_runtime_service_loop_payload(session_id, payload),
    }
  }

  if binding.runtime_service_running {
    @async.protect_from_cancel(
      () => {
        mooncode_runtime_service_release_gates(lifecycle_gate, execution_lease)
      },
      resume_on_cancel=true,
    )
    return {
      "kind": "mooncode-runtime-service",
      "protocol": mooncode_protocol_version(),
      "owner": "moonclaw",
      "accepted": true,
      "session_id": session_id,
      "book_root": book_root,
      "service_id": mooncode_runtime_service_id(session_id, payload),
      "status": "running",
      "started": false,
      "message": "MoonClaw native runtime service is already running for this session.",
      "started_event": null,
      "loop_options": mooncode_runtime_service_loop_payload(session_id, payload),
    }
  }
  binding.runtime_service_running = true
  let started = self.mooncode_runtime_service_started_event(
    session_id, book_root, payload,
  )
  ignore(
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_event(),
      started,
    ),
  ) catch {
    error => {
      binding.runtime_service_running = false
      @async.protect_from_cancel(
        () => {
          mooncode_runtime_service_release_gates(
            lifecycle_gate, execution_lease,
          )
        },
        resume_on_cancel=true,
      )
      raise error
    }
  }
  let task = group.spawn(
    () => {
      defer {
        binding.runtime_service_running = false
        mooncode_runtime_service_release_gates(lifecycle_gate, execution_lease)
      }
      let _ = self.mooncode_runtime_service_execute_under_runtime_gates(
        session_id, book_root, payload,
      ) catch {
        error => {
          let cancelled = @async.is_being_cancelled()
          if !cancelled {
            logger.error("MoonCode runtime service failed: \{error}")
          }
          @async.protect_from_cancel(
            () => {
              if cancelled {
                self.mooncode_runtime_service_persist_cancelled(
                  session_id, book_root, payload,
                )
              } else {
                self.mooncode_runtime_service_persist_failed(
                  session_id,
                  book_root,
                  payload,
                  "\{error}",
                )
              }
            },
            resume_on_cancel=true,
          )
          Json::object({})
        }
      }
    },
    no_wait=true,
    allow_failure=true,
  )
  binding.runtime_service_task = Some(task)
  {
    "kind": "mooncode-runtime-service",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "accepted": true,
    "session_id": session_id,
    "book_root": book_root,
    "service_id": mooncode_runtime_service_id(session_id, payload),
    "status": "started",
    "started": true,
    "message": "MoonClaw native runtime service started in the daemon task group.",
    "started_event": started,
    "loop_options": mooncode_runtime_service_loop_payload(session_id, payload),
  }
}

///|
async fn Daemon::mooncode_runtime_service_events(
  self : Daemon,
  session_id : String,
  book_root : String,
) -> Array[Json] {
  ignore(self)
  let journal = mooncode_read_session_journal(book_root, session_id)
  let events = mooncode_journal_entries(journal, mooncode_journal_event())
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
    "journal_jsonl": mooncode_session_journal_path(book_root, session_id),
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
  let lifecycle_gate = mooncode_open_session_lifecycle_gate(
    book_root, session_id,
  )
  defer lifecycle_gate.close()
  lifecycle_gate.lock(Shared)
  defer lifecycle_gate.unlock()
  mooncode_require_active_session_state_locked(
    book_root,
    session_id,
    allow_create=true,
  )
  let execution_lease = mooncode_open_session_execution_lease(
    book_root, session_id,
  )
  defer execution_lease.close()
  if !execution_lease.try_lock(Exclusive) {
    return {
      "kind": "mooncode-runtime-service-result",
      "protocol": mooncode_protocol_version(),
      "owner": "moonclaw",
      "accepted": false,
      "session_id": session_id,
      "book_root": book_root,
      "service_id": mooncode_runtime_service_id(session_id, payload),
      "status": "busy",
      "busy_reason": "execution-lease-held",
    }
  }
  defer execution_lease.unlock()
  self.mooncode_runtime_service_execute_under_runtime_gates(
    session_id, book_root, payload,
  )
}

///|
async fn Daemon::mooncode_runtime_service_execute_under_runtime_gates(
  self : Daemon,
  session_id : String,
  book_root : String,
  payload : Json,
) -> Json {
  let loop_payload = mooncode_runtime_service_loop_payload(session_id, payload)
  let mut result = self.mooncode_runtime_loop_execute_with_gate_state(
    session_id,
    book_root,
    loop_payload,
    runtime_gates_held=true,
  )
  while mooncode_runtime_service_continues_goal_runtime(
          result, book_root, session_id,
        ) {
    if mooncode_json_string(result, "stopped_by", default="") == "retryable" {
      @async.sleep(mooncode_runtime_loop_poll_ms(loop_payload))
    }
    result = self.mooncode_runtime_loop_execute_with_gate_state(
      session_id,
      book_root,
      loop_payload,
      runtime_gates_held=true,
    )
  }
  let finished = self.mooncode_runtime_service_finished_event(
    session_id, book_root, payload, result,
  )
  @async.protect_from_cancel(
    () => {
      ignore(
        mooncode_append_session_journal(
          book_root,
          session_id,
          mooncode_journal_event(),
          finished,
        ),
      )
    },
    resume_on_cancel=true,
  )
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
async fn mooncode_runtime_service_continues_goal_runtime(
  result : Json,
  book_root : String,
  session_id : String,
) -> Bool {
  let stopped_by = mooncode_json_string(result, "stopped_by", default="")
  if stopped_by != "max_turns" && stopped_by != "retryable" {
    return false
  }
  let turns = mooncode_json_array_items(result, "turns")
  if turns.length() > 0 {
    let execution = mooncode_json_object_field_or_empty(
      turns[turns.length() - 1],
      "execution",
    )
    if mooncode_json_bool(execution, "paused", default=false) {
      return false
    }
  }
  mooncode_goal_runtime_supervisor_is_active(book_root, session_id)
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
async fn Daemon::mooncode_runtime_service_persist_cancelled(
  self : Daemon,
  session_id : String,
  book_root : String,
  payload : Json,
) -> Unit {
  let result : Json = {
    "kind": "mooncode-runtime-loop",
    "accepted": false,
    "ran_turn_count": 0,
    "failed_turn_count": 0,
    "stopped_by": "cancelled",
    "message": "MoonClaw native runtime service was cancelled.",
  }
  let finished = self.mooncode_runtime_service_finished_event(
    session_id, book_root, payload, result,
  )
  ignore(
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_event(),
      finished,
    ),
  )
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
  ignore(
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_event(),
      mooncode_runtime_service_attach(event, book_root, payload),
    ),
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
      "approval" => "waiting"
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
  ignore(
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_command(),
      {
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
          "model": "codex/gpt-5.6-sol",
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
      },
    ),
  )
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
  ignore(
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_event(),
      started,
    ),
  )
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
  let events = @fsx.read_file(
    mooncode_session_journal_path(book_root, session_id),
  )
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
  ignore(
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_event(),
      started,
    ),
  )
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
  ignore(
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_event(),
      finished,
    ),
  )
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

///|
async test "mooncode runtime service gates started and persists cancellation before release" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-service-cancel-XXXXXX"),
  )
  let session_id = "session-service-cancel"
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
  let lifecycle_gate = mooncode_open_session_lifecycle_gate(
    book_root, session_id,
  )
  lifecycle_gate.lock(Exclusive)
  @async.with_task_group(group => {
    let releaser = group.spawn(() => {
      @async.sleep(25)
      assert_false(
        @fsx.exists(mooncode_session_journal_path(book_root, session_id)),
      )
      lifecycle_gate.unlock()
      lifecycle_gate.close()
    })
    let response = daemon.mooncode_start_runtime_service(
      group~,
      session_id,
      book_root,
      {
        "service_id": "service-cancel",
        "max_turns": 1,
        "live_wait_ms": 5000,
        "poll_ms": 25,
      },
    )
    releaser.wait()
    assert_true(mooncode_json_bool(response, "started", default=false))
    let binding = daemon.mooncode_binding_for_session(session_id)
    assert_true(binding.runtime_service_running)
    @async.sleep(25)
    match binding.runtime_service_task {
      Some(task) => {
        task.cancel()
        let _ = task.wait() catch { _ => () }
      }
      None => abort("runtime service task missing")
    }
    assert_false(binding.runtime_service_running)
    let events = daemon.mooncode_runtime_service_events(session_id, book_root)
    assert_eq(events.length(), 2)
    let terminal = events[events.length() - 1]
    assert_eq(
      mooncode_json_string(terminal, "kind", default=""),
      "runtime.service_finished",
    )
    assert_eq(mooncode_json_string(terminal, "status", default=""), "cancelled")
    let exclusive_gate = mooncode_open_session_lifecycle_gate(
      book_root, session_id,
    )
    exclusive_gate.lock(Exclusive)
    exclusive_gate.unlock()
    exclusive_gate.close()
  })
}

///|
async test "mooncode runtime service holds lifecycle gate through terminal persistence" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-service-gate-XXXXXX"),
  )
  let session_id = "session-service-gate"
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
  @async.with_task_group(group => {
    let response = daemon.mooncode_start_runtime_service(
      group~,
      session_id,
      book_root,
      {
        "service_id": "service-gate",
        "max_turns": 1,
        "live_wait_ms": 200,
        "poll_ms": 25,
      },
    )
    assert_true(mooncode_json_bool(response, "started", default=false))
    let binding = daemon.mooncode_binding_for_session(session_id)
    assert_true(binding.runtime_service_running)
    let exclusive_gate = mooncode_open_session_lifecycle_gate(
      book_root, session_id,
    )
    let exclusive = group.spawn(() => {
      exclusive_gate.lock(Exclusive)
      let journal = @fsx.read_file(
        mooncode_session_journal_path(book_root, session_id),
      )
      assert_true(journal.contains("runtime.service_finished"))
      exclusive_gate.unlock()
      exclusive_gate.close()
      true
    })
    @async.sleep(25)
    assert_true(exclusive.try_wait() is None)
    let mut attempts = 0
    while binding.runtime_service_running && attempts < 40 {
      @async.sleep(25)
      attempts += 1
    }
    assert_false(binding.runtime_service_running)
    assert_true(exclusive.wait())
  })
}

///|
async test "mooncode runtime service is single-flight per session" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-service-single-flight-XXXXXX"),
  )
  let session_id = "session-service-single-flight"
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
  let binding = daemon.mooncode_binding_for_session(session_id)
  assert_true(binding.bind_book_root(book_root))
  binding.runtime_service_running = true
  @async.with_task_group(group => {
    let response = daemon.mooncode_start_runtime_service(
      group~,
      session_id,
      book_root,
      { "service_id": "service-reused" },
    )
    assert_eq(mooncode_json_string(response, "status", default=""), "running")
    assert_false(mooncode_json_bool(response, "started", default=true))
    assert_true(binding.runtime_service_running)
  })
  assert_false(
    @fsx.exists(mooncode_session_journal_path(book_root, session_id)),
  )
}
