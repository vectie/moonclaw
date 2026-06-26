///|
test "robot routine joins Moonrobo base URL and route" {
  assert_eq(
    robot_routine_join_url(" http://127.0.0.1:5192/ ", "/api/moonclaw/context"),
    "http://127.0.0.1:5192/api/moonclaw/context",
  )
  assert_eq(
    robot_routine_join_url("http://127.0.0.1:5192", "api/moonrobo/ask"),
    "http://127.0.0.1:5192/api/moonrobo/ask",
  )
  assert_eq(
    robot_routine_join_url(
      "http://127.0.0.1:5192", "http://127.0.0.1:5193/api/moonclaw/context",
    ),
    "http://127.0.0.1:5193/api/moonclaw/context",
  )
}

///|
test "robot routine request requires Moonrobo URL" {
  let params = robot_routine_decode_request_text(
    "{\"moonrobo_url\":\"http://127.0.0.1:5192\",\"now_ms\":42}",
  )
  match params {
    Ok(decoded) => {
      assert_eq(decoded.moonrobo_url, "http://127.0.0.1:5192")
      assert_true(decoded.now_ms is Some(42L))
    }
    Err(message) => abort("expected valid robot routine request: \{message}")
  }
  let missing = robot_routine_decode_request_text(
    { "moonrobo_url": " " }.to_json().stringify(),
  )
  assert_true(missing is Err(_))
}

///|
fn sample_robot_routine_plan() -> @robot_routine.RobotRoutinePlan {
  let decision : @robot_routine.RobotRoutineDecision = {
    decision_id: "robot-routine-work-submit-gateway-command-42",
    status: "route-selected",
    owner: "moonclaw",
    work_id: "work-robo-gateway-command",
    kind: "submit-gateway-command",
    http_method: "POST",
    route: "/api/moonrobo/gateway/command",
    request_body: "{\"goal\":\"inspect workspace\"}",
    target_route: "/api/moonrobo/gateway/command",
    title: "Run MoonClaw gateway command",
    reason: "MoonClaw owns the command routine step.",
    physical_execution_allowed: false,
    message: "MoonClaw selected the next route.",
  }
  let step : @robot_routine.RobotRoutineStep = {
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
fn sample_idle_robot_routine_plan() -> @robot_routine.RobotRoutinePlan {
  let decision : @robot_routine.RobotRoutineDecision = {
    decision_id: "robot-routine-idle-idle-43",
    status: "idle",
    owner: "moontown",
    work_id: "",
    kind: "idle",
    http_method: "POST",
    route: "/api/moonrobo/ask",
    request_body: "",
    target_route: "/api/moonrobo/ask",
    title: "Ask Robo",
    reason: "No queued robot work is present.",
    physical_execution_allowed: false,
    message: "Robot routine is idle.",
  }
  {
    plan_id: "robot-routine-plan-robo-43",
    status: "idle",
    owner: "moontown",
    step_count: 0,
    steps: [],
    next_step: None,
    decision,
    message: "MoonClaw robot routine is idle.",
  }
}

///|
async test "robot routine run ledger writes reads and lists records" {
  let root = "/tmp/moonclaw-robot-routine-ledger-test"
  @fsx.make_directory(root, recursive=true, exists_ok=true) catch {
    error => abort("failed to create test root: \{error}")
  }
  let plan = sample_robot_routine_plan()
  let params : RobotRoutineGatewayRequest = {
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

///|
async test "robot routine run ledger records stopped attempts" {
  let root = "/tmp/moonclaw-robot-routine-stopped-ledger-test"
  @fsx.make_directory(root, recursive=true, exists_ok=true) catch {
    error => abort("failed to create test root: \{error}")
  }
  let params : RobotRoutineGatewayRequest = {
    moonrobo_url: "http://127.0.0.1:5192",
    now_ms: Some(43L),
  }
  let idle_plan = sample_idle_robot_routine_plan()
  let idle_record = robot_routine_run_record(
    root,
    params,
    idle_plan,
    false,
    None,
    "MoonClaw persisted an idle robot routine run.",
    status="idle",
  )
  match write_robot_routine_run(root, idle_record) {
    Ok(_) => ()
    Err(message) => abort("expected idle routine run write: \{message}")
  }
  match read_robot_routine_run(root, idle_record.run_id) {
    Ok(reloaded) => {
      assert_eq(reloaded.status, "idle")
      assert_true(!reloaded.invoked)
      assert_true(reloaded.invocation is None)
      assert_eq(reloaded.plan.step_count, 0)
    }
    Err(message) => abort("expected idle routine run read: \{message}")
  }
  let error_json = robot_routine_run_error(
    "robot_routine_idle", "routine plan has no next step", idle_record,
  )
  assert_true(error_json.stringify().contains("\"run\""))
  assert_true(error_json.stringify().contains(idle_record.record_path))
}
