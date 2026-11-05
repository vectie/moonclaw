///|
fn context_test_messages() -> Array[Json] {
  let messages : Array[Json] = [
    mooncode_runtime_context_text_message(
      "system",
      "immutable system contract",
      SystemContext,
      "system.test_contract",
    ),
    mooncode_runtime_context_text_message(
      "user",
      "complete the original task",
      UserContext,
      "user.test_task",
    ),
  ]
  for index in 0..<50 {
    let id = "call-\{index}"
    messages.push(
      mooncode_runtime_context_message(
        {
          "role": "assistant",
          "content": "reasoning anchor \{index}",
          "tool_calls": [
            {
              "id": id,
              "type": "function",
              "function": { "name": "read", "arguments": "{}" },
            },
          ],
        },
        AssistantContext,
        "assistant.test_response",
      ),
    )
    messages.push(
      mooncode_runtime_context_message(
        {
          "role": "tool",
          "tool_call_id": id,
          "content": "observed-\{index}:" + "x".repeat(240),
        },
        ToolResultContext,
        "tool_result.test_execution",
      ),
    )
  }
  messages
}

///|
async test "default context projection preserves task, latest result and source identity" {
  let messages = context_test_messages()
  let original = messages.copy()
  let first = mooncode_runtime_turn_compile_context({}, messages, [], 1500, 128)
  let second = mooncode_runtime_turn_compile_context(
    {},
    messages,
    [],
    1500,
    128,
  )
  assert_eq(messages, original)
  assert_eq(first.messages, second.messages)
  assert_eq(first.metrics, second.metrics)
  assert_true(mooncode_json_bool(first.metrics, "applied", default=false))
  assert_eq(first.messages[0], messages[0])
  assert_eq(first.messages[1], messages[1])
  let visible = Json(first.messages).stringify()
  assert_true(visible.contains("call-49"))
  assert_true(visible.contains("observed-49"))
  for message in first.messages {
    assert_true(mooncode_runtime_context_message_provenance_valid(message))
  }
  let roomy = mooncode_runtime_turn_compile_context(
    {},
    messages,
    [],
    100000,
    128,
  )
  assert_eq(roomy.messages, messages)
}

///|
test "followup refresh keeps complete task revisions and transcript before projection" {
  let messages = context_test_messages()
  let task = "updated task\n" + "constraint".repeat(2000)
  let refreshed = mooncode_runtime_turn_context_previous_messages(
    messages, task,
  )
  assert_eq(refreshed.length(), messages.length())
  assert_eq(mooncode_json_string(refreshed[1], "content", default=""), task)
  assert_eq(refreshed[refreshed.length() - 1], messages[messages.length() - 1])
}

///|
async test "recovered checkpoint uses the same context projection and current task" {
  let messages = context_test_messages()
  let plan = replan_compaction_test_plan(messages)
  let calls = mooncode_json_array_items(plan, "tool_calls")
  let plan = mooncode_json_object_with_field(
    plan,
    "tool_calls",
    Json([
      mooncode_json_object_with_field(calls[0], "tool_call_id", "call-read-1"),
    ]),
  )
  let execution = replan_compaction_test_execution(
    "context-recovery-result", "replan-compaction-command", "latest verification passed",
  )
  let checkpoint = replan_compaction_test_checkpoint(plan, [plan], execution, 1)
  let recovered = mooncode_runtime_continuation_for_command(
    [mooncode_json_object_field_or_empty(execution, "event"), checkpoint],
    "replan-compaction-command",
  )
  let command : Json = {
    "command": "prompt",
    "text": "Deliver the revised feature; preserve the public API.",
  }
  let followup = mooncode_runtime_turn_model_followup_messages(
    command,
    mooncode_json_object_field_or_empty(recovered, "plan"),
    mooncode_json_array_items(plan, "tool_calls"),
    mooncode_json_array_items(recovered, "step_results"),
    mooncode_json_array_items(recovered, "tool_results"),
    [],
    -1,
  )
  let projected = mooncode_runtime_turn_compile_context(
    command,
    followup,
    [],
    3000,
    128,
  )
  assert_true(mooncode_json_bool(projected.metrics, "applied", default=false))
  let visible = Json(projected.messages).stringify()
  assert_true(
    visible.contains("Deliver the revised feature; preserve the public API."),
  )
  assert_true(visible.contains("latest verification passed"))
  assert_true(visible.contains("context-recovery-result"))
  assert_true(visible.contains("immutable system contract"))
  assert_eq(mooncode_json_array_items(recovered, "tool_results"), [execution])
}
