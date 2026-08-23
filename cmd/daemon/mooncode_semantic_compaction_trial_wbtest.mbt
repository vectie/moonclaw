///|
fn semantic_compaction_trial_plan(count : Int) -> Json {
  let messages : Array[Json] = []
  for index in 0..<count {
    messages.push({ "role": "assistant", "content": "message-\{index}" })
  }
  { "model_messages": Json::array(messages) }
}

///|
test "mooncode semantic compaction trial is off and very-long only" {
  let disabled = mooncode_runtime_turn_semantic_compaction_trial(
    { "payload": {} },
    semantic_compaction_trial_plan(120),
    [],
  )
  assert_false(mooncode_json_bool(disabled, "enabled", default=true))
  assert_false(mooncode_json_bool(disabled, "eligible", default=true))
  assert_eq(mooncode_json_string(disabled, "mode", default=""), "shadow")

  let command : Json = {
    "payload": {
      "planner_hybrid_semantic_compaction_trial": true,
      "planner_context_window_tokens": 1000,
    },
  }
  let short = mooncode_runtime_turn_semantic_compaction_trial(
    command,
    semantic_compaction_trial_plan(95),
    [],
  )
  assert_false(mooncode_json_bool(short, "eligible", default=true))
  let long = mooncode_runtime_turn_semantic_compaction_trial(
    command,
    semantic_compaction_trial_plan(96),
    [],
  )
  assert_true(mooncode_json_bool(long, "eligible", default=false))
  assert_true(
    mooncode_json_int(long, "context_pressure_ppm", default=0) >= 750000,
  )
  assert_eq(
    mooncode_json_string(long, "reason", default=""),
    "eligible-for-offline-semantic-summary-evaluation",
  )
}

///|
test "mooncode semantic compaction follows context pressure" {
  let command : Json = {
    "payload": {
      "planner_hybrid_semantic_compaction_trial": true,
      "planner_context_window_tokens": 100000,
    },
  }
  let low = mooncode_runtime_turn_semantic_compaction_trial(
    command,
    semantic_compaction_trial_plan(96),
    [],
  )
  assert_false(mooncode_json_bool(low, "eligible", default=true))
  assert_eq(
    mooncode_json_string(low, "reason", default=""),
    "below-context-pressure-threshold",
  )

  let unknown = mooncode_runtime_turn_semantic_compaction_trial(
    { "payload": { "planner_hybrid_semantic_compaction_trial": true } },
    semantic_compaction_trial_plan(96),
    [],
  )
  assert_false(mooncode_json_bool(unknown, "eligible", default=true))
  assert_eq(
    mooncode_json_string(unknown, "reason", default=""),
    "context-window-unknown",
  )
}

///|
test "mooncode semantic compaction prefers provider prompt usage" {
  let messages = mooncode_json_array_items(
    semantic_compaction_trial_plan(96),
    "model_messages",
  )
  let previous : Json = {
    "model_messages": Json::array(messages),
    "planner_metrics": { "prompt_tokens": 80000 },
  }
  let trial = mooncode_runtime_turn_semantic_compaction_trial(
    {
      "payload": {
        "planner_hybrid_semantic_compaction_trial": true,
        "planner_context_window_tokens": 100000,
      },
    },
    previous,
    [],
  )
  assert_true(mooncode_json_bool(trial, "eligible", default=false))
  assert_eq(
    mooncode_json_int(trial, "estimated_context_tokens", default=0),
    80000,
  )
  assert_eq(
    mooncode_json_int(trial, "observed_context_tokens", default=0),
    80000,
  )
  assert_eq(
    mooncode_json_string(trial, "context_usage_source", default=""),
    "provider-prompt-tokens",
  )
}

///|
test "mooncode semantic compaction threshold is bounded" {
  assert_eq(
    mooncode_runtime_turn_semantic_compaction_trial_threshold({
      "payload": { "planner_semantic_compaction_message_threshold": 1 },
    }),
    64,
  )
  assert_eq(
    mooncode_runtime_turn_semantic_compaction_trial_threshold({
      "payload": { "planner_semantic_compaction_message_threshold": 9999 },
    }),
    512,
  )
}
