///|
fn moondesk_test_promotion_request() -> MoonDeskPromotionRequest {
  {
    protocol_version: 1,
    instance_id: "0123456789abcdef0123456789abcdef",
    request_id: "request-0123456789",
    workspace_id: "book-primary",
    retention_id: "retention-0123456789",
    approval_digest: "a".repeat(64),
    command_digest: "b".repeat(64),
    items: [
      {
        source_relative: "reports/result.txt",
        destination_relative: "reviewed/result.txt",
      },
    ],
  }
}

///|
test "promotion public request translates to MoonFort promotion v4 without host paths" {
  let request = moondesk_test_promotion_request()
  let encoded = moondesk_promotion_moonfort_request(request).stringify()
  assert_true(encoded.contains("artifact_path"))
  assert_true(encoded.contains("destination_path"))
  assert_false(encoded.contains("source_relative_path"))
  assert_false(encoded.contains("destination_relative_path"))
  assert_true(encoded.contains("reports/result.txt"))
  assert_false(encoded.contains("/Users/"))
  assert_false(encoded.contains("workspace_root"))
}

///|
test "promotion requires trusted MoonFort echo of every reviewed binding" {
  let request = moondesk_test_promotion_request()
  let response : MoonFortPromotionResponse = {
    protocol_version: 4,
    retention_id: request.retention_id,
    workspace_id: request.workspace_id,
    approval_digest: request.approval_digest,
    command_digest: request.command_digest,
    promoted_paths: ["reviewed/result.txt"],
    destination_outcome: "applied-durable",
    uncertain_paths: [],
    completed: true,
    error: None,
  }
  assert_eq(moondesk_promotion_validate_response(request, response), response)
  try
    moondesk_promotion_validate_response(request, {
      ..response,
      command_digest: "c".repeat(64),
    })
  catch {
    error => assert_true("\{error}".contains("did not match"))
  } noraise {
    _ => fail("mismatched trusted command digest was accepted")
  }
}

///|
test "promotion parser requires exactly one safe mapping" {
  let base = @json.to_json(moondesk_test_promotion_request())
  guard base is Object(fields) else { fail("expected object") }
  fields["items"] = [
    { "source_relative": "../escape", "destination_relative": "safe/a" },
  ].to_json()
  try moondesk_promotion_parse_request(base) catch {
    _ => ()
  } noraise {
    _ => fail("scratch traversal was accepted")
  }
  fields["items"] = [
    { "source_relative": "one", "destination_relative": "same" },
    { "source_relative": "two", "destination_relative": "same" },
  ].to_json()
  try moondesk_promotion_parse_request(base) catch {
    _ => ()
  } noraise {
    _ => fail("multiple promotion items were accepted")
  }
  fields["items"] = Json::array([])
  try moondesk_promotion_parse_request(base) catch {
    _ => ()
  } noraise {
    _ => fail("empty promotion was accepted")
  }
}

///|
fn moondesk_test_promotion_response(
  request : MoonDeskPromotionRequest,
) -> MoonFortPromotionResponse {
  {
    protocol_version: 4,
    retention_id: request.retention_id,
    workspace_id: request.workspace_id,
    approval_digest: request.approval_digest,
    command_digest: request.command_digest,
    promoted_paths: [request.items[0].destination_relative],
    destination_outcome: "applied-durable",
    uncertain_paths: [],
    completed: true,
    error: None,
  }
}

///|
test "promotion preserves every truthful MoonFort destination outcome" {
  let request = moondesk_test_promotion_request()
  let applied = moondesk_test_promotion_response(request)
  let cleanup_unverified : MoonFortPromotionResponse = {
    ..applied,
    completed: false,
    error: Some({
      code: "promotion-cleanup-unverified",
      message: "private provider diagnostic",
    }),
  }
  let not_applied : MoonFortPromotionResponse = {
    ..applied,
    workspace_id: "",
    approval_digest: "",
    command_digest: "",
    promoted_paths: [],
    destination_outcome: "not-applied",
    completed: false,
    error: Some({
      code: "promotion-refused",
      message: "private provider diagnostic",
    }),
  }
  let claim_recovery : MoonFortPromotionResponse = {
    ..applied,
    promoted_paths: [],
    destination_outcome: "not-applied",
    completed: false,
    error: Some({
      code: "promotion-recovery-required",
      message: "private provider diagnostic",
    }),
  }
  let destination_recovery : MoonFortPromotionResponse = {
    ..claim_recovery,
    destination_outcome: "recovery-required",
    uncertain_paths: [request.items[0].destination_relative],
  }
  for
    response in [
      applied, cleanup_unverified, not_applied, claim_recovery, destination_recovery,
    ] {
    assert_eq(moondesk_promotion_validate_response(request, response), response)
    let public = moondesk_promotion_public_response(request, response).stringify()
    assert_false(public.contains("private provider diagnostic"))
    assert_false(public.contains("native status"))
  }
  let cleanup_json = moondesk_promotion_public_response(
    request, cleanup_unverified,
  ).stringify()
  assert_true(cleanup_json.contains("applied-durable"))
  assert_true(cleanup_json.contains("promotion-cleanup-unverified"))
  let recovery_json = moondesk_promotion_public_response(
    request, destination_recovery,
  ).stringify()
  assert_true(recovery_json.contains("\"recovery_required\":true"))
  assert_true(recovery_json.contains("reviewed/result.txt"))
}

///|
test "promotion rejects contradictory outcomes and unreviewed uncertainty" {
  let request = moondesk_test_promotion_request()
  let applied = moondesk_test_promotion_response(request)
  let invalid : Array[MoonFortPromotionResponse] = [
    { ..applied, destination_outcome: "not-applied" },
    {
      ..applied,
      completed: false,
      error: Some({ code: "promotion-refused", message: "wrong code" }),
    },
    {
      ..applied,
      promoted_paths: [],
      destination_outcome: "recovery-required",
      uncertain_paths: ["/private/host-secret"],
      completed: false,
      error: Some({
        code: "promotion-recovery-required",
        message: "native status 5",
      }),
    },
    {
      ..applied,
      promoted_paths: [],
      destination_outcome: "recovery-required",
      uncertain_paths: ["other/result.txt"],
      completed: false,
      error: Some({ code: "promotion-recovery-required", message: "wrong path" }),
    },
  ]
  for response in invalid {
    try moondesk_promotion_validate_response(request, response) catch {
      _ => ()
    } noraise {
      _ => fail("contradictory promotion outcome was accepted")
    }
  }
}

///|
test "conversation projection keeps only sanitized sandbox evidence" {
  let metadata : Json = {
    "approval_plan_digest": "b".repeat(64),
    "audit_path": "/private/host/audit.json",
    "run_id": "/private/host/run",
    "sandbox_evidence": {
      "approval_digest": "a".repeat(64),
      "approval_plan_digest": "b".repeat(64),
      "backend": "MicroVm",
      "enforcement": "Enforced",
      "cleanup_verified": true,
      "profile_digest": "c".repeat(64),
      "command_digest": "d".repeat(64),
      "unverified_limits": [],
      "changed_paths": ["reports/result.txt"],
      "changes": [],
      "artifacts": ["reports/result.txt"],
      "retention_id": "retention-0123456789",
      "requested_policy": {
        "network": "Deny",
        "limits": {
          "wall_clock_ms": 5000,
          "cpu_seconds": 5,
          "memory_mib": 256,
          "disk_mib": 512,
          "processes": 16,
          "output_bytes": 4096,
        },
      },
    },
  }
  let evidence = mooncode_conversation_sandbox_evidence(metadata)
  assert_eq(
    mooncode_json_string(evidence, "approval_digest", default=""),
    "a".repeat(64),
  )
  assert_eq(mooncode_json_string(evidence, "network", default=""), "Deny")
  let encoded = evidence.stringify()
  assert_true(encoded.contains("reports/result.txt"))
  assert_false(encoded.contains("audit_path"))
  assert_false(encoded.contains("/private/host"))
}
