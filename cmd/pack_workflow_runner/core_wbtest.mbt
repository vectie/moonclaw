///|
test "runner parses file sources and required identifiers" {
  let parsed = parse_pack_workflow_runner_args([
    "--workspace", "/tmp/workspace", "--pack-id", "fixture", "--workflow-id", "daily",
    "--run-id", "run-1", "--policy", "policy.json", "--input", "input.json",
  ])
  guard parsed is Ok(options) else { fail("expected valid runner arguments") }
  assert_eq(options.workspace, "/tmp/workspace")
  assert_eq(options.pack_id, "fixture")
  assert_eq(options.workflow_id, "daily")
  assert_eq(options.run_id, "run-1")
  assert_true(options.policy is JsonFile("policy.json"))
  assert_true(options.input is Some(JsonFile("input.json")))
  assert_false(options.uses_stdin())
}

///|
test "runner permits one stdin JSON source" {
  let base = [
    "--workspace", "/tmp/workspace", "--pack-id", "fixture", "--workflow-id", "daily",
    "--run-id", "run-1",
  ]
  guard parse_pack_workflow_runner_args([..base, "--policy", "-"])
    is Ok(policy_stdin) else {
    fail("expected stdin policy")
  }
  assert_true(policy_stdin.uses_stdin())
  let both = parse_pack_workflow_runner_args(
    [..base, "--policy", "-", "--input", "-"],
  )
  assert_true(both is Err("only one of --policy or --input may use stdin"))
}

///|
test "runner result exposes durable status and outputs" {
  let options : PackWorkflowRunnerOptions = {
    workspace: "/tmp/workspace",
    pack_id: "fixture",
    workflow_id: "daily",
    run_id: "run-1",
    policy: JsonFile("policy.json"),
    input: None,
  }
  let result = runner_execution_result(
    options,
    "pack.fixture.job.daily",
    "pack.fixture.workflow.daily",
    Succeeded,
    { "final": { "value": 42 } },
    None,
  )
  assert_true(result.ok)
  assert_true(result.status is Some(Succeeded))
  assert_true(
    result.outputs.get("final") is Some({ "value": Number(42, ..), .. }),
  )
  guard result.to_json() is { "contract": String(contract), .. } else {
    fail("expected runner result contract")
  }
  assert_eq(contract, "moonsuite.pack-workflow-runner-result.v1")
}
