///|
fn parallel_read_test_plan(tool_calls : Array[Json]) -> Json {
  {
    "planner_mode": mooncode_planner_mode_model_tool_calls(),
    "tool_calls": Json::array(tool_calls),
  }
}

///|
async test "mooncode parallel read batches accept independent read-only tools" {
  let command : Json = {
    "command": "prompt",
    "text": "Read the project files and summarize them.",
    "book_root": "/tmp/book",
  }
  let calls : Array[Json] = [
    { "tool": "read", "arguments": { "path": "a.txt" } },
    { "tool": "read", "arguments": { "path": "b.txt" } },
  ]
  assert_true(
    mooncode_runtime_turn_parallel_read_batch_allowed(
      command,
      "/tmp/book",
      parallel_read_test_plan(calls),
      calls,
      [],
      [],
      resuming_step=false,
    ),
  )
  let duplicate : Array[Json] = [calls[0], calls[0]]
  assert_false(
    mooncode_runtime_turn_parallel_read_batch_allowed(
      command,
      "/tmp/book",
      parallel_read_test_plan(duplicate),
      duplicate,
      [],
      [],
      resuming_step=false,
    ),
  )
  let path_escape : Array[Json] = [
    calls[0],
    { "tool": "read", "arguments": { "path": "../outside.txt" } },
  ]
  assert_false(
    mooncode_runtime_turn_parallel_read_batch_allowed(
      command,
      "/tmp/book",
      parallel_read_test_plan(path_escape),
      path_escape,
      [],
      [],
      resuming_step=false,
    ),
  )
  let alias_duplicate : Array[Json] = [
    { "tool": "read", "arguments": { "path": "a.txt" } },
    { "tool": "read", "arguments": { "path": "./a.txt" } },
  ]
  assert_false(
    mooncode_runtime_turn_parallel_read_batch_allowed(
      command,
      "/tmp/book",
      parallel_read_test_plan(alias_duplicate),
      alias_duplicate,
      [],
      [],
      resuming_step=false,
    ),
  )
  let batch_seal : Array[Json] = [
    calls[0],
    { "tool": "finish", "arguments": { "answer": "done" } },
  ]
  assert_false(
    mooncode_runtime_turn_parallel_read_batch_allowed(
      command,
      "/tmp/book",
      parallel_read_test_plan(batch_seal),
      batch_seal,
      [],
      [],
      resuming_step=false,
    ),
  )
  let approval_boundary : Array[Json] = [
    calls[0],
    {
      "tool": "read",
      "approval": "operator",
      "arguments": { "path": "approved.txt" },
    },
  ]
  assert_false(
    mooncode_runtime_turn_parallel_read_batch_allowed(
      command,
      "/tmp/book",
      parallel_read_test_plan(approval_boundary),
      approval_boundary,
      [],
      [],
      resuming_step=false,
    ),
  )
  let heterogeneous : Array[Json] = [
    {
      "tool": "moon_ide",
      "planner": "model-tool-call",
      "arguments": { "action": "outline", "path": "cmd/daemon" },
    },
    {
      "tool": "moon_cmd",
      "planner": "model-tool-call",
      "arguments": { "command": "check", "path": "cmd/daemon" },
    },
  ]
  assert_true(
    mooncode_runtime_turn_parallel_read_batch_allowed(
      command,
      "/tmp/book",
      parallel_read_test_plan(heterogeneous),
      heterogeneous,
      [],
      [],
      resuming_step=false,
    ),
  )
  let browser_mutation : Array[Json] = [
    calls[0],
    {
      "tool": "browser",
      "planner": "model-tool-call",
      "arguments": { "action": "eval", "expression": "document.body.remove()" },
    },
  ]
  assert_false(
    mooncode_runtime_turn_parallel_read_batch_allowed(
      command,
      "/tmp/book",
      parallel_read_test_plan(browser_mutation),
      browser_mutation,
      [],
      [],
      resuming_step=false,
    ),
  )
  let mixed : Array[Json] = [
    calls[0],
    {
      "tool": "edit",
      "arguments": { "path": "a.txt", "old_string": "a", "new_string": "b" },
    },
  ]
  assert_false(
    mooncode_runtime_turn_parallel_read_batch_allowed(
      command,
      "/tmp/book",
      parallel_read_test_plan(mixed),
      mixed,
      [],
      [],
      resuming_step=false,
    ),
  )
  assert_false(
    mooncode_runtime_turn_parallel_read_batch_allowed(
      command,
      "/tmp/book",
      parallel_read_test_plan(calls),
      calls,
      [],
      [],
      resuming_step=true,
    ),
  )
}

///|
async test "mooncode parallel reads retain model call order" {
  @fsx.with_temporary_directory("mooncode-parallel-reads-XXXXXX", async fn(
    root,
  ) {
    @fsx.write_to_file(@pathx.join(root, "a.txt"), "alpha")
    @fsx.write_to_file(@pathx.join(root, "b.txt"), "beta")
    let daemon = mooncode_control_test_daemon(root)
    let command : Json = {
      "command": "prompt",
      "session_id": "parallel-read-session",
      "book_root": root,
      "packet": { "command_id": "parallel-read-command" },
    }
    let calls : Array[Json] = [
      { "tool": "read", "arguments": { "path": "b.txt" } },
      { "tool": "read", "arguments": { "path": "a.txt" } },
    ]
    let results = daemon.mooncode_runtime_turn_execute_parallel_reads(
      command, "parallel-read-session", root, calls,
    )
    assert_eq(results.length(), 2)
    let first = mooncode_json_object_field_or_empty(results[0], "result")
    let second = mooncode_json_object_field_or_empty(results[1], "result")
    assert_eq(mooncode_json_string(first, "output", default=""), "beta")
    assert_eq(mooncode_json_string(second, "output", default=""), "alpha")
  })
}

///|
async test "mooncode parallel read-only batches contain errors without reordering peers" {
  @fsx.with_temporary_directory("mooncode-parallel-read-errors-XXXXXX", async fn(
    root,
  ) {
    @fsx.write_to_file(@pathx.join(root, "present.txt"), "present")
    let daemon = mooncode_control_test_daemon(root)
    let command : Json = {
      "command": "prompt",
      "session_id": "parallel-read-error-session",
      "book_root": root,
      "packet": { "command_id": "parallel-read-error-command" },
    }
    let calls : Array[Json] = [
      { "tool": "read", "arguments": { "path": "missing.txt" } },
      { "tool": "read", "arguments": { "path": "present.txt" } },
    ]
    let results = daemon.mooncode_runtime_turn_execute_parallel_reads(
      command, "parallel-read-error-session", root, calls,
    )
    assert_eq(results.length(), 2)
    assert_false(mooncode_json_bool(results[0], "accepted", default=true))
    assert_true(mooncode_json_bool(results[1], "accepted", default=false))
    assert_eq(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(results[1], "result"),
        "output",
        default="",
      ),
      "present",
    )
  })
}
