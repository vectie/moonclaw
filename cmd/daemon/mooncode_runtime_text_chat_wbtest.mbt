///|
test "explicit text-only transport sends no tools or unsupported controls" {
  let request = mooncode_runtime_text_chat_request("gemini-4-neon", [
    { "role": "system", "content": "Call tools to edit the book" },
    { "role": "user", "content": "Reply hello" },
  ]).to_json()
  guard request is Object(fields) else { fail("expected object") }
  assert_eq(fields.length(), 3)
  assert_true(fields.contains("model"))
  assert_true(fields.contains("messages"))
  assert_true(fields.contains("stream"))
  assert_true(
    request
    is {
      "messages": [
        { "role": "system", "content": String(text), .. },
        { "role": "user", "content": "Reply hello", .. },
      ],
      ..
    } &&
    text.contains("text-only"),
  )
  let calls = mooncode_runtime_turn_tool_calls_from_model_response({
    "choices": [
      {
        "message": { "role": "assistant", "content": "hello" },
        "finish_reason": "stop",
      },
    ],
  })
  assert_true(
    calls is [{ "tool": "finish", "arguments": { "answer": "hello", .. }, .. }],
  )
}

///|
test "text-only transport refuses tool history instead of silently dropping it" {
  let rejected = try {
    ignore(
      mooncode_runtime_text_chat_request("plain", [
        { "role": "tool", "content": "untrusted result", "tool_call_id": "x" },
      ]),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
