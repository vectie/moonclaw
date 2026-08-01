///|
fn supervisor_worker_test_request(
  max_cost_micro_usd? : Int64 = 0L,
) -> SupervisorDelegateIntentRequestV1 raise {
  {
    envelope: {
      contract_id: "moonclaw.supervisor-command.v1",
      command_id: "delegate-command-1",
      request_digest: "sha256:" + "a".repeat(64),
      issued_at: supervisor_epoch_ms_v1(9007199254740993L),
      evaluated_at: "2026-08-01T00:00:00Z",
      expected_cursor: Some(2),
      authority: {},
    },
    supervisor_id: "supervisor-1",
    instruction: "Inspect the repository and produce bounded evidence.",
    task: {
      task_id: "task-1",
      conversation_id: "conversation-1",
      title: "Bounded repository inspection",
      cwd: "/tmp/workspace",
      model: None,
      web_search: false,
      metadata: { "requested_by": "human" },
    },
    scope: {
      claim_ceiling: "evidence-only",
      budget: {
        max_cost_micro_usd,
        max_runtime_ms: 60000L,
        max_tokens: 2000L,
        max_artifacts: 2,
      },
      artifact_prefixes: ["artifacts/supervisor-1/task-1"],
      expires_at: "2026-08-01T01:00:00Z",
    },
  }
}

///|
fn supervisor_worker_test_outcome_candidate() -> SupervisorBookkeeperOutcomeEvidenceV1 {
  let digest = "sha256:" + "b".repeat(64)
  let evidence_id = "artifacts/supervisor-1/task-1/result.json"
  let gap = SupervisorGapStatementV1::{
    present: false,
    severity: 0,
    summary: "No known gap.",
    evidence_refs: [evidence_id],
  }
  {
    contract_version: "moonbook.bookkeeper.product_outcome_submission.v1",
    submission: {
      record_id: "submission-1",
      record_version: "1",
      record_digest: digest,
    },
    source_product: "moonclaw",
    deliverable_title: "Verified worker result",
    deliverable_summary: "Bounded evidence is ready for review.",
    outcome_summary: "The worker produced reviewable evidence.",
    owner_route: "town/supervisor-1",
    evidence_refs: [
      {
        reference_id: evidence_id,
        reference_version: "1",
        digest,
        provenance_ref: "supervisor:supervisor-1:worker-1",
      },
    ],
    decision_evidence_id: evidence_id,
    observed_at: 1700000000,
    recorded_at: 1700000001,
    information_gap: gap,
    recognition_gap: gap,
    decisiveness_gap: gap,
    capability_id: "supervisor-worker",
    capability_version: "1",
    capability_change_digest: digest,
    capability_summary: "Prepared exact evidence without acceptance.",
  }
}

///|
test "supervisor delegate intent is high level and explicitly bounded" {
  let request = supervisor_worker_test_request()
  assert_true(
    validate_supervisor_worker_intent(request, "local-unmetered") is Ok(_),
  )
  let payload = supervisor_delegate_intent_payload_v1(
    request.supervisor_id,
    request.instruction,
    request.task,
    request.scope,
  )
  let encoded = payload.stringify()
  assert_true(encoded.contains("\"instruction\""))
  assert_true(encoded.contains("\"max_runtime_ms\":\"60000\""))
  assert_false(encoded.contains("worker_run_id"))
  assert_false(encoded.contains("delegation_ref"))
}

///|
test "supervisor delegate intent accepts host-resolved local accounting" {
  let request = supervisor_worker_test_request(max_cost_micro_usd=1L)
  assert_true(
    validate_supervisor_worker_intent(request, "local-unmetered") is Ok(_),
  )
  assert_true(
    validate_supervisor_worker_intent(request, "metered-external") is Err(_),
  )
  assert_true(validate_supervisor_worker_intent(request, "unknown") is Err(_))
}

///|
test "supervisor epoch milliseconds preserve values above JavaScript precision" {
  let exact = 9007199254740993L
  let encoded = supervisor_epoch_ms_v1(exact).to_json()
  json_inspect(encoded, content="9007199254740993")
  let decoded : SupervisorEpochMsV1 = @json.from_json(encoded)
  assert_eq(decoded.value(), exact)
}

///|
test "MoonBook outcome projection keeps exact integer timestamp shape" {
  let digest = "sha256:" + "b".repeat(64)
  let projection_json : Json = {
    "contract_version": "moonbook.bookkeeper.product_outcome_submission.v1",
    "submission": {
      "record_id": "submission-1",
      "record_version": "1",
      "record_digest": digest,
    },
    "source_product": "moonclaw",
    "deliverable_title": "Verified worker result",
    "deliverable_summary": "Bounded evidence is ready for review.",
    "outcome_summary": "The worker produced reviewable evidence.",
    "owner_route": "town/supervisor-1",
    "evidence_refs": [
      {
        "reference_id": "artifacts/supervisor-1/task-1/result.json",
        "reference_version": "1",
        "digest": digest,
        "provenance_ref": "supervisor:supervisor-1:worker-1",
      },
    ],
    "decision_evidence_id": "artifacts/supervisor-1/task-1/result.json",
    "observed_at": 1700000000,
    "recorded_at": 1700000001,
    "information_gap": {
      "present": false,
      "severity": 0,
      "summary": "No known information gap.",
      "evidence_refs": ["artifacts/supervisor-1/task-1/result.json"],
    },
    "recognition_gap": {
      "present": false,
      "severity": 0,
      "summary": "No known recognition gap.",
      "evidence_refs": ["artifacts/supervisor-1/task-1/result.json"],
    },
    "decisiveness_gap": {
      "present": false,
      "severity": 0,
      "summary": "No known decisiveness gap.",
      "evidence_refs": ["artifacts/supervisor-1/task-1/result.json"],
    },
    "capability_id": "supervisor-worker",
    "capability_version": "1",
    "capability_change_digest": digest,
    "capability_summary": "Prepared exact evidence without acceptance.",
  }
  let projection : SupervisorBookkeeperOutcomeEvidenceV1 = @json.from_json(
    projection_json,
  )
  assert_true(validate_outcome_evidence(projection) is Ok(_))
  assert_eq(projection.to_json(), projection_json)
}

///|
test "verified artifact-bound outcome candidate becomes reviewable evidence" {
  let candidate = supervisor_worker_test_outcome_candidate()
  let artifact : Json = {
    "artifact_ref": candidate.evidence_refs[0].reference_id,
    "digest": candidate.evidence_refs[0].digest,
  }
  let result : Json = {
    "summary": "done",
    "artifact_evidence": [artifact],
    "outcome_evidence_candidate": candidate,
  }
  match supervisor_worker_outcome_candidate(result.stringify(), [artifact]) {
    Ok(Some(decoded)) => assert_eq(decoded, candidate)
    _ => fail("expected exact artifact-bound review candidate")
  }
}

///|
test "provider artifact evidence accepts the prompted sha256 field and normalizes it" {
  let raw : Json = {
    "summary": "done",
    "artifact_evidence": [
      {
        "artifact_ref": "books/coding/artifacts/onboarding.md",
        "sha256": "7bad34f8a1aedddbf9d863cacacad4810f8166937aa0d426edb816ae439a98cb",
      },
    ],
  }
  match supervisor_worker_artifact_evidence(raw.stringify()) {
    Ok((refs, [Object(fields)])) => {
      assert_eq(refs, ["books/coding/artifacts/onboarding.md"])
      assert_eq(
        fields["digest"],
        Json::string(
          "sha256:7bad34f8a1aedddbf9d863cacacad4810f8166937aa0d426edb816ae439a98cb",
        ),
      )
    }
    _ => fail("expected normalized sha256 artifact evidence")
  }
}

///|
test "MoonBook outcome validation rejects incompatible evidence and gaps" {
  let candidate = supervisor_worker_test_outcome_candidate()
  let evidence = candidate.evidence_refs[0]
  assert_true(
    validate_outcome_evidence({
      ..candidate,
      information_gap: { ..candidate.information_gap, severity: 1 },
    })
    is Err(_),
  )
  assert_true(
    validate_outcome_evidence({
      ..candidate,
      recognition_gap: {
        ..candidate.recognition_gap,
        present: true,
        severity: 0,
      },
    })
    is Err(_),
  )
  assert_true(
    validate_outcome_evidence({
      ..candidate,
      decisiveness_gap: {
        ..candidate.decisiveness_gap,
        evidence_refs: [evidence.reference_id, evidence.reference_id],
      },
    })
    is Err(_),
  )
  assert_true(
    validate_outcome_evidence({
      ..candidate,
      information_gap: { ..candidate.information_gap, summary: "" },
    })
    is Err(_),
  )
  assert_true(
    validate_outcome_evidence({
      ..candidate,
      information_gap: {
        ..candidate.information_gap,
        evidence_refs: ["artifacts/outside-submission.json"],
      },
    })
    is Err(_),
  )
  assert_true(
    validate_outcome_evidence({
      ..candidate,
      evidence_refs: [evidence, evidence],
    })
    is Err(_),
  )
  assert_true(
    validate_outcome_evidence({
      ..candidate,
      evidence_refs: [{ ..evidence, reference_version: "" }],
    })
    is Err(_),
  )
  assert_true(
    validate_outcome_evidence({
      ..candidate,
      evidence_refs: [{ ..evidence, provenance_ref: "" }],
    })
    is Err(_),
  )
  assert_true(
    validate_outcome_evidence({
      ..candidate,
      evidence_refs: [{ ..evidence, digest: "sha256:not-canonical" }],
    })
    is Err(_),
  )
  assert_true(
    validate_outcome_evidence({
      ..candidate,
      submission: { ..candidate.submission, record_id: "" },
    })
    is Err(_),
  )
  assert_true(
    validate_outcome_evidence({
      ..candidate,
      submission: { ..candidate.submission, record_version: "" },
    })
    is Err(_),
  )
  assert_true(
    validate_outcome_evidence({
      ..candidate,
      submission: {
        ..candidate.submission,
        record_digest: "sha256:not-canonical",
      },
    })
    is Err(_),
  )
  assert_true(
    validate_outcome_evidence({ ..candidate, capability_id: "" }) is Err(_),
  )
  assert_true(
    validate_outcome_evidence({ ..candidate, capability_version: "" }) is Err(_),
  )
  assert_true(
    validate_outcome_evidence({ ..candidate, capability_summary: "" }) is Err(_),
  )
  assert_true(
    validate_outcome_evidence({
      ..candidate,
      capability_change_digest: "sha256:not-canonical",
    })
    is Err(_),
  )
}

///|
test "invalid MoonBook candidate stays omitted and evidence-required" {
  let candidate = supervisor_worker_test_outcome_candidate()
  let artifact : Json = {
    "artifact_ref": candidate.evidence_refs[0].reference_id,
    "digest": candidate.evidence_refs[0].digest,
  }
  let invalid = {
    ..candidate,
    information_gap: { ..candidate.information_gap, severity: 1 },
  }
  let result : Json = {
    "summary": "done",
    "artifact_evidence": [artifact],
    "outcome_evidence_candidate": invalid,
  }
  let retained = match
    supervisor_worker_outcome_candidate(result.stringify(), [artifact]) {
    Ok(value) => value
    Err(_) => None
  }
  assert_true(retained is None)
  let status = if retained is Some(_) {
    "review_ready"
  } else {
    "outcome_evidence_required"
  }
  assert_eq(status, "outcome_evidence_required")
}

///|
test "worker control digests include exact persisted child identity" {
  let payload = supervisor_worker_steer_payload_v1(
    "supervisor-1",
    "worker-run-1",
    "Focus on the failing test.",
    { "source": "human" },
  )
  assert_eq(
    payload,
    (
      {
        "instruction": "Focus on the failing test.",
        "metadata": { "source": "human" },
        "supervisor_id": "supervisor-1",
        "worker_run_id": "worker-run-1",
      } : Json),
  )
}
