///|
#skip("Explicit cross-repository production Gate and Desk loopback qualification")
async test "Desk imports through actual Claw and production Gate before saving" {
  guard @os.getenv("GATE_PROVIDER_VALIDATION_FIXTURE") is Some(raw) &&
    @os.getenv("CHECKPOINT26_GATE_EVIDENCE") is Some(evidence) &&
    @os.getenv("CHECKPOINT26_DESK_ROOT") is Some(desk) &&
    @os.getenv("MOON_HOME") is Some(moon_home) else {
    fail(
      "Explicit synthetic Gate fixture, Desk source, evidence and pinned toolchain are required",
    )
  }
  let gate = @json.parse(raw)
  guard gate
    is {
      "contract": "moonclaw-provider-import.gate.loopback.v1",
      "synthetic": True,
      "gate_url": String(gate_url),
      "gate_control_token": "provider-import-gate-control-token",
      "base_url": String(base_url),
      "api_key": "provider-import-synthetic-key",
      "model": "fixture-import-model",
      "rejected_model": "missing-import-model",
      ..
    } &&
    gate_url.has_prefix("http://127.0.0.1:") &&
    base_url.has_prefix("http://127.0.0.1:") else {
    fail("The chain requires the explicit synthetic loopback contract")
  }
  with_integration_http_fixture(owner => {
    provider_import_status(owner.workspace, gate_url)
    let old = @os.getenv("MOONGATE_CONTROL_TOKEN")
    defer (match old {
      Some(value) => @os.setenv("MOONGATE_CONTROL_TOKEN", value)
      None => @os.unsetenv("MOONGATE_CONTROL_TOKEN")
    })
    @os.setenv("MOONGATE_CONTROL_TOKEN", "provider-import-gate-control-token")
    let descriptor : Json = {
      "contract": "moondesk-claw-provider-import.loopback.v1",
      "synthetic": true,
      "port": owner.daemon.port,
      "workspace_root": owner.workspace,
      "instance_id": owner.config.instance_id,
      "auth_token": owner.config.auth_token,
      "base_url": base_url,
      "api_key": "provider-import-synthetic-key",
      "model": "fixture-import-model",
      "rejected_model": "missing-import-model",
    }
    @fsx.write_to_file(
      evidence + "/actual-claw-provider-import-fixture.json",
      descriptor.stringify(indent=2),
    )
    let (code, stdout, stderr) = @async.with_timeout(1200000, () => {
      @process.collect_output(
        moon_home + "/bin/moon",
        [
          "test", "internal/moonwiki/provider_connection_import_wbtest.mbt", "--target",
          "native", "--strip", "-j", "2", "--deny-warn", "--include-skipped",
        ],
        cwd=desk,
        extra_env={
          "MOONDESK_CLAW_PROVIDER_IMPORT_FIXTURE": descriptor.stringify(),
          "RUST_LOG": "error",
        },
      )
    })
    let log = stdout.text() + stderr.text()
    @fsx.write_to_file(evidence + "/actual-desk-provider-import-tests.log", log)
    assert_eq(code, 0, msg=log)
    assert_true(log.contains("Total tests: 4, passed: 4, failed: 0."))
    assert_true(
      log.contains(
        "DESK_ACTUAL_PROVIDER_IMPORT_VALIDATION_CREATE_UPDATE_PASSED",
      ),
    )
  })
}
