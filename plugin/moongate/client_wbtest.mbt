///|
test "moongate client resolves manifest base url" {
  let status = {
    "contract": Json::string("moon.suite.status.v2"),
    "service": Json::string("moongate"),
    "manifest": {
      "contract": Json::string("moon.suite.service.v1"),
      "service": Json::string("moongate"),
      "baseUrl": Json::string("http://127.0.0.1:18081"),
    }.to_json(),
  }.to_json()
  assert_true(
    moongate_base_url_from_status(status) == Some("http://127.0.0.1:18081"),
  )
}

///|
test "moongate client reads validated default model from suite status" {
  let status = {
    "contract": Json::string("moon.suite.status.v2"),
    "service": Json::string("moongate"),
    "manifest": {
      "contract": Json::string("moon.suite.service.v1"),
      "service": Json::string("moongate"),
      "baseUrl": Json::string("http://127.0.0.1:15721"),
      "defaultModel": Json::string("gpt-5.6-sol"),
    }.to_json(),
  }.to_json()
  let models = moongate_default_models_from_status(status)
  assert_eq(models.length(), 1)
  assert_eq(models[0].id(), "gpt-5.6-sol")
  assert_true(models[0].context_window() == Some(128000))
}

///|
test "moongate client rejects legacy suite status shortcuts" {
  let health_only = { "health_url": "http://127.0.0.1:18082/health" }.to_json()
  let root_base = { "base_url": "http://127.0.0.1:18082" }.to_json()
  let manifest_only = {
    "manifest": { "base_url": "http://127.0.0.1:18082" }.to_json(),
  }.to_json()
  assert_true(moongate_base_url_from_status(health_only) is None)
  assert_true(moongate_base_url_from_status(root_base) is None)
  assert_true(moongate_base_url_from_status(manifest_only) is None)
}

///|
test "moongate client reads suite status from workspace moonsuite state" {
  let root = "/tmp/moonsuite/books/research-demo"
  let path = moongate_suite_status_path_for_workspace_root(root)
  assert_true(path == "/tmp/moonsuite/.moonsuite/suite-status.json")
  assert_false(path.contains("/.moonsuite/.moonsuite/suite-status.json"))
}

///|
test "moongate client builds openclaw route url" {
  let client = Client::{ base_url: "http://127.0.0.1:18081" }
  assert_true(
    client.route_openclaw_chat_url() ==
    "http://127.0.0.1:18081/openclaw/v1/chat/completions",
  )
}

///|
test "moongate client separates HTTP origin and request path" {
  assert_true(
    moongate_http_parts("http://127.0.0.1:15721/v1/models") ==
    Ok(("http://127.0.0.1:15721", "/v1/models")),
  )
  assert_true(
    moongate_http_parts("https://moongate.example") ==
    Ok(("https://moongate.example", "/")),
  )
  assert_true(
    moongate_http_parts("127.0.0.1:15721/v1/models") ==
    Err("invalid URL: missing scheme"),
  )
}

///|
test "moongate client parses typed models" {
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
  guard moongate_models_from_json(catalog) is Ok(models) else {
    fail("expected parsed models")
  }
  assert_true(models.length() == 2)
  assert_true(models[0].id == "gpt-5")
  assert_true(models[0].id() == "gpt-5")
  assert_true(models[0].owner == Some("openai"))
  assert_true(models[0].owner() == Some("openai"))
  assert_true(models[0].context_window == Some(128000))
  assert_true(models[0].context_window() == Some(128000))
  assert_true(models[1].id == "moon/local")
}

///|
test "moongate client parses typed usage summary" {
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
  guard MoonGateUsageSummary::from_json(summary) is Ok(parsed) else {
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
