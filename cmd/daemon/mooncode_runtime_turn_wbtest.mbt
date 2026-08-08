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
  assert_eq(chat_tools.length(), 2)
  assert_true(chat_tools.to_json().stringify().contains("finish"))
  assert_false(chat_tools.to_json().stringify().contains("goal_runtime"))
  assert_false(chat_tools.to_json().stringify().contains("achieved"))
  assert_false(chat_tools.to_json().stringify().contains("blocked"))
  assert_true(chat_tools.to_json().stringify().contains("read_skill"))
  assert_false(chat_tools.to_json().stringify().contains("moon_check"))

  let plan_request = mooncode_runtime_turn_model_plan_request(
    "gpt-5.6-sol", command,
  ).to_json()
  assert_eq(mooncode_json_int(plan_request, "max_tokens", default=0), 1200)
  assert_eq(
    mooncode_json_string(plan_request, "reasoning_effort", default=""),
    "none",
  )
  let kimi_request = mooncode_runtime_turn_model_plan_request(
    "moongate/kimi-k3", command,
  ).to_json()
  assert_eq(mooncode_json_int(kimi_request, "max_tokens", default=0), 2000)
  let deepseek_request = mooncode_runtime_turn_model_plan_request(
    "moongate/deepseek-v4-flash", command,
  ).to_json()
  assert_eq(mooncode_json_int(deepseek_request, "max_tokens", default=0), 2000)

  let summary : Json = {
    "command": "prompt",
    "text": "Read README.md and summarize it.",
  }
  let summary_tools = mooncode_runtime_turn_model_tools_for_command(summary)
  assert_eq(summary_tools.length(), 3)
  let summary_json = summary_tools.to_json().stringify()
  assert_true(summary_json.contains("read"))
  assert_true(summary_json.contains("finish"))
  assert_false(summary_json.contains("moon_check"))

  let coding : Json = {
    "command": "prompt",
    "text": "Fix the parser and run tests.",
  }
  let coding_tools = mooncode_runtime_turn_model_tools_for_command(coding).map(tool => {
    tool.to_json().stringify()
  })
  for tool_name in ["edit", "apply_patch", "spawn_workers", "wait_workers"] {
    assert_true(
      coding_tools.any(tool => tool.contains("\"name\":\"\{tool_name}\"")),
    )
  }

  let ui_command : Json = {
    "command": "prompt",
    "text": "Test the app UI in the browser and fix the interaction.",
  }
  let ui_tools = mooncode_runtime_turn_model_tools_for_command(ui_command).map(tool => {
    tool.to_json().stringify()
  })
  assert_true(ui_tools.any(tool => tool.contains("\"name\":\"browser\"")))
  assert_true(ui_tools.any(tool => tool.contains("@ prefix")))
  assert_true(ui_tools.any(tool => tool.contains("Visible labels")))

  let workspace_prompts = [
    "Complete the Phase 4 extraction", "Replace the legacy boundary with the typed provider",
    "Reshape the extraction boundary around the typed provider", "Separate the legacy boundary from the typed provider",
  ]
  for text in workspace_prompts {
    let command : Json = {
      "command": "prompt",
      "text": text,
      "payload": { "task_intent": "workspace_change" },
    }
    let tools = mooncode_runtime_turn_model_tools_for_command(command)
    let serialized_tools = tools.map(tool => tool.to_json().stringify())
    for
      tool_name in [
        "edit", "apply_patch", "shell", "spawn_workers", "wait_workers",
      ] {
      assert_true(
        serialized_tools.any(tool => tool.contains("\"name\":\"\{tool_name}\"")),
      )
    }
    assert_true(mooncode_runtime_turn_requires_verification(command))
  }

  let review_prompts = [
    "Review the app code for naming consistency.", "Review the code for the app boundary.",
  ]
  for text in review_prompts {
    let command : Json = {
      "command": "prompt",
      "text": text,
      "payload": { "task_intent": "read_only" },
    }
    assert_eq(
      mooncode_runtime_turn_model_tools_for_command(command).length(),
      2,
    )
    assert_false(mooncode_runtime_turn_requires_verification(command))
  }

  let fallback_prompt = "Fix the parser and run tests."
  let absent_hint : Json = { "command": "prompt", "text": fallback_prompt }
  let unknown_hint : Json = {
    "command": "prompt",
    "text": fallback_prompt,
    "payload": { "task_intent": "deployment" },
  }
  assert_eq(
    mooncode_runtime_turn_model_tools_for_command(absent_hint).length(),
    mooncode_runtime_turn_model_tools_for_command(unknown_hint).length(),
  )
  assert_eq(
    mooncode_runtime_turn_requires_verification(absent_hint),
    mooncode_runtime_turn_requires_verification(unknown_hint),
  )

  let coding_with_path : Json = {
    "command": "prompt",
    "text": "Edit first. The scaffold has already been read. Overwrite tools/robot-design-validator/src/main.mbt with a substantive validator, then add tests, fixtures, and a README; run moon check and moon test before finishing. Implement the result; do not merely explain it.",
  }
  let coding_with_path_tools = mooncode_runtime_turn_model_tools_for_command(
    coding_with_path,
  ).map(tool => tool.to_json().stringify())
  for tool_name in ["edit", "apply_patch", "spawn_workers", "wait_workers"] {
    assert_true(
      coding_with_path_tools.any(tool => {
        tool.contains("\"name\":\"\{tool_name}\"")
      }),
    )
  }
  let initial = mooncode_runtime_turn_model_initial_messages(
    coding_with_path,
    skill_catalog="\n<available_skills><skill><name>moonbit-agent-guide</name></skill></available_skills>",
  )
  let system = mooncode_json_string(initial[0], "content", default="")
  assert_true(system.contains("read_skill"))
  assert_true(system.contains("moonbit-agent-guide"))
  assert_true(
    initial
    .to_json()
    .stringify()
    .contains(
      "Dynamic skill gate: the user's wording may omit the implementation language",
    ),
  )
  assert_true(
    initial.to_json().stringify().contains("the gate is already satisfied"),
  )
  assert_true(
    initial
    .to_json()
    .stringify()
    .contains("never through read, shell, glob, grep, find, ls, or web tools"),
  )
  assert_true(system.contains("Never ask for tool approval in assistant prose"))
  assert_true(
    system.contains(
      "read their authoritative local implementation or specification",
    ),
  )
  assert_true(
    system.contains(
      "never invent fields or call a synthetic subset a captured runtime payload",
    ),
  )
  assert_true(system.contains("Before any replace-all or repeated replacement"))
  assert_true(system.contains("rerun the nearest affected tests"))
  assert_true(
    system.contains(
      "Never create marker files, no-op edits, comments, or other artifacts",
    ),
  )
  assert_true(
    system.contains(
      "Interpret `no cleanup` and similar scope constraints as forbidding unrelated refactors",
    ),
  )
  assert_true(
    system.contains(
      "not as permission to skip the repository's canonical formatter",
    ),
  )
  assert_true(
    system.contains(
      "Do not set `requires_approval` or `approval=operator` for read, view_image, local browser observation, moon_ide, moon_check",
    ),
  )
  assert_true(
    system.contains(
      "`moon fmt` accepts path/paths but never target or package selectors",
    ),
  )
  assert_true(
    system.contains(
      "a path inside a nested module lets the runtime infer its nearest module root",
    ),
  )
  assert_true(
    system.contains(
      "Treat exact paths named by the user and task-contract `context_paths` as authoritative starting evidence",
    ),
  )
  assert_true(
    system.contains(
      "that failed lookup is not a blocker while a causally different next action remains",
    ),
  )
  assert_true(
    system.contains(
      "If any required milestone is pending or active, choose the next useful tool batch",
    ),
  )
  assert_true(
    system.contains(
      "Batch independent inspections in one response; start another inference round only when a later action depends on an earlier result",
    ),
  )
  assert_false(system.contains("MoonBit baseline:"))

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
  let slow_command : Json = { "payload": { "planner_timeout_ms": 300000 } }
  assert_true(
    mooncode_runtime_turn_model_timeout_for_provider(direct, slow_command)
    is Some(120000),
  )
  let kimi = @model.Model::new(
    api_key="test",
    base_url="http://127.0.0.1:15721/v1",
    name="moongate/kimi-k3",
    model_name="kimi-k3",
    safe_zone_tokens=1000,
  )
  assert_true(
    mooncode_runtime_turn_model_timeout_for_provider(kimi, command) is None,
  )
  assert_true(
    mooncode_runtime_turn_model_timeout_for_provider(kimi, slow_command) is None,
  )
  let deepseek = @model.Model::new(
    api_key="test",
    base_url="http://127.0.0.1:15721/v1",
    name="moongate/deepseek-v4-flash",
    model_name="deepseek-v4-flash",
    safe_zone_tokens=1000,
  )
  assert_true(
    mooncode_runtime_turn_model_timeout_for_provider(deepseek, command) is None,
  )
  assert_true(
    mooncode_runtime_turn_model_timeout_for_provider(deepseek, slow_command)
    is None,
  )
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
  let tools_json = mooncode_runtime_turn_model_tools().to_json().stringify()
  assert_true(tools_json.contains("start_line"))
  assert_true(tools_json.contains("end_line"))
  let kimi_system = mooncode_json_string(
    mooncode_runtime_turn_kimi_messages(
      { "command": "prompt", "text": "repair the UI" },
      [],
    )[0],
    "content",
    default="",
  )
  assert_true(
    kimi_system.contains(
      "when the target and intended change are already clear",
    ),
  )
  assert_true(kimi_system.contains("read with start_line/end_line"))
  let prompt = mooncode_runtime_turn_model_prompt({
    "command": "prompt",
    "text": "repair the UI",
  })
  assert_true(prompt.contains("Choose one dependency-aware bounded tool batch"))
  assert_true(prompt.contains("Batch every independent inspection or mutation"))
  assert_false(prompt.contains("Choose the smallest useful tool batch"))
  let planner_system = mooncode_json_string(
    mooncode_runtime_turn_model_initial_messages({
      "command": "prompt",
      "text": "repair the UI",
    })[0],
    "content",
    default="",
  )
  assert_true(planner_system.contains("at most six broad and twelve total"))
  assert_true(
    planner_system.contains(
      "the next tool batch must contain edit, write, or apply_patch",
    ),
  )
}

///|
test "mooncode discovery saturation locks implementation until mutation" {
  let saturated : Json = {
    "accepted": false,
    "tool": "read",
    "result": { "ok": false, "metadata": { "discovery_saturated": true } },
  }
  assert_true(mooncode_runtime_turn_discovery_saturation_active([saturated]))
  let mutation : Json = {
    "accepted": true,
    "tool": "edit",
    "arguments": { "path": "src/main.mbt" },
    "result": { "ok": true },
  }
  assert_false(
    mooncode_runtime_turn_discovery_saturation_active([saturated, mutation]),
  )
}

///|
test "mooncode MoonGate planner survives transient overload until cancellation" {
  assert_true(
    mooncode_runtime_turn_model_retries_transient_summary(
      "moongate/kimi-k3", "HTTP 429: provider overloaded",
    ),
  )
  assert_true(
    mooncode_runtime_turn_model_retries_transient_summary(
      "kimi-k3", "HTTP 503: service unavailable",
    ),
  )
  assert_true(
    mooncode_runtime_turn_model_retries_transient_summary(
      "moongate/deepseek-v4-flash", "HTTP 429: provider overloaded",
    ),
  )
  assert_false(
    mooncode_runtime_turn_model_retries_transient_summary(
      "gpt-5.6-sol", "HTTP 429: provider overloaded",
    ),
  )
  assert_false(
    mooncode_runtime_turn_model_retries_transient_summary(
      "kimi-k3", "HTTP 400: invalid request",
    ),
  )
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
    overload_compaction_tier=2,
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
    mooncode_json_int(retry_event, "overload_compaction_tier", default=0),
    2,
  )
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
test "mooncode planner has no implicit budget and scopes goal settlement" {
  let command : Json = {
    "command": "prompt",
    "text": "Continue implementation until the requested work is complete.",
  }
  let system = mooncode_json_string(
    mooncode_runtime_turn_model_initial_messages(command)[0],
    "content",
    default="",
  )
  assert_true(system.contains("no implicit token, turn, time, step"))
  assert_true(system.contains("Difficulty, elapsed work, a large context"))
  assert_true(system.contains("Honor real caller-supplied budgets exactly"))
  assert_true(system.contains("time-budget-exhausted"))
  assert_true(
    system.contains("unless that exact caller-supplied budget exists"),
  )
  assert_true(system.contains("genuine external dependency"))
  assert_true(
    system.contains(
      "Never include finish.goal_runtime unless active goal_runtime context is explicitly present",
    ),
  )
  assert_false(
    mooncode_runtime_turn_model_tools_for_command(command)
    .to_json()
    .stringify()
    .contains("goal_runtime"),
  )

  let goal_command : Json = {
    "command": "prompt",
    "text": "Continue the goal",
    "goal_runtime": {
      "goal_id": "goal-1",
      "objective": "Complete all work",
      "criteria": [{ "id": "criterion-1", "criterion": "tests pass" }],
      "status": { "terminal": false },
    },
  }
  let goal_prompt = mooncode_runtime_turn_model_prompt(goal_command)
  assert_true(goal_prompt.contains("Active long-running goal"))
  assert_true(goal_prompt.contains("criterion-1"))
  assert_true(goal_prompt.contains("There is no implicit task budget"))
  assert_true(
    goal_prompt.contains("genuine external or user-authority blocker"),
  )
  let goal_tools_json = mooncode_runtime_turn_model_tools_for_command(
      goal_command,
    )
    .to_json()
    .stringify()
  assert_true(goal_tools_json.contains("goal_runtime"))
  assert_true(goal_tools_json.contains("achieved"))
  assert_true(goal_tools_json.contains("blocked"))
  assert_true(goal_tools_json.contains("genuine external dependency"))
  assert_true(goal_tools_json.contains("implicit token, turn, time, step"))
}

///|
test "kimi planner uses a concise autonomous execution envelope" {
  let command : Json = {
    "command": "prompt",
    "text": "Redesign the complete interface and verify it visually.",
  }
  let messages = mooncode_runtime_turn_kimi_messages(command, [])
  assert_eq(messages.length(), 3)
  let system = mooncode_json_string(messages[0], "content", default="")
  assert_true(system.contains("complete request as the task contract"))
  assert_true(system.contains("do not ask for micro-instructions"))
  assert_true(system.contains("no implicit step, turn, time, or effort budget"))
  assert_false(system.contains("<available_skills>"))
  assert_true(
    mooncode_json_string(messages[2], "content", default="").contains(
      "Redesign the complete interface",
    ),
  )
}

///|
async test "mooncode finish rejects goal settlement without active authority" {
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-no-implicit-goal-XXXXXX"),
  )
  let ordinary = mooncode_tool_finish({ "answer": "completed ordinary task" })
  assert_true(mooncode_json_bool(ordinary, "ok", default=false))

  let invented = mooncode_tool_finish_for_session("no-active-goal", book_root, {
    "answer": "blocked by invented budget",
    "goal_runtime": {
      "type": "blocked",
      "reason": {
        "code": "time-budget-exhausted",
        "detail": "No caller supplied a time budget.",
      },
      "attempted_alternatives": ["continue useful work"],
      "required_event": null,
    },
  })
  assert_false(mooncode_json_bool(invented, "ok", default=true))
  assert_true(
    mooncode_json_string(invented, "message", default="").contains(
      "requires an active runtime goal",
    ),
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
  assert_eq(mooncode_json_string(messages[3], "role", default=""), "user")
  assert_true(
    mooncode_json_string(messages[3], "content", default="").contains(
      "steer-live-1",
    ),
  )
  assert_true(
    mooncode_json_string(messages[3], "content", default="").contains(
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
  assert_true(
    transcript.contains(
      "do not repeat the same or an equivalent directory, status, or inventory inspection",
    ),
  )
  assert_true(transcript.contains("src/parser.mbt"))
  assert_true(transcript.contains("src/adapter.mbt"))
  assert_true(transcript.contains("src/earlier-retained.mbt"))
  assert_true(transcript.contains("failed_tool_calls"))
  assert_true(transcript.contains("src/guessed.mbt"))
  assert_true(transcript.contains("path does not exist"))
  assert_true(
    transcript.contains("Do not completely reread a retained complete path"),
  )
  assert_true(transcript.contains("causally targeted narrow reread"))
  assert_true(transcript.contains("do not repeat an identical failed call"))
  assert_true(
    transcript.contains(
      "After a relevant repair or transient cause is resolved, rerun the exact focused verification",
    ),
  )
  assert_true(transcript.contains("internal/parser/parser.mbt"))
  assert_true(transcript.contains("paths in this steering as authoritative"))
  let recovery = mooncode_json_string(
    messages[messages.length() - 2],
    "content",
    default="",
  )
  assert_true(recovery.contains("Authoritative immutable checkpoint contract"))
  assert_true(recovery.contains("\"id\": \"implementation\""))
  assert_true(recovery.contains("Recent runtime evidence"))
  assert_true(recovery.contains("Loaded-skill receipt"))
  assert_true(recovery.contains("moonbit-agent-guide/SKILL.md"))
  assert_true(
    recovery.contains("A missing or empty filesystem result cannot invalidate"),
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
      { "role": "user", "content": "remembered plan inventory" },
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
  assert_eq(retained.length(), 3)
  assert_eq(
    mooncode_json_string(retained[2], "content", default=""),
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
  assert_eq(checkpointed.length(), 4)
  assert_eq(
    mooncode_json_string(checkpointed[2], "content", default=""),
    "remembered plan inventory",
  )
  let receipt = mooncode_json_string(checkpointed[3], "content", default="")
  assert_true(receipt.contains("Loaded-skill receipt"))
  assert_true(receipt.contains("fixture-review/SKILL.md"))
  assert_true(receipt.contains("fixture-digest"))
  assert_false(receipt.contains("complete retained skill instructions"))
  assert_true(
    mooncode_json_string(checkpointed[1], "content", default="").contains(
      "A missing or empty filesystem result cannot invalidate the receipt",
    ),
  )
}

///|
test "mooncode forces an exact read after a failed content mutation" {
  let failed_edit : Json = {
    "tool": "edit",
    "accepted": false,
    "arguments": {
      "path": "docs/STATUS.md",
      "old_string": "guessed source",
      "new_string": "replacement",
    },
    "result": { "message": "old_string not found" },
  }
  let guessed_retry : Json = {
    "planner_mode": mooncode_planner_mode_model_tool_calls(),
    "tool_calls": [
      {
        "tool": "apply_patch",
        "arguments": { "path": "docs/STATUS.md", "diff": "*** Begin Patch" },
      },
    ],
  }
  let recovery = mooncode_runtime_turn_recovery_plan(guessed_retry, [
    failed_edit,
  ])
  let calls = mooncode_json_array_items(recovery, "tool_calls")
  assert_eq(calls.length(), 1)
  assert_eq(mooncode_json_string(calls[0], "tool", default=""), "read")
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(calls[0], "arguments"),
      "path",
      default="",
    ),
    "docs/STATUS.md",
  )
  let recovery_id = mooncode_json_string(calls[0], "tool_call_id", default="")
  assert_true(recovery_id != "")
  assert_true(mooncode_runtime_turn_model_tool_call_accepts_result(calls[0]))
  let response_calls = mooncode_json_array_items(
    mooncode_json_object_field_or_empty(recovery, "model_response_message"),
    "tool_calls",
  )
  assert_eq(response_calls.length(), 1)
  assert_eq(
    mooncode_json_string(response_calls[0], "id", default=""),
    recovery_id,
  )
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(response_calls[0], "function"),
      "name",
      default="",
    ),
    "read",
  )
  let already_reads : Json = {
    "planner_mode": mooncode_planner_mode_model_tool_calls(),
    "tool_calls": [
      { "tool": "read", "arguments": { "path": "docs/STATUS.md" } },
    ],
  }
  let retained_calls = mooncode_json_array_items(
    mooncode_runtime_turn_recovery_plan(already_reads, [failed_edit]),
    "tool_calls",
  )
  assert_eq(retained_calls.length(), 1)
  assert_eq(mooncode_json_string(retained_calls[0], "tool", default=""), "read")
  let failed_directory_patch : Json = {
    "tool": "apply_patch",
    "accepted": false,
    "arguments": {
      "path": ".",
      "diff": "*** Begin Patch\n*** Update File: docs/STATUS.md",
    },
    "result": { "message": "patch syntax rejected" },
  }
  let unforced = mooncode_runtime_turn_recovery_plan(guessed_retry, [
    failed_directory_patch,
  ])
  assert_eq(
    mooncode_json_string(
      mooncode_json_array_items(unforced, "tool_calls")[0],
      "tool",
      default="",
    ),
    "apply_patch",
  )
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
test "mooncode rejects unchanged repetition of an identical failed verification" {
  let call : Json = {
    "tool": "shell",
    "arguments": {
      "cmd": "moon test cmd/daemon --target native",
      "verification_kind": "test",
    },
  }
  let failed : Json = {
    "tool": "shell",
    "accepted": false,
    "arguments": {
      "cmd": "moon test cmd/daemon --target native",
      "verification_kind": "test",
    },
    "result": { "ok": false, "metadata": { "status": 1 } },
  }
  assert_true(mooncode_runtime_turn_repeats_failed_verification(call, [failed]))
  assert_false(
    mooncode_runtime_turn_repeats_failed_verification(
      {
        "tool": "shell",
        "arguments": {
          "cmd": "moon test cmd/daemon/mooncode_runtime_turn_wbtest.mbt --target native",
          "verification_kind": "test",
        },
      },
      [failed],
    ),
  )
  let changed : Json = {
    "tool": "edit",
    "accepted": true,
    "arguments": { "path": "cmd/daemon/runtime.mbt" },
    "result": {
      "ok": true,
      "metadata": {
        "changed": true,
        "path": "cmd/daemon/runtime.mbt",
        "before_fingerprint": "before",
        "after_fingerprint": "after",
      },
    },
  }
  assert_false(
    mooncode_runtime_turn_repeats_failed_verification(call, [failed, changed]),
  )
  assert_false(
    mooncode_runtime_turn_repeats_failed_verification(
      {
        "tool": "shell",
        "arguments": {
          "cmd": "git status --short",
          "verification_kind": "check",
        },
      },
      [failed],
    ),
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
test "mooncode native runtime recovers adjacent provider tool arguments" {
  let response : Json = {
    "choices": [
      {
        "message": {
          "tool_calls": [
            {
              "id": "shell-0",
              "type": "function",
              "function": {
                "name": "shell",
                "arguments": "{\"cmd\":\"pwd\"}{\"cmd\":\"git status --short\"}",
              },
            },
          ],
        },
      },
    ],
  }
  let calls = mooncode_runtime_turn_tool_calls_from_model_response(response)
  assert_eq(calls.length(), 2)
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(calls[0], "arguments"),
      "cmd",
      default="",
    ),
    "pwd",
  )
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(calls[1], "arguments"),
      "cmd",
      default="",
    ),
    "git status --short",
  )
  assert_eq(
    mooncode_json_string(calls[0], "tool_call_id", default=""),
    "shell-0-1",
  )
  assert_eq(
    mooncode_json_string(calls[1], "tool_call_id", default=""),
    "shell-0-2",
  )
  let assistant = mooncode_runtime_turn_model_response_message(
    response,
    normalized_tool_calls=calls,
  )
  let normalized = mooncode_json_array_items(assistant, "tool_calls")
  assert_eq(normalized.length(), 2)
  assert_eq(mooncode_json_string(normalized[1], "id", default=""), "shell-0-2")
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(normalized[1], "function"),
      "arguments",
      default="",
    ),
    "{\"cmd\":\"git status --short\"}",
  )
}

///|
test "mooncode native runtime normalizes heterogeneous adjacent provider calls" {
  let response : Json = {
    "choices": [
      {
        "message": {
          "tool_calls": [
            {
              "id": "mixed-0",
              "type": "function",
              "function": {
                "name": "edit",
                "arguments": "{\"path\":\"src/ui.mbt\",\"old_string\":\"old\",\"new_string\":\"new\"}{\"cmd\":\"git diff --check\"}",
              },
            },
          ],
        },
      },
    ],
  }
  let calls = mooncode_runtime_turn_tool_calls_from_model_response(response)
  assert_eq(calls.length(), 2)
  assert_eq(mooncode_json_string(calls[0], "tool", default=""), "edit")
  assert_eq(mooncode_json_string(calls[1], "tool", default=""), "shell")
  let assistant = mooncode_runtime_turn_model_response_message(
    response,
    normalized_tool_calls=calls,
  )
  let normalized = mooncode_json_array_items(assistant, "tool_calls")
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(normalized[1], "function"),
      "name",
      default="",
    ),
    "shell",
  )
}

///|
test "mooncode native runtime recovers checkpoint followed by path read" {
  let response : Json = {
    "choices": [
      {
        "message": {
          "tool_calls": [
            {
              "id": "checkpoint-read-0",
              "type": "function",
              "function": {
                "name": "checkpoint",
                "arguments": "{\"horizon_id\":\"horizon\",\"milestones\":[],\"next_action\":\"read exact file\"}{\"path\":\"src/ui/types.mbt\"}",
              },
            },
          ],
        },
      },
    ],
  }
  let calls = mooncode_runtime_turn_tool_calls_from_model_response(response)
  assert_eq(calls.length(), 2)
  assert_eq(mooncode_json_string(calls[0], "tool", default=""), "checkpoint")
  assert_eq(mooncode_json_string(calls[1], "tool", default=""), "read")
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(calls[1], "arguments"),
      "path",
      default="",
    ),
    "src/ui/types.mbt",
  )
}

///|
test "mooncode native runtime recovers read followed by named skill" {
  let response : Json = {
    "choices": [
      {
        "message": {
          "tool_calls": [
            {
              "id": "read-skill-0",
              "type": "function",
              "function": {
                "name": "read",
                "arguments": "{\"path\":\"src/ui.mbt\"}{\"name\":\"moonbit-agent-guide\"}",
              },
            },
          ],
        },
      },
    ],
  }
  let calls = mooncode_runtime_turn_tool_calls_from_model_response(response)
  assert_eq(calls.length(), 2)
  assert_eq(mooncode_json_string(calls[0], "tool", default=""), "read")
  assert_eq(mooncode_json_string(calls[1], "tool", default=""), "read_skill")
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(calls[1], "arguments"),
      "name",
      default="",
    ),
    "moonbit-agent-guide",
  )
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
          "metadata": { "answer": "Completed with proof." },
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
  assert_true(
    mooncode_json_string(settled[2], "content", default="").contains(
      "\"skipped\": true",
    ),
  )
  let oversized = mooncode_runtime_turn_model_tool_result_content({
    "result": { "output": "x".repeat(9000) },
  })
  assert_true(oversized.length() < 4100)
  assert_true(oversized.contains("truncated for planner context"))
  let retained_source = mooncode_runtime_turn_model_tool_result_content({
    "tool": "read",
    "result": { "output": "x".repeat(9000) },
  })
  assert_true(retained_source.length() > 9000)
  assert_false(retained_source.contains("truncated for planner context"))
  let oversized_source = mooncode_runtime_turn_model_tool_result_content({
    "tool": "read",
    "result": { "output": "x".repeat(50000) },
  })
  assert_true(oversized_source.length() < 40100)
  assert_true(oversized_source.contains("truncated for planner context"))
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
test "mooncode implementation discovery bounds broad and total reads until mutation" {
  let implementation : Json = {
    "command": "prompt",
    "text": "Implement the requested UI behavior and run checks.",
    "payload": { "task_intent": "workspace_change" },
  }
  let discoveries : Array[Json] = []
  for index in 0..<6 {
    discoveries.push({
      "accepted": true,
      "tool": "shell",
      "arguments": { "cmd": "find src -maxdepth {index + 1} -type f" },
      "result": { "ok": true, "output": "src/main.mbt" },
    })
  }
  assert_true(
    mooncode_runtime_turn_discovery_saturated(
      implementation,
      { "tool": "shell", "arguments": { "cmd": "ls -la src" } },
      discoveries,
    ),
  )
  assert_true(
    mooncode_runtime_turn_discovery_saturated(
      implementation,
      { "tool": "read", "arguments": { "path": "src/main.mbt" } },
      discoveries,
    ),
  )
  assert_false(
    mooncode_runtime_turn_discovery_saturated(
      implementation,
      {
        "tool": "read",
        "arguments": {
          "path": "src/main.mbt",
          "start_line": 40,
          "end_line": 80,
        },
      },
      discoveries,
    ),
  )
  assert_false(
    mooncode_runtime_turn_discovery_saturated(
      implementation,
      {
        "tool": "shell",
        "arguments": { "cmd": "rg -n 'render_agent' src/main.mbt" },
      },
      discoveries,
    ),
  )
  let targeted = discoveries.copy()
  for index in 0..<6 {
    targeted.push({
      "accepted": true,
      "tool": "read",
      "arguments": {
        "path": "src/main.mbt",
        "start_line": index * 20 + 1,
        "end_line": index * 20 + 20,
      },
      "result": { "ok": true, "output": "source range" },
    })
  }
  assert_true(
    mooncode_runtime_turn_discovery_saturated(
      implementation,
      {
        "tool": "read",
        "arguments": {
          "path": "src/other.mbt",
          "start_line": 1,
          "end_line": 20,
        },
      },
      targeted,
    ),
  )
  assert_true(
    mooncode_runtime_turn_discovery_saturated(
      implementation,
      {
        "tool": "moon_ide",
        "arguments": { "action": "outline", "path": "src/main.mbt" },
      },
      targeted,
    ),
  )
  let failed_edit : Json = {
    "accepted": false,
    "tool": "edit",
    "arguments": {
      "path": "src/main.mbt",
      "old_string": "stale bytes",
      "new_string": "replacement",
    },
    "result": {
      "ok": false,
      "message": "old_string not found",
      "metadata": { "context_mismatch": true, "path": "src/main.mbt" },
    },
  }
  let after_failed_edit = targeted.copy()
  after_failed_edit.push(failed_edit)
  assert_false(
    mooncode_runtime_turn_discovery_saturated(
      implementation,
      { "tool": "read", "arguments": { "path": "src/main.mbt" } },
      after_failed_edit,
    ),
  )
  assert_true(
    mooncode_runtime_turn_discovery_saturated(
      implementation,
      { "tool": "read", "arguments": { "path": "src/other.mbt" } },
      after_failed_edit,
    ),
  )
  let after_recovery_read = after_failed_edit.copy()
  after_recovery_read.push({
    "accepted": true,
    "tool": "read",
    "arguments": { "path": "src/main.mbt" },
    "result": {
      "ok": true,
      "output": "current source bytes",
      "metadata": { "path": "src/main.mbt", "truncated": false },
    },
  })
  assert_true(
    mooncode_runtime_turn_discovery_saturated(
      implementation,
      { "tool": "read", "arguments": { "path": "src/main.mbt" } },
      after_recovery_read,
    ),
  )
  let after_mutation = discoveries.copy()
  after_mutation.push({
    "accepted": true,
    "tool": "edit",
    "arguments": { "path": "src/main.mbt" },
    "result": { "ok": true },
  })
  assert_false(
    mooncode_runtime_turn_discovery_saturated(
      implementation,
      { "tool": "shell", "arguments": { "cmd": "ls -la src" } },
      after_mutation,
    ),
  )
}

///|
test "mooncode compacted provider context retains complete-read receipts and permits ranges" {
  let read_call : Json = {
    "tool": "read",
    "arguments": { "path": "src/main.mbt" },
  }
  let complete_read : Json = {
    "accepted": true,
    "tool": "read",
    "arguments": { "path": "src/main.mbt" },
    "result": {
      "ok": true,
      "metadata": { "path": "src/main.mbt", "truncated": false },
    },
  }
  let retained_messages : Array[Json] = [
    {
      "role": "assistant",
      "tool_calls": [
        {
          "id": "read-main",
          "type": "function",
          "function": {
            "name": "read",
            "arguments": "{\"path\":\"src/main.mbt\"}",
          },
        },
      ],
    },
    {
      "role": "tool",
      "tool_call_id": "read-main",
      "content": "current source bytes",
    },
  ]
  assert_true(
    mooncode_runtime_turn_repeats_complete_read(
      read_call,
      [complete_read],
      active_model_messages=retained_messages,
    ),
  )
  assert_false(
    mooncode_runtime_turn_repeats_complete_read(read_call, [complete_read], active_model_messages=[
      { "role": "system", "content": "planner contract" },
      { "role": "user", "content": "task contract" },
      {
        "role": "user",
        "content": "MoonCode compacted older provider messages.",
      },
    ]),
  )
  assert_true(
    mooncode_runtime_turn_repeats_complete_read(read_call, [complete_read], active_model_messages=[
      {
        "role": "user",
        "content": "Retained evidence: {\"complete_read_paths\":[\"src/main.mbt\"]}",
      },
    ]),
  )
  assert_false(
    mooncode_runtime_turn_repeats_complete_read(
      {
        "tool": "read",
        "arguments": {
          "path": "src/main.mbt",
          "start_line": 40,
          "end_line": 80,
        },
      },
      [complete_read],
      active_model_messages=[
        {
          "role": "user",
          "content": "Retained evidence: {\"complete_read_paths\":[\"src/main.mbt\"]}",
        },
      ],
    ),
  )
  let truncated_messages : Array[Json] = [
    retained_messages[0],
    {
      "role": "tool",
      "tool_call_id": "read-main",
      "content": "partial bytes\n...[truncated for planner context]",
    },
  ]
  assert_false(
    mooncode_runtime_turn_repeats_complete_read(
      read_call,
      [complete_read],
      active_model_messages=truncated_messages,
    ),
  )
}

///|
test "mooncode context mismatch permits one same-path complete reread" {
  let main_read : Json = {
    "accepted": true,
    "tool": "read",
    "arguments": { "path": "src/main.mbt" },
    "result": {
      "ok": true,
      "metadata": { "path": "src/main.mbt", "truncated": false },
    },
  }
  let other_read : Json = {
    "accepted": true,
    "tool": "read",
    "arguments": { "path": "src/other.mbt" },
    "result": {
      "ok": true,
      "metadata": { "path": "src/other.mbt", "truncated": false },
    },
  }
  let failed_patch : Json = {
    "accepted": false,
    "tool": "apply_patch",
    "result": {
      "ok": false,
      "metadata": { "path": "src/main.mbt#hunk-2", "context_mismatch": true },
    },
  }
  let main_call : Json = {
    "tool": "read",
    "arguments": { "path": "src/main.mbt" },
  }
  let other_call : Json = {
    "tool": "read",
    "arguments": { "path": "src/other.mbt" },
  }
  assert_false(
    mooncode_runtime_turn_repeats_complete_read(main_call, [
      main_read, other_read, failed_patch,
    ]),
  )
  assert_true(
    mooncode_runtime_turn_repeats_complete_read(other_call, [
      main_read, other_read, failed_patch,
    ]),
  )
  let refreshed_main = main_read
  assert_true(
    mooncode_runtime_turn_repeats_complete_read(main_call, [
      main_read, other_read, failed_patch, refreshed_main,
    ]),
  )
  let failed_other : Json = {
    "accepted": false,
    "tool": "edit",
    "result": {
      "ok": false,
      "metadata": { "path": "src/other.mbt", "context_mismatch": true },
    },
  }
  assert_true(
    mooncode_runtime_turn_repeats_complete_read(main_call, [
      main_read, failed_patch, refreshed_main, failed_other,
    ]),
  )
  let second_failed_main : Json = {
    "accepted": false,
    "tool": "write",
    "result": {
      "ok": false,
      "metadata": { "path": "src/main.mbt", "context_mismatch": true },
    },
  }
  assert_false(
    mooncode_runtime_turn_repeats_complete_read(main_call, [
      main_read, failed_patch, refreshed_main, second_failed_main,
    ]),
  )
}

///|
test "mooncode shell observation ordering preserves causal narrow rereads" {
  let complete_read : Json = {
    "accepted": true,
    "tool": "read",
    "arguments": { "path": "src/main.mbt" },
    "result": {
      "ok": true,
      "metadata": { "path": "src/main.mbt", "truncated": false },
    },
  }
  let compiler_failure : Json = {
    "accepted": false,
    "tool": "moon_check",
    "result": { "ok": false, "message": "compiler error at line 12" },
  }
  let patch_failure : Json = {
    "accepted": false,
    "tool": "apply_patch",
    "result": { "ok": false, "message": "patch context did not match" },
  }
  let unrelated_complete : Json = {
    "accepted": true,
    "tool": "read",
    "arguments": { "path": "src/other.mbt" },
    "result": {
      "ok": true,
      "metadata": { "path": "src/other.mbt", "truncated": false },
    },
  }
  let narrow_shell : Json = {
    "accepted": true,
    "tool": "shell",
    "arguments": { "cmd": "sed -n '8,16p' src/main.mbt" },
    "result": {
      "ok": true,
      "metadata": {
        "file_observation": {
          "path": "src/main.mbt",
          "scope": "partial",
          "source": "shell",
        },
      },
    },
  }
  let complete_shell : Json = {
    "accepted": true,
    "tool": "shell",
    "arguments": { "cmd": "cat src/main.mbt" },
    "result": {
      "ok": true,
      "metadata": {
        "file_observation": {
          "path": "src/main.mbt",
          "scope": "complete",
          "source": "shell",
        },
      },
    },
  }
  assert_true(
    mooncode_runtime_turn_duplicate_complete_observation_path(narrow_shell, [
      complete_read, unrelated_complete, compiler_failure, patch_failure,
    ])
    is None,
  )
  assert_true(
    mooncode_runtime_turn_duplicate_complete_observation_path(complete_shell, [
      complete_read, unrelated_complete, compiler_failure, patch_failure, narrow_shell,
    ])
    is Some("src/main.mbt"),
  )
  assert_true(
    mooncode_runtime_turn_repeats_complete_read(
      { "tool": "read", "arguments": { "path": "src/main.mbt" } },
      [complete_shell],
    ),
  )
  assert_true(
    mooncode_runtime_turn_repeats_complete_read(
      { "tool": "read", "arguments": { "path": "src/other.mbt" } },
      [
        complete_read, unrelated_complete, compiler_failure, patch_failure, narrow_shell,
      ],
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
  assert_true(
    mooncode_json_string(initial[0], "content", default="").contains(
      "do not repeat it against the same intended dirty state",
    ),
  )
  assert_true(
    mooncode_json_string(initial[0], "content", default="").contains(
      "Never guess a toolchain or dependency-management command",
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
