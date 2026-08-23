///|
fn moondesk_control_auth_test_config() -> @moondesk_sandbox_config.Config {
  {
    protocol_version: 1,
    instance_id: "0123456789abcdef0123456789abcdef",
    auth_token: "a".repeat(64),
    workspace_id: "book",
    workspace_root: "/registered/book",
  }
}

///|
test "MoonDesk control auth rejects missing and wrong credentials" {
  let config = moondesk_control_auth_test_config()
  assert_false(moondesk_control_headers_authorized({}, config))
  assert_false(
    moondesk_control_headers_authorized(
      {
        "x-moonclaw-execution-token": "b".repeat(64),
        "x-moonclaw-instance-id": config.instance_id,
      },
      config,
    ),
  )
  assert_false(
    moondesk_control_headers_authorized(
      {
        "x-moonclaw-execution-token": config.auth_token,
        "x-moonclaw-instance-id": "f".repeat(32),
      },
      config,
    ),
  )
}

///|
test "MoonDesk control auth accepts only the bound private credential" {
  let config = moondesk_control_auth_test_config()
  assert_true(
    moondesk_control_headers_authorized(
      {
        "x-moonclaw-execution-token": config.auth_token,
        "x-moonclaw-instance-id": config.instance_id,
      },
      config,
    ),
  )
}

///|
test "MoonDesk control route policy protects runtime state but leaves public callbacks" {
  assert_true(moondesk_control_route_requires_auth(Get, ["", "v1", "models"]))
  assert_true(moondesk_control_route_requires_auth(Post, ["", "v1", "task"]))
  assert_true(
    moondesk_control_route_requires_auth(Get, ["", "v1", "code", "sessions"]),
  )
  assert_true(
    moondesk_control_route_requires_auth(Post, [
      "", "v1", "supervisors", "supervisor-1", "commands", "message",
    ]),
  )
  assert_false(moondesk_control_route_requires_auth(Get, ["", "v1", "health"]))
  assert_false(
    moondesk_control_route_requires_auth(Get, [
      "", "v1", "auth", "codex", "callback",
    ]),
  )
  assert_false(
    moondesk_control_route_requires_auth(Post, [
      "", "v1", "execution-sandbox", "moon-diagnostics",
    ]),
  )
  assert_false(
    moondesk_control_route_requires_auth(Post, [
      "", "v1", "execution-sandbox", "promote",
    ]),
  )
}
