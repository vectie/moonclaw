///|
fn semantic_compaction_lifecycle_test_messages() -> Array[Json] {
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
fn semantic_compaction_lifecycle_active_command(
  context_window_tokens? : Int = 1000,
) -> Json {
  {
    "payload": {
      "planner_hybrid_semantic_compaction_active": true,
      "planner_context_window_tokens": context_window_tokens,
      "planner_semantic_compaction_message_threshold": 64,
      "planner_semantic_compaction_pressure_threshold_ppm": 750000,
      "planner_semantic_compaction_target_pressure_ppm": 500000,
    },
  }
}

///|
fn semantic_compaction_lifecycle_previous_plan(
  prompt_tokens? : Int = 800,
) -> Json {
  { "planner_metrics": { "prompt_tokens": prompt_tokens } }
}

///|
test "active mode defers the unreachable legacy 32-message projection" {
  let messages = semantic_compaction_lifecycle_test_messages()
  let previous : Json = { "model_messages": Json::array(messages) }
  let compatibility = mooncode_runtime_turn_model_followup_base_messages(
    { "command": "prompt", "text": "complete the original task" },
    previous,
    [],
  )
  let active = mooncode_runtime_turn_model_followup_base_messages(
    {
      "command": "prompt",
      "text": "complete the original task",
      "payload": { "planner_hybrid_semantic_compaction_active": true },
    },
    previous,
    [],
  )
  assert_true(compatibility.length() < 64)
  assert_eq(active.length(), messages.length())
  assert_true(active.length() >= 96)
  assert_true(
    mooncode_json_string(active[1], "content", default="").contains(
      "complete the original task",
    ),
  )
}

///|
async test "active semantic compaction is default-off and pressure gated" {
  let tools : Array[@openai.ChatCompletionToolParam] = []
  let messages = semantic_compaction_lifecycle_test_messages()
  let disabled = mooncode_runtime_turn_active_semantic_compaction(
    { "payload": { "planner_context_window_tokens": 1000 } },
    semantic_compaction_lifecycle_previous_plan(),
    messages,
    tools,
    1000,
  )
  assert_eq(disabled.messages, messages)
  assert_false(mooncode_json_bool(disabled.metrics, "enabled", default=true))
  assert_eq(
    mooncode_json_string(disabled.metrics, "reason", default=""),
    "flag-disabled",
  )

  let low_pressure = mooncode_runtime_turn_active_semantic_compaction(
    semantic_compaction_lifecycle_active_command(context_window_tokens=100000),
    semantic_compaction_lifecycle_previous_plan(prompt_tokens=1000),
    messages,
    tools,
    100000,
  )
  assert_eq(low_pressure.messages, messages)
  assert_false(
    mooncode_json_bool(low_pressure.metrics, "eligible", default=true),
  )
  assert_eq(
    mooncode_json_string(low_pressure.metrics, "reason", default=""),
    "below-context-pressure-threshold",
  )
}

///|
async test "active semantic compaction is deterministic and preserves contracts" {
  let tools : Array[@openai.ChatCompletionToolParam] = []
  let messages = semantic_compaction_lifecycle_test_messages()
  let command = semantic_compaction_lifecycle_active_command()
  let previous = semantic_compaction_lifecycle_previous_plan()
  let first = mooncode_runtime_turn_active_semantic_compaction(
    command, previous, messages, tools, 1000,
  )
  let second = mooncode_runtime_turn_active_semantic_compaction(
    command, previous, messages, tools, 1000,
  )
  assert_true(mooncode_json_bool(first.metrics, "applied", default=false))
  assert_eq(first.messages, second.messages)
  assert_eq(first.metrics, second.metrics)
  assert_true(
    mooncode_json_int(first.metrics, "after_message_chars", default=0) <
    mooncode_json_int(first.metrics, "before_message_chars", default=0),
  )
  assert_true(
    mooncode_json_int(first.metrics, "compacted_messages", default=0) > 0,
  )
  assert_true(
    mooncode_json_bool(first.metrics, "invariants_preserved", default=false),
  )
  assert_true(
    mooncode_runtime_turn_semantic_compaction_provenance_valid(first.messages),
  )
  assert_true(
    mooncode_runtime_turn_semantic_compaction_tool_protocol_valid(
      first.messages,
    ),
  )
  assert_eq(
    mooncode_runtime_turn_semantic_compaction_instructions(first.messages),
    mooncode_runtime_turn_semantic_compaction_instructions(messages),
  )
  let visible = Json::array(
    mooncode_runtime_context_visible_messages(first.messages),
  ).stringify()
  assert_true(visible.contains("complete the original task"))
  assert_true(visible.contains("Context checkpoint: MoonClaw compacted"))
  assert_true(visible.contains("call-49"))
  assert_true(visible.contains("observed-49"))
  let mut checkpoint : Json? = None
  for message in first.messages {
    if mooncode_json_string(message, "content", default="").contains(
        "Context checkpoint: MoonClaw compacted",
      ) {
      checkpoint = Some(message)
      break
    }
  }
  guard checkpoint is Some(checkpoint) else { fail("missing checkpoint") }
  assert_true(mooncode_runtime_context_kind(checkpoint) is EnvironmentContext)
}

///|
async test "active semantic compaction refuses malformed or late-instruction input" {
  let tools : Array[@openai.ChatCompletionToolParam] = []
  let command = semantic_compaction_lifecycle_active_command()
  let previous = semantic_compaction_lifecycle_previous_plan()

  let orphan = semantic_compaction_lifecycle_test_messages()
  orphan.push(
    mooncode_runtime_context_message(
      { "role": "tool", "tool_call_id": "orphan", "content": "bad" },
      ToolResultContext,
      "tool_result.orphan",
    ),
  )
  let orphan_result = mooncode_runtime_turn_active_semantic_compaction(
    command, previous, orphan, tools, 1000,
  )
  assert_eq(orphan_result.messages, orphan)
  assert_eq(
    mooncode_json_string(orphan_result.metrics, "reason", default=""),
    "source-invariant-invalid",
  )

  let late_system = semantic_compaction_lifecycle_test_messages()
  late_system.push(
    mooncode_runtime_context_text_message(
      "system",
      "late immutable contract",
      SystemContext,
      "system.late_contract",
    ),
  )
  let late_result = mooncode_runtime_turn_active_semantic_compaction(
    command, previous, late_system, tools, 1000,
  )
  assert_eq(late_result.messages, late_system)
  assert_eq(
    mooncode_json_string(late_result.metrics, "reason", default=""),
    "source-invariant-invalid",
  )

  let invalid_provenance = semantic_compaction_lifecycle_test_messages()
  invalid_provenance[10] = mooncode_json_object_with_field(
    invalid_provenance[10],
    MOONCODE_CONTEXT_PROVENANCE_FIELD,
    { "contract": "wrong", "kind": "tool_result", "source": "test" },
  )
  let provenance_result = mooncode_runtime_turn_active_semantic_compaction(
    command, previous, invalid_provenance, tools, 1000,
  )
  assert_eq(provenance_result.messages, invalid_provenance)
  assert_eq(
    mooncode_json_string(provenance_result.metrics, "reason", default=""),
    "source-invariant-invalid",
  )
}

///|
async test "unsupported developer message is retained byte-identically" {
  let tools : Array[@openai.ChatCompletionToolParam] = []
  let messages : Array[Json] = [
    mooncode_runtime_context_text_message(
      "system",
      "system contract",
      SystemContext,
      "system.test_contract",
    ),
    mooncode_runtime_context_text_message(
      "developer",
      "developer contract",
      SystemContext,
      "system.developer_contract",
    ),
    mooncode_runtime_context_text_message(
      "user",
      "task",
      UserContext,
      "user.test_task",
    ),
  ]
  for message in semantic_compaction_lifecycle_test_messages()[2:] {
    messages.push(message)
  }
  let result = mooncode_runtime_turn_active_semantic_compaction(
    semantic_compaction_lifecycle_active_command(),
    semantic_compaction_lifecycle_previous_plan(),
    messages,
    tools,
    1000,
  )
  assert_eq(result.messages, messages)
  assert_eq(
    mooncode_json_string(result.metrics, "reason", default=""),
    "unsupported-message-shape",
  )
  assert_true(
    Json::array(mooncode_runtime_context_visible_messages(result.messages))
    .stringify()
    .contains("developer contract"),
  )
}
