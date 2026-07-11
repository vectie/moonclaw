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
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "created_at": @clock.Timestamp::from_ms(1L),
    "command": command,
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
    mooncode_runtime_receipts_path(book_root, session_id),
  )
  assert_true(receipt_log.contains("\"runtime-claimed\""))
  assert_true(receipt_log.contains("\"runtime-completed\""))
  assert_true(receipt_log.contains("\"web_search\":true"))
  let events_log = @fsx.read_file(mooncode_events_path(book_root, session_id))
  assert_true(events_log.contains("\"runtime.turn_started\""))
  assert_true(events_log.contains("\"tool_result\""))
  assert_true(events_log.contains("\"runtime.turn_finished\""))
  let after = mooncode_json_object_field_or_empty(result, "claim_state")
  assert_true(after.stringify().contains("\"delivered_command_count\":1"))
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
    "model": "unavailable-model",
  }
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "created_at": @clock.Timestamp::from_ms(2L),
    "command": command,
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
    mooncode_events_path(book_root, session_id),
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
    "packet": { "command_id": prompt_id },
  }
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": prompt_id,
    "created_at": @clock.Timestamp::from_ms(4L),
    "command": prompt,
  })
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
    mooncode_events_path(book_root, session_id),
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
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "created_at": @clock.Timestamp::from_ms(3L),
    "command": command,
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
  let events_log = @fsx.read_file(mooncode_events_path(book_root, session_id))
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
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "created_at": @clock.Timestamp::from_ms(4L),
    "command": command,
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
  let events_log = @fsx.read_file(mooncode_events_path(book_root, session_id))
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
    "model": "unavailable-model",
  }
  let reject_command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "reject",
    "context_path": "apps/demo/index.html",
    "packet": {
      "command_id": reject_id,
      "context_path": "apps/demo/index.html",
    },
  }
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": accept_id,
    "created_at": @clock.Timestamp::from_ms(3L),
    "command": accept_command,
  })
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": reject_id,
    "created_at": @clock.Timestamp::from_ms(4L),
    "command": reject_command,
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
  let events_log = @fsx.read_file(mooncode_events_path(book_root, session_id))
  assert_true(events_log.contains("\"receipt.accept\""))
  assert_true(events_log.contains("\"receipt.reject\""))
  assert_true(events_log.contains("\"command\":\"accept\""))
  assert_true(events_log.contains("\"command\":\"reject\""))
  let after = mooncode_json_object_field_or_empty(rejected, "claim_state")
  assert_true(after.stringify().contains("\"delivered_command_count\":2"))
}

///|
test "mooncode native runtime turn plans prompt tool calls" {
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Create an executable tool for this MoonBook",
    "packet": { "command_id": "cmd-planner" },
  }
  let calls = mooncode_runtime_turn_tool_calls(command)
  assert_eq(calls.length(), 4)
  assert_eq(mooncode_json_string(calls[0], "tool", default=""), "write")
  assert_true(calls[0].stringify().contains("tools/mooncode-generated"))
  assert_eq(mooncode_json_string(calls[2], "tool", default=""), "shell")
  assert_eq(mooncode_json_string(calls[3], "tool", default=""), "finish")
  let miniapp : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Build a tiny html miniapp",
    "packet": { "command_id": "cmd-miniapp" },
  }
  let miniapp_calls = mooncode_runtime_turn_tool_calls(miniapp)
  assert_eq(miniapp_calls.length(), 4)
  assert_true(miniapp_calls[0].stringify().contains("apps/mooncode-generated"))
  assert_eq(mooncode_json_string(miniapp_calls[2], "tool", default=""), "shell")
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
  let engineering_fallback = mooncode_runtime_turn_tool_calls(
    engineering_prompt,
  )
  assert_eq(engineering_fallback.length(), 1)
  assert_eq(
    mooncode_json_string(engineering_fallback[0], "tool", default=""),
    "finish",
  )
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
    "model": "codex/gpt-5.4",
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
  assert_false(mooncode_runtime_turn_requires_model_planning(read))

  let write : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Create tools/e2e-fixed.txt in this MoonBook with exactly ROOT_OK, then reply that it is done.",
    "model": "codex/gpt-5.4",
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
  assert_false(mooncode_runtime_turn_requires_model_planning(write))
}

///|
async test "mooncode deterministic explicit prompts execute without model delay" (
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
    "model": "codex/gpt-5.4",
    "packet": { "command_id": write_id },
  }
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": write_id,
    "created_at": @clock.Timestamp::from_ms(1L),
    "command": write,
  })
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
    "model": "codex/gpt-5.4",
    "packet": { "command_id": read_id },
  }
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": read_id,
    "created_at": @clock.Timestamp::from_ms(2L),
    "command": read,
  })
  let read_result = daemon.mooncode_runtime_turn_execute(
    session_id,
    book_root,
    { "consumer_id": "test-runtime" },
  )
  assert_true(mooncode_json_bool(read_result, "accepted", default=false))
  assert_true(read_result.stringify().contains("fixture read"))
  let event_log = @fsx.read_file(mooncode_events_path(book_root, session_id))
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
  assert_false(chat_tools.to_json().stringify().contains("moon_check"))

  let plan_request = mooncode_runtime_turn_model_plan_request(
    "gpt-5.4", command,
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
  assert_eq(mooncode_runtime_turn_model_tools_for_command(coding).length(), 8)
  let coding_with_path : Json = {
    "command": "prompt",
    "text": "Edit first. The scaffold has already been read. Overwrite tools/robot-design-validator/src/main.mbt with a substantive validator, then add tests, fixtures, and a README; run moon check and moon test before finishing. Implement the result; do not merely explain it.",
  }
  assert_eq(
    mooncode_runtime_turn_model_tools_for_command(coding_with_path).length(),
    8,
  )

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
    is Some(30000),
  )
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
  }
  daemon.mooncode_runtime_turn_record_event(binding, events, persisted, event)
  daemon.mooncode_runtime_turn_record_event(binding, events, persisted, event)
  assert_eq(events.length(), 1)
  assert_eq(
    mooncode_read_jsonl(mooncode_events_path(book_root, session_id)).length(),
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
  let finish : Json = { "tool": "finish", "accepted": true }
  assert_false(
    mooncode_runtime_turn_model_execution_accepted(coding, [write_ok]),
  )
  assert_false(
    mooncode_runtime_turn_model_execution_accepted(
      coding, [write_ok, read_failed, finish],
    ),
  )
  assert_true(
    mooncode_runtime_turn_model_execution_accepted(
      coding, [write_ok, read_failed, read_recovered, finish],
    ),
  )
  assert_false(
    mooncode_runtime_turn_model_execution_accepted(coding, [finish]),
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
  assert_true(!mooncode_runtime_turn_tool_calls_include_finish(calls))
  assert_true(
    mooncode_runtime_turn_tool_calls_include_finish([
      { "tool": "finish", "arguments": { "answer": "done" } },
    ]),
  )
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
async test "mooncode native runtime turn creates executable tool from prompt" (
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
    "packet": { "command_id": command_id },
  }
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "created_at": @clock.Timestamp::from_ms(2L),
    "command": command,
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
    mooncode_package_results_path(book_root, session_id),
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
    mooncode_book_results_path(book_root, session_id),
  )
  assert_true(book_result_log.contains("\"mooncode-book-result\""))
  assert_true(book_result_log.contains("\"moonbook.executable_event.v1\""))
  let events_log = @fsx.read_file(mooncode_events_path(book_root, session_id))
  assert_true(events_log.contains("\"runtime.turn_started\""))
  assert_true(events_log.contains("\"tool_result\""))
  assert_true(events_log.contains("\"finish\""))
  assert_true(events_log.contains("\"runtime.package_built\""))
  assert_true(events_log.contains("\"runtime.package_verified\""))
  assert_true(events_log.contains("\"runtime.turn_finished\""))
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
    "packet": { "command_id": command_id },
  }
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "created_at": @clock.Timestamp::from_ms(5L),
    "command": command,
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
  let events_log = @fsx.read_file(mooncode_events_path(book_root, session_id))
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
    "packet": { "command_id": command_id },
  }
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "created_at": @clock.Timestamp::from_ms(5L),
    "command": command,
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
  let events_log = @fsx.read_file(mooncode_events_path(book_root, session_id))
  assert_true(events_log.contains("\"moon_cmd.finished\""))
  assert_true(events_log.contains("\"moon_command\":\"build\""))
  assert_true(events_log.contains("\"moon_check.finished\""))
  assert_true(events_log.contains("\"test_result\""))
  assert_true(events_log.contains("\"test_status\":\"passed\""))
  assert_true(events_log.contains("\"runtime.turn_finished\""))
}
