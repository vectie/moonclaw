///|
async test "mooncode native runtime turn executes explicit tool calls" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-turn-XXXXXX"),
  )
  @fsx.write_to_file(@pathx.join(book_root, "README.md"), "hello mooncode")
  let session_id = "session-runtime-turn"
  let command_id = "cmd-runtime-turn"
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "model": "codex/gpt-5.6-sol",
    "web_search": true,
    "packet": { "command_id": command_id },
    "runtime_tool_calls": [
      { "tool": "read", "arguments": { "path": "README.md" } },
      {
        "tool": "shell",
        "arguments": { "cmd": "printf turn-ok", "timeout_ms": 5000 },
      },
      { "tool": "finish", "arguments": { "answer": "done" } },
    ],
  }
  mooncode_with_fixture_moonfort(book_root, async fn(config) {
    let command = mooncode_fixture_authorized_runtime_command(
      config, book_root, command,
    )
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_command(),
      {
        "kind": "mooncode-command",
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "command_id": command_id,
        "created_at": @clock.Timestamp::from_ms(1L),
        "command": command,
      },
    )
    mooncode_fixture_approve_runtime_commands(book_root, command)
    let daemon = Daemon::{
      clock: @clock.epoch,
      models: @model.Loader::new(home=@os.home(), cwd=book_root),
      uuid: @uuid.generator(@rand.chacha8()),
      process: @trusted_host_process.DaemonChildManager::new(cwd=book_root),
      by_cwd: {},
      by_id: {},
      rqs: {},
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
    let result = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
      "consumer_id": "test-runtime",
    })
    assert_true(mooncode_json_bool(result, "accepted", default=false))
    assert_eq(
      mooncode_json_string(result, "command_id", default=""),
      command_id,
    )
    let execution = mooncode_json_object_field_or_empty(result, "execution")
    assert_true(mooncode_json_bool(execution, "web_search", default=false))
    let tool_results = mooncode_json_array_items(execution, "tool_results")
    assert_eq(tool_results.length(), 3)
    assert_true(execution.stringify().contains("turn-ok"))
    let receipt_log = @fsx.read_file(
      mooncode_session_journal_path(book_root, session_id),
    )
    assert_true(receipt_log.contains("\"runtime-claimed\""))
    assert_true(receipt_log.contains("\"runtime-completed\""))
    assert_true(receipt_log.contains("\"web_search\":true"))
    let events_log = @fsx.read_file(
      mooncode_session_journal_path(book_root, session_id),
    )
    assert_true(events_log.contains("\"runtime.turn_started\""))
    assert_true(events_log.contains("\"tool_result\""))
    assert_true(events_log.contains("\"runtime.turn_finished\""))
    let after = mooncode_json_object_field_or_empty(result, "claim_state")
    assert_true(after.stringify().contains("\"delivered_command_count\":1"))
    let snapshot = mooncode_load_session_snapshot(book_root, session_id)
    assert_eq(mooncode_json_int(snapshot, "command_count", default=0), 1)
  })
}

///|
async test "mooncode native runtime turn defers idle steer into next command" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-steer-XXXXXX"),
  )
  let session_id = "session-runtime-steer"
  let command_id = "cmd-runtime-steer"
  let prompt_id = "cmd-runtime-prompt"
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "steer",
    "text": "Keep the next patch inside tools/ and add tests.",
    "packet": { "command_id": command_id },
    "model": "codex/gpt-5.6-sol",
  }
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": command_id,
      "created_at": @clock.Timestamp::from_ms(2L),
      "command": command,
    },
  )
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @trusted_host_process.DaemonChildManager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
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
  let result = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
    "consumer_id": "test-runtime",
  })
  assert_true(mooncode_json_bool(result, "accepted", default=false))
  let execution = mooncode_json_object_field_or_empty(result, "execution")
  assert_eq(
    mooncode_json_string(execution, "control", default=""),
    "steer_deferred",
  )
  assert_eq(
    mooncode_json_string(execution, "planner_mode", default=""),
    "runtime-control",
  )
  let decision = mooncode_json_object_field_or_empty(
    result, "runtime_control_decision",
  )
  assert_eq(mooncode_json_string(decision, "effect", default=""), "defer-steer")
  let tool_results = mooncode_json_array_items(execution, "tool_results")
  assert_eq(tool_results.length(), 0)
  let events_log_before = @fsx.read_file(
    mooncode_session_journal_path(book_root, session_id),
  )
  assert_true(events_log_before.contains("\"steer_deferred\""))
  assert_false(events_log_before.contains("\"steer_dropped\""))
  assert_false(events_log_before.contains("\"steer_applied\""))
  assert_true(events_log_before.contains("Keep the next patch inside tools/"))
  assert_false(events_log_before.contains("runtime.planner_failed"))
  let after = mooncode_json_object_field_or_empty(result, "claim_state")
  assert_true(after.stringify().contains("\"delivered_command_count\":1"))
  let prompt : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "text": "Record this MoonCode prompt.",
    "model": "codex/gpt-5.6-sol",
    "packet": { "command_id": prompt_id },
    "runtime_tool_calls": [
      {
        "tool": "finish",
        "arguments": { "answer": "Recorded the MoonCode prompt." },
      },
    ],
  }
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": prompt_id,
      "created_at": @clock.Timestamp::from_ms(4L),
      "command": prompt,
    },
  )
  let prompt_result = daemon.mooncode_runtime_turn_execute(
    session_id,
    book_root,
    { "consumer_id": "test-runtime" },
  )
  assert_true(mooncode_json_bool(prompt_result, "accepted", default=false))
  let prompt_execution = mooncode_json_object_field_or_empty(
    prompt_result, "execution",
  )
  let deferred = mooncode_json_array_items(
    prompt_execution, "deferred_steering",
  )
  assert_eq(deferred.length(), 1)
  assert_eq(
    mooncode_json_string(deferred[0], "command_id", default=""),
    command_id,
  )
  let events_log_after = @fsx.read_file(
    mooncode_session_journal_path(book_root, session_id),
  )
  assert_true(events_log_after.contains("\"steer_deferred\""))
  assert_true(events_log_after.contains("\"steer_applied\""))
  assert_true(
    events_log_after.contains("\"applied_to_command_id\":\"\{prompt_id}\""),
  )
  assert_true(events_log_after.contains("Keep the next patch inside tools/"))
}

///|
async test "mooncode native runtime turn drops idle cancel commands" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-cancel-XXXXXX"),
  )
  let session_id = "session-runtime-cancel"
  let command_id = "cmd-runtime-cancel"
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "cancel",
    "packet": { "command_id": command_id },
  }
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": command_id,
      "created_at": @clock.Timestamp::from_ms(3L),
      "command": command,
    },
  )
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @trusted_host_process.DaemonChildManager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
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
  let result = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
    "consumer_id": "test-runtime",
  })
  assert_true(mooncode_json_bool(result, "accepted", default=false))
  let decision = mooncode_json_object_field_or_empty(
    result, "runtime_control_decision",
  )
  assert_eq(mooncode_json_string(decision, "effect", default=""), "drop-cancel")
  let execution = mooncode_json_object_field_or_empty(result, "execution")
  assert_eq(
    mooncode_json_string(execution, "control", default=""),
    "cancel_dropped",
  )
  assert_eq(
    mooncode_json_string(execution, "planner_mode", default=""),
    "runtime-control",
  )
  let receipt = mooncode_json_object_field_or_empty(result, "turn_receipt")
  assert_eq(
    mooncode_json_string(receipt, "status", default=""),
    "runtime-completed",
  )
  let events_log = @fsx.read_file(
    mooncode_session_journal_path(book_root, session_id),
  )
  assert_true(events_log.contains("\"cancel_dropped\""))
  assert_true(events_log.contains("\"runtime.turn_finished\""))
}

///|
async test "mooncode native runtime loop stops on dropped cancel commands" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-loop-cancel-XXXXXX"),
  )
  let session_id = "session-runtime-loop-cancel"
  let command_id = "cmd-runtime-loop-cancel"
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "cancel",
    "packet": { "command_id": command_id },
  }
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": command_id,
      "created_at": @clock.Timestamp::from_ms(4L),
      "command": command,
    },
  )
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @trusted_host_process.DaemonChildManager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
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
  let result = daemon.mooncode_runtime_loop_execute(session_id, book_root, {
    "consumer_id": "test-runtime-loop",
    "max_turns": 4,
  })
  assert_true(mooncode_json_bool(result, "accepted", default=false))
  assert_eq(mooncode_json_string(result, "stopped_by", default=""), "cancelled")
  assert_eq(mooncode_json_int(result, "ran_turn_count", default=0), 1)
  let turns = mooncode_json_array_items(result, "turns")
  assert_eq(turns.length(), 1)
  let execution = mooncode_json_object_field_or_empty(turns[0], "execution")
  assert_eq(
    mooncode_json_string(execution, "control", default=""),
    "cancel_dropped",
  )
  let events_log = @fsx.read_file(
    mooncode_session_journal_path(book_root, session_id),
  )
  assert_true(events_log.contains("\"cancel_dropped\""))
}

///|
async test "mooncode native runtime turn records review receipts" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-review-XXXXXX"),
  )
  let session_id = "session-runtime-review"
  let accept_id = "cmd-runtime-accept"
  let reject_id = "cmd-runtime-reject"
  let accept_command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "accept",
    "context_path": "tools/demo/run.sh",
    "packet": { "command_id": accept_id, "context_path": "tools/demo/run.sh" },
    "model": "codex/gpt-5.6-sol",
  }
  let reject_command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "reject",
    "model": "codex/gpt-5.6-sol",
    "context_path": "apps/demo/index.html",
    "packet": {
      "command_id": reject_id,
      "context_path": "apps/demo/index.html",
    },
  }
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": accept_id,
      "created_at": @clock.Timestamp::from_ms(3L),
      "command": accept_command,
    },
  )
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": reject_id,
      "created_at": @clock.Timestamp::from_ms(4L),
      "command": reject_command,
    },
  )
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @trusted_host_process.DaemonChildManager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
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
  let accepted = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
    "consumer_id": "test-runtime",
  })
  assert_true(mooncode_json_bool(accepted, "accepted", default=false))
  let accepted_execution = mooncode_json_object_field_or_empty(
    accepted, "execution",
  )
  assert_eq(
    mooncode_json_string(accepted_execution, "control", default=""),
    "accept",
  )
  assert_eq(
    mooncode_json_string(accepted_execution, "planner_mode", default=""),
    "deterministic-fallback",
  )
  assert_false(
    accepted_execution.stringify().contains("runtime.planner_failed"),
  )
  let accept_receipts = mooncode_json_array_items(
    accepted_execution, "review_receipts",
  )
  assert_eq(accept_receipts.length(), 1)
  assert_eq(
    mooncode_json_string(accept_receipts[0], "action", default=""),
    "accept",
  )
  let accept_path = @pathx.join(
    book_root, "wiki/reviews/mooncode/session-runtime-review/accept-cmd-runtime-accept.json",
  )
  assert_true(@fsx.exists(accept_path))
  let accept_text = @fsx.read_file(accept_path)
  assert_true(accept_text.contains("\"mooncode-review-receipt\""))
  assert_true(accept_text.contains("\"decision\": \"accepted\""))
  let rejected = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
    "consumer_id": "test-runtime",
  })
  assert_true(mooncode_json_bool(rejected, "accepted", default=false))
  let rejected_execution = mooncode_json_object_field_or_empty(
    rejected, "execution",
  )
  assert_eq(
    mooncode_json_string(rejected_execution, "control", default=""),
    "reject",
  )
  let reject_receipts = mooncode_json_array_items(
    rejected_execution, "review_receipts",
  )
  assert_eq(reject_receipts.length(), 1)
  assert_eq(
    mooncode_json_string(reject_receipts[0], "action", default=""),
    "reject",
  )
  let reject_path = @pathx.join(
    book_root, "wiki/reviews/mooncode/session-runtime-review/reject-cmd-runtime-reject.json",
  )
  assert_true(@fsx.exists(reject_path))
  let reject_text = @fsx.read_file(reject_path)
  assert_true(reject_text.contains("\"decision\": \"rejected\""))
  let events_log = @fsx.read_file(
    mooncode_session_journal_path(book_root, session_id),
  )
  assert_true(events_log.contains("\"receipt.accept\""))
  assert_true(events_log.contains("\"receipt.reject\""))
  assert_true(events_log.contains("\"command\":\"accept\""))
  assert_true(events_log.contains("\"command\":\"reject\""))
  let after = mooncode_json_object_field_or_empty(rejected, "claim_state")
  assert_true(after.stringify().contains("\"delivered_command_count\":2"))
}

///|
test "mooncode exact model adversarial prompts bypass deterministic preplanning" {
  for
    text in [
      "Read README.md.", "Create tools/stray.txt with exactly STRAY, then write the result.",
    ] {
    let command : Json = {
      "session_id": "session-exact-boundary",
      "book_root": "/tmp/book",
      "command": "prompt",
      "text": text,
      "model": "codex/gpt-5.6-sol",
      "packet": { "command_id": "cmd-exact-boundary" },
    }
    assert_true(mooncode_runtime_turn_requires_model_planning(command))
  }
}

///|
test "mooncode failed planner cannot become a successful fallback" {
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-planner-failed",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Explain this project",
    "packet": { "command_id": "cmd-planner-failed" },
  }
  let started = mooncode_event(
    session_id="session-planner-failed",
    command_id="cmd-planner-failed",
    lane="runtime",
    kind="runtime.planner_started",
    title="started",
    status="running",
    detail="started",
    now=@clock.Timestamp::from_ms(1L),
  )
  for
    message in [
      "model unavailable", "model planner failed: ConnectionClosed", "model planner returned no usable MoonCode tool calls",
    ] {
    let result = mooncode_runtime_turn_failed_planner_result(
      command,
      "codex/gpt-5.6-sol",
      message,
      started,
      now=@clock.Timestamp::from_ms(2L),
    )
    assert_eq(
      mooncode_json_string(result, "planner_mode", default=""),
      "model-tool-calls",
    )
    assert_eq(mooncode_json_array_items(result, "tool_calls").length(), 0)
    assert_true(mooncode_json_bool(result, "failed", default=false))
    let serialized = result.stringify()
    assert_true(serialized.contains("runtime.planner_failed"))
    assert_false(serialized.contains("deterministic-fallback"))
    assert_false(serialized.contains("fell back"))
  }
}

///|
test "transient planner close is retryable while other errors stay terminal" {
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-planner-transport",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Continue the current task",
    "model": "codex/gpt-5.6-sol",
    "packet": { "command_id": "cmd-planner-transport" },
  }
  let started = mooncode_event(
    session_id="session-planner-transport",
    command_id="cmd-planner-transport",
    lane="runtime",
    kind="runtime.planner_started",
    title="started",
    status="running",
    detail="started",
    now=@clock.Timestamp::from_ms(1L),
  )
  let transient = mooncode_runtime_turn_transient_transport_result(
    "codex/gpt-5.6-sol", "model planner follow-up failed: ConnectionClosed", started,
  )
  assert_true(
    mooncode_json_bool(transient, "transient_transport_close", default=false),
  )
  assert_false(mooncode_json_bool(transient, "failed", default=false))
  assert_false(transient.stringify().contains("runtime.planner_failed"))
  let terminal = mooncode_runtime_turn_planner_error_result(
    command,
    "codex/gpt-5.6-sol",
    "model planner follow-up failed",
    InvalidJournal("malformed model response"),
    started,
    now=@clock.Timestamp::from_ms(3L),
  )
  assert_false(
    mooncode_json_bool(terminal, "transient_transport_close", default=false),
  )
  assert_true(mooncode_json_bool(terminal, "failed", default=false))
  assert_true(terminal.stringify().contains("runtime.planner_failed"))
}

///|
test "retryable planner HTTP statuses retain the durable turn" {
  for
    summary in [
      "HTTP 408: timed out", "HTTP 429: rate limited", "HTTP 500", "HTTP 502: overloaded",
      "HTTP 503: unavailable", "HTTP 504: gateway timeout",
    ] {
    assert_true(
      mooncode_runtime_turn_planner_error_summary_is_transient(summary),
    )
  }
  for terminal in ["HTTP 400: invalid request", "HTTP 401: unauthorized"] {
    assert_false(
      mooncode_runtime_turn_planner_error_summary_is_transient(terminal),
    )
  }
}

///|
test "mooncode model planner selects runtime default when model is omitted" {
  let command : Json = {
    "command": "prompt",
    "text": "Explain the current project structure",
  }
  assert_true(mooncode_runtime_turn_requires_model_planning(command))
  assert_eq(mooncode_runtime_turn_requested_model(command), "")
  assert_eq(
    mooncode_runtime_turn_requested_model_label(command),
    "default model",
  )
}

///|
async test "mooncode caller supplied explicit tools execute without model delay" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-explicit-plan-XXXXXX"),
  )
  @fsx.write_to_file(@pathx.join(book_root, "README.md"), "fixture read")
  let session_id = "session-explicit-plan"
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @trusted_host_process.DaemonChildManager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
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
  let write_id = "cmd-explicit-write"
  let write : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "text": "Create tools/e2e-fixed.txt with exactly ROOT_OK, then reply that it is done.",
    "model": "codex/gpt-5.6-sol",
    "packet": { "command_id": write_id },
    "runtime_tool_calls": [
      {
        "tool": "write",
        "arguments": { "path": "tools/e2e-fixed.txt", "content": "ROOT_OK" },
      },
      { "tool": "finish", "arguments": { "answer": "done" } },
    ],
  }
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": write_id,
      "created_at": @clock.Timestamp::from_ms(1L),
      "command": write,
    },
  )
  let write_result = daemon.mooncode_runtime_turn_execute(
    session_id,
    book_root,
    { "consumer_id": "test-runtime" },
  )
  assert_true(mooncode_json_bool(write_result, "accepted", default=false))
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "tools/e2e-fixed.txt")),
    "ROOT_OK",
  )
  let read_id = "cmd-explicit-read"
  let read : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "text": "Read README.md.",
    "model": "codex/gpt-5.6-sol",
    "packet": { "command_id": read_id },
    "runtime_tool_calls": [
      { "tool": "read", "arguments": { "path": "README.md" } },
      { "tool": "finish", "arguments": { "answer": "done" } },
    ],
  }
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": read_id,
      "created_at": @clock.Timestamp::from_ms(2L),
      "command": read,
    },
  )
  let read_result = daemon.mooncode_runtime_turn_execute(
    session_id,
    book_root,
    { "consumer_id": "test-runtime" },
  )
  assert_true(mooncode_json_bool(read_result, "accepted", default=false))
  assert_true(read_result.stringify().contains("fixture read"))
  let event_log = @fsx.read_file(
    mooncode_session_journal_path(book_root, session_id),
  )
  assert_false(event_log.contains("runtime.planner_started"))
  assert_false(event_log.contains("runtime.planner_failed"))
}

///|
test "mooncode planner permits parallel tool calls" {
  let request = mooncode_runtime_turn_model_plan_request_from_messages(
    "test-model",
    [
      { "role": "system", "content": "inspect independently" },
      { "role": "user", "content": "read both files" },
    ],
  ) catch {
    _ => abort("planner request should be valid")
  }
  assert_true(
    mooncode_json_bool(request.to_json(), "parallel_tool_calls", default=false),
  )
  assert_false(
    mooncode_runtime_turn_stops_tool_batch(
      { "planner_mode": "model-tool-calls" },
      { "accepted": true, "tool": "read", "result": { "ok": true } },
    ),
  )
  let tools_json = Json(mooncode_runtime_turn_model_tools()).stringify()
  assert_true(tools_json.contains("start_line"))
  assert_true(tools_json.contains("end_line"))
}

///|
test "mooncode planner scopes prompt cache identity to MoonGate sessions" {
  let moongate = @model.Model::new(
    api_key="test",
    base_url="http://127.0.0.1:15721/openclaw/v1",
    name="moongate/test-model",
    model_name="test-model",
    safe_zone_tokens=1000,
  )
  let cached = mooncode_runtime_turn_model_extra_body(moongate, {
    "session_id": "session-cache-stable",
  })
  assert_eq(
    cached.get("prompt_cache_key"),
    Some(Json::string("moonclaw-session:session-cache-stable")),
  )
  let direct = @model.Model::new(
    api_key="test",
    base_url="https://example.invalid/v1",
    name="direct/test-model",
    model_name="test-model",
    safe_zone_tokens=1000,
  )
  assert_true(
    mooncode_runtime_turn_model_extra_body(direct, {
      "session_id": "session-cache-stable",
    }).is_empty(),
  )
  assert_true(
    mooncode_runtime_turn_model_extra_body(moongate, { "session_id": "   " }).is_empty(),
  )
}

///|
test "mooncode planner retry delays and events retain bounded backoff evidence" {
  let transient_delay = mooncode_runtime_turn_model_retry_delay_ms(
    0,
    entropy="session-a",
  )
  assert_true(transient_delay >= 850 && transient_delay <= 1150)
  let capped_transient_delay = mooncode_runtime_turn_model_retry_delay_ms(
    50,
    entropy="session-a",
  )
  assert_true(capped_transient_delay >= 25500)
  assert_true(capped_transient_delay <= 30000)
  let overload_delay = mooncode_runtime_turn_model_retry_delay_ms(
    0,
    summary="HTTP 429: provider overloaded",
    entropy="session-a",
  )
  assert_true(overload_delay >= 25500 && overload_delay <= 34500)
  assert_eq(
    mooncode_runtime_turn_model_retry_delay_ms(
      0,
      summary="HTTP 429: provider overloaded",
      retry_after_ms=Some(90000),
      entropy="session-a",
    ),
    90000,
  )
  assert_eq(
    mooncode_runtime_turn_model_retry_jitter_percent("stable"),
    mooncode_runtime_turn_model_retry_jitter_percent("stable"),
  )
  let retry_event = mooncode_runtime_turn_model_retry_event(
    {
      "session_id": "session-kimi",
      "book_root": "/tmp/book",
      "packet": { "command_id": "command-kimi" },
    },
    "kimi-k3",
    3,
    "HTTP 429: provider overloaded",
    120000,
    provider_error_class="server_overloaded",
    retry_after_ms=Some(90000),
    retry_request_chars=32000,
    now=@clock.Timestamp::from_ms(42L),
  )
  assert_eq(
    mooncode_json_string(retry_event, "kind", default=""),
    "runtime.planner_retrying",
  )
  assert_eq(mooncode_json_string(retry_event, "status", default=""), "waiting")
  assert_true(
    mooncode_json_string(retry_event, "detail", default="").contains("HTTP 429"),
  )
  assert_eq(
    mooncode_json_string(retry_event, "provider_error_class", default=""),
    "server_overloaded",
  )
  assert_eq(mooncode_json_int(retry_event, "retry_after_ms", default=0), 90000)
  assert_eq(
    mooncode_json_int(retry_event, "retry_request_chars", default=0),
    32000,
  )
}

///|
test "mooncode line-range reads remain partial observations" {
  let observation = mooncode_runtime_turn_result_file_observation({
    "accepted": true,
    "tool": "read",
    "arguments": { "path": "src/main.mbt", "start_line": 20, "end_line": 40 },
    "result": {
      "ok": true,
      "metadata": {
        "path": "src/main.mbt",
        "range_requested": true,
        "truncated": false,
      },
    },
  })
  assert_eq(mooncode_json_string(observation, "scope", default=""), "partial")
}

///|
test "mooncode live steering becomes an explicit planner user message" {
  let steering : Json = {
    "command_id": "steer-live-1",
    "steering_text": "Patch now and run the focused test.",
  }
  let message = mooncode_runtime_turn_model_live_steering_message(steering)
  assert_eq(mooncode_json_string(message, "role", default=""), "user")
  let content = mooncode_json_string(message, "content", default="")
  assert_true(content.contains("steer-live-1"))
  assert_true(content.contains("Patch now and run the focused test."))
  assert_true(content.contains("before choosing the next"))
  let messages = mooncode_runtime_turn_model_messages(
    { "command": "prompt", "text": "Implement the repair." },
    [steering],
    1,
  )
  assert_eq(messages.length(), 3)
  assert_eq(mooncode_json_string(messages[2], "role", default=""), "user")
  assert_true(
    mooncode_json_string(messages[2], "content", default="").contains(
      "steer-live-1",
    ),
  )
  assert_true(
    mooncode_json_string(messages[2], "content", default="").contains(
      "paths in this steering as authoritative",
    ),
  )
}

///|
async test "mooncode followup makes retained reads errors and path hints actionable" {
  let command : Json = {
    "command": "prompt",
    "text": "Implement the parser repair without repeating discovery.",
  }
  let previous : Json = {
    "model_messages": [
      { "role": "system", "content": "planner contract" },
      { "role": "user", "content": "repair request" },
    ],
    "model_response_message": {
      "role": "assistant",
      "content": "",
      "tool_calls": [
        {
          "id": "read-good",
          "type": "function",
          "function": {
            "name": "read",
            "arguments": "{\"path\":\"src/parser.mbt\"}",
          },
        },
        {
          "id": "read-guessed",
          "type": "function",
          "function": {
            "name": "read",
            "arguments": "{\"path\":\"src/guessed.mbt\"}",
          },
        },
        {
          "id": "shell-observation",
          "type": "function",
          "function": {
            "name": "shell",
            "arguments": "{\"cmd\":\"sed -n '1,80p' src/adapter.mbt\"}",
          },
        },
      ],
    },
  }
  let tool_calls : Array[Json] = [
    {
      "tool": "read",
      "tool_call_id": "read-good",
      "arguments": { "path": "src/parser.mbt" },
    },
    {
      "tool": "read",
      "tool_call_id": "read-guessed",
      "arguments": { "path": "src/guessed.mbt" },
    },
    {
      "tool": "shell",
      "tool_call_id": "shell-observation",
      "arguments": { "cmd": "sed -n '1,80p' src/adapter.mbt" },
    },
  ]
  let tool_results : Array[Json] = [
    {
      "tool": "read",
      "accepted": true,
      "result": { "ok": true, "output": "current parser source" },
    },
    {
      "tool": "read",
      "accepted": false,
      "result": { "ok": false, "message": "path does not exist" },
    },
    {
      "tool": "shell",
      "accepted": true,
      "result": {
        "ok": true,
        "output": "current adapter source",
        "metadata": {
          "file_observation": {
            "path": "src/adapter.mbt",
            "scope": "partial",
            "source": "shell",
          },
        },
      },
    },
  ]
  let all_tool_results : Array[Json] = [
    {
      "tool": "read",
      "arguments": { "path": "src/earlier-retained.mbt" },
      "accepted": true,
      "result": {
        "ok": true,
        "output": "earlier retained source",
        "metadata": { "path": "src/earlier-retained.mbt", "truncated": false },
      },
    },
    tool_results[0],
    tool_results[1],
    tool_results[2],
    {
      "tool": "read_skill",
      "accepted": true,
      "result": {
        "ok": true,
        "output": "complete skill body",
        "metadata": {
          "name": "moonbit-agent-guide",
          "path": "SKILL.md",
          "location": "/installed/moonbit-agent-guide/SKILL.md",
          "content_sha256_base64": "guide-digest",
          "content_chars": 34084,
        },
      },
    },
  ]
  let steering : Json = {
    "command_id": "steer-exact-path",
    "steering_text": "The implementation is at internal/parser/parser.mbt.",
  }
  let messages = mooncode_runtime_turn_model_followup_messages(
    command,
    previous,
    tool_calls,
    tool_results,
    all_tool_results,
    [steering],
    -1,
  )
  let transcript = Json::array(messages).stringify()
  assert_true(transcript.contains("successful_read_paths"))
  assert_true(transcript.contains("complete_read_paths"))
  assert_true(transcript.contains("successful_inspections"))
  assert_true(transcript.contains("sed -n '1,80p' src/adapter.mbt"))
  assert_true(transcript.contains("current adapter source"))
  assert_true(transcript.contains("src/parser.mbt"))
  assert_true(transcript.contains("src/adapter.mbt"))
  assert_true(transcript.contains("src/earlier-retained.mbt"))
  assert_true(transcript.contains("failed_tool_calls"))
  assert_true(transcript.contains("src/guessed.mbt"))
  assert_true(transcript.contains("path does not exist"))
  assert_true(transcript.contains("internal/parser/parser.mbt"))
  assert_true(transcript.contains("paths in this steering as authoritative"))
  let recovery = mooncode_json_string(
    messages[messages.length() - 2],
    "content",
    default="",
  )
  assert_true(recovery.contains("Saved progress (advisory)"))
  assert_true(recovery.contains("Recent results"))
  let receipts = messages.filter(message => {
    mooncode_json_string(
      mooncode_runtime_context_provenance(message),
      "source",
      default="",
    ) ==
    "skill.loaded_receipt"
  })
  assert_eq(receipts.length(), 1)
  assert_true(
    mooncode_json_string(receipts[0], "content", default="").contains(
      "moonbit-agent-guide/SKILL.md",
    ),
  )
  assert_eq(
    mooncode_json_string(messages[messages.length() - 1], "content", default="").contains(
      "steer-exact-path",
    ),
    true,
  )
}

///|
test "mooncode retains planner memory across accepted checkpoints" {
  let command : Json = {
    "command": "prompt",
    "text": "Implement the multi-phase repair.",
  }
  let previous : Json = {
    "model_messages": [
      { "role": "system", "content": "planner" },
      {
        "role": "system",
        "content": "Dynamic skill gate: legacy checkpoint wording",
      },
      { "role": "user", "content": "original task" },
      { "role": "assistant", "content": "remembered plan inventory" },
    ],
  }
  let retained = mooncode_runtime_turn_model_followup_base_messages(
    command,
    previous,
    [
      {
        "tool": "read",
        "accepted": true,
        "result": { "output": "source contents" },
      },
    ],
  )
  assert_eq(retained.length(), 4)
  assert_true(
    mooncode_json_string(retained[2], "content", default="").contains(
      "Implement the multi-phase repair.",
    ),
  )
  assert_eq(
    mooncode_json_string(retained[3], "content", default=""),
    "remembered plan inventory",
  )
  let checkpointed = mooncode_runtime_turn_model_followup_base_messages(
    command,
    previous,
    [
      {
        "tool": "checkpoint",
        "accepted": true,
        "result": { "message": "checkpoint recorded" },
      },
    ],
    all_tool_results=[
      {
        "tool": "read_skill",
        "accepted": true,
        "result": {
          "output": "complete retained skill instructions",
          "metadata": {
            "name": "fixture-review",
            "path": "SKILL.md",
            "location": "/installed/fixture-review/SKILL.md",
            "content_sha256_base64": "fixture-digest",
            "content_chars": 36,
          },
        },
      },
    ],
    skill_catalog="<available_skills />",
  )
  assert_eq(checkpointed.length(), 5)
  assert_eq(
    mooncode_json_string(checkpointed[3], "content", default=""),
    "remembered plan inventory",
  )
  let receipt = mooncode_json_string(checkpointed[4], "content", default="")
  assert_true(receipt.contains("Loaded-skill receipt"))
  assert_true(receipt.contains("fixture-review/SKILL.md"))
  assert_true(receipt.contains("fixture-digest"))
  assert_false(receipt.contains("complete retained skill instructions"))
}

///|
test "mooncode accepts explicitly typed successful shell verification" {
  let hosted : Json = {
    "tool": "shell",
    "accepted": true,
    "arguments": {
      "cmd": "moon test cmd/daemon --target native",
      "verification_kind": "test",
    },
    "result": { "ok": true, "metadata": { "status": 0 } },
  }
  assert_eq(mooncode_runtime_turn_result_verification_kind(hosted), "test")
  assert_eq(
    mooncode_runtime_turn_result_verification_kind({
      "tool": "shell",
      "accepted": true,
      "arguments": { "cmd": "git status --short", "verification_kind": "check" },
      "result": { "ok": true, "metadata": { "status": 0 } },
    }),
    "",
  )
  assert_eq(
    mooncode_runtime_turn_result_verification_kind({
      "tool": "shell",
      "accepted": true,
      "arguments": { "cmd": "git status --short" },
      "result": { "ok": true, "metadata": { "status": 0 } },
    }),
    "",
  )
  assert_eq(
    mooncode_runtime_turn_result_verification_kind({
      "tool": "shell",
      "accepted": false,
      "arguments": {
        "cmd": "moon test cmd/daemon --target native",
        "verification_kind": "test",
      },
      "result": { "ok": false, "metadata": { "status": 1 } },
    }),
    "",
  )
}

///|
async test "mooncode live steering settles once before later queue work" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-live-steer-boundary-XXXXXX"),
  )
  let session_id = "session-live-steer-boundary"
  let prompt_id = "prompt-live"
  let steer_id = "steer-live"
  let prompt : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "text": "Implement the fix.",
    "packet": { "command_id": prompt_id },
  }
  let steer : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "steer",
    "text": "Run the focused test before finish.",
    "packet": { "command_id": steer_id },
  }
  for item in [(prompt_id, prompt, 1L), (steer_id, steer, 3L)] {
    let (id, command, created_at) = item
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_command(),
      {
        "kind": "mooncode-command",
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "command_id": id,
        "created_at": @clock.Timestamp::from_ms(created_at),
        "command": command,
      },
    )
  }
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_runtime_receipt(),
    {
      "kind": mooncode_kind_runtime_receipt(),
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command_id": prompt_id,
      "status": "runtime-claimed",
      "claim_id": "claim-live",
      "claimed_at": @clock.Timestamp::from_ms(2L),
    },
  )
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @trusted_host_process.DaemonChildManager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
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
  let first = daemon.mooncode_runtime_turn_claim_live_steering(
    session_id, book_root, prompt_id,
  )
  assert_eq(first.length(), 1)
  assert_eq(mooncode_json_string(first[0], "command_id", default=""), steer_id)
  let events : Array[Json] = []
  let persisted : Map[String, Bool] = Map([])
  daemon.mooncode_runtime_turn_record_event(
    binding,
    events,
    persisted,
    mooncode_runtime_turn_applied_live_steer_event(
      session_id,
      first[0],
      now=@clock.Timestamp::from_ms(4L),
    ),
  )
  let second = daemon.mooncode_runtime_turn_claim_live_steering(
    session_id, book_root, prompt_id,
  )
  assert_eq(second.length(), 0)
  let claim_state = daemon.mooncode_runtime_claim_state_payload(
    session_id, book_root,
  )
  assert_eq(
    mooncode_json_array_items(claim_state, "claimable_commands").length(),
    0,
  )
  assert_true(claim_state.stringify().contains("\"delivered_command_count\":1"))
  let records = mooncode_read_session_journal(book_root, session_id)
  let journal = @fsx.read_file(
    mooncode_session_journal_path(book_root, session_id),
  )
  let mut applied_event_count = 0
  for event in mooncode_journal_entries(records, mooncode_journal_event()) {
    if mooncode_json_string(event, "kind", default="") ==
      mooncode_event_steer_applied() {
      applied_event_count += 1
    }
  }
  let mut applied_receipt_count = 0
  for
    receipt in mooncode_journal_entries(
      records,
      mooncode_journal_runtime_receipt(),
    ) {
    if mooncode_json_string(receipt, "control", default="") == "steer_applied" {
      applied_receipt_count += 1
    }
  }
  assert_eq(applied_event_count, 1)
  assert_eq(applied_receipt_count, 1)
  assert_true(journal.contains("\"applied_to_command_id\":\"prompt-live\""))
  assert_true(
    journal.contains("\"runtime_mode\":\"moonclaw-native-runtime-live-steer\""),
  )
  assert_false(journal.contains("\"steer_deferred\""))
}

///|
async test "mooncode runtime turn records progress immediately and once" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-live-progress-XXXXXX"),
  )
  let session_id = "session-live-progress"
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @trusted_host_process.DaemonChildManager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
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
  let events : Array[Json] = []
  let persisted : Map[String, Bool] = Map([])
  let event : Json = {
    "id": "live-progress-1",
    "session_id": session_id,
    "command_id": "cmd-live-progress",
    "kind": "runtime.planner_started",
    "status": "running",
    "created_at": "2026-07-15T00:07:00Z",
  }
  daemon.mooncode_runtime_turn_record_event(binding, events, persisted, event)
  daemon.mooncode_runtime_turn_record_event(binding, events, persisted, event)
  assert_eq(events.length(), 1)
  assert_eq(
    mooncode_journal_entries(
      mooncode_read_session_journal(book_root, session_id),
      mooncode_journal_event(),
    ).length(),
    1,
  )
}

///|
test "mooncode native runtime turn decodes model-selected tool calls" {
  let calls = mooncode_runtime_turn_tool_calls_from_model_response({
    "choices": [
      {
        "message": {
          "tool_calls": [
            {
              "id": "call-write",
              "type": "function",
              "function": {
                "name": "write",
                "arguments": "{\"path\":\"tools/model-plan/run.sh\",\"content\":\"#!/bin/sh\\nprintf model-plan\\\\n\"}",
              },
            },
            {
              "id": "call-finish",
              "type": "function",
              "function": {
                "name": "finish",
                "arguments": "{\"answer\":\"created model-planned tool\"}",
              },
            },
            {
              "id": "call-unsafe",
              "type": "function",
              "function": { "name": "delete_everything", "arguments": "{}" },
            },
          ],
        },
      },
    ],
  })
  assert_eq(calls.length(), 3)
  assert_true(
    mooncode_json_string(calls[2], "validation_error", default="") != "",
  )
  assert_eq(mooncode_json_string(calls[0], "tool", default=""), "write")
  assert_eq(
    mooncode_json_string(calls[0], "tool_call_id", default=""),
    "call-write",
  )
  let arguments = mooncode_json_object_field_or_empty(calls[0], "arguments")
  assert_eq(
    mooncode_json_string(arguments, "path", default=""),
    "tools/model-plan/run.sh",
  )
  assert_eq(mooncode_json_string(calls[1], "tool", default=""), "finish")
}

///|
test "mooncode native runtime turn treats assistant text as finish" {
  let calls = mooncode_runtime_turn_tool_calls_from_model_response({
    "choices": [
      { "message": { "content": "Hello from model.", "tool_calls": [] } },
    ],
  })
  assert_eq(calls.length(), 1)
  assert_eq(mooncode_json_string(calls[0], "tool", default=""), "finish")
  assert_eq(
    mooncode_json_string(calls[0], "tool_call_id", default=""),
    "model-assistant-content-finish",
  )
  assert_eq(
    mooncode_json_string(calls[0], "planner", default=""),
    "model-assistant-content",
  )
  assert_false(mooncode_runtime_turn_model_tool_call_accepts_result(calls[0]))
  let arguments = mooncode_json_object_field_or_empty(calls[0], "arguments")
  assert_eq(
    mooncode_json_string(arguments, "answer", default=""),
    "Hello from model.",
  )
  assert_true(
    mooncode_runtime_turn_model_tool_call_accepts_result({
      "tool": "finish",
      "tool_call_id": "call-finish",
      "planner": "model-tool-call",
    }),
  )
}

///|
test "mooncode completion accepts an inspected baseline after fresh verification" {
  let command : Json = {
    "command": "prompt",
    "text": "Implement the MoonBit fix and run focused tests.",
  }
  let first_edit : Json = {
    "tool": "edit",
    "accepted": true,
    "result": {
      "metadata": {
        "path": "src/runtime.mbt",
        "changed": true,
        "before_fingerprint": "present:baseline",
        "after_fingerprint": "present:speculative",
      },
    },
  }
  let revert_edit : Json = {
    "tool": "edit",
    "accepted": true,
    "result": {
      "metadata": {
        "path": "src/runtime.mbt",
        "changed": true,
        "before_fingerprint": "present:speculative",
        "after_fingerprint": "present:baseline",
      },
    },
  }
  let test_result : Json = {
    "tool": "moon_cmd",
    "accepted": true,
    "arguments": { "command": "test" },
  }
  let finish : Json = { "tool": "finish", "accepted": true }
  let reverted = mooncode_runtime_turn_completion_verdict(command, [
    first_edit, test_result, revert_edit, test_result, finish,
  ])
  assert_true(reverted.accepted)
  let retained_edit = mooncode_json_object_with_field(revert_edit, "result", {
    "metadata": {
      "path": "src/runtime.mbt",
      "changed": true,
      "before_fingerprint": "present:speculative",
      "after_fingerprint": "present:repaired",
    },
  })
  let retained = mooncode_runtime_turn_completion_verdict(command, [
    first_edit, retained_edit, test_result, finish,
  ])
  assert_true(retained.accepted)
}

///|
test "mooncode completion reason survives terminal and compact projection" {
  let reason = "coding completion has no successful typed test"
  let event = mooncode_runtime_turn_finished_event(
    "session-verdict",
    "command-verdict",
    accepted=false,
    tool_count=3,
    completion_reason=reason,
    now=@clock.Timestamp::from_ms(90L),
  )
  assert_eq(mooncode_json_string(event, "status", default=""), "failed")
  assert_true(
    mooncode_json_string(event, "detail", default="").contains(reason),
  )
  let compact = mooncode_runtime_turn_execution_compact({
    "accepted": false,
    "message": reason,
    "completion_verdict": {
      "kind": "mooncode-coding-completion-verdict",
      "accepted": false,
      "reason": reason,
    },
  })
  let verdict = mooncode_json_object_field_or_empty(
    compact, "completion_verdict",
  )
  assert_false(mooncode_json_bool(verdict, "accepted", default=true))
  assert_eq(mooncode_json_string(verdict, "reason", default=""), reason)
}

///|
test "mooncode runtime receipt keeps completion without replaying tool payloads" {
  let large_output = "receipt-payload-marker-".repeat(10000)
  let receipt = mooncode_runtime_turn_receipt(
    "session-receipt",
    "/tmp/mooncode-receipt",
    {
      "command_id": "command-receipt",
      "command": { "command": "prompt", "web_search": true },
      "receipt": { "claim_id": "claim-receipt" },
    },
    {
      "accepted": true,
      "planner_mode": "model-tool-calls",
      "completion_verdict": {
        "kind": "mooncode-coding-completion-verdict",
        "accepted": true,
        "reason": "verified",
      },
      "tool_results": [
        {
          "tool": "read",
          "accepted": true,
          "result": { "output": large_output },
        },
        {
          "tool": "finish",
          "accepted": true,
          "result": {
            "ok": true,
            "metadata": { "answer": "Completed with proof." },
          },
        },
      ],
      "events": [{ "kind": "tool_result", "detail": large_output }],
    },
    consumer_id="test-runtime",
    now=@clock.Timestamp::from_ms(91L),
  )
  let receipt_text = receipt.stringify()
  assert_false(receipt_text.contains("receipt-payload-marker"))
  assert_true(receipt_text.length() < 5000)
  assert_eq(mooncode_json_array_items(receipt, "events").length(), 0)
  let execution = mooncode_json_object_field_or_empty(receipt, "execution")
  let tool_results = mooncode_json_array_items(execution, "tool_results")
  assert_eq(tool_results.length(), 1)
  assert_eq(mooncode_json_string(tool_results[0], "tool", default=""), "finish")
  assert_eq(
    mooncode_conversation_receipt_answer(receipt),
    "Completed with proof.",
  )
  let verdict = mooncode_json_object_field_or_empty(
    execution, "completion_verdict",
  )
  assert_true(mooncode_json_bool(verdict, "accepted", default=false))
  assert_eq(mooncode_json_string(verdict, "reason", default=""), "verified")
}

///|
test "mooncode native runtime turn builds model follow-up transcript" {
  let response : Json = {
    "choices": [
      {
        "message": {
          "content": "",
          "tool_calls": [
            {
              "id": "call-read",
              "type": "function",
              "function": {
                "name": "read",
                "arguments": "{\"path\":\"README.md\"}",
              },
            },
          ],
        },
      },
    ],
  }
  let assistant = mooncode_runtime_turn_model_response_message(response)
  assert_eq(mooncode_json_string(assistant, "role", default=""), "assistant")
  assert_eq(mooncode_json_array_items(assistant, "tool_calls").length(), 1)
  let calls = mooncode_runtime_turn_tool_calls_from_model_response(response)
  let tool_message = mooncode_runtime_turn_model_tool_result_message(calls[0], {
    "accepted": true,
    "result": { "ok": true, "message": "read README.md", "output": "# Book" },
    "event": { "id": "durable-read-event" },
  })
  assert_eq(mooncode_json_string(tool_message, "role", default=""), "tool")
  assert_eq(
    mooncode_json_string(tool_message, "tool_call_id", default=""),
    "call-read",
  )
  assert_true(
    mooncode_json_string(tool_message, "content", default="").contains(
      "read README.md",
    ),
  )
  assert_true(
    mooncode_json_string(tool_message, "content", default="").contains(
      "durable-read-event",
    ),
  )
  assert_true(
    mooncode_json_string(tool_message, "content", default="").contains(
      "evidence_ref",
    ),
  )
  let settled = mooncode_runtime_turn_model_tool_result_messages(
    [
      {
        "tool": "read",
        "tool_call_id": "call-read",
        "arguments": { "path": "README.md" },
      },
      {
        "tool": "read",
        "tool_call_id": "call-second",
        "arguments": { "path": "moon.mod.json" },
      },
      {
        "tool": "shell",
        "tool_call_id": "call-third",
        "arguments": { "command": "git status --short" },
      },
    ],
    [
      {
        "tool": "read",
        "accepted": true,
        "result": { "ok": true, "message": "read README.md" },
      },
    ],
  )
  assert_eq(settled.length(), 3)
  assert_eq(
    mooncode_json_string(settled[0], "tool_call_id", default=""),
    "call-read",
  )
  assert_eq(
    mooncode_json_string(settled[1], "tool_call_id", default=""),
    "call-second",
  )
  assert_eq(
    mooncode_json_string(settled[2], "tool_call_id", default=""),
    "call-third",
  )
  assert_true(
    mooncode_json_string(settled[0], "content", default="").contains(
      "read README.md",
    ),
  )
  assert_true(
    mooncode_json_string(settled[1], "content", default="").contains(
      "earlier call ended the batch",
    ),
  )
  let skipped = @json.parse(
    mooncode_json_string(settled[2], "content", default=""),
  )
  let skipped_metadata = mooncode_json_object_field_or_empty(skipped, "result")
    |> mooncode_json_object_field_or_empty("metadata")
  assert_true(mooncode_json_bool(skipped_metadata, "skipped", default=false))
  let oversized = mooncode_runtime_turn_model_tool_result_content({
    "result": { "output": "x".repeat(9000) },
  })
  assert_true(oversized.contains("x".repeat(9000)))
  ignore(@json.parse(oversized))
  let retained_source = mooncode_runtime_turn_model_tool_result_content({
    "tool": "read",
    "result": { "output": "x".repeat(9000) },
  })
  assert_true(retained_source.length() > 9000)
  let oversized_source = mooncode_runtime_turn_model_tool_result_content({
    "tool": "read",
    "result": { "output": "x".repeat(50000) },
  })
  assert_true(oversized_source.contains("x".repeat(50000)))
  ignore(@json.parse(oversized_source))
  assert_true(!mooncode_runtime_turn_tool_calls_include_finish(calls))
  assert_eq(
    mooncode_runtime_turn_pipeline_evidence_warning([
      {
        "tool": "shell",
        "arguments": { "cmd": "scripts/validate.sh full 2>&1 | tail -100" },
        "result": { "metadata": { "pipeline_exit_ambiguous": true } },
      },
    ]).contains("cannot prove"),
    true,
  )
  assert_eq(
    mooncode_runtime_turn_pipeline_evidence_warning([
      {
        "tool": "shell",
        "arguments": {
          "cmd": "set -o pipefail; scripts/validate.sh full 2>&1 | tail -100",
        },
        "result": { "metadata": { "pipeline_exit_ambiguous": false } },
      },
    ]),
    "",
  )
  assert_true(
    mooncode_runtime_turn_tool_calls_include_finish([
      { "tool": "finish", "arguments": { "answer": "done" } },
    ]),
  )
  let incomplete_horizon : Json = {
    "command": "prompt",
    "text": "Implement the requested fix and run tests.",
    "payload": {
      "horizon_id": "recover-finish",
      "task_contract": {
        "objective": "Complete the requested fix.",
        "milestones": [{ "id": "implementation" }],
        "required_checks": mooncode_json_array_items(
          completion_test_contract(),
          "required_checks",
        ),
      },
    },
  }
  let finish_plan : Json = { "planner_mode": "model-tool-calls" }
  let finish_calls : Array[Json] = [
    { "tool": "finish", "arguments": { "answer": "incomplete" } },
  ]
  assert_true(
    mooncode_runtime_turn_recoverable_horizon_finish(
      incomplete_horizon,
      finish_plan,
      finish_calls,
      [{ "tool": "finish", "accepted": true }],
    ),
  )
  let rejection = mooncode_runtime_turn_horizon_finish_rejection_message(
    incomplete_horizon,
    finish_calls,
    [{ "tool": "finish", "accepted": true }],
  )
  assert_true(rejection.contains("Completion was rejected"))
  assert_true(rejection.contains("Continue the same task"))
  assert_false(
    mooncode_runtime_turn_recoverable_horizon_finish(
      { "command": "prompt", "text": "Reply only." },
      finish_plan,
      finish_calls,
      [{ "tool": "finish", "accepted": true }],
    ),
  )
  assert_eq(
    mooncode_runtime_turn_horizon_finish_rejection_message(
      { "command": "prompt", "text": "Reply only." },
      finish_calls,
      [{ "tool": "finish", "accepted": true }],
    ),
    "",
  )
  assert_eq(mooncode_runtime_turn_model_max_steps({}), 0)
  assert_eq(
    mooncode_runtime_turn_model_max_steps({
      "payload": { "planner_max_steps": 0 },
    }),
    0,
  )
  assert_eq(
    mooncode_runtime_turn_model_max_steps({
      "payload": { "planner_max_steps": 99 },
    }),
    99,
  )
  assert_eq(
    mooncode_runtime_turn_model_max_steps({
      "payload": {
        "horizon_id": "phase-plan",
        "task_contract": {
          "objective": "Complete every milestone",
          "milestones": [{ "id": "phase-2" }],
        },
      },
    }),
    0,
  )
  assert_false(
    mooncode_runtime_turn_stops_tool_batch(
      { "planner_mode": "model-tool-calls" },
      { "accepted": false },
    ),
  )
  assert_true(
    mooncode_runtime_turn_stops_tool_batch(
      { "planner_mode": "explicit-tool-calls" },
      { "accepted": false },
    ),
  )
  assert_true(
    mooncode_runtime_turn_stops_tool_batch(
      { "planner_mode": "model-tool-calls" },
      {
        "accepted": true,
        "tool": "shell",
        "result": { "metadata": { "approval_state": "rejected" } },
      },
    ),
  )
  assert_true(
    mooncode_runtime_turn_stops_tool_batch(
      { "planner_mode": "model-tool-calls" },
      {
        "accepted": false,
        "tool": "shell",
        "result": { "metadata": { "pipeline_exit_ambiguous": true } },
      },
    ),
  )
  assert_false(
    mooncode_runtime_turn_stops_tool_batch(
      { "planner_mode": "model-tool-calls" },
      {
        "accepted": true,
        "tool": "shell",
        "result": {
          "ok": true,
          "metadata": { "pipeline_exit_ambiguous": true },
        },
      },
    ),
  )
  assert_true(
    mooncode_runtime_turn_stops_tool_batch(
      { "planner_mode": "model-tool-calls" },
      { "accepted": true, "tool": "read_skill", "result": {} },
    ),
  )
  assert_true(
    mooncode_runtime_turn_stops_tool_batch(
      { "planner_mode": "model-tool-calls" },
      {
        "accepted": false,
        "tool": "read_skill",
        "result": { "is_error": true, "message": "installed skill not found" },
      },
    ),
  )
}

///|
test "mooncode skill boundary keeps safe inspections in one planner batch" {
  let plan : Json = { "planner_mode": "model-tool-calls" }
  let loaded : Json = {
    "accepted": true,
    "tool": "read_skill",
    "result": { "ok": true },
  }
  let status : Json = {
    "tool": "shell",
    "arguments": {
      "cmd": "git status --short | head -60 && echo \"---\" && git log --oneline -8",
    },
  }
  assert_false(
    mooncode_runtime_turn_stops_tool_batch(
      plan,
      loaded,
      skill_boundary_active=true,
      next_tool_call=status,
    ),
  )
  assert_false(
    mooncode_runtime_turn_stops_tool_batch(
      plan,
      { "accepted": true, "tool": "shell", "result": { "ok": true } },
      skill_boundary_active=true,
      next_tool_call={ "tool": "read", "arguments": { "path": "README.md" } },
    ),
  )
}

///|
test "mooncode skill boundary stops before pre-skill mutations" {
  let plan : Json = { "planner_mode": "model-tool-calls" }
  let loaded : Json = {
    "accepted": true,
    "tool": "read_skill",
    "result": { "ok": true },
  }
  assert_true(
    mooncode_runtime_turn_stops_tool_batch(
      plan,
      loaded,
      skill_boundary_active=true,
      next_tool_call={
        "tool": "edit",
        "arguments": {
          "path": "src/main.mbt",
          "old_text": "a",
          "new_text": "b",
        },
      },
    ),
  )
  assert_true(
    mooncode_runtime_turn_stops_tool_batch(
      plan,
      { "accepted": false, "tool": "read_skill", "result": { "ok": false } },
      skill_boundary_active=true,
      next_tool_call={ "tool": "read", "arguments": { "path": "README.md" } },
    ),
  )
}

///|
test "mooncode finish is a hard boundary for its planner tool batch" {
  assert_true(
    mooncode_runtime_turn_stops_tool_batch(
      { "planner_mode": "model-tool-calls" },
      { "accepted": true, "tool": "finish", "result": {} },
    ),
  )
}

///|
test "mooncode native runtime turn emits planner progress events" {
  let plan : Json = {
    "planner_mode": "model-tool-calls",
    "model": "test-model",
    "model_response_message": {
      "role": "assistant",
      "content": "I will inspect the file and then finish.",
    },
  }
  let events = mooncode_runtime_turn_planner_progress_events(
    "session-progress",
    "cmd-progress",
    plan,
    [
      {
        "tool": "read",
        "tool_call_id": "call-read",
        "arguments": { "path": "README.md" },
      },
      {
        "tool": "finish",
        "tool_call_id": "call-finish",
        "arguments": { "answer": "done" },
      },
    ],
    step_index=0,
    now=@clock.Timestamp::from_ms(42L),
  )
  assert_eq(events.length(), 3)
  assert_eq(
    mooncode_json_string(events[0], "kind", default=""),
    "reasoning_delta",
  )
  assert_eq(mooncode_json_string(events[0], "lane", default=""), "runtime")
  assert_eq(mooncode_json_int(events[0], "planner_step", default=0), 1)
  assert_eq(
    mooncode_json_string(events[1], "kind", default=""),
    "assistant_delta",
  )
  assert_true(
    mooncode_json_string(events[1], "content", default="").contains("inspect"),
  )
  assert_eq(mooncode_json_string(events[2], "kind", default=""), "tool_call")
  assert_eq(mooncode_json_string(events[2], "lane", default=""), "diff")
  assert_eq(
    mooncode_json_string(events[2], "tool_call_id", default=""),
    "call-read",
  )
  assert_false(Json::array(events).stringify().contains("call-finish"))
}

///|
async test "mooncode native runtime turn packages an explicit executable tool plan" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-prompt-XXXXXX"),
  )
  let session_id = "session-runtime-prompt"
  let command_id = "cmd-runtime-prompt"
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "text": "Create an executable tool for this MoonBook",
    "model": "codex/gpt-5.6-sol",
    "packet": { "command_id": command_id },
    "runtime_tool_calls": [
      {
        "tool": "write",
        "arguments": {
          "path": "tools/mooncode-generated/cmd-runtime-prompt/run.sh",
          "content": "#!/bin/sh\nset -eu\nprintf 'MoonCode generated tool executed.\\n'\n",
        },
      },
      {
        "tool": "write",
        "arguments": {
          "path": "tools/mooncode-generated/cmd-runtime-prompt/README.md",
          "content": "# Explicit MoonCode Tool\n",
        },
      },
      {
        "tool": "shell",
        "arguments": {
          "cmd": "sh tools/mooncode-generated/cmd-runtime-prompt/run.sh",
          "timeout_ms": 10000,
          "max_output_chars": 4000,
        },
      },
      {
        "tool": "finish",
        "arguments": { "answer": "Created and verified the tool." },
      },
    ],
  }
  mooncode_with_fixture_moonfort(book_root, async fn(config) {
    let command = mooncode_fixture_authorized_runtime_command(
      config, book_root, command,
    )
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_command(),
      {
        "kind": "mooncode-command",
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "command_id": command_id,
        "created_at": @clock.Timestamp::from_ms(2L),
        "command": command,
      },
    )
    mooncode_fixture_approve_runtime_commands(book_root, command)
    let daemon = Daemon::{
      clock: @clock.epoch,
      models: @model.Loader::new(home=@os.home(), cwd=book_root),
      uuid: @uuid.generator(@rand.chacha8()),
      process: @trusted_host_process.DaemonChildManager::new(cwd=book_root),
      by_cwd: {},
      by_id: {},
      rqs: {},
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
    let result = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
      "consumer_id": "test-runtime",
    })
    assert_true(mooncode_json_bool(result, "accepted", default=false))
    let execution = mooncode_json_object_field_or_empty(result, "execution")
    let tool_results = mooncode_json_array_items(execution, "tool_results")
    assert_eq(tool_results.length(), 4)
    assert_true(
      execution.stringify().contains("MoonCode generated tool executed."),
    )
    let script_path = @pathx.join(
      book_root, "tools/mooncode-generated/cmd-runtime-prompt/run.sh",
    )
    let readme_path = @pathx.join(
      book_root, "tools/mooncode-generated/cmd-runtime-prompt/README.md",
    )
    assert_true(@fsx.exists(script_path))
    assert_true(@fsx.exists(readme_path))
    let package_results = mooncode_json_array_items(result, "package_results")
    assert_eq(package_results.length(), 1)
    assert_eq(
      mooncode_json_string(package_results[0], "event", default=""),
      "package_built",
    )
    let manifest_path = @pathx.join(
      book_root, "portable/app-tool/mooncode/session-runtime-prompt/package-cmd-runtime-prompt.json",
    )
    let index_path = @pathx.join(
      book_root, "portable/app-tool/mooncode/session-runtime-prompt/index.json",
    )
    assert_true(@fsx.exists(manifest_path))
    assert_true(@fsx.exists(index_path))
    let manifest_text = @fsx.read_file(manifest_path)
    assert_true(manifest_text.contains("mooncode-package-manifest"))
    assert_true(manifest_text.contains("\"package_kind\""))
    assert_true(manifest_text.contains("\"tool\""))
    assert_true(
      manifest_text.contains("\"source_promotion_status\": \"promoted\""),
    )
    assert_true(manifest_text.contains("\"promoted_source_count\": 2"))
    assert_true(manifest_text.contains("\"sha256_base64\""))
    assert_true(manifest_text.contains("\"promoted_path\""))
    let promoted_script_path = @pathx.join(
      book_root, "portable/app-tool/mooncode/session-runtime-prompt/sources/cmd-runtime-prompt/tools/mooncode-generated/cmd-runtime-prompt/run.sh",
    )
    let promoted_readme_path = @pathx.join(
      book_root, "portable/app-tool/mooncode/session-runtime-prompt/sources/cmd-runtime-prompt/tools/mooncode-generated/cmd-runtime-prompt/README.md",
    )
    assert_true(@fsx.exists(promoted_script_path))
    assert_true(@fsx.exists(promoted_readme_path))
    assert_eq(@fsx.read_file(promoted_script_path), @fsx.read_file(script_path))
    let package_log = @fsx.read_file(
      mooncode_session_journal_path(book_root, session_id),
    )
    assert_true(package_log.contains("\"package_built\""))
    assert_false(package_log.contains("\"event\":\"package_verified\""))
    let book_results = mooncode_json_array_items(result, "book_results")
    assert_eq(book_results.length(), 1)
    let book_result_record = book_results[0]
    assert_eq(
      mooncode_json_string(book_result_record, "protocol", default=""),
      "moonbook.executable_event.v1",
    )
    assert_eq(
      mooncode_json_string(book_result_record, "command_id", default=""),
      command_id,
    )
    let result_id = mooncode_json_string(
      book_result_record,
      "result_id",
      default="",
    )
    assert_true(result_id.contains("cmd-runtime-prompt"))
    let book_result = mooncode_json_object_field_or_empty(
      book_result_record, "book_result",
    )
    assert_eq(
      mooncode_json_string(book_result, "result_id", default=""),
      result_id,
    )
    assert_eq(mooncode_json_string(book_result, "task_id", default=""), "")
    assert_true(
      mooncode_json_bool(book_result, "requires_review", default=false),
    )
    assert_true(mooncode_json_bool(book_result, "notify_town", default=false))
    assert_true(
      book_result
      .stringify()
      .contains("tools/mooncode-generated/cmd-runtime-prompt/run.sh"),
    )
    let book_event = mooncode_json_object_field_or_empty(
      book_result_record, "executable_book_event",
    )
    assert_eq(
      mooncode_json_string(book_event, "command_id", default=""),
      command_id,
    )
    assert_eq(
      mooncode_json_string(book_event, "result_id", default=""),
      result_id,
    )
    assert_eq(
      mooncode_json_string(book_event, "event_type", default=""),
      "review_required",
    )
    assert_true(!mooncode_json_bool(book_event, "accepted", default=true))
    let result_path = @pathx.join(
      book_root, "portable/app-tool/mooncode/session-runtime-prompt/book-result-cmd-runtime-prompt.json",
    )
    assert_true(@fsx.exists(result_path))
    let book_result_log = @fsx.read_file(
      mooncode_session_journal_path(book_root, session_id),
    )
    assert_true(book_result_log.contains("\"mooncode-book-result\""))
    assert_true(book_result_log.contains("\"moonbook.executable_event.v1\""))
    let events_log = @fsx.read_file(
      mooncode_session_journal_path(book_root, session_id),
    )
    assert_true(events_log.contains("\"runtime.turn_started\""))
    assert_true(events_log.contains("\"tool_result\""))
    assert_true(events_log.contains("\"finish\""))
    assert_true(events_log.contains("\"runtime.package_built\""))
    assert_false(events_log.contains("\"runtime.package_verified\""))
    assert_true(events_log.contains("\"runtime.turn_finished\""))
  })
}

///|
async test "mooncode package inventory expands a MoonBit module from one changed manifest" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-package-tree-XXXXXX"),
  )
  for
    item in [
      ("tools/validator/moon.mod", "name = \"example/validator\"\n"),
      ("tools/validator/src/moon.pkg", "options(\"is-main\": true)\n"),
      ("tools/validator/src/main.mbt", "fn main { println(\"ok\") }\n"),
      ("tools/validator/fixtures/valid.json", "{}\n"),
      ("tools/validator/_build/generated.txt", "ignore\n"),
      ("tools/validator/.git/config", "ignore\n"),
    ] {
    let (path, content) = item
    let absolute = @pathx.join(book_root, path)
    @fsx.make_directory(
      @pathx.dirname(absolute),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(absolute, content)
  }
  let paths = mooncode_runtime_turn_package_paths(book_root, {
    "tool_results": [
      {
        "accepted": true,
        "tool": "edit",
        "result": { "metadata": { "path": "tools/validator/src/moon.pkg" } },
      },
    ],
  })
  assert_true(
    mooncode_runtime_turn_string_array_contains(
      paths, "tools/validator/moon.mod",
    ),
  )
  assert_true(
    mooncode_runtime_turn_string_array_contains(
      paths, "tools/validator/src/main.mbt",
    ),
  )
  assert_true(
    mooncode_runtime_turn_string_array_contains(
      paths, "tools/validator/fixtures/valid.json",
    ),
  )
  assert_false(
    paths.any(path => path.contains("/_build/") || path.contains("/.git/")),
  )
}

///|
async test "mooncode native runtime turn emits run_tests proof" (t : @test.Test) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-tests-XXXXXX"),
  )
  @fsx.write_to_file(
    @pathx.join(book_root, "moon.mod"),
    "name = \"mooncode/runtime_tests_fixture\"\nversion = \"0.0.1\"\npreferred_target = \"native\"\n",
  )
  @fsx.write_to_file(@pathx.join(book_root, "moon.pkg"), "")
  @fsx.write_to_file(
    @pathx.join(book_root, "lib.mbt"),
    "///|\npub fn answer() -> Int {\n  42\n}\n",
  )
  let session_id = "session-runtime-tests"
  let command_id = "cmd-runtime-tests"
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "run_tests",
    "model": "codex/gpt-5.6-sol",
    "packet": { "command_id": command_id },
  }
  mooncode_with_fixture_moonfort(book_root, async fn(_) {
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_command(),
      {
        "kind": "mooncode-command",
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "command_id": command_id,
        "created_at": @clock.Timestamp::from_ms(5L),
        "command": command,
      },
    )
    let daemon = Daemon::{
      clock: @clock.epoch,
      models: @model.Loader::new(home=@os.home(), cwd=book_root),
      uuid: @uuid.generator(@rand.chacha8()),
      process: @trusted_host_process.DaemonChildManager::new(cwd=book_root),
      by_cwd: {},
      by_id: {},
      rqs: {},
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
    let result = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
      "consumer_id": "test-runtime",
    })
    assert_true(mooncode_json_bool(result, "accepted", default=false))
    let execution = mooncode_json_object_field_or_empty(result, "execution")
    let tool_results = mooncode_json_array_items(execution, "tool_results")
    assert_eq(tool_results.length(), 3)
    assert_eq(
      mooncode_json_string(tool_results[0], "tool", default=""),
      "moon_cmd",
    )
    assert_eq(
      mooncode_json_string(tool_results[1], "tool", default=""),
      "moon_check",
    )
    let test_results = mooncode_json_array_items(execution, "test_results")
    assert_eq(test_results.length(), 1)
    assert_eq(
      mooncode_json_string(test_results[0], "kind", default=""),
      "test_result",
    )
    assert_eq(
      mooncode_json_string(test_results[0], "test_status", default=""),
      "passed",
    )
    assert_eq(mooncode_json_int(test_results[0], "exit_status", default=-1), 0)
    assert_eq(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(test_results[0], "command_packet"),
        "command_id",
        default="",
      ),
      command_id,
    )
    let events_log = @fsx.read_file(
      mooncode_session_journal_path(book_root, session_id),
    )
    assert_true(events_log.contains("\"moon_cmd.finished\""))
    assert_true(events_log.contains("\"moon_check.finished\""))
    assert_true(events_log.contains("\"test_result\""))
    assert_true(events_log.contains("\"test_status\":\"passed\""))
    assert_true(events_log.contains("\"runtime.turn_finished\""))
  })
}

///|
async test "mooncode native runtime turn emits run_build proof" (t : @test.Test) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-build-XXXXXX"),
  )
  @fsx.write_to_file(
    @pathx.join(book_root, "moon.mod"),
    "name = \"mooncode/runtime_build_fixture\"\nversion = \"0.0.1\"\npreferred_target = \"native\"\n",
  )
  @fsx.write_to_file(@pathx.join(book_root, "moon.pkg"), "")
  @fsx.write_to_file(
    @pathx.join(book_root, "lib.mbt"),
    "///|\npub fn answer() -> Int {\n  42\n}\n",
  )
  let session_id = "session-runtime-build"
  let command_id = "cmd-runtime-build"
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "run_build",
    "model": "codex/gpt-5.6-sol",
    "packet": { "command_id": command_id },
  }
  mooncode_with_fixture_moonfort(book_root, async fn(_) {
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_command(),
      {
        "kind": "mooncode-command",
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "command_id": command_id,
        "created_at": @clock.Timestamp::from_ms(5L),
        "command": command,
      },
    )
    let daemon = Daemon::{
      clock: @clock.epoch,
      models: @model.Loader::new(home=@os.home(), cwd=book_root),
      uuid: @uuid.generator(@rand.chacha8()),
      process: @trusted_host_process.DaemonChildManager::new(cwd=book_root),
      by_cwd: {},
      by_id: {},
      rqs: {},
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
    let result = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
      "consumer_id": "test-runtime",
    })
    assert_true(mooncode_json_bool(result, "accepted", default=false))
    let execution = mooncode_json_object_field_or_empty(result, "execution")
    let tool_results = mooncode_json_array_items(execution, "tool_results")
    assert_eq(tool_results.length(), 3)
    assert_eq(
      mooncode_json_string(tool_results[0], "tool", default=""),
      "moon_cmd",
    )
    let moon_cmd_metadata = mooncode_json_object_field_or_empty(
      mooncode_json_object_field_or_empty(tool_results[0], "result"),
      "metadata",
    )
    assert_eq(
      mooncode_json_string(moon_cmd_metadata, "moon_command", default=""),
      "build",
    )
    assert_eq(
      mooncode_json_string(tool_results[1], "tool", default=""),
      "moon_check",
    )
    let test_results = mooncode_json_array_items(execution, "test_results")
    assert_eq(test_results.length(), 1)
    assert_eq(
      mooncode_json_string(test_results[0], "kind", default=""),
      "test_result",
    )
    assert_eq(
      mooncode_json_string(test_results[0], "test_status", default=""),
      "passed",
    )
    assert_eq(mooncode_json_int(test_results[0], "exit_status", default=-1), 0)
    assert_eq(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(test_results[0], "command_packet"),
        "command_id",
        default="",
      ),
      command_id,
    )
    let events_log = @fsx.read_file(
      mooncode_session_journal_path(book_root, session_id),
    )
    assert_true(events_log.contains("\"moon_cmd.finished\""))
    assert_true(events_log.contains("\"moon_command\":\"build\""))
    assert_true(events_log.contains("\"moon_check.finished\""))
    assert_true(events_log.contains("\"test_result\""))
    assert_true(events_log.contains("\"test_status\":\"passed\""))
    assert_true(events_log.contains("\"runtime.turn_finished\""))
  })
}
