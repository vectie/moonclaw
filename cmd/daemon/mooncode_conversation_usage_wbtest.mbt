///|
test "conversation usage sums only provider-observed planner responses" {
  let usage = mooncode_conversation_receipt_usage({
    "planner_steps": [
      {
        "planner_metrics": {
          "usage_observed": true,
          "prompt_tokens": 100,
          "completion_tokens": 20,
          "cache_read_tokens": 40,
        },
      },
      {
        "planner_metrics": {
          "usage_observed": false,
          "prompt_tokens": 0,
          "completion_tokens": 0,
          "cache_read_tokens": 0,
        },
      },
      {
        "planner_metrics": {
          "usage_observed": true,
          "prompt_tokens": 80,
          "completion_tokens": 15,
          "cache_read_tokens": 25,
        },
      },
    ],
  })
  assert_true(mooncode_json_bool(usage, "measured", default=false))
  assert_eq(mooncode_json_int(usage, "response_count", default=0), 2)
  assert_eq(mooncode_json_int(usage, "input_tokens", default=0), 180)
  assert_eq(mooncode_json_int(usage, "output_tokens", default=0), 35)
  assert_eq(mooncode_json_int(usage, "cached_input_tokens", default=0), 65)
  assert_eq(mooncode_conversation_receipt_usage({}).stringify(), "{}")
}
