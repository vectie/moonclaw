///|
fn mooncode_horizon_test_milestones(
  scope : String,
  implementation : String,
  tests : String,
) -> Array[Json] {
  [
    {
      "id": "scope",
      "title": "Locate the owned implementation surface",
      "status": scope,
      "evidence_kind": "scope",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "implementation",
      "title": "Implement the requested behavior",
      "status": implementation,
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "tests",
      "title": "Pass the requested typed tests",
      "status": tests,
      "evidence_kind": "test",
      "path": "",
      "context_paths": [],
    },
  ]
}

///|
test "mooncode long-horizon loop compacts reference appendices and proves every milestone" {
  let mut appendix = ""
  for _ in 0..<2000 {
    appendix += "0123456789"
  }
  let command : Json = {
    "command": "prompt",
    "command_id": "command-horizon",
    "payload": { "horizon_id": "horizon-1" },
    "text": "Implement the parser repair across src/parser.mbt and src/parser_test.mbt, then run tests.\nFull authoritative plan follows:\n" +
    appendix,
  }
  let compact = mooncode_runtime_horizon_compact_request(command)
  assert_true(compact.contains("Implement the parser repair"))
  assert_true(compact.contains("Reference appendix omitted"))
  assert_false(compact.contains("0123456789"))
  assert_true(compact.length() < 1000)
  let exposed_tools = mooncode_runtime_turn_model_tools_for_command(command)
    .to_json()
    .stringify()
  assert_true(exposed_tools.contains("\"apply_patch\""))
  assert_true(exposed_tools.contains("\"checkpoint\""))

  let results : Array[Json] = [
    {
      "tool": "read",
      "accepted": true,
      "arguments": { "path": "src/parser.mbt" },
      "result": {
        "message": "read src/parser.mbt",
        "metadata": { "path": "src/parser.mbt", "truncated": false },
      },
    },
  ]
  let initial_checkpoint = mooncode_runtime_horizon_checkpoint_execution(
    command,
    "session-horizon",
    "/tmp/book",
    "command-horizon",
    {
      "tool": "checkpoint",
      "arguments": {
        "horizon_id": "horizon-1",
        "milestones": Json::array(
          mooncode_horizon_test_milestones("done", "active", "pending"),
        ),
        "next_action": "Patch the parser and its tests.",
      },
    },
    results,
    now=@clock.Timestamp::from_ms(1L),
  )
  assert_true(mooncode_json_bool(initial_checkpoint, "accepted", default=false))
  results.push(initial_checkpoint)
  results.push({
    "tool": "apply_patch",
    "accepted": true,
    "result": {
      "message": "patched parser and tests",
      "metadata": {
        "changed": true,
        "files": [
          {
            "file_path": "src/parser.mbt",
            "changed": true,
            "before_fingerprint": "present:parser-0",
            "after_fingerprint": "present:parser-1",
          },
          {
            "file_path": "src/parser_test.mbt",
            "changed": true,
            "before_fingerprint": "present:test-0",
            "after_fingerprint": "present:test-1",
          },
        ],
      },
    },
  })
  results.push({
    "tool": "moon_cmd",
    "accepted": false,
    "arguments": { "command": "test" },
    "result": { "message": "compiler error in parser branch" },
  })
  results.push({
    "tool": "edit",
    "accepted": true,
    "arguments": { "path": "src/parser.mbt" },
    "result": {
      "message": "repaired compiler diagnostic",
      "metadata": {
        "path": "src/parser.mbt",
        "changed": true,
        "before_fingerprint": "present:parser-1",
        "after_fingerprint": "present:parser-2",
      },
    },
  })
  results.push({
    "tool": "moon_cmd",
    "accepted": true,
    "arguments": { "command": "test" },
    "result": { "message": "tests passed" },
  })
  let final_checkpoint = mooncode_runtime_horizon_checkpoint_execution(
    command,
    "session-horizon",
    "/tmp/book",
    "command-horizon",
    {
      "tool": "checkpoint",
      "arguments": {
        "horizon_id": "horizon-1",
        "milestones": Json::array(
          mooncode_horizon_test_milestones("done", "done", "done"),
        ),
        "next_action": "Finish with the verified result.",
      },
    },
    results,
    now=@clock.Timestamp::from_ms(2L),
  )
  assert_true(mooncode_json_bool(final_checkpoint, "accepted", default=false))
  results.push(final_checkpoint)
  results.push({
    "tool": "finish",
    "accepted": true,
    "result": { "message": "finished" },
  })
  let verdict = mooncode_runtime_turn_completion_verdict(
    command,
    results,
    require_horizon=true,
  )
  assert_true(verdict.accepted)
  let progress = mooncode_runtime_horizon_progress_message(command, results, 3)
  let progress_text = mooncode_json_string(progress, "content", default="")
  assert_true(progress_text.contains("Planner opportunities remaining: 3"))
  assert_true(progress_text.contains("Do not rediscover completed milestones"))
  assert_true(progress_text.length() < 16000)
}

///|
test "mooncode long-horizon completion rejects unproven milestone claims" {
  let command : Json = {
    "command": "prompt",
    "command_id": "command-horizon-reject",
    "payload": { "horizon_id": "horizon-reject" },
    "text": "Implement the fix and run tests.",
  }
  let rejected = mooncode_runtime_horizon_checkpoint_execution(
    command,
    "session-horizon",
    "/tmp/book",
    "command-horizon-reject",
    {
      "tool": "checkpoint",
      "arguments": {
        "horizon_id": "horizon-reject",
        "milestones": Json::array(
          mooncode_horizon_test_milestones("done", "done", "done"),
        ),
        "next_action": "Finish.",
      },
    },
    [],
    now=@clock.Timestamp::from_ms(3L),
  )
  assert_false(mooncode_json_bool(rejected, "accepted", default=true))
  assert_true(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(rejected, "result"),
      "message",
      default="",
    ).contains("no matching runtime evidence"),
  )
}

///|
test "mooncode long-horizon resume restores only accepted journal checkpoints" {
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-resume",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Implement the fix and run tests.",
    "payload": { "horizon_id": "horizon-resume" },
    "packet": { "command_id": "command-resume" },
  }
  let failed : Json = {
    "tool": "checkpoint",
    "tool_result": {
      "ok": false,
      "metadata": {
        "horizon_id": "horizon-resume",
        "checkpoint": { "milestones": [{ "id": "failed", "status": "done" }] },
      },
    },
  }
  let accepted : Json = {
    "tool": "checkpoint",
    "tool_result": {
      "ok": true,
      "metadata": {
        "horizon_id": "horizon-resume",
        "checkpoint": {
          "milestones": [{ "id": "implementation", "status": "active" }],
        },
      },
    },
  }
  let resumed = mooncode_runtime_horizon_attach_checkpoint(command, [
    failed, accepted,
  ])
  assert_true(
    mooncode_json_bool(
      mooncode_validate_command_body("session-resume", resumed),
      "ok",
      default=false,
    ),
  )
  let checkpoint = mooncode_json_object_field_or_empty(
    mooncode_json_object_field_or_empty(resumed, "payload"),
    "horizon_checkpoint",
  )
  assert_eq(
    mooncode_json_string(
      mooncode_json_array_items(checkpoint, "milestones")[0],
      "id",
      default="",
    ),
    "implementation",
  )
}
