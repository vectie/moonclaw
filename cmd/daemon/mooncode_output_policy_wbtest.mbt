///|
test "mooncode output policy preserves the current default without a flag" {
  assert_eq(
    mooncode_normalize_tool_output_chars(0),
    MOONCODE_DEFAULT_TOOL_OUTPUT_CHARS,
  )
  let body = mooncode_runtime_turn_tool_body(
    {
      "command": "prompt",
      "session_id": "session-output-default",
      "packet": { "command_id": "command-output-default" },
    },
    { "tool": "read", "arguments": { "path": "README.md" } },
  )
  let arguments = mooncode_json_object_field_or_empty(body, "arguments")
  assert_eq(mooncode_json_int(arguments, "max_output_chars", default=-1), -1)
}

///|
test "mooncode output policy permits a larger bounded opt-in" {
  let body = mooncode_runtime_turn_tool_body(
    {
      "command": "prompt",
      "session_id": "session-output-large",
      "packet": { "command_id": "command-output-large" },
      "payload": { "planner_tool_output_chars": 120000 },
    },
    { "tool": "read", "arguments": { "path": "README.md" } },
  )
  let arguments = mooncode_json_object_field_or_empty(body, "arguments")
  assert_eq(mooncode_json_int(arguments, "max_output_chars", default=0), 120000)
  assert_true(
    mooncode_json_bool(
      arguments,
      "mooncode_large_output_enabled",
      default=false,
    ),
  )
  let capped = mooncode_cap_tool_output(
    "x".repeat(150000),
    mooncode_json_int(arguments, "max_output_chars", default=0),
    maximum=mooncode_tool_output_maximum(arguments),
  )
  assert_eq(mooncode_json_string(capped, "output", default="").length(), 120000)
}

///|
test "mooncode output policy clamps opt-in and preserves explicit tool limits" {
  let command : Json = { "payload": { "planner_tool_output_chars": 999999 } }
  let injected = mooncode_runtime_turn_apply_output_policy(command, "shell", {
    "cmd": "moon test",
  })
  assert_eq(
    mooncode_json_int(injected, "max_output_chars", default=0),
    MOONCODE_OPT_IN_TOOL_OUTPUT_MAX_CHARS,
  )
  let explicit = mooncode_runtime_turn_apply_output_policy(command, "shell", {
    "cmd": "moon test",
    "max_output_chars": 24000,
  })
  assert_eq(mooncode_json_int(explicit, "max_output_chars", default=0), 24000)
  assert_false(
    mooncode_json_bool(explicit, "mooncode_large_output_enabled", default=false),
  )
}
