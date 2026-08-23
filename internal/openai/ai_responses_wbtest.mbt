///|
test "Responses transport is confined to loopback MoonGate" {
  let local_model = @model.new(
    api_key="",
    base_url="http://127.0.0.1:15721/openclaw/v1",
    name="gpt-5.6-sol",
    safe_zone_tokens=128000,
  )
  guard moongate_responses_route_for_model(local_model) is Some(route) else {
    fail("expected loopback MoonGate route")
  }
  assert_eq(route.url, "http://127.0.0.1:15721/openclaw/v1/responses")
  assert_false(route.headers.contains("Authorization"))
  let remote = @model.new(
    api_key="sk-must-not-be-used",
    base_url="https://provider.example/openclaw/v1",
    name="gpt-5.6-sol",
    safe_zone_tokens=128000,
  )
  assert_true(moongate_responses_route_for_model(remote) is None)
  for
    hostile in [
      "http://127.0.0.1:15721@remote.example/openclaw/v1", "http://localhost:15721/other/openclaw/v1",
      "http://localhost:15721/openclaw/v1?target=remote", "https://localhost:15721/openclaw/v1",
      "http://localhost:not-a-port/openclaw/v1",
    ] {
    assert_true(
      moongate_responses_route_for_model(
        @model.new(
          api_key="",
          base_url=hostile,
          name="gpt-5.6-sol",
          safe_zone_tokens=128000,
        ),
      )
      is None,
    )
  }
}

///|
test "Responses request keeps provider storage off by default" {
  let model = @model.new(
    api_key="",
    base_url="http://localhost:15721/openclaw/v1",
    name="gpt-5.6-sol",
    safe_zone_tokens=128000,
  )
  let request = chat_completion(
    model="gpt-5.6-sol",
    messages=[
      system_message(content="Keep the tool boundary explicit."),
      user_message(content="Read README.md"),
    ],
    max_tokens=2048,
    reasoning_effort=High,
    parallel_tool_calls=true,
  )
  let payload = openai_responses_request(
    model,
    request,
    prompt_cache_key="moonclaw-session:test",
    prompt_cache_mode="implicit",
  ).to_json()
  guard payload is Object(fields) else { fail("expected request object") }
  assert_true(fields.get("store") is Some(False))
  assert_false(fields.contains("previous_response_id"))
  assert_true(
    fields.get("reasoning")
    is Some({ "effort": "high", "context": "current_turn", .. }),
  )
  assert_true(fields.get("max_output_tokens") is Some(Number(2048, ..)))
  assert_true(fields.get("parallel_tool_calls") is Some(True))
}

///|
test "Responses result preserves response id and cache write usage" {
  let result : ResponsesStreamResult = {
    response_id: "resp_123",
    text_chunks: [],
    output_items: [
      @responses.ResponseItem::FunctionCall(
        call_id="call_123",
        name="read",
        arguments="{\"path\":\"README.md\"}",
      ),
    ],
    usage: Some({
      "input_tokens": 100,
      "input_tokens_details": { "cached_tokens": 60, "cache_write_tokens": 20 },
      "output_tokens": 25,
      "output_tokens_details": { "reasoning_tokens": 10 },
      "total_tokens": 125,
    }),
  }
  let completion = responses_stream_result_to_chat_completion(
    "gpt-5.6-sol", result,
  ).to_json()
  assert_eq(response_json_string(completion, "id"), "resp_123")
  let usage = response_json_field(completion, "usage").unwrap_or({})
  guard usage is Object(usage_fields) else { fail("expected usage") }
  assert_true(usage_fields.get("prompt_tokens") is Some(Number(100, ..)))
  guard usage_fields.get("prompt_tokens_details") is Some(Object(details)) else {
    fail("expected prompt token details")
  }
  assert_true(details.get("cached_tokens") is Some(Number(60, ..)))
  assert_true(details.get("cache_write_tokens") is Some(Number(20, ..)))
}

///|
test "Responses stream parser fails closed on terminal and malformed events" {
  assert_true(response_stream_event_from_data("[DONE]") is Some(Failed(_)))
  assert_true(response_stream_event_from_data("not-json") is None)
  assert_true(
    response_stream_event_from_data(
      "{\"type\":\"response.incomplete\",\"response\":{\"error\":{\"message\":\"limit reached\"}}}",
    )
    is Some(Failed("limit reached")),
  )
  assert_true(
    response_stream_event_from_data(
      "{\"type\":\"response.completed\",\"response\":{\"id\":\"resp_done\"}}",
    )
    is Some(Completed({ "id": "resp_done", .. })),
  )
  assert_true(
    response_stream_event_from_data(
      "{\"type\":\"response.completed\",\"response\":{\"id\":\"resp_partial\",\"status\":\"incomplete\",\"incomplete_details\":{\"reason\":\"max_output_tokens\"}}}",
    )
    is Some(Failed("Responses request incomplete: max_output_tokens")),
  )
}
