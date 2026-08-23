///|
test "Responses transport is compatibility-off and provider storage stays disabled" {
  let disabled : Json = { "payload": {} }
  assert_false(mooncode_runtime_responses_transport_enabled(disabled))
  let stateless : Json = {
    "payload": {
      "planner_responses_transport": true,
      "planner_responses_store": false,
    },
  }
  assert_true(mooncode_runtime_responses_transport_enabled(stateless))
}

///|
test "Responses cache controls are closed and bounded" {
  let command : Json = {
    "session_id": "session-a",
    "payload": {
      "planner_responses_transport": true,
      "planner_prompt_cache_mode": "explicit",
      "planner_prompt_cache_ttl": "24h",
    },
  }
  assert_eq(
    mooncode_runtime_responses_prompt_cache_key(command),
    Some("moonclaw-session:session-a"),
  )
  assert_eq(
    mooncode_runtime_responses_prompt_cache_mode(command),
    Some("explicit"),
  )
  assert_eq(mooncode_runtime_responses_prompt_cache_ttl(command), Some("24h"))
}

///|
test "Responses invalid cache values fail closed" {
  let command : Json = {
    "payload": {
      "planner_responses_transport": true,
      "planner_prompt_cache_mode": "invented",
      "planner_prompt_cache_ttl": "forever",
    },
  }
  assert_true(mooncode_runtime_responses_prompt_cache_mode(command) is None)
  assert_true(mooncode_runtime_responses_prompt_cache_ttl(command) is None)
  assert_eq(mooncode_runtime_responses_transport_name(command), "responses")
}

///|
test "Responses metrics retain transport and cache write tokens" {
  let metrics = mooncode_runtime_turn_planner_metrics(
    {
      "model": "gpt-5.6-sol",
      "messages": [{ "role": "user", "content": "inspect" }],
      "tools": [],
    },
    {
      "usage": {
        "prompt_tokens": 100,
        "completion_tokens": 20,
        "total_tokens": 120,
        "prompt_tokens_details": {
          "cached_tokens": 40,
          "cache_write_tokens": 15,
        },
      },
    },
    [{ "role": "user", "content": "inspect" }],
    [],
    model_transport="responses",
  )
  assert_eq(
    mooncode_json_string(metrics, "model_transport", default=""),
    "responses",
  )
  assert_eq(mooncode_json_int(metrics, "cache_write_tokens", default=0), 15)
}
