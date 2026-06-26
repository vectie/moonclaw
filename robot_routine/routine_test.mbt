///|
fn capability_with_mode(
  http_method : String,
  route : String,
  execution_mode : String,
) -> Json {
  {
    "capability_id": Json::string("test-\{http_method}-\{route}"),
    "label": Json::string("Test capability"),
    "http_method": Json::string(http_method),
    "route": Json::string(route),
    "body_schema": Json::string("none"),
    "execution_mode": Json::string(execution_mode),
    "physical_execution_allowed": false.to_json(),
    "safety_note": Json::string("test capability"),
  }.to_json()
}

///|
fn capability(http_method : String, route : String) -> Json {
  capability_with_mode(http_method, route, "test")
}

///|
fn tool_registry() -> Json {
  {
    "registry_id": Json::string("tool-registry-noetix-e1-lab-01"),
    "robot_id": Json::string("noetix-e1-lab-01"),
    "generated_at_ms": (1000).to_json(),
    "provider_count": (1).to_json(),
    "capability_count": (8).to_json(),
    "providers": [
      {
        "provider_id": Json::string("moonrobo-host-api"),
        "label": Json::string("Moonrobo Host API"),
        "kind": Json::string("moonrobo-runtime"),
        "robot_id": Json::string("noetix-e1-lab-01"),
        "endpoint_base": Json::string("/api"),
        "memory_required": true.to_json(),
        "registered_at_ms": (1000).to_json(),
        "capabilities": [
          capability("POST", "/api/runtime/validation/session"),
          capability("POST", "/api/moonrobo/gateway/command"),
          capability("POST", "/api/moonrobo/proof-session"),
          capability_with_mode(
            "POST", "/api/moonrobo/executions/feedback", "operator-verification",
          ),
          capability("POST", "/api/moonbook/remember"),
          capability("POST", "/api/moontown/tasks/observe-run"),
          capability_with_mode(
            "POST", "/api/replays/{session_id}/annotations", "operator-curation",
          ),
          capability_with_mode(
            "POST", "/api/moonbook/task-messages/{task_id}/{gate}", "operator-safety",
          ),
        ].to_json(),
      }.to_json(),
    ].to_json(),
  }.to_json()
}

///|
fn context_with_work(kind : String, target_path : String) -> Json {
  {
    "context": {
      "robot_id": "noetix-e1-lab-01",
      "tool_registry": tool_registry(),
      "task_intent": {
        "has_task": true,
        "task_id": "message-routine-test",
        "message_id": "routine-test",
        "goal": "inspect the tool bench",
        "classification": "command-review",
        "stage": "ready-to-prove",
        "next_route": "/api/moonrobo/gateway/command",
        "requires_review": false,
        "physical_execution_allowed": false,
        "message_path": "/moonbook/task-messages/message-routine-test.json",
        "created_at_ms": 1000,
      },
      "platform_queue": {
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
fn context_with_live_readiness(
  status : String,
  can_run_proof_session : Bool,
  can_submit_gateway_command : Bool,
  feedback_closed : Bool,
  work? : Json = {},
) -> Json {
  {
    "context": {
      "robot_id": "noetix-e1-lab-01",
      "tool_registry": tool_registry(),
      "task_intent": {
        "has_task": true,
        "task_id": "message-routine-test",
        "message_id": "routine-test",
        "goal": "inspect the tool bench",
        "classification": "command-review",
        "stage": "ready-to-prove",
        "next_route": "/api/moonrobo/gateway/command",
        "requires_review": false,
        "physical_execution_allowed": false,
        "message_path": "/moonbook/task-messages/message-routine-test.json",
        "created_at_ms": 1000,
      },
      "platform_queue": if work == {} {
        { "item_count": 0, "next_item": null }
      } else {
        { "item_count": 1, "next_item": work }
      },
      "gateway": {
        "status": status,
        "next_method": "POST",
        "next_route": "/api/moonrobo/proof-session",
        "next_title": "Run proof session",
        "can_submit_gateway_command": can_submit_gateway_command,
        "physical_execution_allowed": false,
      },
    },
    "live_readiness": {
      "status": status,
      "can_run_proof_session": can_run_proof_session,
      "can_submit_gateway_command": can_submit_gateway_command,
      "proof_session_feedback_closed": feedback_closed,
    },
  }
}

///|
fn work_item(kind : String, target_path : String) -> Json {
  {
    "work_id": "work-test",
    "kind": kind,
    "priority": 100,
    "title": "Test work",
    "summary": "test summary",
    "target_id": "robot-test",
    "target_path": target_path,
    "reason": "test reason",
  }
}

///|
fn selected_decision(payload : Json, now_ms : Int64) -> RobotRoutineDecision {
  plan_routine_from_context(payload, now_ms~).decision
}

///|
test "robot routine decision routes operator-owned blockers to operator" {
  let decision = selected_decision(
    context_with_work("start-runtime", "/api/runtime/supervisor/start"),
    1000L,
  )
  assert_eq(decision.status, "needs-operator")
  assert_eq(decision.owner, "operator")
  assert_eq(decision.route, "/api/runtime/supervisor/start")
  assert_eq(decision.http_method, "GET")
  assert_eq(decision.request_body, "")
}

///|
test "robot routine decision selects explicit Moonrobo route for MoonClaw work" {
  let decision = selected_decision(
    context_with_work("validate-runtime", "/api/runtime/validation/session"),
    1001L,
  )
  assert_eq(decision.status, "route-selected")
  assert_eq(decision.owner, "moonclaw")
  assert_eq(decision.route, "/api/runtime/validation/session")
  assert_eq(decision.kind, "validate-runtime")
  assert_eq(decision.request_body, "{}")
}

///|
test "robot routine decision authors gateway command request body in MoonClaw" {
  let decision = selected_decision(
    context_with_work("submit-gateway-command", "/api/moonrobo/gateway/command"),
    1005L,
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
  assert_true(
    decision.request_body.contains("\"goal\":\"inspect the tool bench\""),
  )
  assert_true(decision.request_body.contains("\"remember\":true"))
}

///|
test "robot routine decision falls back to gateway route when queue is empty" {
  let decision = selected_decision(
    {
      "context": {
        "robot_id": "noetix-e1-lab-01",
        "tool_registry": tool_registry(),
        "task_intent": {
          "has_task": true,
          "task_id": "message-routine-test",
          "message_id": "routine-test",
          "goal": "inspect the tool bench",
        },
        "platform_queue": { "item_count": 0, "next_item": null },
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
    1002L,
  )
  assert_eq(decision.status, "route-selected")
  assert_eq(decision.owner, "moonclaw")
  assert_eq(decision.route, "/api/moonrobo/proof-session")
  assert_true(decision.request_body.contains("\"session_id\""))
  assert_true(decision.request_body.contains("\"task_message\""))
  assert_true(
    decision.request_body.contains("\"message\":\"inspect the tool bench\""),
  )
}

///|
test "robot routine decision authors gateway command from gateway status" {
  let decision = selected_decision(
    {
      "context": {
        "robot_id": "noetix-e1-lab-01",
        "tool_registry": tool_registry(),
        "task_intent": {
          "has_task": true,
          "task_id": "message-routine-test",
          "message_id": "routine-test",
          "goal": "inspect the tool bench",
        },
        "platform_queue": { "item_count": 0, "next_item": null },
        "gateway": {
          "status": "ready-for-command",
          "next_method": "POST",
          "next_route": "/api/moonrobo/gateway/command",
          "next_title": "Submit gateway command",
          "can_submit_gateway_command": true,
          "physical_execution_allowed": false,
        },
      },
    },
    1010L,
  )
  assert_eq(decision.status, "route-selected")
  assert_eq(decision.owner, "moonclaw")
  assert_eq(decision.kind, "submit-gateway-command")
  assert_eq(decision.route, "/api/moonrobo/gateway/command")
  assert_true(
    decision.request_body.contains(
      "moonclaw-gateway-command-submit-gateway-command-1010",
    ),
  )
  assert_true(
    decision.request_body.contains("\"goal\":\"inspect the tool bench\""),
  )
  assert_true(decision.request_body.contains("\"remember\":true"))
}

///|
test "robot routine decision skips Moonrobo aggregate live exercise work" {
  let decision = selected_decision(
    context_with_work("run-live-exercise", "/api/moonrobo/live-exercise"),
    1006L,
  )
  assert_eq(decision.status, "route-selected")
  assert_eq(decision.owner, "moonclaw")
  assert_eq(decision.route, "/api/moonrobo/proof-session")
  assert_true(decision.request_body.contains("\"session_id\""))
}

///|
test "robot routine decision keeps curation route templates operator-owned" {
  let decision = selected_decision(
    context_with_work("annotate-replay", "/api/replays/session-a/annotations"),
    1011L,
  )
  assert_eq(decision.status, "needs-operator")
  assert_eq(decision.owner, "operator")
  assert_eq(decision.http_method, "GET")
  assert_eq(decision.route, "/api/replays/session-a/annotations")
  assert_eq(decision.request_body, "")
  assert_true(decision.reason.contains("operator-curation"))
}

///|
test "robot routine decision keeps safety execution modes operator-owned" {
  let decision = selected_decision(
    context_with_work(
      "advance-task-message", "/api/moonbook/task-messages/message-a/evaluate",
    ),
    1017L,
  )
  assert_eq(decision.status, "needs-operator")
  assert_eq(decision.owner, "operator")
  assert_eq(decision.http_method, "GET")
  assert_eq(decision.route, "/api/moonbook/task-messages/message-a/evaluate")
  assert_eq(decision.request_body, "")
  assert_true(decision.reason.contains("operator-safety"))
}

///|
test "robot routine decision keeps feedback binding operator-owned" {
  let decision = selected_decision(
    context_with_work(
      "bind-execution-feedback", "/api/moonrobo/executions/feedback",
    ),
    1018L,
  )
  assert_eq(decision.status, "needs-operator")
  assert_eq(decision.owner, "operator")
  assert_eq(decision.http_method, "GET")
  assert_eq(decision.route, "/api/moonrobo/executions/feedback")
  assert_eq(decision.request_body, "")
  assert_true(decision.reason.contains("operator-verification"))
}

///|
test "robot routine decision authors bounded observation run body" {
  let decision = selected_decision(
    context_with_work("observe", "/api/moontown/tasks/observe-run"),
    1016L,
  )
  assert_eq(decision.status, "route-selected")
  assert_eq(decision.owner, "moonclaw")
  assert_eq(decision.route, "/api/moontown/tasks/observe-run")
  assert_true(
    decision.request_body.contains(
      "\"task_id\":\"moonclaw-observe-noetix-e1-lab-01-1016\"",
    ),
  )
  assert_true(
    decision.request_body.contains("\"robot_id\":\"noetix-e1-lab-01\""),
  )
  assert_true(decision.request_body.contains("\"kind\":\"moontown\""))
  assert_true(decision.request_body.contains("\"id\":\"moonclaw\""))
  assert_true(
    decision.request_body.contains("\"goal\":\"inspect the tool bench\""),
  )
  assert_true(decision.request_body.contains("\"frame_count\":3"))
  assert_true(decision.request_body.contains("\"frame_interval_ms\":\"5\""))
}

///|
test "robot routine decision keeps command-message gates operator-owned" {
  let evaluate = selected_decision(
    context_with_work(
      "evaluate-command-message", "/api/moonbook/task-messages/message-a/evaluate",
    ),
    1014L,
  )
  assert_eq(evaluate.status, "needs-operator")
  assert_eq(evaluate.owner, "operator")
  assert_eq(evaluate.http_method, "GET")
  assert_eq(evaluate.route, "/api/moonbook/task-messages/message-a/evaluate")
  assert_eq(evaluate.request_body, "")
  let dry_run = selected_decision(
    context_with_work(
      "dry-run-command-message", "/api/moonbook/task-messages/message-a/dry-run",
    ),
    1015L,
  )
  assert_eq(dry_run.status, "needs-operator")
  assert_eq(dry_run.owner, "operator")
  assert_eq(dry_run.http_method, "GET")
  assert_eq(dry_run.route, "/api/moonbook/task-messages/message-a/dry-run")
  assert_eq(dry_run.request_body, "")
}

///|
test "robot routine decision blocks unregistered Moonrobo routes" {
  let decision = selected_decision(
    context_with_work("submit-gateway-command", "/api/moonrobo/unregistered"),
    1012L,
  )
  assert_eq(decision.status, "needs-operator")
  assert_eq(decision.owner, "operator")
  assert_eq(decision.route, "/api/tools/registry")
  assert_eq(decision.target_route, "/api/moonrobo/unregistered")
  assert_true(decision.reason.contains("not registered"))
}

///|
test "robot routine decision blocks unregistered gateway next route" {
  let decision = selected_decision(
    {
      "context": {
        "robot_id": "noetix-e1-lab-01",
        "tool_registry": tool_registry(),
        "platform_queue": { "item_count": 0, "next_item": null },
        "gateway": {
          "status": "ready-for-command",
          "next_method": "POST",
          "next_route": "/api/moonrobo/unregistered",
          "next_title": "Submit unknown route",
          "can_submit_gateway_command": true,
          "physical_execution_allowed": false,
        },
      },
    },
    1013L,
  )
  assert_eq(decision.status, "needs-operator")
  assert_eq(decision.owner, "operator")
  assert_eq(decision.route, "/api/tools/registry")
  assert_eq(decision.target_route, "/api/moonrobo/unregistered")
}

///|
test "robot routine decision idles without queue or ready gateway route" {
  let decision = selected_decision(
    {
      "context": {
        "platform_queue": { "item_count": 0, "next_item": null },
        "gateway": {
          "status": "mapped-needs-evidence",
          "can_submit_gateway_command": false,
        },
      },
    },
    1003L,
  )
  assert_eq(decision.status, "idle")
  assert_eq(decision.owner, "moontown")
  assert_eq(decision.route, "/api/moonrobo/ask")
}

///|
test "robot routine decodes context text" {
  let plan = plan_routine_from_context_text(
    context_with_work("run-proof-session", "/api/moonrobo/proof-session").stringify(),
    now_ms=1004L,
  ).unwrap()
  let decision = plan.decision
  assert_eq(decision.owner, "moonclaw")
  assert_eq(decision.route, "/api/moonrobo/proof-session")
}

///|
test "robot routine plan starts with runtime validation when live readiness is stale" {
  let plan = plan_routine_from_context(
    context_with_live_readiness("needs-runtime-validation", false, false, false),
    now_ms=1007L,
  )
  assert_eq(plan.status, "ready")
  assert_eq(plan.owner, "moonclaw")
  assert_eq(plan.step_count, 1)
  assert_true(plan.next_step is Some({ kind: "validate-runtime", .. }))
  assert_eq(plan.steps[0].route, "/api/runtime/validation/session")
  assert_true(plan.steps[0].request_body.contains("\"sample_count\":3"))
}

///|
test "robot routine plan sequences gateway proof feedback and memory" {
  let plan = plan_routine_from_context(
    context_with_live_readiness(
      "ready-for-proof-session",
      true,
      true,
      false,
      work=work_item("submit-gateway-command", "/api/moonrobo/gateway/command"),
    ),
    now_ms=1008L,
  )
  assert_eq(plan.status, "ready")
  assert_eq(plan.owner, "moonclaw")
  assert_eq(plan.step_count, 4)
  assert_eq(plan.steps[0].kind, "submit-gateway-command")
  assert_eq(plan.steps[0].route, "/api/moonrobo/gateway/command")
  assert_true(
    plan.steps[0].request_body.contains("\"goal\":\"inspect the tool bench\""),
  )
  assert_eq(plan.steps[1].kind, "run-proof-session")
  assert_eq(plan.steps[1].route, "/api/moonrobo/proof-session")
  assert_true(plan.steps[1].request_body.contains("\"session_id\""))
  assert_true(plan.steps[1].request_body.contains("\"task_message\""))
  assert_eq(plan.steps[2].kind, "bind-execution-feedback")
  assert_eq(plan.steps[2].owner, "operator")
  assert_eq(plan.steps[3].kind, "remember-robot-context")
}

///|
test "robot routine plan routes calibration blockers to operator" {
  let plan = plan_routine_from_context(
    context_with_live_readiness("needs-calibration", false, false, false),
    now_ms=1009L,
  )
  assert_eq(plan.status, "needs-operator")
  assert_eq(plan.owner, "operator")
  assert_true(plan.next_step is Some({ kind: "calibrate-runtime", .. }))
  assert_eq(plan.steps[0].route, "/api/moonclaw/runtime-calibration/latest")
}
