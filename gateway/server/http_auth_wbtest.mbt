///|
test "configured gateway token protects all API families" {
  for
    path in [
      "/v1/agent", "/v1/rpc", "/v1/runs", "/v1/events", "/v1/shutdown", "/v1/jobs",
      "/v1/mailboxes",
    ] {
    assert_false(gateway_http_authorized(path, {}, Some("secret")))
    assert_false(
      gateway_http_authorized(
        path,
        { "authorization": "Bearer wrong" },
        Some("secret"),
      ),
    )
    assert_true(
      gateway_http_authorized(
        path,
        { "authorization": "Bearer secret" },
        Some("secret"),
      ),
    )
  }
  assert_true(gateway_http_authorized("/health", {}, Some("secret")))
  assert_true(gateway_http_authorized("/webhook/feishu", {}, Some("secret")))
  assert_true(gateway_http_authorized("/v1/agent", {}, None))
  assert_false(
    gateway_http_authorized(
      "/v1/agent",
      { "authorization": "Bearer " },
      Some(""),
    ),
  )
}
