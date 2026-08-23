///|
test "mooncode planner metrics separate cached and fresh prompt tokens" {
  let request : Json = {
    "messages": [
      { "role": "system", "content": "stable system prompt" },
      { "role": "user", "content": "inspect the workspace" },
    ],
    "tools": [
      { "type": "function", "function": { "name": "read" } },
      { "type": "function", "function": { "name": "finish" } },
    ],
  }
  let response : Json = {
    "usage": {
      "prompt_tokens": 1000,
      "completion_tokens": 120,
      "total_tokens": 1120,
      "prompt_tokens_details": { "cached_tokens": 750 },
    },
  }
  let messages = mooncode_json_array_items(request, "messages")
  let metrics = mooncode_runtime_turn_planner_metrics(
    request,
    response,
    messages,
    [{ "id": "call-1", "function": { "name": "read" } }],
  )
  assert_eq(
    mooncode_json_string(metrics, "contract", default=""),
    "moonclaw.planner.metrics.v1",
  )
  assert_eq(mooncode_json_int(metrics, "prompt_tokens", default=0), 1000)
  assert_eq(mooncode_json_int(metrics, "cache_read_tokens", default=0), 750)
  assert_eq(mooncode_json_int(metrics, "fresh_input_tokens", default=0), 250)
  assert_eq(
    mooncode_json_int(metrics, "cache_read_ratio_ppm", default=0),
    750000,
  )
  assert_eq(mooncode_json_int(metrics, "tool_count", default=0), 2)
  assert_eq(mooncode_json_int(metrics, "tool_call_count", default=0), 1)
  assert_eq(mooncode_json_array_items(metrics, "selected_tool_names"), [
    "read", "finish",
  ])
  assert_true(mooncode_json_int(metrics, "system_prompt_chars", default=0) > 0)
  assert_false(mooncode_json_bool(metrics, "request_compacted", default=true))
}

///|
test "mooncode planner metrics clamp invalid cache usage and observe compaction" {
  let request : Json = {
    "messages": [
      { "role": "system", "content": "stable" },
      { "role": "user", "content": "a very long request that was compacted" },
    ],
    "tools": [],
  }
  let effective : Array[Json] = [{ "role": "system", "content": "stable" }]
  let metrics = mooncode_runtime_turn_planner_metrics(
    request,
    {
      "usage": {
        "prompt_tokens": 10,
        "completion_tokens": 2,
        "prompt_tokens_details": { "cached_tokens": 100 },
      },
    },
    effective,
    [],
  )
  assert_eq(mooncode_json_int(metrics, "cache_read_tokens", default=0), 10)
  assert_eq(mooncode_json_int(metrics, "fresh_input_tokens", default=-1), 0)
  assert_true(mooncode_json_bool(metrics, "request_compacted", default=false))
  assert_true(
    mooncode_json_int(metrics, "effective_request_chars", default=0) <
    mooncode_json_int(metrics, "configured_request_chars", default=0),
  )
}
