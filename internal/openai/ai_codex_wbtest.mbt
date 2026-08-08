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
test "Codex OAuth request payload uses exact gpt-5.6-sol model" {
  let model = @model.codex_oauth_model(
    access_token="test-access",
    account_id="test-account",
    refresh_token="test-refresh",
  )
  let payload = codex_responses_request(
    model,
    chat_completion(model="must-not-reach-wire", messages=[
      user_message(content="Read README.md"),
    ]),
  ).to_json()
  guard payload is Object(fields) else { fail("expected Codex request object") }
  guard fields.get("model") is Some(String(request_model)) else {
    fail("expected Codex request model")
  }
  assert_eq(request_model, "gpt-5.6-sol")
  assert_false(payload.stringify().contains("gpt-5.4"))
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

///|
test "provider error classification separates Ark overload from quota" {
  let overloaded : Error = HttpRetryError(
    code=429,
    body="{\"error\":{\"code\":\"ServerOverloaded\"}}",
    retry_after_ms=Some(45000),
  )
  assert_eq(error_class(overloaded), "server_overloaded")
  assert_true(error_is_transient(overloaded))
  assert_eq(error_retry_after_ms(overloaded), Some(45000))
  let quota : Error = HttpRetryError(
    code=429,
    body="{\"error\":{\"code\":\"QuotaExceeded\"}}",
    retry_after_ms=None,
  )
  assert_eq(error_class(quota), "quota_exhausted")
  assert_false(error_is_transient(quota))
}

///|
test "retry after parser accepts seconds and rejects non numeric dates" {
  assert_eq(response_retry_after_ms({ "Retry-After": "42" }), Some(42000))
  assert_eq(response_retry_after_ms({ "retry-after": "999" }), Some(300000))
  assert_eq(
    response_retry_after_ms({ "retry-after": "Wed, 21 Oct 2015" }),
    None,
  )
}
