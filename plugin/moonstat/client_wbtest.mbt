///|
test "moonstat client resolves manifest base url" {
  let status = {
    "contract": Json::string("moon.suite.status.v2"),
    "service": Json::string("moonstat"),
    "manifest": {
      "contract": Json::string("moon.suite.service.v1"),
      "service": Json::string("moonstat"),
      "base_url": Json::string("http://127.0.0.1:18081"),
    }.to_json(),
  }.to_json()
  assert_true(
    moonstat_base_url_from_status(status) == Some("http://127.0.0.1:18081"),
  )
}

///|
test "moonstat client rejects legacy suite status shortcuts" {
  let health_only = { "health_url": "http://127.0.0.1:18082/health" }.to_json()
  let root_base = { "base_url": "http://127.0.0.1:18082" }.to_json()
  let manifest_only = {
    "manifest": { "base_url": "http://127.0.0.1:18082" }.to_json(),
  }.to_json()
  assert_true(moonstat_base_url_from_status(health_only) is None)
  assert_true(moonstat_base_url_from_status(root_base) is None)
  assert_true(moonstat_base_url_from_status(manifest_only) is None)
}

///|
test "moonstat client builds moonclaw route url" {
  let client = Client::{ base_url: "http://127.0.0.1:18081" }
  assert_true(
    client.route_moonclaw_chat_url() ==
    "http://127.0.0.1:18081/moonclaw/v1/chat/completions",
  )
}

///|
test "moonstat client parses typed models" {
  let catalog = {
    "models": [
      {
        "slug": Json::string("gpt-5"),
        "owned_by": Json::string("openai"),
        "context_window": Json::number(128000.0),
      },
      { "id": Json::string("moon/local") },
    ],
  }.to_json()
  guard moonstat_models_from_json(catalog) is Ok(models) else {
    fail("expected parsed models")
  }
  assert_true(models.length() == 2)
  assert_true(models[0].id == "gpt-5")
  assert_true(models[0].owner == Some("openai"))
  assert_true(models[0].context_window == Some(128000))
  assert_true(models[1].id == "moon/local")
}

///|
test "moonstat client parses typed usage summary" {
  let summary = {
    "totalRequests": Json::number(3.0),
    "totalCost": Json::string("0.000300"),
    "totalInputTokens": Json::number(100.0),
    "totalOutputTokens": Json::number(20.0),
    "totalCacheCreationTokens": Json::number(7.0),
    "totalCacheReadTokens": Json::number(11.0),
    "successRate": Json::number(66.7),
    "realTotalTokens": Json::number(127.0),
    "cacheHitRate": Json::number(12.5),
  }.to_json()
  guard MoonstatUsageSummary::from_json(summary) is Ok(parsed) else {
    fail("expected parsed usage summary")
  }
  assert_true(parsed.total_requests == 3)
  assert_true(parsed.total_cost == "0.000300")
  assert_true(parsed.total_input_tokens == 100L)
  assert_true(parsed.total_output_tokens == 20L)
  assert_true(parsed.total_cache_creation_tokens == 7L)
  assert_true(parsed.total_cache_read_tokens == 11L)
  assert_true(parsed.real_total_tokens == 127L)
  assert_true(parsed.success_rate == 66.7)
  assert_true(parsed.cache_hit_rate == 12.5)
}
