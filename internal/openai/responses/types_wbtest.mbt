///|
test "Responses request carries bounded reasoning options" {
  let request = ResponsesRequest::new(
    model="gpt-5.6-sol",
    input=[message_input(role="user", content="Read README.md")],
    instructions="Use one bounded tool batch.",
    reasoning_effort="minimal",
    reasoning_context="all_turns",
    stream=true,
    store=true,
    previous_response_id="resp_previous",
    prompt_cache_key="moonclaw-session:test",
    prompt_cache_mode="implicit",
    prompt_cache_ttl="24h",
    max_output_tokens=2048,
    parallel_tool_calls=true,
  ).to_json()
  json_inspect(request, content={
    "model": "gpt-5.6-sol",
    "input": [
      {
        "type": "message",
        "role": "user",
        "content": [{ "type": "input_text", "text": "Read README.md" }],
      },
    ],
    "instructions": "Use one bounded tool batch.",
    "tools": [],
    "tool_choice": "auto",
    "stream": true,
    "reasoning": { "effort": "minimal", "context": "all_turns" },
    "store": true,
    "previous_response_id": "resp_previous",
    "prompt_cache_key": "moonclaw-session:test",
    "prompt_cache_options": { "mode": "implicit", "ttl": "24h" },
    "max_output_tokens": 2048,
    "parallel_tool_calls": true,
  })
}
