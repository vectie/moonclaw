///|
test "Responses request carries bounded reasoning options" {
  let request = ResponsesRequest::new(
    model="gpt-5.4",
    input=[message_input(role="user", content="Read README.md")],
    instructions="Use one bounded tool batch.",
    reasoning_effort="minimal",
    stream=true,
    store=false,
  ).to_json()
  json_inspect(request, content={
    "model": "gpt-5.4",
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
    "reasoning": { "effort": "minimal" },
    "store": false,
  })
}
