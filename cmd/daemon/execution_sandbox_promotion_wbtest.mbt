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
test "promotion public request translates to MoonFort v3 without host paths" {
  let request = moondesk_test_promotion_request()
  let encoded = moondesk_promotion_moonfort_request(request).stringify()
  assert_true(encoded.contains("source_relative_path"))
  assert_true(encoded.contains("destination_relative_path"))
  assert_true(encoded.contains("reports/result.txt"))
  assert_false(encoded.contains("/Users/"))
  assert_false(encoded.contains("workspace_root"))
}

///|
test "promotion requires trusted MoonFort echo of every reviewed binding" {
  let request = moondesk_test_promotion_request()
  let response : MoonFortPromotionResponse = {
    protocol_version: 3,
    retention_id: request.retention_id,
    workspace_id: request.workspace_id,
    approval_digest: request.approval_digest,
    command_digest: request.command_digest,
    promoted_paths: ["reviewed/result.txt"],
    completed: true,
    error: None,
  }
  assert_eq(moondesk_promotion_validate_response(request, response), [
    "reviewed/result.txt",
  ])
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
test "promotion parser rejects traversal and duplicate destinations" {
  let base = moondesk_test_promotion_request().to_json()
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
    error => assert_true("\{error}".contains("duplicate"))
  } noraise {
    _ => fail("duplicate promotion destination was accepted")
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
