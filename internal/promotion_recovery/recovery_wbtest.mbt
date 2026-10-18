///|
fn recovery_test_selection() -> MoonDeskPromotionRequest {
  {
    protocol_version: 1,
    instance_id: "0123456789abcdef0123456789abcdef",
    workspace_id: "book",
    retention_id: "retained-55",
    request_id: "return-original-55",
    approval_digest: "b".repeat(64),
    command_digest: "c".repeat(64),
    items: [
      { source_relative: "artifact", destination_relative: "reviewed/result", },
    ],
  }
}

///|
fn recovery_test_request() -> MoonDeskRecoveryRequest {
  let pending = recovery_test_selection()
  {
    protocol_version: 1,
    instance_id: pending.instance_id,
    workspace_id: pending.workspace_id,
    retention_id: pending.retention_id,
    pending_attempt_id: pending.request_id,
    request_id: "inspect-55",
  }
}

///|
fn recovery_test_response(outcome : String) -> MoonFortRecoveryResponse {
  let pending = recovery_test_selection()
  {
    protocol_version: 4,
    retention_id: pending.retention_id,
    workspace_id: pending.workspace_id,
    profile_digest: "a".repeat(64),
    approval_digest: pending.approval_digest,
    command_digest: pending.command_digest,
    destination_path: "reviewed/result",
    reviewed_state_digest: "1".repeat(64),
    desired_state_digest: "2".repeat(64),
    observed_state_digest: match outcome {
      "desired-applied" => "2".repeat(64)
      "reviewed-prestate" => "1".repeat(64)
      "diverged" => "3".repeat(64)
      _ => ""
    },
    outcome,
    error: match outcome {
      "manual-recovery" =>
        Some(
          try! @json.from_json({
            "code": "root-mapping-unproven",
            "message": "/private/CANARY-secret",
          }),
        )
      "unavailable" =>
        Some(
          try! @json.from_json({
            "code": "destination-unavailable",
            "message": "/private/CANARY-secret",
          }),
        )
      _ => None
    },
  }
}

///|
test "recovery error validates required remote fields before retaining only code" {
  let valid : MoonFortPromotionError = @json.from_json({
    "code": "root-mapping-unproven",
    "message": "/private/CANARY-secret",
    "future_field": true,
  })
  assert_eq(valid.code, "root-mapping-unproven")
  let invalids : Array[Json] = [
    { "code": "root-mapping-unproven" },
    { "code": "root-mapping-unproven", "message": Json::null() },
    { "code": "root-mapping-unproven", "message": 7 },
    { "message": "diagnostic" },
    { "code": false, "message": "diagnostic" },
  ]
  for invalid in invalids {
    try {
      let _ : MoonFortPromotionError = @json.from_json(invalid)
    } catch {
      _ => ()
    } noraise {
      _ => fail("invalid recovery error must fail required-field validation")
    }
  }
}

///|
async fn recovery_test_pending(root : String) -> String {
  let pending = recovery_test_selection()
  let path = moondesk_promotion_identity_path(
    root,
    pending.instance_id,
    pending.workspace_id,
    pending.retention_id,
  )
  @fs.write_file(
    path,
    ({ "request": pending.to_json(), "pending_attempt": true } : Json).stringify(),
    create_mode=CreateNew,
    permission=0o600,
  )
  @fs.write_file(path + ".lock", "", create_mode=CreateNew, permission=0o600)
  path
}

///|
async test "read-only recovery projects all five observations without confirming or retrying return" {
  @fsx.with_temporary_directory("recovery-read-only-XXXXXX", async fn(root) {
    let root = @fs.realpath(root)
    let path = recovery_test_pending(root)
    let before = @fs.read_file(path).binary()
    let names = @fs.readdir(root)
    for
      outcome in [
        "desired-applied", "reviewed-prestate", "diverged", "unavailable", "manual-recovery",
      ] {
      let value = moondesk_recovery_inspect(recovery_test_request(), root, async fn(
        retention,
      ) {
        assert_eq(retention, "retained-55")
        recovery_test_response(outcome)
      })
      let text = value.stringify()
      assert_true(text.contains(outcome))
      assert_true(text.contains("\"pending_attempt\":true"))
      assert_true(text.contains("\"retry_allowed\":false"))
      assert_true(text.contains("\"historical_success_confirmed\":false"))
      assert_false(text.contains("CANARY"))
      assert_false(text.contains("/private"))
      assert_eq(@fs.read_file(path).binary(), before)
      assert_eq(@fs.readdir(root), names)
    }
  })
}

///|
async test "recovery refuses wrong pending attempt missing lock active return and stale readback" {
  @fsx.with_temporary_directory("recovery-stale-XXXXXX", async fn(root) {
    let root = @fs.realpath(root)
    let path = recovery_test_pending(root)
    let invoked = Ref(0)
    let invoke = async fn(_retention) {
      invoked.val += 1
      recovery_test_response("desired-applied")
    }
    let request = recovery_test_request()
    for
      wrong in [
        { ..request, pending_attempt_id: "another-attempt", },
        { ..request, workspace_id: "another", },
        { ..request, instance_id: "another", },
        { ..request, retention_id: "another", },
      ] {
      assert_true(
        (Ok(moondesk_recovery_inspect(wrong, root, invoke)) catch {
          error => Err(error)
        })
        is Err(_),
      )
    }
    assert_eq(invoked.val, 0)
    let lock = @fs.open(path + ".lock", mode=ReadWrite)
    lock.lock(Exclusive)
    assert_true(
      (Ok(moondesk_recovery_inspect(request, root, invoke)) catch {
        error => Err(error)
      })
      is Err(_),
    )
    lock.unlock()
    lock.close()
    assert_eq(invoked.val, 0)
    assert_true(
      (Ok(
        moondesk_recovery_inspect(request, root, async fn(_) {
          let changed = {
            ..recovery_test_selection(),
            request_id: "new-attempt",
          }
          @fs.write_file(
            path,
            ({ "request": changed.to_json(), "pending_attempt": true } : Json).stringify(),
          )
          recovery_test_response("desired-applied")
        }),
      ) catch {
        error => Err(error)
      })
      is Err(_),
    )
    @fs.remove(path + ".lock")
    assert_true(
      (Ok(moondesk_recovery_inspect(request, root, invoke)) catch {
        error => Err(error)
      })
      is Err(_),
    )
    assert_false(@fs.exists(path + ".lock"))
  })
}

///|
test "inspection response binding and state matrix reject substituted contradictory or leaking fields" {
  let pending = recovery_test_selection()
  let response = recovery_test_response("desired-applied")
  for
    wrong in [
      { ..response, retention_id: "another", },
      { ..response, workspace_id: "another", },
      { ..response, approval_digest: "f".repeat(64), },
      { ..response, command_digest: "f".repeat(64), },
      { ..response, destination_path: "/private/secret", },
      { ..response, outcome: "applied-durable", },
      { ..response, observed_state_digest: "1".repeat(64), },
      { ..response, outcome: "reviewed-prestate", },
      { ..response, outcome: "diverged", },
      { ..response, outcome: "manual-recovery", },
      { ..response, profile_digest: "secret", },
    ] {
    assert_true(
      (Ok(moondesk_recovery_validate(pending, wrong)) catch {
        error => Err(error)
      })
      is Err(_),
    )
  }
  moondesk_recovery_validate(pending, {
    ..response,
    reviewed_state_digest: response.desired_state_digest,
  })
  assert_true(token_equal("a".repeat(64), "a".repeat(64)))
  assert_false(token_equal("b".repeat(64), "a".repeat(64)))
  assert_false(token_equal("", "a".repeat(64)))
  let request = recovery_test_request()
  let extra : Json = {
    "protocol_version": request.protocol_version,
    "instance_id": request.instance_id,
    "workspace_id": request.workspace_id,
    "retention_id": request.retention_id,
    "pending_attempt_id": request.pending_attempt_id,
    "request_id": request.request_id,
  }
  guard extra is Object(fields) else { fail("object") }
  fields["workspace_root"] = Json("/private/secret")
  assert_true(
    (Ok(moondesk_recovery_parse_request(extra)) catch { error => Err(error) })
    is Err(_),
  )
}
