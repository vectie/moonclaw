///|
fn live_protocol_fixture() -> MoonFortLiveOutputReadResponse {
  {
    protocol_version: 1,
    approval_id: "approval-test",
    stream_id: "a".repeat(64),
    run_id: "request-test",
    offset: 0L,
    next_offset: 3L,
    available_bytes: 3L,
    content_base64: "YWJj",
    status: "running",
    terminal: false,
    retry_after_ms: 0,
    error: None,
  }
}

///|
test "live bytes validate identity protocol bounds and exact canonical decoded length" {
  let good = live_protocol_fixture()
  assert_eq(
    validated_live_output_bytes(good, "approval-test", "request-test", 0L, 8192),
    b"abc",
  )
  let empty = {
    ..good,
    next_offset: 0L,
    available_bytes: 0L,
    content_base64: "",
  }
  assert_eq(
    validated_live_output_bytes(
      empty, "approval-test", "request-test", 0L, 8192,
    ),
    b"",
  )
  for
    bad in [
      { ..good, protocol_version: 2, },
      { ..good, approval_id: "wrong", },
      { ..good, run_id: "cross-run", },
      { ..good, stream_id: "wrong", },
      { ..good, offset: 1L, },
      { ..good, next_offset: -1L, },
      { ..good, next_offset: 4L, },
      { ..good, available_bytes: 8193L, },
      { ..good, content_base64: "YWJjAA==", },
      { ..good, content_base64: "!!!!", },
      { ..good, content_base64: "YWJj\n", },
      { ..good, status: "succeeded", },
      { ..good, terminal: true, },
      { ..good, status: "exited", terminal: false, },
      { ..good, retry_after_ms: 999999, },
      { ..good, error: Some({ code: "unavailable", message: "fixture", }), },
    ] {
    try
      validated_live_output_bytes(
        bad, "approval-test", "request-test", 0L, 8192,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("Invalid live read was accepted")
    }
  }
  let terminal = { ..good, status: "failed", terminal: true, }
  assert_eq(
    validated_live_output_bytes(
      terminal, "approval-test", "request-test", 0L, 8192,
    ),
    b"abc",
  )
}

///|
async test "pre-dispatch live binding is immutable and independent of terminal receipt" {
  @fsx.with_temporary_directory("claw-live-binding-XXXXXX", dir => {
    let dir = @fs.realpath(dir)
    @fs.write_file(dir + "/config.json", "{}", create_mode=CreateNew)
    let config = local_sandbox_executor_config(
      "/usr/bin/true",
      "/usr/bin/true",
      dir + "/config.json",
      dir,
      "fixture-workspace",
    )
    let plan = make_sandbox_plan(
      config, dir, dir, "fixture-only-not-executed", 1000,
    )
    validate_approved_plan(plan, config, dir, dir, "fixture-only-not-executed")
    let owner = CommandOutputOwner::{ run_id: "claw-run", step_id: "step-1", }
    persist_command_live_binding(config, owner, plan)
    persist_command_live_binding(config, owner, plan)
    assert_eq(list_bound_command_live_outputs(config, owner.run_id).length(), 1)
    assert_true(
      list_bound_command_outputs(config, owner.run_id, @clock.epoch.now().ms()).is_empty(),
    )
    assert_false(@fs.exists(dir + "/" + plan.grant.request_id + ".json"))
    for wrong in [{ ..owner, run_id: "other", }, { ..owner, step_id: "other", }] {
      try persist_command_live_binding(config, wrong, plan) catch {
        _ => ()
      } noraise {
        _ => fail("Ownership changed")
      }
    }
    try command_live_binding(config, "other", plan.grant.request_id) catch {
      _ => ()
    } noraise {
      _ => fail("Cross-run ownership accepted")
    }
    try
      read_bound_command_live_output(
        config,
        owner.run_id,
        plan.grant.request_id,
        "start",
      )
    catch {
      error => assert_true(error.to_string().contains("not configured"))
    } noraise {
      _ => fail("Unconfigured reader was used")
    }
    let invalid = { ..plan, runtime_binding_digest: "0".repeat(64), }
    try persist_command_live_binding(config, owner, invalid) catch {
      _ => ()
    } noraise {
      _ => fail("Unvalidated plan bound")
    }
    let changed = { ..config, live_output_reader_path: Some("/usr/bin/true"), }
    try
      command_live_binding(changed, owner.run_id, plan.grant.request_id)
    catch {
      _ => ()
    } noraise {
      _ => fail("Changed operator configuration accepted")
    }
    let root = command_live_root(config, owner.run_id)
    command_live_write_once(root + "/pin.stream", "a".repeat(64))
    command_live_write_once(root + "/pin.stream", "a".repeat(64))
    try command_live_write_once(root + "/pin.stream", "b".repeat(64)) catch {
      _ => ()
    } noraise {
      _ => fail("Stream identity replaced")
    }
    assert_eq(
      command_output_read_file(root + "/pin.stream", 8192),
      "a".repeat(64),
    )
  })
}
