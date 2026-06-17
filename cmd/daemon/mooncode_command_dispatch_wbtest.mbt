///|
test "mooncode validates native command body" {
  let body : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-demo",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Build a miniapp",
    "packet": { "command_id": "cmd-1" },
  }
  let report = mooncode_validate_command_body("session-demo", body)
  assert_true(mooncode_json_bool(report, "ok", default=false))
  assert_eq(mooncode_json_string(report, "command_id", default=""), "cmd-1")
}

///|
test "mooncode validation reports mismatched session and missing command id" {
  let body : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "other",
    "book_root": "/tmp/book",
    "packet": {},
  }
  let report = mooncode_validate_command_body("session-demo", body)
  assert_false(mooncode_json_bool(report, "ok", default=true))
  let payload = report.stringify()
  assert_true(payload.contains("session_id"))
  assert_true(payload.contains("command_id"))
}

///|
test "mooncode native controls classify prompt steer and cancel" {
  assert_eq(mooncode_command_control("prompt"), "prompt")
  assert_eq(mooncode_command_control("run_tests"), "prompt")
  assert_eq(mooncode_command_control("steer"), "steer")
  assert_eq(mooncode_command_control("cancel"), "cancel")
  assert_eq(mooncode_accept_event_kind("prompt"), "command.accepted")
  assert_eq(mooncode_accept_event_kind("steer"), "steer.accepted")
  assert_eq(
    mooncode_accept_event_title("steer"),
    "MoonClaw accepted MoonCode steering",
  )
}

///|
async test "mooncode queue-only command persists durable command without task" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-queue-only-XXXXXX"),
  )
  let session_id = "session-queue-only"
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
  let response = daemon.mooncode_queue_command_response(
    session_id~,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command": "run_tests",
      "web_search": true,
      "native_dispatch_mode": "queue-only",
      "packet": { "command_id": "cmd-queue-only" },
    },
    dispatch_source="test-queue-only",
  )
  assert_true(mooncode_json_bool(response, "accepted", default=false))
  assert_eq(
    mooncode_json_string(response, "native_dispatch_mode", default=""),
    "queue-only",
  )
  assert_true(
    response
    .stringify()
    .contains("\"task_id\":\"00000000-0000-0000-0000-000000000000\""),
  )
  let command_log = @fsx.read_file(
    mooncode_commands_path(book_root, session_id),
  )
  assert_true(command_log.contains("\"cmd-queue-only\""))
  assert_true(command_log.contains("\"native_dispatch_mode\":\"queue-only\""))
  assert_true(command_log.contains("\"web_search\":true"))
  let events_log = @fsx.read_file(mooncode_events_path(book_root, session_id))
  assert_true(events_log.contains("\"command.queued_for_runtime_turn\""))
}
