///|
fn mooncode_context_test_kind(message : Json) -> String {
  mooncode_runtime_context_kind_key(mooncode_runtime_context_kind(message))
}

///|
test "mooncode context provenance covers initial system skill and user fragments" {
  let command : Json = {
    "command": "prompt",
    "text": "Inspect README.md and explain it.",
  }
  let messages = mooncode_runtime_turn_model_initial_messages(command)
  assert_eq(messages.length(), 3)
  assert_eq(mooncode_context_test_kind(messages[0]), "system")
  assert_eq(mooncode_context_test_kind(messages[1]), "skill")
  assert_eq(mooncode_context_test_kind(messages[2]), "user")
  let request = mooncode_runtime_turn_model_plan_request_from_messages(
    "test-model",
    messages,
    tools=[],
  ).to_json()
  let provider_messages = mooncode_json_array_items(request, "messages")
  assert_eq(provider_messages.length(), messages.length())
  for index in 0..<messages.length() {
    assert_eq(
      provider_messages[index],
      mooncode_runtime_context_visible_message(messages[index]),
    )
  }
  assert_false(
    request.stringify().contains(MOONCODE_CONTEXT_PROVENANCE_CONTRACT),
  )
}

///|
test "mooncode context provenance does not inflate provider metrics" {
  let messages : Array[Json] = [
    mooncode_runtime_context_text_message(
      "system",
      "system contract",
      SystemContext,
      "planner.system",
    ),
    mooncode_runtime_context_text_message(
      "user",
      "mission",
      UserContext,
      "user.task_contract",
    ),
  ]
  let request = mooncode_runtime_turn_model_plan_request_from_messages(
    "test-model",
    messages,
    tools=[],
  ).to_json()
  let metrics = mooncode_runtime_turn_planner_metrics(
    request,
    { "usage": {} },
    messages,
    [],
  )
  assert_false(mooncode_json_bool(metrics, "request_compacted", default=true))
  assert_eq(
    mooncode_json_int(metrics, "configured_request_chars", default=-1),
    mooncode_json_int(metrics, "effective_request_chars", default=-2),
  )
}

///|
test "mooncode injected context identifies environment warning tool and user content" {
  let environment = mooncode_runtime_context_text_message(
    "user",
    "runtime context",
    EnvironmentContext,
    "environment.fixture",
  )
  let warning = mooncode_runtime_context_text_message(
    "user",
    "warning",
    WarningContext,
    "warning.fixture",
  )
  let tool = mooncode_runtime_turn_model_tool_result_message(
    {
      "tool": "read",
      "tool_call_id": "call-read",
      "planner": "model-tool-call",
    },
    {
      "tool": "read",
      "accepted": true,
      "result": { "ok": true, "output": "book" },
    },
  )
  let user = mooncode_runtime_turn_model_live_steering_message({
    "command_id": "steer-1",
    "steering_text": "Use docs/spec.md",
  })
  assert_eq(mooncode_context_test_kind(environment), "environment")
  assert_eq(mooncode_context_test_kind(warning), "warning")
  assert_eq(mooncode_context_test_kind(tool), "tool_result")
  assert_eq(mooncode_context_test_kind(user), "user")
}

///|
test "mooncode v2 context provenance closes unknown kinds but keeps v1 readable" {
  let message : Json = {
    "role": "user",
    "content": "future retrieval context",
    "_moonclaw_context": {
      "contract": MOONCODE_CONTEXT_PROVENANCE_CONTRACT,
      "kind": "retrieval_v2",
      "source": "extension.search",
      "future_field": { "rank": 2 },
    },
  }
  let normalized = mooncode_runtime_context_normalize_message(message)
  assert_eq(mooncode_context_test_kind(normalized), "user")
  assert_false(normalized == message)
  let legacy : Json = {
    "role": "user",
    "content": "future retrieval context",
    "_moonclaw_context": {
      "contract": MOONCODE_CONTEXT_PROVENANCE_CONTRACT_V1,
      "kind": "retrieval_v2",
      "source": "extension.search",
    },
  }
  let normalized_legacy = mooncode_runtime_context_normalize_message(legacy)
  assert_eq(normalized_legacy, legacy)
  assert_true(
    mooncode_runtime_context_kind(normalized_legacy)
    is UnknownContext("retrieval_v2"),
  )
  let durable = mooncode_runtime_turn_durable_model_message(normalized_legacy)
  assert_eq(durable, legacy)
  assert_eq(
    mooncode_json_string(durable, "content", default=""),
    "future retrieval context",
  )
}

///|
test "mooncode v2 context provenance is cardinality checked per content item" {
  let message = mooncode_runtime_context_message(
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "Inspect this" },
        {
          "type": "image_url",
          "image_url": { "url": "data:image/png;base64,eA==" },
        },
      ],
    },
    UserContext,
    "user.multimodal",
  )
  assert_true(mooncode_runtime_context_message_provenance_valid(message))
  let metadata = mooncode_runtime_context_provenance(message)
  assert_eq(mooncode_json_array_items(metadata, "content_items").length(), 2)
  let malformed = mooncode_json_object_with_field(
    message,
    MOONCODE_CONTEXT_PROVENANCE_FIELD,
    mooncode_json_object_with_field(
      metadata,
      "content_items",
      Json::array([{ "kind": "user", "source": "user.multimodal" }]),
    ),
  )
  assert_false(mooncode_runtime_context_message_provenance_valid(malformed))
  let repaired = mooncode_runtime_context_normalize_message(malformed)
  assert_true(mooncode_runtime_context_message_provenance_valid(repaired))
  assert_eq(
    mooncode_json_array_items(
      mooncode_runtime_context_provenance(repaired),
      "content_items",
    ).length(),
    2,
  )
}

///|
test "mooncode malformed provenance fails soft without changing content" {
  let malformed_messages : Array[Json] = [
    { "role": "user", "content": "one", "_moonclaw_context": "not-an-object" },
    {
      "role": "user",
      "content": "two",
      "_moonclaw_context": {
        "contract": MOONCODE_CONTEXT_PROVENANCE_CONTRACT,
        "source": "missing.kind",
      },
    },
    {
      "role": "user",
      "content": "three",
      "_moonclaw_context": {
        "contract": "unknown.contract",
        "kind": "user",
        "source": "bad.contract",
      },
    },
    {
      "role": "user",
      "content": "four",
      "_moonclaw_context": {
        "contract": MOONCODE_CONTEXT_PROVENANCE_CONTRACT,
        "kind": "not valid",
        "source": "bad.kind",
      },
    },
  ]
  for message in malformed_messages {
    let content = mooncode_json_string(message, "content", default="")
    let normalized = mooncode_runtime_context_normalize_message(message)
    assert_eq(mooncode_json_string(normalized, "content", default=""), content)
    assert_eq(mooncode_context_test_kind(normalized), "user")
    assert_true(
      mooncode_runtime_context_provenance_valid(
        mooncode_runtime_context_provenance(normalized),
      ),
    )
  }
}

///|
test "mooncode provenance merge survives overload compaction and length changes" {
  let source : Array[Json] = [
    mooncode_runtime_context_text_message(
      "system",
      "system contract",
      SystemContext,
      "planner.system",
    ),
    mooncode_runtime_context_text_message(
      "user",
      "user mission",
      UserContext,
      "user.task_contract",
    ),
    mooncode_runtime_context_message(
      {
        "role": "assistant",
        "content": "",
        "tool_calls": [
          {
            "id": "call-read",
            "type": "function",
            "function": { "name": "read", "arguments": "{}" },
          },
        ],
      },
      AssistantContext,
      "assistant.model_response",
    ),
    mooncode_runtime_context_message(
      {
        "role": "tool",
        "tool_call_id": "call-read",
        "content": "complete tool evidence",
      },
      ToolResultContext,
      "tool_result.execution",
    ),
  ]
  let provider : Array[Json] = [
    mooncode_runtime_context_visible_message(source[0]),
    mooncode_runtime_context_visible_message(source[1]),
    {
      "role": "user",
      "content": "MoonCode compacted 8 older transport messages after repeated provider overload.",
    },
    mooncode_runtime_context_visible_message(source[2]),
    {
      "role": "tool",
      "tool_call_id": "call-read",
      "content": "compacted evidence",
    },
  ]
  let merged = mooncode_runtime_context_merge_messages(provider, source)
  assert_eq(merged.length(), provider.length())
  assert_eq(mooncode_context_test_kind(merged[0]), "system")
  assert_eq(mooncode_context_test_kind(merged[1]), "user")
  assert_eq(mooncode_context_test_kind(merged[2]), "environment")
  assert_eq(mooncode_context_test_kind(merged[3]), "assistant")
  assert_eq(mooncode_context_test_kind(merged[4]), "tool_result")
  for index in 0..<provider.length() {
    assert_eq(
      mooncode_runtime_context_visible_message(merged[index]),
      provider[index],
    )
  }
}

///|
test "mooncode continuation journal roundtrip preserves provenance alignment" {
  let messages : Array[Json] = [
    mooncode_runtime_context_text_message(
      "system",
      "system",
      SystemContext,
      "planner.system",
    ),
    mooncode_runtime_context_text_message(
      "user",
      "mission",
      UserContext,
      "user.task_contract",
    ),
  ]
  let plan : Json = {
    "kind": mooncode_kind_runtime_turn_planner(),
    "protocol": mooncode_protocol_version(),
    "planner_mode": mooncode_planner_mode_model_tool_calls(),
    "model": "test-model",
    "tool_calls": [],
    "model_messages": Json::array(messages),
    "model_response_message": mooncode_runtime_context_text_message(
      "assistant",
      "done",
      AssistantContext,
      "assistant.model_response",
    ),
  }
  let checkpoint = mooncode_runtime_planner_continuation_event(
    "session-context",
    "cmd-context",
    plan,
    [plan],
    [],
    [],
    next_step_index=1,
    now=@clock.Timestamp::from_ms(42L),
  )
  let decoded = @json.parse(checkpoint.stringify())
  let stored_plan = mooncode_json_object_field_or_empty(decoded, "plan")
  let stored = mooncode_json_array_items(stored_plan, "model_messages")
  assert_eq(stored.length(), messages.length())
  assert_eq(mooncode_context_test_kind(stored[0]), "system")
  assert_eq(mooncode_context_test_kind(stored[1]), "user")
  assert_eq(mooncode_json_string(stored[1], "content", default=""), "mission")
}
