///|
test "ACP coding transport preserves real tools and omits unsupported generation controls" {
  let request = mooncode_runtime_acp_tool_request(
    "gemini-4-neon",
    [
      { "role": "system", "content": "Use the caller's registered tools" },
      { "role": "user", "content": "Edit the selected Book" },
    ],
    mooncode_runtime_turn_model_tools(),
  ).to_json()
  guard request is Object(fields) else { fail("expected object") }
  assert_eq(fields.length(), 4)
  assert_true(fields.contains("model"))
  assert_true(fields.contains("messages"))
  assert_true(fields.contains("stream"))
  assert_true(fields.get("tools") is Some(Array(tools)) && !tools.is_empty())
}
