///|
test "openai chat route uses direct endpoint without moongate" {
  let model = @model.new(
    api_key="sk-test",
    base_url="https://openrouter.ai/api/v1",
    name="openai/gpt-5.2",
    safe_zone_tokens=128000,
  )
  let route = openai_chat_route_for_model(model)
  assert_eq(route.url, "https://openrouter.ai/api/v1/chat/completions")
  assert_false(route.via_moongate)
  assert_eq(route.headers["Authorization"], "Bearer sk-test")
}

///|
test "openai chat route does not redirect a direct model through MoonGate" {
  let model = @model.new(
    api_key="sk-test",
    base_url="https://openrouter.ai/api/v1",
    name="openai/gpt-5.2",
    safe_zone_tokens=128000,
  )
  let route = openai_chat_route_for_model(model)
  assert_eq(route.url, "https://openrouter.ai/api/v1/chat/completions")
  assert_false(route.via_moongate)
  assert_eq(route.headers["Authorization"], "Bearer sk-test")
}

///|
test "openai chat route recognizes a catalog model bound directly to MoonGate" {
  let model = @model.new(
    api_key="",
    base_url="http://127.0.0.1:15721/openclaw/v1",
    name="gpt-5.6-sol",
    safe_zone_tokens=128000,
  )
  let route = openai_chat_route_for_model(model)
  assert_eq(route.url, "http://127.0.0.1:15721/openclaw/v1/chat/completions")
  assert_true(route.via_moongate)
  assert_false(route.headers.contains("Authorization"))
}
