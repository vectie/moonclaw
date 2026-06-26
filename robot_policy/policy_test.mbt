///|
fn context_with_work(kind : String, target_path : String) -> Json {
  {
    "context": {
      "robot_id": "noetix-e1-lab-01",
      "work_queue": {
        "item_count": 1,
        "next_item": {
          "work_id": "work-test",
          "kind": kind,
          "priority": 100,
          "title": "Test work",
          "summary": "test summary",
          "target_id": "robot-test",
          "target_path": target_path,
          "reason": "test reason",
        },
      },
      "gateway": {
        "status": "ready-for-command",
        "next_method": "POST",
        "next_route": "/api/moonrobo/proof-session",
        "next_title": "Run proof session",
        "can_submit_gateway_command": true,
        "physical_execution_allowed": false,
      },
    },
  }
}

///|
test "robot policy routes operator-owned blockers to operator" {
  let decision = select_route_from_context(
    context_with_work("start-runtime", "/api/runtime/supervisor/start"),
    now_ms=1000L,
  )
  assert_eq(decision.status, "needs-operator")
  assert_eq(decision.owner, "operator")
  assert_eq(decision.route, "/api/runtime/supervisor/start")
  assert_eq(decision.http_method, "GET")
  assert_eq(decision.request_body, "")
}

///|
test "robot policy selects explicit Moonrobo route for MoonClaw work" {
  let decision = select_route_from_context(
    context_with_work("validate-runtime", "/api/runtime/validation/session"),
    now_ms=1001L,
  )
  assert_eq(decision.status, "route-selected")
  assert_eq(decision.owner, "moonclaw")
  assert_eq(decision.route, "/api/runtime/validation/session")
  assert_eq(decision.kind, "validate-runtime")
  assert_eq(decision.request_body, "{}")
}

///|
test "robot policy authors gateway command request body in MoonClaw" {
  let decision = select_route_from_context(
    context_with_work("submit-gateway-command", "/api/moonrobo/gateway/command"),
    now_ms=1005L,
  )
  assert_eq(decision.status, "route-selected")
  assert_eq(decision.owner, "moonclaw")
  assert_eq(decision.route, "/api/moonrobo/gateway/command")
  assert_true(decision.request_body.contains("\"command_id\""))
  assert_true(
    decision.request_body.contains(
      "moonclaw-gateway-command-submit-gateway-command-1005",
    ),
  )
  assert_true(
    decision.request_body.contains("\"robot_id\":\"noetix-e1-lab-01\""),
  )
  assert_true(decision.request_body.contains("\"kind\":\"moontown\""))
  assert_true(decision.request_body.contains("\"id\":\"moonclaw\""))
  assert_true(decision.request_body.contains("\"goal\":\"test reason\""))
  assert_true(decision.request_body.contains("\"remember\":true"))
}

///|
test "robot policy falls back to gateway route when queue is empty" {
  let decision = select_route_from_context(
    {
      "context": {
        "work_queue": { "item_count": 0, "next_item": null },
        "gateway": {
          "status": "ready-for-command",
          "next_method": "POST",
          "next_route": "/api/moonrobo/proof-session",
          "next_title": "Run proof session",
          "can_submit_gateway_command": true,
          "physical_execution_allowed": false,
        },
      },
    },
    now_ms=1002L,
  )
  assert_eq(decision.status, "route-selected")
  assert_eq(decision.owner, "moonclaw")
  assert_eq(decision.route, "/api/moonrobo/proof-session")
  assert_eq(decision.request_body, "{}")
}

///|
test "robot policy idles without queue or ready gateway route" {
  let decision = select_route_from_context(
    {
      "context": {
        "work_queue": { "item_count": 0, "next_item": null },
        "gateway": {
          "status": "mapped-needs-evidence",
          "can_submit_gateway_command": false,
        },
      },
    },
    now_ms=1003L,
  )
  assert_eq(decision.status, "idle")
  assert_eq(decision.owner, "moontown")
  assert_eq(decision.route, "/api/moonrobo/ask")
}

///|
test "robot policy decodes context text" {
  let decision = select_route_from_context_text(
    context_with_work("run-proof-session", "/api/moonrobo/proof-session").stringify(),
    now_ms=1004L,
  ).unwrap()
  assert_eq(decision.owner, "moonclaw")
  assert_eq(decision.route, "/api/moonrobo/proof-session")
}
