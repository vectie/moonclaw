///|
fn workflow_projection() -> @host.HostActivationProjection {
  {
    contract: "moonsuite.pack-host-activation.v1",
    pack_id: "fixture",
    product_id: "fixture",
    version: "1.2.0",
    required_runtime_extensions: ["moonclaw"],
    book_templates: [],
    tools: [
      @pack.tool_declaration(
        "fixture.acquire",
        "fixture",
        "request",
        "snapshot",
        Observe,
        evidence_outputs=["raw/snapshots"],
      ),
      @pack.tool_declaration(
        "fixture.evaluate",
        "fixture",
        "snapshot",
        "decision",
        SandboxExecution,
        evidence_outputs=["records/decisions"],
      ),
    ],
    schedules: [
      @pack.schedule_declaration(
        "weekday", "30 7 * * 1-5", "Asia/Shanghai", "daily",
      ),
    ],
    app_entrypoints: [],
    provider_ports: [],
    policies: [],
  }
}

///|
fn workflow_declaration() -> PackWorkflowDeclaration {
  {
    contract: "moonsuite.pack-workflow.v1",
    pack_id: "fixture",
    product_id: "fixture",
    id: "daily",
    version: "2.0.0",
    steps: [
      {
        id: "acquire",
        tool_id: "fixture.acquire",
        config: { "mode": "licensed" },
        retry_policy: Some({ max_attempts: 2, backoff_ms: Some(1000) }),
      },
      {
        id: "evaluate",
        tool_id: "fixture.evaluate",
        config: { "threshold": 70 },
        retry_policy: None,
      },
    ],
    output_bindings: ["evaluate"],
  }
}

///|
test "pack workflow compiler projects only declared generic tool bindings" {
  let compilation = compile_workflow_job(
    workflow_projection(),
    workflow_declaration(),
    100,
    schedule_id="weekday",
  )
  assert_eq(
    compilation.definition.id,
    "pack.fixture.v1.2.0.job.daily.v2.0.0.schedule.weekday",
  )
  assert_eq(compilation.definition.kind, "moonsuite.pack.job")
  assert_true(
    compilation.definition.workflow_id
    is Some("pack.fixture.v1.2.0.workflow.daily.v2.0.0"),
  )
  guard compilation.definition.schedule is Some(schedule) else {
    fail("expected projected schedule")
  }
  assert_eq(schedule.kind, "cron")
  assert_true(schedule.interval_minutes is None)
  assert_true(schedule.timezone is Some("Asia/Shanghai"))
  assert_eq(compilation.workflow.steps.length(), 2)
  assert_eq(compilation.workflow.steps[0].kind, "moonsuite.pack.tool")
  guard compilation.workflow.steps[0].config
    is {
      "contract": String(contract),
      "pack_id": String(pack_id),
      "tool": { "tool_id": String(tool_id), .. },
      "config": { "mode": String(mode), .. },
      ..
    } else {
    fail("expected generic pack tool step config")
  }
  assert_eq(contract, "moonsuite.pack-tool-step.v1")
  assert_eq(pack_id, "fixture")
  assert_eq(tool_id, "fixture.acquire")
  assert_eq(mode, "licensed")
}

///|
test "pack workflow declaration has a stable JSON intake boundary" {
  let declaration = decode_workflow_declaration(
    workflow_declaration().to_json().stringify(),
  )
  assert_eq(declaration.pack_id, "fixture")
  assert_eq(declaration.product_id, "fixture")
  assert_eq(declaration.steps.length(), 2)
}

///|
test "pack workflow compiler fails closed on undeclared tools" {
  let declaration = {
    ..workflow_declaration(),
    steps: [
      {
        id: "unknown",
        tool_id: "fixture.unknown",
        config: {},
        retry_policy: None,
      },
    ],
    output_bindings: ["unknown"],
  }
  try compile_workflow_job(workflow_projection(), declaration, 100) catch {
    error =>
      assert_true(
        "\{error}".contains("references undeclared tool fixture.unknown"),
      )
  } noraise {
    _ => fail("expected undeclared tool to be rejected")
  }
}

///|
test "pack workflow compiler rejects a declaration from another pack" {
  let declaration = { ..workflow_declaration(), pack_id: "other" }
  try compile_workflow_job(workflow_projection(), declaration, 100) catch {
    error =>
      assert_true(
        "\{error}".contains(
          "pack workflow ownership does not match activation projection",
        ),
      )
  } noraise {
    _ => fail("expected mismatched pack ownership to be rejected")
  }
}

///|
test "pack workflow compiler rejects an unknown output binding" {
  let declaration = {
    ..workflow_declaration(),
    output_bindings: ["missing-step"],
  }
  try compile_workflow_job(workflow_projection(), declaration, 100) catch {
    error =>
      assert_true(
        "\{error}".contains(
          "output binding references unknown step: missing-step",
        ),
      )
  } noraise {
    _ => fail("expected unknown output binding to be rejected")
  }
}

///|
async test "pack workflow intake persists definition workflow run and checkpoint" {
  @fsx.with_temporary_directory("packtool-workflow-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let runtime = @job.RuntimeManager::new(root~)
    let intake = match
      intake_workflow_run(
        runtime,
        workflow_projection(),
        workflow_declaration(),
        "run-pack-1",
        200,
      ) {
      Ok(intake) => intake
      Err(error) => fail(error)
    }
    assert_eq(intake.definition.id, "pack.fixture.v1.2.0.job.daily.v2.0.0")
    assert_eq(intake.run.job_id, intake.definition.id)
    assert_true(intake.run.status is Pending)

    let reloaded = @job.RuntimeManager::new(root~)
    reloaded.load()
    assert_true(
      reloaded.store().get_definition(intake.definition.id) is Some(_),
    )
    assert_true(reloaded.store().get_workflow(intake.workflow.id) is Some(_))
    assert_true(reloaded.store().get_run("run-pack-1") is Some(_))
    assert_true(reloaded.checkpoints().get(intake.definition.id) is Some(_))
  })
}

///|
async test "pack workflow intake never overwrites an existing run id" {
  @fsx.with_temporary_directory("packtool-run-id-XXXXXX", dir => {
    let runtime = @job.RuntimeManager::new(root=@pathx.join(dir, "jobs"))
    let first = intake_workflow_run(
      runtime,
      workflow_projection(),
      workflow_declaration(),
      "run-pack-1",
      200,
    )
    assert_true(first is Ok(_))
    let second = intake_workflow_run(
      runtime,
      workflow_projection(),
      workflow_declaration(),
      "run-pack-1",
      300,
    )
    guard second is Err(error) else {
      fail("expected duplicate run id to be rejected")
    }
    assert_true(error.contains("already exists"))
    guard runtime.store().get_run("run-pack-1") is Some(run) else {
      fail("expected original run")
    }
    assert_eq(run.job_id, "pack.fixture.v1.2.0.job.daily.v2.0.0")
  })
}
