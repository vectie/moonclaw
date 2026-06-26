///|
test "robot policy joins Moonrobo base URL and route" {
  assert_eq(
    robot_policy_join_url(" http://127.0.0.1:5192/ ", "/api/moonclaw/context"),
    "http://127.0.0.1:5192/api/moonclaw/context",
  )
  assert_eq(
    robot_policy_join_url("http://127.0.0.1:5192", "api/moonrobo/ask"),
    "http://127.0.0.1:5192/api/moonrobo/ask",
  )
  assert_eq(
    robot_policy_join_url(
      "http://127.0.0.1:5192", "http://127.0.0.1:5193/api/moonclaw/context",
    ),
    "http://127.0.0.1:5193/api/moonclaw/context",
  )
}

///|
test "robot policy request requires Moonrobo URL" {
  let params = robot_policy_decode_request_text(
    "{\"moonrobo_url\":\"http://127.0.0.1:5192\",\"now_ms\":42}",
  )
  match params {
    Ok(decoded) => {
      assert_eq(decoded.moonrobo_url, "http://127.0.0.1:5192")
      assert_true(decoded.now_ms is Some(42L))
    }
    Err(message) => abort("expected valid robot policy request: \{message}")
  }
  let missing = robot_policy_decode_request_text(
    { "moonrobo_url": " " }.to_json().stringify(),
  )
  assert_true(missing is Err(_))
}

///|
fn sample_robot_routine_plan() -> @robot_policy.RobotRoutinePlan {
  let decision : @robot_policy.RobotPolicyDecision = {
    decision_id: "robot-policy-work-submit-gateway-command-42",
    status: "route-selected",
    owner: "moonclaw",
    work_id: "work-robo-gateway-command",
    kind: "submit-gateway-command",
    http_method: "POST",
    route: "/api/moonrobo/gateway/command",
    request_body: "{\"goal\":\"inspect workspace\"}",
    target_route: "/api/moonrobo/gateway/command",
    title: "Run MoonClaw gateway command",
    reason: "MoonClaw owns the command policy.",
    physical_execution_allowed: false,
    message: "MoonClaw selected the next route.",
  }
  let step : @robot_policy.RobotRoutineStep = {
    step_id: "routine-step-gateway-command",
    order: 1,
    kind: "submit-gateway-command",
    owner: "moonclaw",
    status: "pending",
    http_method: "POST",
    route: "/api/moonrobo/gateway/command",
    request_body: "{\"goal\":\"inspect workspace\"}",
    reason: "MoonClaw routine selected the next gateway command.",
    physical_execution_allowed: false,
  }
  {
    plan_id: "robot-routine-plan-robo-42",
    status: "ready",
    owner: "moonclaw",
    step_count: 1,
    steps: [step],
    next_step: Some(step),
    decision,
    message: "MoonClaw planned the route sequence.",
  }
}

///|
async test "robot routine run ledger writes reads and lists records" {
  let root = "/tmp/moonclaw-robot-routine-ledger-test"
  @fsx.make_directory(root, recursive=true, exists_ok=true) catch {
    error => abort("failed to create test root: \{error}")
  }
  let plan = sample_robot_routine_plan()
  let params : RobotPolicyGatewayRequest = {
    moonrobo_url: " http://127.0.0.1:5192/ ",
    now_ms: Some(42L),
  }
  let record = robot_routine_run_record(
    root,
    params,
    plan,
    true,
    Some({ status: 200, body: "{\"ok\":true}" }),
    "persisted",
  )
  assert_eq(record.run_id, "robot-routine-run-robot-routine-plan-robo-42")
  assert_eq(record.moonrobo_url, "http://127.0.0.1:5192")
  assert_eq(record.status, "invoked")
  match write_robot_routine_run(root, record) {
    Ok(_) => ()
    Err(message) => abort("expected routine run write: \{message}")
  }
  match read_robot_routine_run(root, record.run_id) {
    Ok(reloaded) => {
      assert_eq(reloaded.run_id, record.run_id)
      assert_eq(reloaded.plan.plan_id, plan.plan_id)
      assert_true(reloaded.invocation is Some({ status: 200, .. }))
    }
    Err(message) => abort("expected routine run read: \{message}")
  }
  let runs = list_robot_routine_runs(root)
  assert_true(runs.any(run => run.run_id == record.run_id))
}
