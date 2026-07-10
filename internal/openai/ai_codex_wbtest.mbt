///|
test "Codex transport preserves request instructions" {
  let instructions = extract_system_instructions([
    system_message(content="Plan one bounded tool batch."),
    user_message(content="Read README.md"),
    system_message(content="Stay inside the selected MoonBook."),
  ])
  assert_eq(
    instructions, "Plan one bounded tool batch.\n\nStay inside the selected MoonBook.",
  )
}

///|
test "Codex response stream exposes terminal provider errors" {
  let event : Map[String, Json] = {
    "type": "response.failed",
    "response": { "error": { "message": "provider rejected request" } },
  }
  assert_eq(response_stream_error_message(event), "provider rejected request")
}

///|
test "Codex retries only transient or refreshable HTTP failures" {
  assert_true(codex_http_status_is_fatal(400))
  assert_true(codex_http_status_is_fatal(403))
  assert_false(codex_http_status_is_fatal(401))
  assert_false(codex_http_status_is_fatal(408))
  assert_false(codex_http_status_is_fatal(429))
  assert_false(codex_http_status_is_fatal(500))
}
