///|
test "planner observations use the compiled request and observed provider usage" {
  let request : Json = { "messages": [], "tools": [] }
  let metrics = mooncode_runtime_turn_planner_metrics(
    request,
    {
      "usage": {
        "prompt_tokens": 10000,
        "completion_tokens": 120,
        "prompt_tokens_details": { "cached_tokens": 7500 },
      },
    },
    [],
    model_retry_count=2,
    planner_latency_ms=25,
  )
  assert_true(mooncode_json_bool(metrics, "usage_observed", default=false))
  assert_eq(mooncode_json_int(metrics, "cache_read_tokens", default=0), 7500)
  assert_eq(mooncode_json_int(metrics, "model_retry_count", default=0), 2)
  assert_eq(mooncode_json_int(metrics, "planner_latency_ms", default=0), 25)
  assert_eq(
    mooncode_json_int(metrics, "request_chars", default=0),
    request.stringify().length(),
  )
  let absent : Array[Json] = [
    {},
    { "usage": { "prompt_tokens": -1, "completion_tokens": 20 } },
  ]
  for response in absent {
    let missing = mooncode_runtime_turn_planner_metrics(request, response, [])
    assert_false(mooncode_json_bool(missing, "usage_observed", default=true))
  }
}
