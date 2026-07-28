///|
fn replan_compaction_test_plan(model_messages : Array[Json]) -> Json {
  {
    "planner_mode": mooncode_planner_mode_model_tool_calls(),
    "failed": false,
    "model_messages": Json::array(model_messages),
    "model_response_message": {
      "role": "assistant",
      "content": "",
      "tool_calls": [
        {
          "id": "call-read-1",
          "type": "function",
          "function": {
            "name": "read",
            "arguments": "{\"path\":\"README.md\",\"max_output_chars\":1024}",
          },
        },
      ],
    },
    "tool_calls": [
      {
        "tool": "read",
        "arguments": { "path": "README.md", "max_output_chars": 1024 },
      },
    ],
  }
}

///|
fn replan_compaction_test_execution(
  event_id : String,
  command_id : String,
  body : String,
) -> Json {
  let result : Json = {
    "tool": "read",
    "ok": true,
    "is_error": false,
    "message": "read complete",
    "output": body,
  }
  let event = mooncode_json_object_with_field(
    mooncode_tool_result_event(
      "replan-compaction-session",
      "/tmp/replan-compaction-book",
      command_id,
      "read",
      result,
      now=@clock.Timestamp::from_ms(1000L),
    ),
    "id",
    event_id.to_json(),
  )
  {
    "kind": "mooncode-tool-execution",
    "accepted": true,
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": "replan-compaction-session",
    "book_root": "/tmp/replan-compaction-book",
    "command_id": command_id,
    "tool": "read",
    "arguments": { "path": "README.md", "max_output_chars": 1024 },
    "result": result,
    "event": event,
  }
}

///|
fn replan_compaction_test_checkpoint(
  plan : Json,
  planner_steps : Array[Json],
  execution : Json,
  next_step_index : Int,
) -> Json {
  mooncode_runtime_planner_replan_continuation_event(
    "replan-compaction-session",
    "replan-compaction-command",
    plan,
    finish_rejected=false,
    planner_steps,
    [execution],
    [execution],
    next_step_index~,
    replan_count=next_step_index,
    guidance="continue after rejected replan",
    now=@clock.Timestamp::from_ms(1000L + next_step_index.to_int64()),
  )
}

///|
test "compact continuation hydrates inline result events" {
  let execution = replan_compaction_test_execution(
    "replan-inline-result", "replan-compaction-command", "inline execution result",
  )
  let event = mooncode_json_object_with_field(
    mooncode_json_object_field_or_empty(execution, "event"),
    "event",
    "inline_result",
  )
  let inline_execution = mooncode_json_object_with_field(
    execution, "event", event,
  )
  let plan = replan_compaction_test_plan([{ "role": "user", "content": "read" }])
  let checkpoint = replan_compaction_test_checkpoint(
    plan,
    [plan],
    inline_execution,
    1,
  )
  let hydrated = mooncode_runtime_continuation_for_command(
    [checkpoint],
    "replan-compaction-command",
  )
  assert_true(mooncode_runtime_planner_replan_continuation_is_active(hydrated))
  assert_eq(
    mooncode_json_array_items(hydrated, "tool_results")[0].stringify(),
    inline_execution.stringify(),
  )
  assert_eq(
    mooncode_json_array_items(hydrated, "step_results")[0].stringify(),
    inline_execution.stringify(),
  )
}

///|
test "replan checkpoints compact history and journaled result bodies" {
  let large_body = "large-result-body:" + "x".repeat(32768)
  let execution = replan_compaction_test_execution(
    "replan-result-1", "replan-compaction-command", large_body,
  )
  let messages1 : Array[Json] = [{ "role": "user", "content": "first" }]
  let plan1 = replan_compaction_test_plan(messages1)
  let checkpoint1 = replan_compaction_test_checkpoint(
    plan1,
    [plan1],
    execution,
    1,
  )
  let messages2 : Array[Json] = [
    { "role": "user", "content": "first" },
    { "role": "assistant", "content": "reading" },
    {
      "role": "tool",
      "content": "read complete",
      "tool_call_id": "call-read-1",
    },
  ]
  let plan2 = replan_compaction_test_plan(messages2)
  let checkpoint2 = replan_compaction_test_checkpoint(
    plan2,
    [plan1, plan2],
    execution,
    2,
  )
  let messages3 : Array[Json] = [
    { "role": "user", "content": "first" },
    { "role": "assistant", "content": "reading" },
    {
      "role": "tool",
      "content": "read complete",
      "tool_call_id": "call-read-1",
    },
    { "role": "user", "content": "third" },
  ]
  let plan3 = replan_compaction_test_plan(messages3)
  let checkpoint3 = replan_compaction_test_checkpoint(
    plan3,
    [plan1, plan2, plan3],
    execution,
    3,
  )
  for checkpoint in [checkpoint1, checkpoint2, checkpoint3] {
    for historical in mooncode_json_array_items(checkpoint, "planner_steps") {
      assert_eq(
        mooncode_json_array_items(historical, "model_messages").length(),
        0,
      )
    }
    assert_false(checkpoint.stringify().contains(large_body))
  }
  assert_eq(
    mooncode_json_array_items(
      mooncode_json_object_field_or_empty(checkpoint3, "plan"),
      "model_messages",
    ).length(),
    messages3.length(),
  )
  let body_size = large_body.length()
  assert_true(
    checkpoint2.stringify().length() - checkpoint1.stringify().length() <
    body_size,
  )
  assert_true(
    checkpoint3.stringify().length() - checkpoint2.stringify().length() <
    body_size,
  )
}

///|
async test "compact continuation hydrates through the real journal" {
  @fsx.with_temporary_directory("mooncode-replan-compaction-XXXXXX", async fn(
    root,
  ) {
    let session_id = "replan-round-trip-session"
    let command_id = "replan-compaction-command"
    let event_id = "replan-result-round-trip"
    let body = "full execution result"
    let execution = replan_compaction_test_execution(event_id, command_id, body)
    let result_event = mooncode_json_object_field_or_empty(execution, "event")
    let plan = replan_compaction_test_plan([
      { "role": "user", "content": "read README" },
    ])
    let checkpoint = mooncode_runtime_planner_replan_continuation_event(
      session_id,
      command_id,
      plan,
      finish_rejected=false,
      [plan],
      [execution],
      [execution],
      next_step_index=1,
      replan_count=1,
      guidance="continue",
      now=@clock.Timestamp::from_ms(1001L),
    )
    mooncode_append_session_journal(
      root,
      session_id,
      mooncode_journal_event(),
      result_event,
    )
    mooncode_append_session_journal(
      root,
      session_id,
      mooncode_journal_event(),
      checkpoint,
    )
    let events = mooncode_journal_entries(
      mooncode_read_session_journal(root, session_id),
      mooncode_journal_event(),
    )
    let hydrated = mooncode_runtime_continuation_for_command(events, command_id)
    assert_true(
      mooncode_runtime_planner_replan_continuation_is_active(hydrated),
    )
    assert_eq(
      mooncode_json_array_items(hydrated, "tool_results")[0].stringify(),
      execution.stringify(),
    )
    assert_eq(
      mooncode_json_array_items(hydrated, "step_results")[0].stringify(),
      execution.stringify(),
    )
    assert_false(
      mooncode_json_array_items(hydrated, "tool_results")[0]
      .stringify()
      .contains("journal_sequence"),
    )
  })
}

///|
test "corrupt compact references fail closed without fallback" {
  let command_id = "replan-compaction-command"
  let execution = replan_compaction_test_execution(
    "replan-result-corruption", command_id, "complete result",
  )
  let event = mooncode_json_object_field_or_empty(execution, "event")
  let plan = replan_compaction_test_plan([{ "role": "user", "content": "read" }])
  let valid = replan_compaction_test_checkpoint(plan, [plan], execution, 1)
  let references = mooncode_json_array_items(valid, "tool_result_references")
  let bad_id_reference = mooncode_json_object_with_field(
    references[0],
    "event_id",
    "wrong-event-id",
  )
  let bad_digest_reference = mooncode_json_object_with_field(
    references[0],
    "event_digest",
    "wrong-digest",
  )
  let bad_id = mooncode_json_object_with_field(
    valid,
    "tool_result_references",
    Json::array([bad_id_reference]),
  )
  let bad_digest = mooncode_json_object_with_field(
    valid,
    "tool_result_references",
    Json::array([bad_digest_reference]),
  )
  for malformed in [bad_id, bad_digest] {
    let hydrated = mooncode_runtime_continuation_for_command(
      [event, malformed],
      command_id,
    )
    assert_eq(hydrated.stringify(), "{}")
    assert_false(
      mooncode_runtime_planner_replan_continuation_is_active(hydrated),
    )
  }
  let hydrated = mooncode_runtime_continuation_for_command(
    [event, valid, bad_digest],
    command_id,
  )
  assert_eq(hydrated.stringify(), "{}")
  assert_false(mooncode_runtime_planner_replan_continuation_is_active(hydrated))
}

///|
test "old inline replan continuation remains unchanged and active" {
  let session_id = "old-inline-session"
  let command_id = "replan-compaction-command"
  let execution = replan_compaction_test_execution(
    "old-inline-result", command_id, "old full result",
  )
  let plan = replan_compaction_test_plan([{ "role": "user", "content": "read" }])
  let inline : Json = {
    "id": "moonclaw-old-inline-session-replan-compaction-command-planner-replan-checkpoint-1-1",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "target_command_id": command_id,
    "lane": "runtime-control",
    "kind": mooncode_runtime_continuation_kind(),
    "event": mooncode_runtime_continuation_kind(),
    "state": "planner-replan-paused",
    "status": "paused",
    "reason": "planner-empty-followup",
    "next_step_index": 1,
    "replan_count": 1,
    "patient_replan_guidance": "continue",
    "plan": plan,
    "finish_rejected": false,
    "planner_steps": [plan],
    "tool_results": [execution],
    "step_results": [execution],
    "created_at": @clock.Timestamp::from_ms(1001L),
    "source": "moonclaw-native-runtime-continuation",
  }
  let decoded = mooncode_runtime_continuation_for_command([inline], command_id)
  assert_eq(decoded.stringify(), inline.stringify())
  assert_true(mooncode_runtime_planner_replan_continuation_is_active(decoded))
}
