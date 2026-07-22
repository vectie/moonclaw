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
test "mooncode validation rejects unsupported command fields" {
  let body : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-demo",
    "book_root": "/tmp/book",
    "command": "prompt",
    "extra_mode": "invalid",
    "packet": { "command_id": "cmd-1" },
  }
  let report = mooncode_validate_command_body("session-demo", body)
  assert_false(mooncode_json_bool(report, "ok", default=true))
  let payload = report.stringify()
  assert_true(payload.contains("unsupported"))
  assert_true(payload.contains("extra_mode"))
}

///|
test "mooncode native controls classify prompt steer and cancel" {
  assert_eq(mooncode_command_control("prompt"), "prompt")
  assert_eq(mooncode_command_control("run_tests"), "prompt")
  assert_eq(mooncode_command_control("steer"), "steer")
  assert_eq(mooncode_command_control("cancel"), "cancel")
}

///|
async test "MoonCode rejects missing and stale models before explicit tools can queue" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-model-reject-XXXXXX"),
  )
  let session_id = "session-model-reject"
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
  let commands : Array[Json] = [
    {
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command": "prompt",
      "text": "Missing model must not run explicit tools",
      "packet": { "command_id": "cmd-model-missing" },
      "runtime_tool_calls": [
        {
          "tool": "write",
          "arguments": { "path": "missing-model.txt", "content": "bad" },
        },
      ],
    },
    {
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command": "prompt",
      "model": "moongate/not-configured",
      "text": "Unavailable provider model must not run explicit tools",
      "packet": { "command_id": "cmd-model-stale" },
      "runtime_tool_calls": [
        {
          "tool": "write",
          "arguments": { "path": "stale-model.txt", "content": "bad" },
        },
      ],
    },
  ]
  for command in commands {
    let rejected = try {
      ignore(
        daemon.mooncode_queue_command_response(
          session_id~,
          command,
          queue_source="test-exact-model-rejection",
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let binding = daemon.mooncode_binding_for_session(session_id)
  assert_eq(binding.command_count, 0)
  assert_eq(binding.model, "")
  assert_false(
    @fsx.exists(mooncode_session_journal_path(book_root, session_id)),
  )
  assert_false(@fsx.exists(@pathx.join(book_root, "missing-model.txt")))
  assert_false(@fsx.exists(@pathx.join(book_root, "stale-model.txt")))
}

///|
async test "mooncode command persists durable native queue entry without task" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-native-queue-XXXXXX"),
  )
  let session_id = "session-native-queue"
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
      "model": "codex/gpt-5.6-sol",
      "web_search": true,
      "packet": { "command_id": "cmd-native-queue" },
    },
    queue_source="test-native-queue",
  )
  assert_true(mooncode_json_bool(response, "accepted", default=false))
  assert_true(mooncode_json_bool(response, "queued", default=false))
  assert_false(response.stringify().contains("\"task_id\""))
  let command_log = @fsx.read_file(
    mooncode_session_journal_path(book_root, session_id),
  )
  assert_true(command_log.contains("\"cmd-native-queue\""))
  assert_true(command_log.contains("\"web_search\":true"))
  let events_log = @fsx.read_file(
    mooncode_session_journal_path(book_root, session_id),
  )
  assert_true(events_log.contains("\"command.queued_for_runtime_turn\""))
}

///|
async test "MoonCode persists and reloads the provider model selector" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-model-persist-XXXXXX"),
  )
  let session_id = "session-model-persist"
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
  ignore(
    daemon.mooncode_queue_command_response(
      session_id~,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "book_root": book_root,
        "command": "prompt",
        "text": "Inspect the project structure",
        "model": "codex/gpt-5.6-sol",
        "payload": {
          "model": "codex/gpt-5.6-sol",
          "planner_model": "codex/gpt-5.6-sol",
        },
        "packet": { "command_id": "cmd-model-persist" },
      },
      queue_source="test-model-persist",
    ),
  )
  let journal = mooncode_read_session_journal(book_root, session_id)
  let commands = mooncode_journal_entries(journal, mooncode_journal_command())
  assert_eq(commands.length(), 1)
  let persisted = mooncode_json_object_field_or_empty(commands[0], "command")
  assert_eq(
    mooncode_runtime_turn_requested_model(persisted),
    "codex/gpt-5.6-sol",
  )
  let persisted_payload = mooncode_json_object_field_or_empty(
    persisted, "payload",
  )
  assert_eq(
    mooncode_json_string(persisted_payload, "planner_model", default=""),
    "codex/gpt-5.6-sol",
  )
  let snapshot = mooncode_load_session_snapshot(book_root, session_id)
  assert_eq(
    mooncode_json_string(snapshot, "model", default=""),
    "codex/gpt-5.6-sol",
  )
  guard daemon.mooncode_session_record(session_id, book_root) is Some(record) else {
    fail("expected reloaded MoonCode session")
  }
  assert_eq(
    mooncode_json_string(record, "model", default=""),
    "codex/gpt-5.6-sol",
  )
  let follow_ups : Array[Json] = [
    { "action": "prompt", "command_id": "cmd-model-follow-up" },
    { "action": "package", "command_id": "cmd-model-package" },
    { "action": "steer", "command_id": "cmd-model-steer" },
  ]
  for follow_up in follow_ups {
    let action = mooncode_json_string(follow_up, "action", default="")
    let command_id = mooncode_json_string(follow_up, "command_id", default="")
    ignore(
      daemon.mooncode_queue_command_response(
        session_id~,
        {
          "protocol": mooncode_protocol_version(),
          "session_id": session_id,
          "book_root": book_root,
          "command": action,
          "text": "Create tools/stray.txt with exactly STRAY",
          "packet": { "command_id": command_id },
        },
        queue_source="test-model-inheritance",
      ),
    )
  }
  let inherited_commands = mooncode_journal_entries(
    mooncode_read_session_journal(book_root, session_id),
    mooncode_journal_command(),
  )
  assert_eq(inherited_commands.length(), 4)
  for entry in inherited_commands {
    let command = mooncode_json_object_field_or_empty(entry, "command")
    assert_eq(
      mooncode_runtime_turn_requested_model(command),
      "codex/gpt-5.6-sol",
    )
  }
  let restarted = Daemon::{
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
  ignore(
    restarted.mooncode_queue_command_response(
      session_id~,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "book_root": book_root,
        "command": "prompt",
        "text": "Follow up after restart",
        "packet": { "command_id": "cmd-model-restarted" },
      },
      queue_source="test-model-restart",
    ),
  )
  let restarted_commands = mooncode_journal_entries(
    mooncode_read_session_journal(book_root, session_id),
    mooncode_journal_command(),
  )
  assert_eq(restarted_commands.length(), 5)
  assert_eq(
    mooncode_runtime_turn_requested_model(
      mooncode_json_object_field_or_empty(restarted_commands[4], "command"),
    ),
    "codex/gpt-5.6-sol",
  )
  ignore(
    restarted.mooncode_queue_command_response(
      session_id~,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "book_root": book_root,
        "command": "prompt",
        "text": "Caller deliberately supplies a finish call",
        "packet": { "command_id": "cmd-model-explicit-tools" },
        "runtime_tool_calls": [
          { "tool": "finish", "arguments": { "answer": "done" } },
        ],
      },
      queue_source="test-explicit-tool-provenance",
    ),
  )
  let explicit_commands = mooncode_journal_entries(
    mooncode_read_session_journal(book_root, session_id),
    mooncode_journal_command(),
  )
  assert_eq(
    mooncode_json_string(explicit_commands[5], "planner_mode", default=""),
    "explicit-tool-calls",
  )
  for i in 0..<5 {
    assert_eq(
      mooncode_json_string(explicit_commands[i], "planner_mode", default=""),
      "",
    )
  }
}
