///|
#skip("Requires the real Fort signed retained-output fixture and freshly built native reader")
async test "Fort retained receipt crosses Claw trusted binding gateway and shipped UI without changing bytes" {
  guard @os.getenv("MOONFORT_R13_FIXTURE_ROOT") is Some(fixture) &&
    @os.getenv("MOONFORT_R13_READER") is Some(reader) else {
    fail("Fort fixture and reader are required")
  }
  let payload = @json.parse(
    @fs.read_file(fixture + "/fort-fixture.json").text(),
  )
  guard payload is { "grant": grant_json, "receipt": receipt_json, .. } else {
    fail("Invalid Fort fixture")
  }
  let grant : @execution_sandbox.MoonFortExecutionGrant = @json.from_json(
    grant_json,
  )
  let receipt : @execution_sandbox.MoonFortReceipt = @json.from_json(
    receipt_json,
  )
  let expected = b"Fort\x00\xff\x80\xc0\xfe\nexact"
  @fsx.with_temporary_directory("claw-fort-linked-XXXXXX", dir => {
    let receipts = dir + "/receipts"
    @fsx.make_directory(receipts)
    let config = {
      ..@execution_sandbox.local_sandbox_executor_config(
        "/usr/bin/true",
        "/usr/bin/true",
        fixture + "/fort-config.json",
        receipts,
        grant.workspace_id,
        allow_degraded=true,
      ),
      command_output_reader_path: Some(reader),
      limits: grant.limits,
    }
    let plan : @execution_sandbox.SandboxApprovalPlan = {
      grant,
      expected_approval_digest: @execution_sandbox.moonfort_grant_digest(grant),
      runtime_binding_digest: "synthetic-recorded-execution",
    }
    ignore(@execution_sandbox.persist_sandbox_audit(config, plan, receipt))
    let owner : @execution_sandbox.CommandOutputOwner = {
      run_id: "run-1",
      step_id: "step-1",
    }
    @execution_sandbox.persist_command_output_binding(
      config, owner, plan, receipt,
    )
    @execution_sandbox.persist_command_output_binding(
      config, owner, plan, receipt,
    )
    let now = @clock.epoch.now().ms()
    let outputs = @execution_sandbox.list_bound_command_outputs(
      config, "run-1", now,
    )
    assert_eq(outputs.length(), 1)
    assert_eq(outputs[0].status, "available")
    assert_eq(outputs[0].output_truncated, receipt.output_truncated)
    assert_eq(outputs[0].receipt_status, "exited")
    assert_eq(outputs[0].exit_code, receipt.exit_code)
    assert_eq(outputs[0].limit_reason, receipt.limit_reason)
    assert_eq(
      @execution_sandbox.download_bound_command_output(
        config,
        "run-1",
        receipt.run_id,
        now,
      ),
      expected,
    )
    assert_true(
      @execution_sandbox.list_bound_command_outputs(
        config, "old-unbound-run", now,
      ).is_empty(),
    )
    try
      @execution_sandbox.persist_command_output_binding(
        config,
        { ..owner, run_id: "other-run", },
        plan,
        receipt,
      )
    catch {
      error => assert_true(error.to_string().contains("different run"))
    } noraise {
      _ => fail("execution was rebound to another Claw run")
    }
    try
      @execution_sandbox.persist_command_output_binding(
        config,
        { ..owner, step_id: "other-step", },
        plan,
        receipt,
      )
    catch {
      error => assert_true(error.to_string().contains("different run"))
    } noraise {
      _ => fail("execution was rebound to another step")
    }
    let bad_root = dir + "/tampered-reference"
    @fsx.make_directory(bad_root)
    let bad_config = { ..config, receipt_root: bad_root, }
    let bad_receipt = {
      ..receipt,
      output_artifact: Some({
        ..receipt.output_artifact.unwrap(),
        signature: "0".repeat(64),
      }),
    }
    ignore(
      @execution_sandbox.persist_sandbox_audit(bad_config, plan, bad_receipt),
    )
    @execution_sandbox.persist_command_output_binding(
      bad_config, owner, plan, bad_receipt,
    )
    try
      @execution_sandbox.download_bound_command_output(
        bad_config,
        owner.run_id,
        receipt.run_id,
        now,
      )
    catch {
      error => assert_true(error.to_string().contains("verification"))
    } noraise {
      _ => fail("Fort signed-reference tamper was accepted")
    }
    let expired = @execution_sandbox.list_bound_command_outputs(
      config,
      "run-1",
      receipt.output_artifact.unwrap().expires_at_ms,
    )
    assert_eq(expired[0].status, "expired")
    try
      @execution_sandbox.download_bound_command_output(
        config,
        "run-1",
        receipt.run_id,
        receipt.output_artifact.unwrap().expires_at_ms,
      )
    catch {
      error => assert_true(error.to_string().contains("expired"))
    } noraise {
      _ => fail("expired output downloaded")
    }
    let gateway = Gateway::new(
      port=0,
      cwd=dir[:],
      home=dir[:],
      auth={ token: Some("fixture-only-token"), _password: None, },
      command_output_config=config,
    )
    defer gateway.httpx.close()
    let store = gateway.job_runtime().store()
    store.save_definition({
      id: "job-fixture",
      kind: "job.proposal.research",
      enabled: true,
      config: {},
      schedule: None,
      retry_policy: None,
      workflow_id: None,
      created_at: 10,
      updated_at: 10,
      tags: [],
    })
    let run : @job.JobRun = {
      id: "run-1",
      job_id: "job-fixture",
      trigger: Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: Some(dir),
      status: Succeeded,
      attempt: 1,
      retry_of: None,
      started_at: Some(20),
      finished_at: Some(30),
      summary: Some("Fixture completed"),
      error: None,
    }
    store.save_run(run)
    store.save_run({ ..run, id: "other-run", })
    store.load()
    let base = "http://127.0.0.1:\{gateway.httpx.port()}"
    let endpoint = base +
      "/v1/jobs/runs/run-1/command-outputs/" +
      receipt.run_id +
      "/download"
    let headers = { "authorization": "Bearer fixture-only-token" }
    @async.with_task_group(group => {
      group.spawn_bg(
        () => {
          gateway.httpx.serve(
            @httpx.Handler((r, w) => gateway.handle_request(r, w)),
          )
        },
        no_wait=true,
      )
      // Exercise the default served production build, not a source-only
      // harness or a custom UI root. Every shipped JavaScript asset must match
      // the fresh tracked dist byte-for-byte over the real gateway.
      let dist = @os.cwd() + "/ui/rabbita-job/dist"
      let (index_response, index_body) = @http.get(base + "/ui")
      assert_eq(index_response.code, 200)
      let index = @fs.read_file(dist + "/index.html").text()
      assert_eq(index_body.text(), index)
      let entry_paths = index.split("src=\"/assets/").to_array()
      guard entry_paths.length() == 2 else {
        fail("Built HTML must name its production entry")
      }
      let entry = entry_paths[1].split("\"").next().unwrap().to_owned()
      let (entry_response, entry_body) = @http.get(base + "/assets/" + entry)
      assert_eq(entry_response.code, 200)
      let entry_code = entry_body.text()
      let current = operator_ui_current_compiled_entry(
        entry_code,
        @fs.readdir(dist + "/assets"),
      )
      assert_true(entry_code.contains("moonbook.product-outcome-package.v1"))
      let served = StringBuilder()
      for asset in @fs.readdir(dist + "/assets", sort=true) {
        if !asset.has_suffix(".js") {
          continue
        }
        if asset == current {
          assert_true(
            entry_code.contains(asset),
            msg="Production entry must load the compiled operator controls",
          )
        }
        let (response, body) = @http.get(base + "/assets/" + asset)
        assert_eq(response.code, 200)
        assert_eq(
          body.binary(),
          @fs.read_file(dist + "/assets/" + asset).binary(),
        )
        if asset == current || asset == entry {
          served.write_string(body.text())
        }
      }
      assert_true(served.to_string().contains("Download retained output"))
      assert_true(served.to_string().contains("approved output ceiling"))
      assert_true(served.to_string().contains("Send completed output to Book"))
      assert_true(
        served.to_string().contains("moonbook.product-outcome-package.v1"),
      )
      println("DEFAULT_GATEWAY_TRACKED_DIST_PASSED")
      let (ui_code, ui_output) = @process.collect_output_merged(
        "moon",
        [
          "test", "--target", "js", "--warn-list", "-a", "main/command_output_http_wbtest.mbt",
          "--index", "0",
        ],
        extra_env={ "MOONCLAW_HTTP_FIXTURE_URL": base },
        cwd=@os.cwd() + "/ui/rabbita-job",
      )
      assert_eq(ui_code, 0, msg=ui_output.text())
      assert_true(
        ui_output.text().contains("ACTUAL_FORT_CLAW_UI_PASSED"),
        msg=ui_output.text(),
      )
      println("ACTUAL_FORT_CLAW_UI_PASSED")
      let (ok, body) = @http.get(endpoint, headers~)
      assert_eq(ok.code, 200)
      assert_eq(body.binary(), expected)
      let (denied, _) = @http.get(endpoint)
      assert_eq(denied.code, 401)
      let audit_path = receipts + "/" + receipt.run_id + ".json"
      let original = @fs.read_file(audit_path).binary()
      @fs.write_file(audit_path, "{}", create_mode=CreateOrTruncate)
      let (tampered, body) = @http.get(endpoint, headers~)
      assert_eq(tampered.code, 409)
      assert_true(body.text().contains("verification"))
      assert_false(body.text().contains(fixture))
      @fs.write_file(audit_path, original, create_mode=CreateOrTruncate)
      let configuration = @json.parse(
        @fs.read_file(fixture + "/fort-config.json").text(),
      )
      guard configuration is { "retention_root": String(root), .. } else {
        fail("Fixture root missing")
      }
      let blob = root +
        "/output-artifacts/" +
        receipt.output_artifact.unwrap().artifact_id +
        ".blob"
      let retained = @fs.read_file(blob).binary()
      @fs.remove(blob)
      let (missing, _) = @http.get(endpoint, headers~)
      assert_eq(missing.code, 409)
      @fs.write_file(blob, retained, create_mode=CreateNew, permission=0o600)
      let (retried, body) = @http.get(endpoint, headers~)
      assert_eq(retried.code, 200)
      assert_eq(body.binary(), expected)
      group.return_immediately(())
    })
  })
}
