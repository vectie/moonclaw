///|
#skip("Requires prepared round55 real Fort inspector fixtures")
async test "normal daemon route preserves exact pending identity and read-only outcomes" {
  guard @os.getenv("ROUND55_ROOT") is Some(root) &&
    @os.getenv("ROUND55_FIXTURE_ROOT") is Some(fixture) else {
    fail("round55 fixture required")
  }
  @fsx.with_temporary_directory("round55-daemon-XXXXXX", dir => {
    let daemon = Daemon::new(
      exec_path=root +
        "/evidence/build-moonfort/native/debug/build/cmd/inspect-promotion-recovery/inspect-promotion-recovery.exe",
      port=0,
      serve=dir,
      cwd=dir[:],
      home=dir[:],
      lock=false,
    ).unwrap()
    defer daemon.httpx.close()
    let endpoint = "http://127.0.0.1:\{daemon.port()}/v1/execution-sandbox/promotion-recovery"
    @async.with_task_group(group => {
      group.spawn_bg(() => daemon.serve(), no_wait=true)
      let cases = @json.parse(@fs.read_file(fixture + "/cases.json").text())
      guard cases is Array(cases) else { fail("cases") }
      for item in cases {
        guard item
          is {
            "retention_id": String(retention),
            "pending_attempt_id": String(attempt),
            "outcome": String(outcome),
            "destination_relative": String(destination),
            ..
          } else {
          fail("case")
        }
        let request : Json = {
          "protocol_version": 1,
          "instance_id": "a".repeat(32),
          "workspace_id": "book",
          "retention_id": retention,
          "pending_attempt_id": attempt,
          "request_id": "daemon-read-55",
        }
        let (response, body) = @http.post(endpoint, request.stringify(), headers={
          "x-moonclaw-execution-token": "b".repeat(64),
        })
        assert_eq(response.code, 200, msg=body.text())
        assert_eq(response.headers.get("cache-control"), Some("no-store"))
        let value = @json.parse(body.text())
        assert_true(
          value
          is {
            "outcome": String(actual),
            "pending_attempt_id": String(bound),
            "pending_attempt": true,
            "retry_allowed": false,
            "historical_success_confirmed": false,
            ..
          } &&
          actual == outcome &&
          bound == attempt,
        )
        assert_false(body.text().contains("CANARY"))
        assert_false(body.text().contains(fixture))
        let lookup : Json = {
          "protocol_version": 1,
          "instance_id": "a".repeat(32),
          "workspace_id": "book",
          "retention_id": retention,
          "request_id": "later-receipt-lookup",
          "approval_digest": "b".repeat(64),
          "command_digest": "c".repeat(64),
          "items": [
            {
              "source_relative": "artifact",
              "destination_relative": destination,
            },
          ],
        }
        let receipt_endpoint = "http://127.0.0.1:\{daemon.port()}/v1/execution-sandbox/promotion-receipt"
        let (receipt_response, receipt_body) = @http.post(
          receipt_endpoint,
          lookup.stringify(),
          headers={ "x-moonclaw-execution-token": "b".repeat(64) },
        )
        assert_eq(receipt_response.code, 503)
        assert_true(receipt_body.text().contains("pending_return"))
        assert_true(receipt_body.text().contains(attempt))
        assert_false(receipt_body.text().contains("later-receipt-lookup"))
        assert_false(receipt_body.text().contains(fixture))
      }
      let (denied, _) = @http.post(endpoint, "{}")
      assert_eq(denied.code, 401)
      group.return_immediately(())
    })
  })
  println("ROUND55_NORMAL_DAEMON_ROUTE_PASSED")
}
