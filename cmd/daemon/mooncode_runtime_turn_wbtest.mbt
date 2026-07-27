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
  let result = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
    "consumer_id": "test-runtime",
  })
  assert_true(mooncode_json_bool(result, "accepted", default=false))
  assert_eq(mooncode_json_string(result, "command_id", default=""), command_id)
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
test "mooncode user prompts require model planning instead of canned artifacts" {
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Create an executable tool for this MoonBook",
    "packet": { "command_id": "cmd-planner" },
  }
  let calls = mooncode_runtime_turn_tool_calls(command)
  assert_eq(calls.length(), 0)
  assert_eq(mooncode_runtime_turn_deterministic_preplan(command).length(), 0)
  assert_true(mooncode_runtime_turn_requires_model_planning(command))
  let miniapp : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Build a tiny html miniapp",
    "packet": { "command_id": "cmd-miniapp" },
  }
  let miniapp_calls = mooncode_runtime_turn_tool_calls(miniapp)
  assert_eq(miniapp_calls.length(), 0)
  assert_eq(mooncode_runtime_turn_deterministic_preplan(miniapp).length(), 0)
  assert_true(mooncode_runtime_turn_requires_model_planning(miniapp))
  let engineering_prompt : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Implement a substantive reusable MoonBit validator and command-line tool in the existing module. Read external criteria, validate unknown and required fields, add positive and negative fixtures, add automated tests, produce deterministic machine-readable output, run moon check and moon test, and fix every failure before finishing. Do not generate a placeholder script.",
    "model": "test-model",
    "packet": { "command_id": "cmd-engineering" },
  }
  assert_eq(
    mooncode_runtime_turn_deterministic_preplan(engineering_prompt).length(),
    0,
  )
  assert_true(mooncode_runtime_turn_requires_model_planning(engineering_prompt))
  let implementation_with_negative_read : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Apply a focused repair to tools/decision-packet. Do not read fixtures from a helper; implement the CLI and run tests.",
    "model": "test-model",
    "packet": { "command_id": "cmd-negative-read" },
  }
  assert_eq(
    mooncode_runtime_turn_deterministic_preplan(
      implementation_with_negative_read,
    ).length(),
    0,
  )
  assert_true(
    mooncode_runtime_turn_requires_model_planning(
      implementation_with_negative_read,
    ),
  )
  let engineering_fallback = mooncode_runtime_turn_tool_calls(
    engineering_prompt,
  )
  assert_eq(engineering_fallback.length(), 0)
  assert_false(
    Json::array(engineering_fallback).stringify().contains("\"tool\":\"write\""),
  )
  let steer : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "steer",
    "text": "Create an executable tool, but keep the next turn focused",
    "packet": { "command_id": "cmd-steer" },
    "model": "test-model",
  }
  let steer_calls = mooncode_runtime_turn_tool_calls(steer)
  assert_eq(steer_calls.length(), 1)
  assert_eq(mooncode_json_string(steer_calls[0], "tool", default=""), "finish")
  assert_true(mooncode_runtime_turn_model_planning_allowed(steer))
  let accept : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "accept",
    "packet": { "command_id": "cmd-accept" },
    "model": "test-model",
  }
  let accept_calls = mooncode_runtime_turn_tool_calls(accept)
  assert_eq(accept_calls.length(), 1)
  assert_eq(mooncode_json_string(accept_calls[0], "tool", default=""), "finish")
  assert_false(mooncode_runtime_turn_model_planning_allowed(accept))
  let commit : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "commit",
    "packet": { "command_id": "cmd-commit" },
    "model": "test-model",
  }
  let commit_calls = mooncode_runtime_turn_tool_calls(commit)
  assert_eq(commit_calls.length(), 1)
  assert_eq(mooncode_json_string(commit_calls[0], "tool", default=""), "finish")
  assert_false(mooncode_runtime_turn_model_planning_allowed(commit))

  let read : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Read README.md.",
    "model": "codex/gpt-5.6-sol",
    "packet": { "command_id": "cmd-read" },
  }
  let read_calls = mooncode_runtime_turn_deterministic_preplan(read)
  assert_eq(read_calls.length(), 2)
  assert_eq(mooncode_json_string(read_calls[0], "tool", default=""), "read")
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(read_calls[0], "arguments"),
      "path",
      default="",
    ),
    "README.md",
  )
  assert_true(mooncode_runtime_turn_requires_model_planning(read))

  let write : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Create tools/e2e-fixed.txt in this MoonBook with exactly ROOT_OK, then reply that it is done.",
    "model": "codex/gpt-5.6-sol",
    "packet": { "command_id": "cmd-write" },
  }
  let write_calls = mooncode_runtime_turn_deterministic_preplan(write)
  assert_eq(write_calls.length(), 2)
  assert_eq(mooncode_json_string(write_calls[0], "tool", default=""), "write")
  let write_arguments = mooncode_json_object_field_or_empty(
    write_calls[0],
    "arguments",
  )
  assert_eq(
    mooncode_json_string(write_arguments, "path", default=""),
    "tools/e2e-fixed.txt",
  )
  assert_eq(
    mooncode_json_string(write_arguments, "content", default=""),
    "ROOT_OK",
  )
  assert_true(mooncode_runtime_turn_requires_model_planning(write))
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
test "mooncode model planner sends a compact request envelope" {
  let command : Json = {
    "command": "prompt",
    "text": "Reply briefly with MODEL_OK.",
    "context_path": "README.md",
    "web_search": false,
    "packet": {
      "command_id": "cmd-compact",
      "tool_contract": { "very_large": "must not be copied" },
      "result_contract": { "very_large": "must not be copied" },
    },
  }
  let prompt = mooncode_runtime_turn_model_prompt(command)
  assert_true(prompt.contains("Reply briefly with MODEL_OK."))
  assert_true(prompt.contains("Selected context: `README.md`."))
  assert_false(prompt.contains("tool_contract"))
  assert_false(prompt.contains("result_contract"))
  assert_true(prompt.length() < 1000)

  let chat_tools = mooncode_runtime_turn_model_tools_for_command(command)
  assert_eq(chat_tools.length(), 1)
  assert_true(chat_tools.to_json().stringify().contains("finish"))
  assert_true(chat_tools.to_json().stringify().contains("goal_runtime"))
  assert_true(chat_tools.to_json().stringify().contains("achieved"))
  assert_true(chat_tools.to_json().stringify().contains("blocked"))
  assert_false(chat_tools.to_json().stringify().contains("moon_check"))

  let goal_prompt = mooncode_runtime_turn_model_prompt({
    "command": "prompt",
    "text": "Continue the goal",
    "goal_runtime": {
      "goal_id": "goal-1",
      "objective": "Complete all work",
      "criteria": [{ "id": "criterion-1", "criterion": "tests pass" }],
      "status": { "terminal": false },
    },
  })
  assert_true(goal_prompt.contains("Active long-running goal"))
  assert_true(goal_prompt.contains("criterion-1"))
  assert_true(goal_prompt.contains("Do not infer completion from a turn limit"))

  let plan_request = mooncode_runtime_turn_model_plan_request(
    "gpt-5.6-sol", command,
  ).to_json()
  assert_eq(
    mooncode_json_string(plan_request, "reasoning_effort", default=""),
    "none",
  )

  let summary : Json = {
    "command": "prompt",
    "text": "Read README.md and summarize it.",
  }
  let summary_tools = mooncode_runtime_turn_model_tools_for_command(summary)
  assert_eq(summary_tools.length(), 2)
  let summary_json = summary_tools.to_json().stringify()
  assert_true(summary_json.contains("read"))
  assert_true(summary_json.contains("finish"))
  assert_false(summary_json.contains("moon_check"))

  let coding : Json = {
    "command": "prompt",
    "text": "Fix the parser and run tests.",
  }
  assert_eq(mooncode_runtime_turn_model_tools_for_command(coding).length(), 10)
  assert_eq(
    mooncode_runtime_turn_language_grounding({
      "text": "Write a TypeScript file",
    }),
    "",
  )
  let coding_with_path : Json = {
    "command": "prompt",
    "text": "Edit first. The scaffold has already been read. Overwrite tools/robot-design-validator/src/main.mbt with a substantive validator, then add tests, fixtures, and a README; run moon check and moon test before finishing. Implement the result; do not merely explain it.",
  }
  assert_eq(
    mooncode_runtime_turn_model_tools_for_command(coding_with_path).length(),
    10,
  )
  let grounding = mooncode_runtime_turn_language_grounding(coding_with_path)
  assert_true(grounding.contains("Json` is a built-in type"))
  assert_true(grounding.contains("do not inspect SDK files"))

  let codex = @model.codex_oauth_model(
    access_token="test",
    account_id="test",
    refresh_token="test",
  )
  assert_true(
    mooncode_runtime_turn_model_timeout_for_provider(codex, command) is None,
  )
  let direct = @model.Model::new(
    api_key="test",
    base_url="https://example.invalid/v1",
    name="test-model",
    safe_zone_tokens=1000,
  )
  assert_true(
    mooncode_runtime_turn_model_timeout_for_provider(direct, command)
    is Some(60000),
  )
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
  assert_eq(messages.length(), 4)
  assert_eq(mooncode_json_string(messages[2], "role", default=""), "user")
  assert_true(
    mooncode_json_string(messages[2], "content", default="").contains(
      "steer-live-1",
    ),
  )
  assert_true(
    mooncode_json_string(messages[3], "content", default="").contains(
      "must include `finish`",
    ),
  )
}

///|
test "mooncode reserves and enforces the terminal planner opportunity" {
  assert_true(
    mooncode_runtime_turn_model_terminal_boundary_message(2).contains(
      "two planner opportunities remain",
    ),
  )
  assert_true(
    mooncode_runtime_turn_model_terminal_boundary_message(1).contains(
      "must include `finish`",
    ),
  )
  assert_eq(mooncode_runtime_turn_model_terminal_boundary_message(3), "")
  let read_plan : Json = {
    "planner_mode": mooncode_planner_mode_model_tool_calls(),
    "tool_calls": [{ "tool": "read", "arguments": { "path": "README.md" } }],
  }
  assert_eq(mooncode_runtime_turn_terminal_plan_violation(read_plan, 6, 8), "")
  assert_true(
    mooncode_runtime_turn_terminal_plan_violation(read_plan, 7, 8).contains(
      "did not include `finish`",
    ),
  )
  let shell_finish : Json = {
    "planner_mode": mooncode_planner_mode_model_tool_calls(),
    "tool_calls": [
      { "tool": "shell", "arguments": { "cmd": "moon test" } },
      { "tool": "finish", "arguments": { "answer": "done" } },
    ],
  }
  assert_true(
    mooncode_runtime_turn_terminal_plan_violation(shell_finish, 7, 8).contains(
      "nonterminal tool `shell`",
    ),
  )
  let verified_finish : Json = {
    "planner_mode": mooncode_planner_mode_model_tool_calls(),
    "tool_calls": [
      {
        "tool": "moon_cmd",
        "arguments": { "command": "test", "path": "cmd/daemon" },
      },
      { "tool": "finish", "arguments": { "answer": "done" } },
    ],
  }
  assert_eq(
    mooncode_runtime_turn_terminal_plan_violation(verified_finish, 7, 8),
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
  let first = daemon.mooncode_runtime_turn_claim_live_steering(
    session_id, book_root, prompt_id,
  )
  assert_eq(first.length(), 1)
  assert_eq(mooncode_json_string(first[0], "command_id", default=""), steer_id)
  let events : Array[Json] = []
  let persisted : Map[String, Bool] = {}
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
  let events : Array[Json] = []
  let persisted : Map[String, Bool] = {}
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
  assert_eq(calls.length(), 2)
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
  let arguments = mooncode_json_object_field_or_empty(calls[0], "arguments")
  assert_eq(
    mooncode_json_string(arguments, "answer", default=""),
    "Hello from model.",
  )
}

///|
test "mooncode model execution requires finish and explicit recovery" {
  let coding : Json = {
    "command": "prompt",
    "text": "Implement the validator and run tests.",
  }
  let write_ok : Json = { "tool": "write", "accepted": true }
  let read_failed : Json = { "tool": "read", "accepted": false }
  let read_recovered : Json = { "tool": "read", "accepted": true }
  let test_ok : Json = {
    "tool": "moon_cmd",
    "accepted": true,
    "arguments": { "command": "test" },
  }
  let finish : Json = { "tool": "finish", "accepted": true }
  assert_false(
    mooncode_runtime_turn_model_execution_accepted(coding, [write_ok]),
  )
  assert_false(
    mooncode_runtime_turn_model_execution_accepted(coding, [
      write_ok, read_failed, finish,
    ]),
  )
  assert_false(
    mooncode_runtime_turn_model_execution_accepted(coding, [
      write_ok, read_failed, read_recovered, finish,
    ]),
  )
  assert_true(
    mooncode_runtime_turn_model_execution_accepted(coding, [
      write_ok, read_failed, read_recovered, test_ok, finish,
    ]),
  )
  assert_false(mooncode_runtime_turn_model_execution_accepted(coding, [finish]))
}

///|
test "mooncode coding completion requires mutation followed by verification" {
  let command : Json = { "command": "prompt", "text": "Edit the MoonBit code." }
  let write : Json = { "tool": "write", "accepted": true }
  let edit : Json = { "tool": "edit", "accepted": true }
  let finish : Json = { "tool": "finish", "accepted": true }
  let failed_check : Json = { "tool": "moon_check", "accepted": false }
  let read : Json = { "tool": "read", "accepted": true }
  let good_check : Json = { "tool": "moon_check", "accepted": true }
  assert_false(
    mooncode_runtime_turn_model_execution_accepted(command, [write, finish]),
  )
  assert_false(
    mooncode_runtime_turn_model_execution_accepted(command, [
      write, failed_check, read, finish,
    ]),
  )
  assert_true(
    mooncode_runtime_turn_model_execution_accepted(command, [
      write, good_check, finish,
    ]),
  )
  assert_false(
    mooncode_runtime_turn_model_execution_accepted(command, [
      write, good_check, edit, finish,
    ]),
  )
  assert_false(
    mooncode_runtime_turn_model_execution_accepted(command, [
      write, good_check, failed_check, read, finish,
    ]),
  )
  assert_true(
    mooncode_runtime_turn_model_execution_accepted(command, [
      write, good_check, failed_check, read, good_check, finish,
    ]),
  )
}

///|
test "mooncode coding completion rejects mutations reverted before finish" {
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
  assert_false(reverted.accepted)
  assert_true(reverted.reason.contains("no net mutation"))
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
test "mooncode net mutation tracks multi-file patch fingerprints" {
  let patch : Json = {
    "tool": "apply_patch",
    "accepted": true,
    "result": {
      "metadata": {
        "changed": true,
        "files": [
          {
            "file_path": "src/a.mbt",
            "changed": true,
            "before_fingerprint": "present:a0",
            "after_fingerprint": "present:a1",
          },
          {
            "file_path": "src/b.mbt",
            "changed": true,
            "before_fingerprint": "absent",
            "after_fingerprint": "present:b1",
          },
        ],
      },
    },
  }
  let revert : Json = {
    "tool": "revert_patch",
    "accepted": true,
    "result": {
      "metadata": {
        "changed": true,
        "files": [
          {
            "file_path": "src/a.mbt",
            "changed": true,
            "before_fingerprint": "present:a1",
            "after_fingerprint": "present:a0",
          },
          {
            "file_path": "src/b.mbt",
            "changed": true,
            "before_fingerprint": "present:b1",
            "after_fingerprint": "absent",
          },
        ],
      },
    },
  }
  assert_true(mooncode_runtime_turn_has_net_mutation([patch]))
  assert_false(mooncode_runtime_turn_has_net_mutation([patch, revert]))
}

///|
test "mooncode accepted no-op patch is not mutation evidence" {
  let no_op : Json = {
    "tool": "apply_patch",
    "accepted": true,
    "result": {
      "metadata": {
        "path": "src/already-repaired.mbt",
        "changed": false,
        "diff": "",
      },
    },
  }
  assert_false(mooncode_runtime_turn_has_net_mutation([no_op]))
}

///|
test "mooncode reply-only completion still accepts finish" {
  let command : Json = {
    "command": "prompt",
    "text": "Explain this concept without changing files.",
  }
  assert_true(
    mooncode_runtime_turn_model_execution_accepted(command, [
      { "tool": "finish", "accepted": true },
    ]),
  )
}

///|
test "mooncode explanation of an app does not require mutation" {
  let command : Json = {
    "command": "prompt",
    "text": "Explain what this app does without changing files.",
  }
  let request = mooncode_runtime_turn_prompt_text(command)
    .to_lower()
    .to_string()
  assert_false(mooncode_runtime_turn_model_needs_coding_tools(command, request))
  assert_false(mooncode_runtime_turn_requires_verification(command))
  assert_true(
    mooncode_runtime_turn_model_execution_accepted(command, [
      { "tool": "finish", "accepted": true },
    ]),
  )
  let mutate : Json = {
    "command": "prompt",
    "text": "Review this app and fix the broken MoonBit implementation.",
  }
  let mutate_request = mooncode_runtime_turn_prompt_text(mutate)
    .to_lower()
    .to_string()
  assert_true(
    mooncode_runtime_turn_model_needs_coding_tools(mutate, mutate_request),
  )
  assert_true(mooncode_runtime_turn_requires_verification(mutate))
}

///|
test "mooncode completion verdict requires typed tests when requested" {
  let command : Json = {
    "command": "prompt",
    "text": "Implement the MoonBit fix and run focused tests.",
  }
  let write : Json = { "tool": "write", "accepted": true }
  let check : Json = { "tool": "moon_check", "accepted": true }
  let test_result : Json = {
    "tool": "moon_cmd",
    "accepted": true,
    "arguments": { "command": "test" },
  }
  let finish : Json = { "tool": "finish", "accepted": true }
  let missing_test = mooncode_runtime_turn_completion_verdict(command, [
    write, check, finish,
  ])
  assert_false(missing_test.accepted)
  assert_true(missing_test.reason.contains("typed test"))
  let proven = mooncode_runtime_turn_completion_verdict(command, [
    write, check, test_result, finish,
  ])
  assert_true(proven.accepted)
  assert_true(proven.reason.contains("typed test evidence"))
}

///|
test "mooncode verified patch can prove its own mutation" {
  let command : Json = { "command": "prompt", "text": "Fix validator.mbt." }
  let patch : Json = {
    "tool": "apply_patch",
    "accepted": true,
    "result": { "metadata": { "verification": { "ok": true, "status": 0 } } },
  }
  let finish : Json = { "tool": "finish", "accepted": true }
  let verdict = mooncode_runtime_turn_completion_verdict(command, [
    patch, finish,
  ])
  assert_true(verdict.accepted)
}

///|
test "mooncode completion gate covers explicit coding batches" {
  let coding : Json = {
    "command": "prompt",
    "text": "Implement the parser fix.",
  }
  let reply : Json = { "command": "prompt", "text": "Explain the parser." }
  assert_true(mooncode_runtime_turn_completion_gate_applies(coding, false))
  assert_false(mooncode_runtime_turn_completion_gate_applies(reply, false))
  assert_true(mooncode_runtime_turn_completion_gate_applies(reply, true))
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
test "mooncode model execution does not mistake Codex for code intent" {
  let reply_only : Json = {
    "command": "prompt",
    "text": "Reply exactly MOONDESK_CODEX_OK. Do not change any files.",
  }
  let finish : Json = { "tool": "finish", "accepted": true }
  assert_false(
    mooncode_runtime_turn_model_needs_coding_tools(
      reply_only,
      mooncode_runtime_turn_prompt_text(reply_only).to_lower().to_string(),
    ),
  )
  assert_true(
    mooncode_runtime_turn_model_execution_accepted(reply_only, [finish]),
  )
}

///|
test "mooncode model execution does not mistake reply text for test intent" {
  let reply_only : Json = {
    "command": "prompt",
    "text": "Reply with exactly: MoonDesk UI test passed.",
  }
  let finish : Json = { "tool": "finish", "accepted": true }
  assert_false(
    mooncode_runtime_turn_model_needs_coding_tools(
      reply_only,
      mooncode_runtime_turn_prompt_text(reply_only).to_lower().to_string(),
    ),
  )
  assert_true(
    mooncode_runtime_turn_model_execution_accepted(reply_only, [finish]),
  )
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
  let oversized = mooncode_runtime_turn_model_tool_result_content({
    "result": { "output": "x".repeat(9000) },
  })
  assert_true(oversized.length() < 4100)
  assert_true(oversized.contains("truncated for planner context"))
  let transcript : Array[Json] = [
    {
      "role": "assistant",
      "tool_calls": [{ "function": { "name": "read", "arguments": "{}" } }],
    },
    {
      "role": "assistant",
      "tool_calls": [{ "function": { "name": "edit", "arguments": "{}" } }],
    },
  ]
  assert_eq(mooncode_runtime_turn_model_completed_steps(transcript), 2)
  assert_true(mooncode_runtime_turn_model_transcript_has_mutation(transcript))
  assert_false(
    mooncode_runtime_turn_model_transcript_has_mutation([transcript[0]]),
  )
  assert_true(!mooncode_runtime_turn_tool_calls_include_finish(calls))
  assert_true(
    mooncode_runtime_turn_tool_calls_include_finish([
      { "tool": "finish", "arguments": { "answer": "done" } },
    ]),
  )
  assert_eq(mooncode_runtime_turn_model_max_steps({}), 8)
  assert_eq(
    mooncode_runtime_turn_model_max_steps({
      "payload": { "planner_max_steps": 0 },
    }),
    1,
  )
  assert_eq(
    mooncode_runtime_turn_model_max_steps({
      "payload": { "planner_max_steps": 99 },
    }),
    20,
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
test "mooncode model planner rejects only stale duplicate complete reads" {
  let read_call : Json = {
    "tool": "read",
    "arguments": { "path": "src/main.mbt", "max_output_chars": 12000 },
  }
  let complete_read : Json = {
    "accepted": true,
    "tool": "read",
    "arguments": { "path": "src/main.mbt", "max_output_chars": 12000 },
    "result": { "metadata": { "truncated": false } },
  }
  assert_true(
    mooncode_runtime_turn_repeats_complete_read(read_call, [complete_read]),
  )
  assert_false(
    mooncode_runtime_turn_repeats_complete_read(
      { "tool": "read", "arguments": { "path": "src/other.mbt" } },
      [complete_read],
    ),
  )
  assert_false(
    mooncode_runtime_turn_repeats_complete_read(read_call, [
      {
        "accepted": true,
        "tool": "read",
        "arguments": { "path": "src/main.mbt" },
        "result": { "metadata": { "truncated": true } },
      },
    ]),
  )
  let edit : Json = {
    "accepted": true,
    "tool": "edit",
    "arguments": { "path": "src/main.mbt" },
  }
  assert_false(
    mooncode_runtime_turn_repeats_complete_read(read_call, [complete_read, edit]),
  )
  assert_true(
    mooncode_runtime_turn_repeats_complete_read(read_call, [
      complete_read, edit, complete_read,
    ]),
  )
  assert_false(
    mooncode_runtime_turn_repeats_complete_read(
      { "tool": "edit", "arguments": { "path": "src/main.mbt" } },
      [complete_read],
    ),
  )
}

///|
test "mooncode rejects comment-only implementation mutations before execution" {
  let repair : Json = {
    "command": "prompt",
    "text": "Implement the runtime defect repair and run tests.",
  }
  let comment_edit : Json = {
    "tool": "edit",
    "arguments": {
      "path": "src/runtime.mbt",
      "old_string": "pub fn supported(name : String) -> Bool {",
      "new_string": "/// Returns whether the name is supported.\n/// Aliases are normalized before lookup.\npub fn supported(name : String) -> Bool {",
    },
  }
  assert_true(mooncode_runtime_turn_comment_only_repair(repair, comment_edit))
  let rejected = mooncode_runtime_turn_comment_only_repair_execution(
    "session-comment-only",
    "/tmp/book",
    "command-comment-only",
    comment_edit,
    now=@clock.Timestamp::from_ms(1L),
  )
  assert_false(mooncode_json_bool(rejected, "accepted", default=true))
  assert_true(
    mooncode_json_bool(
      mooncode_json_object_field_or_empty(
        mooncode_json_object_field_or_empty(rejected, "result"),
        "metadata",
      ),
      "comment_only_repair",
      default=false,
    ),
  )
  let substantive_edit : Json = {
    "tool": "edit",
    "arguments": {
      "path": "src/runtime.mbt",
      "old_string": "runtime_tool_names().contains(name)",
      "new_string": "runtime_tool_names().contains(canonical_name(name))",
    },
  }
  assert_false(
    mooncode_runtime_turn_comment_only_repair(repair, substantive_edit),
  )
  let comment_patch : Json = {
    "tool": "apply_patch",
    "arguments": {
      "diff": "--- a/src/runtime.mbt\n+++ b/src/runtime.mbt\n@@\n+/// Aliases are normalized before lookup.\n",
    },
  }
  assert_true(mooncode_runtime_turn_comment_only_repair(repair, comment_patch))
  let explanation : Json = {
    "command": "prompt",
    "text": "Document how the runtime alias lookup works.",
  }
  assert_false(
    mooncode_runtime_turn_comment_only_repair(explanation, comment_edit),
  )
  let initial = mooncode_runtime_turn_model_initial_messages(repair)
  assert_true(
    mooncode_json_string(initial[0], "content", default="").contains(
      "comment-only or documentation-only mutation does not satisfy",
    ),
  )
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
  assert_eq(package_results.length(), 2)
  assert_eq(
    mooncode_json_string(package_results[0], "event", default=""),
    "package_built",
  )
  assert_eq(
    mooncode_json_string(package_results[1], "event", default=""),
    "package_verified",
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
  assert_true(package_log.contains("\"package_verified\""))
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
  assert_true(mooncode_json_bool(book_result, "requires_review", default=false))
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
  assert_true(events_log.contains("\"runtime.package_verified\""))
  assert_true(events_log.contains("\"runtime.turn_finished\""))
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
    @pathx.join(book_root, "moon.mod.json"),
    "{\n  \"name\": \"mooncode/runtime_tests_fixture\",\n  \"version\": \"0.0.1\",\n  \"deps\": {},\n  \"preferred-target\": \"native\"\n}\n",
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
}

///|
async test "mooncode native runtime turn emits run_build proof" (t : @test.Test) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-build-XXXXXX"),
  )
  @fsx.write_to_file(
    @pathx.join(book_root, "moon.mod.json"),
    "{\n  \"name\": \"mooncode/runtime_build_fixture\",\n  \"version\": \"0.0.1\",\n  \"deps\": {},\n  \"preferred-target\": \"native\"\n}\n",
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
}
