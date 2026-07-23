///|
fn complete_requested_projection_json(
  revision : Json,
  workspace_digest : Json,
  evaluation_basis_revision : Json,
  pending_approvals : Json,
  command_evidence_complete_and_passing : Json,
) -> Json {
  {
    "revision": revision,
    "evaluation_basis_revision": evaluation_basis_revision,
    "journal_digest": "journal-digest",
    "workspace_digest": workspace_digest,
    "evaluation_digest": "evaluation-digest",
    "pending_approvals": pending_approvals,
    "active_or_retryable_commands": false,
    "open_claims": false,
    "command_evidence_complete_and_passing": command_evidence_complete_and_passing,
    "mutations_have_later_passing_checks": true,
  }
}

///|
fn complete_requested_json(projection : Json) -> Json {
  {
    "schema_version": 1,
    "kind": "mooncode.goal.complete-requested.v1",
    "event_id": "complete-requested",
    "recorded_at": 100,
    "payload": { "proof": { "projection": projection } },
  }
}

///|
test "Resume encode decode equality and strict payload rejection" {
  let event = Resume("resume", 99)
  assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
  let invalid : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.resumed.v1",
    "event_id": "resume",
    "recorded_at": 99,
    "payload": { "extra": true },
  }
  assert_true(decode_goal_event_v1(invalid) is Err(_))
}

///|
test "CompleteRequested encode decode equality including padded digest" {
  let proof : CompletionProof = {
    projection: {
      revision: 9,
      evaluation_basis_revision: 8,
      journal_digest: "journal-digest",
      workspace_digest: "workspace-digest=",
      evaluation_digest: "evaluation-digest",
      pending_approvals: false,
      active_or_retryable_commands: false,
      open_claims: false,
      command_evidence_complete_and_passing: true,
      mutations_have_later_passing_checks: true,
    },
  }
  let event = CompleteRequested("complete-requested", 100, proof)
  assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
}

///|
test "CompleteRequested strict rejection fixtures" {
  let valid = complete_requested_projection_json(
    9, "workspace-digest", 8, false, true,
  )
  let invalid : Array[Json] = [
    {
      "schema_version": 1,
      "kind": "mooncode.goal.complete-requested.v1",
      "event_id": "complete-requested",
      "recorded_at": 100,
      "payload": { "proof": { "projection": valid, "extra": true } },
    },
    complete_requested_json({
      "revision": 9,
      "evaluation_basis_revision": 8,
      "journal_digest": "journal-digest",
      "workspace_digest": "workspace-digest",
      "evaluation_digest": "evaluation-digest",
      "pending_approvals": false,
      "active_or_retryable_commands": false,
      "open_claims": false,
      "command_evidence_complete_and_passing": true,
    }),
    complete_requested_json({
      "revision": 9,
      "evaluation_basis_revision": 8,
      "journal_digest": "journal-digest",
      "workspace_digest": "workspace-digest",
      "evaluation_digest": "evaluation-digest",
      "pending_approvals": false,
      "active_or_retryable_commands": false,
      "open_claims": false,
      "command_evidence_complete_and_passing": true,
      "mutations_have_later_passing_checks": true,
      "extra": true,
    }),
    complete_requested_json(
      complete_requested_projection_json(-1, "workspace-digest", 8, false, true),
    ),
    complete_requested_json(
      complete_requested_projection_json(
        9, "workspace-digest", 8.5, false, true,
      ),
    ),
    complete_requested_json(
      complete_requested_projection_json(9, "   ", 8, false, true),
    ),
    complete_requested_json(
      complete_requested_projection_json(
        9, "workspace-digest", 8, "false", true,
      ),
    ),
    complete_requested_json(
      complete_requested_projection_json(9, "workspace-digest", 8, false, 1),
    ),
  ]
  for json in invalid {
    assert_true(decode_goal_event_v1(json) is Err(_))
  }
}

///|
test "Evaluated all convergence outcomes encode decode equality" {
  let reports : Array[ConvergenceReport] = [
    {
      evaluation_id: "evaluation-converged",
      evaluated_revision: 0,
      outcome: Converged,
      requirement_deltas: [],
      residual_risks: [],
      evidence_digest: "digest-converged",
    },
    {
      evaluation_id: "evaluation-disagreed",
      evaluated_revision: 7,
      outcome: Disagreed,
      requirement_deltas: ["requirement-1 changed", "requirement-2 changed"],
      residual_risks: ["risk-1", "risk-2"],
      evidence_digest: "digest-disagreed",
    },
    {
      evaluation_id: "evaluation-insufficient",
      evaluated_revision: 12,
      outcome: InsufficientEvidence,
      requirement_deltas: ["requirement-3 unresolved"],
      residual_risks: ["risk-3"],
      evidence_digest: "digest-insufficient",
    },
  ]
  for report in reports {
    let event = Evaluated(
      "event-evaluated",
      100,
      report.evaluation_id,
      report.evaluated_revision,
      report.evidence_digest,
      report,
    )
    assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
  }
}

///|
test "Evaluated codec preserves differing outer and report identifiers" {
  let report : ConvergenceReport = {
    evaluation_id: "report-evaluation",
    evaluated_revision: 19,
    outcome: Converged,
    requirement_deltas: ["report delta"],
    residual_risks: [],
    evidence_digest: "report-digest",
  }
  let event = Evaluated(
    "event-mismatch", 103, "outer-evaluation", 18, "outer-digest", report,
  )
  assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
}

///|
test "Evaluated strict rejection fixtures" {
  let reports : Array[Json] = [
    {
      "evaluation_id": "evaluation-1",
      "evaluated_revision": 1,
      "outcome": "converged",
      "requirement_deltas": [],
      "residual_risks": [],
      "evidence_digest": "digest-1",
      "extra": true,
    },
    {
      "evaluation_id": "evaluation-2",
      "evaluated_revision": 2,
      "outcome": "unknown",
      "requirement_deltas": [],
      "residual_risks": [],
      "evidence_digest": "digest-2",
    },
    {
      "evaluation_id": "evaluation-3",
      "evaluated_revision": 3,
      "outcome": "disagreed",
      "requirement_deltas": ["delta", 3],
      "residual_risks": [],
      "evidence_digest": "digest-3",
    },
    {
      "evaluation_id": "evaluation-4",
      "evaluated_revision": -1,
      "outcome": "insufficient_evidence",
      "requirement_deltas": [],
      "residual_risks": ["risk"],
      "evidence_digest": "digest-4",
    },
    {
      "evaluation_id": "evaluation-5",
      "evaluated_revision": 5,
      "outcome": "converged",
      "requirement_deltas": [],
      "residual_risks": [],
      "evidence_digest": "   ",
    },
  ]
  for report in reports {
    let json : Json = {
      "schema_version": 1,
      "kind": "mooncode.goal.evaluated.v1",
      "event_id": "evaluated-invalid",
      "recorded_at": 110,
      "payload": {
        "evaluation_id": "outer-evaluation",
        "evaluated_revision": 1,
        "evidence_digest": "outer-digest",
        "report": report,
      },
    }
    assert_true(decode_goal_event_v1(json) is Err(_))
  }
}

///|
test "BudgetUsageRecorded zero and nonzero values encode decode equality" {
  for
    event in [
      BudgetUsageRecorded("budget-usage-zero", 50, 0, 0, 0),
      BudgetUsageRecorded("budget-usage-nonzero", 51, 10, 20, 30),
    ] {
    assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
  }
}

///|
test "BudgetExhausted encode decode equality" {
  let event = BudgetExhausted("budget-exhausted", 52)
  assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
}

///|
test "BudgetExtended all None encode decode equality" {
  let event = BudgetExtended("budget-extended-none", 53, None, None, None)
  assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
}

///|
test "BudgetExtended mixed limits encode decode equality" {
  let event = BudgetExtended(
    "budget-extended-mixed",
    54,
    Some(10),
    None,
    Some(30),
  )
  assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
}

///|
test "BudgetExhausted rejects extra payload key" {
  let json : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.budget-exhausted.v1",
    "event_id": "budget-exhausted",
    "recorded_at": 55,
    "payload": { "extra": true },
  }
  assert_true(decode_goal_event_v1(json) is Err(_))
}

///|
test "BudgetUsageRecorded rejects negative tokens_used" {
  let json : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.budget-usage-recorded.v1",
    "event_id": "budget-usage",
    "recorded_at": 56,
    "payload": { "tokens_used": -1, "turns_used": 0, "wall_time_used": 0 },
  }
  assert_true(decode_goal_event_v1(json) is Err(_))
}

///|
test "BudgetExtended rejects fractional token_limit" {
  let json : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.budget-extended.v1",
    "event_id": "budget-extended",
    "recorded_at": 57,
    "payload": {
      "token_limit": 10.5,
      "turn_limit": null,
      "wall_time_limit": null,
    },
  }
  assert_true(decode_goal_event_v1(json) is Err(_))
}

///|
test "BudgetExtended rejects negative turn_limit" {
  let json : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.budget-extended.v1",
    "event_id": "budget-extended",
    "recorded_at": 58,
    "payload": {
      "token_limit": null,
      "turn_limit": -1,
      "wall_time_limit": null,
    },
  }
  assert_true(decode_goal_event_v1(json) is Err(_))
}

///|
test "BudgetExtended rejects string wall_time_limit" {
  let json : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.budget-extended.v1",
    "event_id": "budget-extended",
    "recorded_at": 59,
    "payload": {
      "token_limit": null,
      "turn_limit": null,
      "wall_time_limit": "30",
    },
  }
  assert_true(decode_goal_event_v1(json) is Err(_))
}

///|
test "goal event codec schema version is stable" {
  inspect(goal_event_codec_schema_version, content="1")
}

///|
test "RequirementUpdated all states encode decode equality" {
  for state in [Unproven, Proven, Contradicted] {
    let event = RequirementUpdated("event-r", 41, "requirement-1", state, [
      " evidence preserved ", "evidence-2",
    ])
    assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
  }
}

///|
test "RequirementUpdated decodes contested as Contradicted" {
  let json : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.requirement-updated.v1",
    "event_id": "event-r",
    "recorded_at": 41,
    "payload": {
      "requirement_id": "requirement-1",
      "state": "contested",
      "evidence_refs": [" evidence preserved "],
    },
  }
  assert_true(
    goal_event_from_json(json) ==
    RequirementUpdated("event-r", 41, "requirement-1", Contradicted, [
      " evidence preserved ",
    ]),
  )
}

///|
test "RequirementUpdated rejects extra payload key" {
  let json : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.requirement-updated.v1",
    "event_id": "event-r",
    "recorded_at": 41,
    "payload": {
      "requirement_id": "requirement-1",
      "state": "proven",
      "evidence_refs": [],
      "extra": true,
    },
  }
  assert_true(decode_goal_event_v1(json) is Err(_))
}

///|
test "RequirementUpdated rejects invalid state" {
  let json : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.requirement-updated.v1",
    "event_id": "event-r",
    "recorded_at": 41,
    "payload": {
      "requirement_id": "requirement-1",
      "state": "contradicted",
      "evidence_refs": [],
    },
  }
  assert_true(decode_goal_event_v1(json) is Err(_))
}

///|
test "RequirementUpdated rejects mixed evidence array" {
  let json : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.requirement-updated.v1",
    "event_id": "event-r",
    "recorded_at": 41,
    "payload": {
      "requirement_id": "requirement-1",
      "state": "unproven",
      "evidence_refs": ["evidence-1", 2],
    },
  }
  assert_true(decode_goal_event_v1(json) is Err(_))
}

///|
test "AwaitingApproval empty refs encode decode equality" {
  let event : GoalEvent = GoalEvent::AwaitingApproval("event-a0", 45, [])
  assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
}

///|
test "AwaitingApproval multiple refs encode decode equality" {
  let event = GoalEvent::AwaitingApproval("event-a1", 46, [
    "approval-1", "approval-2",
  ])
  assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
}

///|
test "ApprovalSettled Approved encode decode equality" {
  let event = ApprovalSettled("event-s1", 47, ["approval-1"], Approved)
  assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
}

///|
test "ApprovalSettled Rejected encode decode equality" {
  let event = ApprovalSettled(
    "event-s2",
    48,
    ["approval-1", "approval-2"],
    Rejected,
  )
  assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
}

///|
test "AwaitingApproval rejects mixed refs" {
  let json : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.awaiting-approval.v1",
    "event_id": "event-a",
    "recorded_at": 49,
    "payload": { "approval_refs": ["approval-1", 2] },
  }
  assert_true(decode_goal_event_v1(json) is Err(_))
}

///|
test "ApprovalSettled rejects extra payload field" {
  let json : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.approval-settled.v1",
    "event_id": "event-s",
    "recorded_at": 50,
    "payload": {
      "approval_refs": ["approval-1"],
      "outcome": "approved",
      "extra": true,
    },
  }
  assert_true(decode_goal_event_v1(json) is Err(_))
}

///|
test "ApprovalSettled rejects invalid outcome" {
  let json : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.approval-settled.v1",
    "event_id": "event-s",
    "recorded_at": 51,
    "payload": { "approval_refs": ["approval-1"], "outcome": "pending" },
  }
  assert_true(decode_goal_event_v1(json) is Err(_))
}

///|
test "ContinuationAccepted encode decode equality" {
  let event = ContinuationAccepted("event-1", 42, 3, 1)
  let decoded = goal_event_from_json(goal_event_to_json(event))
  assert_true(decoded == event)
}

///|
test "goal event envelope strict mutation fixtures" {
  let fixtures : Array[(Json, String)] = [
    (
      {
        "schema_version": 2,
        "kind": "mooncode.goal.continuation-accepted.v1",
        "event_id": "continuation-accepted",
        "recorded_at": 100,
        "payload": { "run_id": 1, "continuation_count": 2 },
      },
      "unsupported schema_version",
    ),
    (
      {
        "schema_version": 1.5,
        "kind": "mooncode.goal.continuation-accepted.v1",
        "event_id": "continuation-accepted",
        "recorded_at": 100,
        "payload": { "run_id": 1, "continuation_count": 2 },
      },
      "invalid schema_version",
    ),
    (
      {
        "schema_version": 1,
        "kind": "mooncode.goal.unknown.v1",
        "event_id": "continuation-accepted",
        "recorded_at": 100,
        "payload": { "run_id": 1, "continuation_count": 2 },
      },
      "unsupported goal event kind",
    ),
    (
      {
        "schema_version": 1,
        "kind": "mooncode.goal.continuation-accepted.v1",
        "event_id": "",
        "recorded_at": 100,
        "payload": { "run_id": 1, "continuation_count": 2 },
      },
      "invalid event_id",
    ),
    (
      {
        "schema_version": 1,
        "kind": "mooncode.goal.continuation-accepted.v1",
        "event_id": " padded ",
        "recorded_at": 100,
        "payload": { "run_id": 1, "continuation_count": 2 },
      },
      "invalid event_id",
    ),
    (
      {
        "schema_version": 1,
        "kind": "mooncode.goal.continuation-accepted.v1",
        "event_id": "continuation-accepted",
        "recorded_at": -1,
        "payload": { "run_id": 1, "continuation_count": 2 },
      },
      "invalid recorded_at",
    ),
    (
      {
        "schema_version": 1,
        "kind": "mooncode.goal.continuation-accepted.v1",
        "event_id": "continuation-accepted",
        "recorded_at": 1.5,
        "payload": { "run_id": 1, "continuation_count": 2 },
      },
      "invalid recorded_at",
    ),
    (
      {
        "schema_version": 1,
        "kind": "mooncode.goal.continuation-accepted.v1",
        "event_id": "continuation-accepted",
        "recorded_at": 100,
      },
      "invalid envelope fields",
    ),
    (
      {
        "schema_version": 1,
        "kind": "mooncode.goal.continuation-accepted.v1",
        "event_id": "continuation-accepted",
        "recorded_at": 100,
        "payload": "not-an-object",
      },
      "payload must be an object",
    ),
    (
      {
        "schema_version": 1,
        "kind": "mooncode.goal.continuation-accepted.v1",
        "event_id": "continuation-accepted",
        "recorded_at": 100,
        "unknown": { "run_id": 1, "continuation_count": 2 },
      },
      "invalid envelope fields",
    ),
  ]
  for fixture in fixtures {
    match decode_goal_event_v1(fixture.0) {
      Err(message) => assert_eq(message, fixture.1)
      Ok(_) => fail("expected envelope fixture rejection")
    }
  }
}

///|
test "CompleteRequested same-cardinality projection substitution" {
  let fixture = complete_requested_json({
    "revision": 9,
    "evaluation_basis_revision": 8,
    "journal_digest": "journal-digest",
    "unknown_workspace": "workspace-digest",
    "evaluation_digest": "evaluation-digest",
    "pending_approvals": false,
    "active_or_retryable_commands": false,
    "open_claims": false,
    "command_evidence_complete_and_passing": true,
    "mutations_have_later_passing_checks": true,
  })
  match decode_goal_event_v1(fixture) {
    Err(message) => assert_eq(message, "invalid projection fields")
    Ok(_) => fail("expected projection fixture rejection")
  }
}

///|
test "ContinuationAccepted rejects extra envelope key" {
  let json : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.continuation-accepted.v1",
    "event_id": "event-1",
    "recorded_at": 42,
    "payload": { "run_id": 3, "continuation_count": 3 },
    "extra": true,
  }
  assert_true(decode_goal_event_v1(json) is Err(_))
}

///|
test "ContinuationAccepted rejects fractional integer" {
  let json : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.continuation-accepted.v1",
    "event_id": "event-1",
    "recorded_at": 42,
    "payload": { "run_id": 3, "continuation_count": 3.5 },
  }
  assert_true(decode_goal_event_v1(json) is Err(_))
}

///|
test "TurnFinished None encode decode equality" {
  let event = TurnFinished("event-2", 43, 3, 2, None, true)
  assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
}

///|
test "TurnFinished Some blocker encode decode equality" {
  let blocker : BlockerIdentity = {
    kind: "permission",
    authority: "user",
    resource: "repo",
    required_change: "approve",
  }
  let event = TurnFinished("event-3", 44, 3, 3, Some(blocker), false)
  assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
}

///|
test "TurnFinished rejects extra blocker key" {
  let json : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.turn-finished.v1",
    "event_id": "event-4",
    "recorded_at": 45,
    "payload": {
      "run_id": 3,
      "turn": 4,
      "blocker": {
        "kind": "permission",
        "authority": "user",
        "resource": "repo",
        "required_change": "approve",
        "extra": true,
      },
      "made_progress": false,
    },
  }
  assert_true(decode_goal_event_v1(json) is Err(_))
}

///|
test "EvaluationStarted encode decode equality" {
  let event = EvaluationStarted(
    "evaluation-started", 60, "evaluation-1", "digest-1",
  )
  assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
}

///|
test "EvaluationRetryDue encode decode equality" {
  let event = EvaluationRetryDue(
    "evaluation-retry-due", 61, "evaluation-2", 3, 2,
  )
  assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
}

///|
test "EvaluationStarted strict rejection fixtures" {
  let extra : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.evaluation-started.v1",
    "event_id": "event",
    "recorded_at": 62,
    "payload": {
      "evaluation_id": "evaluation-1",
      "evidence_digest": "digest",
      "extra": true,
    },
  }
  let padded : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.evaluation-started.v1",
    "event_id": "event",
    "recorded_at": 62,
    "payload": {
      "evaluation_id": " evaluation-1 ",
      "evidence_digest": "digest",
    },
  }
  let blank : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.evaluation-started.v1",
    "event_id": "event",
    "recorded_at": 62,
    "payload": { "evaluation_id": "evaluation-1", "evidence_digest": "" },
  }
  assert_true(decode_goal_event_v1(extra) is Err(_))
  assert_true(decode_goal_event_v1(padded) is Err(_))
  assert_true(decode_goal_event_v1(blank) is Err(_))
}

///|
test "EvaluationFailed encode decode equality" {
  let event = EvaluationFailed(
    "evaluation-failed", 64, "evaluation-3", 3, 7, "digest-3", 2, "transient", 100,
  )
  assert_true(goal_event_from_json(goal_event_to_json(event)) == event)
}

///|
test "EvaluationFailed strict rejection fixtures" {
  let extra_payload_key : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.evaluation-failed.v1",
    "event_id": "evaluation-failed",
    "recorded_at": 64,
    "payload": {
      "evaluation_id": "evaluation-3",
      "run_id": 3,
      "basis_revision": 7,
      "evidence_digest": "digest-3",
      "attempt": 2,
      "category": "transient",
      "next_retry_at": 100,
      "extra": true,
    },
  }
  let blank_category : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.evaluation-failed.v1",
    "event_id": "evaluation-failed",
    "recorded_at": 64,
    "payload": {
      "evaluation_id": "evaluation-3",
      "run_id": 3,
      "basis_revision": 7,
      "evidence_digest": "digest-3",
      "attempt": 2,
      "category": "   ",
      "next_retry_at": 100,
    },
  }
  let padded_category : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.evaluation-failed.v1",
    "event_id": "evaluation-failed",
    "recorded_at": 64,
    "payload": {
      "evaluation_id": "evaluation-3",
      "run_id": 3,
      "basis_revision": 7,
      "evidence_digest": "digest-3",
      "attempt": 2,
      "category": " transient ",
      "next_retry_at": 100,
    },
  }
  let negative_basis_revision : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.evaluation-failed.v1",
    "event_id": "evaluation-failed",
    "recorded_at": 64,
    "payload": {
      "evaluation_id": "evaluation-3",
      "run_id": 3,
      "basis_revision": -1,
      "evidence_digest": "digest-3",
      "attempt": 2,
      "category": "transient",
      "next_retry_at": 100,
    },
  }
  let fractional_attempt : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.evaluation-failed.v1",
    "event_id": "evaluation-failed",
    "recorded_at": 64,
    "payload": {
      "evaluation_id": "evaluation-3",
      "run_id": 3,
      "basis_revision": 7,
      "evidence_digest": "digest-3",
      "attempt": 2.5,
      "category": "transient",
      "next_retry_at": 100,
    },
  }
  let string_next_retry_at : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.evaluation-failed.v1",
    "event_id": "evaluation-failed",
    "recorded_at": 64,
    "payload": {
      "evaluation_id": "evaluation-3",
      "run_id": 3,
      "basis_revision": 7,
      "evidence_digest": "digest-3",
      "attempt": 2,
      "category": "transient",
      "next_retry_at": "100",
    },
  }
  for
    json in [
      extra_payload_key, blank_category, padded_category, negative_basis_revision,
      fractional_attempt, string_next_retry_at,
    ] {
    assert_true(decode_goal_event_v1(json) is Err(_))
  }
}

///|
test "EvaluationRetryDue strict rejection fixtures" {
  let negative : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.evaluation-retry-due.v1",
    "event_id": "event",
    "recorded_at": 63,
    "payload": { "evaluation_id": "evaluation-2", "run_id": -1, "attempt": 2 },
  }
  let fractional : Json = {
    "schema_version": 1,
    "kind": "mooncode.goal.evaluation-retry-due.v1",
    "event_id": "event",
    "recorded_at": 63,
    "payload": { "evaluation_id": "evaluation-2", "run_id": 3, "attempt": 2.5 },
  }
  assert_true(decode_goal_event_v1(negative) is Err(_))
  assert_true(decode_goal_event_v1(fractional) is Err(_))
}
