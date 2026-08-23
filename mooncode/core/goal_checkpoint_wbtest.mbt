///|
fn checkpoint(
  producer : String,
  id : String,
  epoch : Int,
  key : String,
  source : String,
) -> GoalCheckpointSnapshot {
  let basis : ComparisonBasis = {
    version: 2,
    basis_digest: "basis-v2",
    policy_digest: "policy-v2",
    comparison_epoch: epoch,
    checkpoint_key: key,
    required_requirements: [{ requirement_id: "r1", spec_digest: "rs1" }],
    required_outputs: [{ output_id: "o1", spec_digest: "os1" }],
    required_checks: [{ check_id: "test", spec_digest: "cs1" }],
  }
  {
    contract_version: 2,
    producer: {
      producer_id: producer,
      producer_version: "1",
      contract_version: 2,
    },
    identity: {
      checkpoint_id: id,
      comparison_epoch: epoch,
      checkpoint_key: key,
      parent_checkpoint_id: None,
    },
    basis,
    goal_id: "goal",
    objective_digest: "objective",
    base_workspace_digest: "base",
    requirements: [
      {
        requirement_id: "r1",
        spec_digest: "rs1",
        state: Proven,
        evidence_refs: ["req-e"],
      },
    ],
    evidence: [
      {
        evidence_id: "req-e",
        role: "requirement",
        spec_digest: "rs1",
        content_digest: "req-proof",
        evidence_ref: "local://req",
      },
      {
        evidence_id: "out-e",
        role: "output",
        spec_digest: "os1",
        content_digest: "output-proof",
        evidence_ref: "local://out",
      },
      {
        evidence_id: "check-e",
        role: "verification",
        spec_digest: "cs1",
        content_digest: "check-proof",
        evidence_ref: "local://check",
      },
    ],
    outputs: [
      {
        output_id: "o1",
        spec_digest: "os1",
        content_digest: source,
        api_digest: "api",
        artifact_digest: "artifact",
        evidence_refs: ["out-e"],
      },
    ],
    remaining_work: [],
    blockers: [],
    verification: {
      checks: [
        {
          check_id: "test",
          spec_digest: "cs1",
          passed: true,
          result_digest: "pass",
          evidence_refs: ["check-e"],
        },
      ],
    },
    budget: {
      token_limit: None,
      turn_limit: None,
      wall_time_limit: None,
      tokens_used: 1,
      turns_used: 1,
      wall_time_used: 1,
    },
  }
}

///|
test "different checkpoint goals are not the same basis" {
  let left = checkpoint("a", "a", 1, "k", "source")
  let right = { ..checkpoint("b", "b", 1, "k", "source"), goal_id: "other" }
  let report = compare_goal_checkpoints(left, right)
  assert_false(report.same_basis)
  assert_true(report.outcome == InsufficientEvidence)
}

///|
test "blank checkpoint subject is independently insufficient" {
  let valid = checkpoint("a", "a", 1, "k", "source")
  let invalid = {
    ..checkpoint("b", "b", 1, "k", "source"),
    objective_digest: "   ",
  }
  let report = compare_goal_checkpoints(invalid, valid)
  assert_true(report.left_acceptance == InsufficientEvidence)
  assert_true(report.right_acceptance == Accepted)
  assert_true(report.outcome == InsufficientEvidence)
}

///|
test "wrong producer contract is independently insufficient" {
  let valid = checkpoint("a", "a", 1, "k", "source")
  let base = checkpoint("b", "b", 1, "k", "source")
  let invalid = { ..base, producer: { ..base.producer, contract_version: 1 } }
  let report = compare_goal_checkpoints(valid, invalid)
  assert_true(report.left_acceptance == Accepted)
  assert_true(report.right_acceptance == InsufficientEvidence)
  assert_true(report.outcome == InsufficientEvidence)
}

///|
test "empty required basis arrays are insufficient" {
  let valid = checkpoint("a", "a", 1, "k", "source")
  let invalid_basis = {
    ..valid.basis,
    required_requirements: [],
    required_outputs: [],
    required_checks: [],
  }
  let invalid = { ..valid, basis: invalid_basis }
  let report = compare_goal_checkpoints(invalid, invalid)
  assert_false(report.same_basis)
  assert_true(report.left_acceptance == InsufficientEvidence)
  assert_true(report.right_acceptance == InsufficientEvidence)
  assert_true(report.outcome == InsufficientEvidence)
}

///|
test "blank basis digest is insufficient" {
  let valid = checkpoint("a", "a", 1, "k", "source")
  let invalid = { ..valid, basis: { ..valid.basis, basis_digest: "   " } }
  let report = compare_goal_checkpoints(invalid, invalid)
  assert_false(report.same_basis)
  assert_true(report.left_acceptance == InsufficientEvidence)
  assert_true(report.right_acceptance == InsufficientEvidence)
  assert_true(report.outcome == InsufficientEvidence)
}

///|
test "blank basis definition field is insufficient" {
  let valid = checkpoint("a", "a", 1, "k", "source")
  let invalid_basis = {
    ..valid.basis,
    required_checks: [{ check_id: "   ", spec_digest: "cs1" }],
  }
  let invalid = { ..valid, basis: invalid_basis }
  let report = compare_goal_checkpoints(invalid, invalid)
  assert_false(report.same_basis)
  assert_true(report.left_acceptance == InsufficientEvidence)
  assert_true(report.right_acceptance == InsufficientEvidence)
  assert_true(report.outcome == InsufficientEvidence)
}

///|
test "empty manifests cannot converge" {
  let a = checkpoint("a", "a", 1, "k", "source")
  let b = { ..a, requirements: [], outputs: [], verification: { checks: [] } }
  assert_true(compare_goal_checkpoints(a, b).outcome == InsufficientEvidence)
}

///|
test "same incomplete result agrees but fails evaluator acceptance" {
  let a = checkpoint("a", "a", 1, "k", "source")
  let bad = {
    ..a,
    requirements: [
      {
        requirement_id: "r1",
        spec_digest: "rs1",
        state: Unproven,
        evidence_refs: ["req-e"],
      },
    ],
  }
  let report = compare_goal_checkpoints(bad, bad)
  assert_true(report.agreement_outcome == Exact)
  assert_true(report.outcome == InsufficientEvidence)
  assert_true(report.left_acceptance == Rejected)
}

///|
test "contradictory evidence disagrees" {
  let a = checkpoint("a", "a", 1, "k", "source")
  let ev = a.evidence.copy()
  ev[0] = { ..ev[0], content_digest: "contradiction" }
  let b = { ..a, producer: { ..a.producer, producer_id: "b" }, evidence: ev }
  assert_true(compare_goal_checkpoints(a, b).outcome == Disagreed)
}

///|
test "missing output evidence is insufficient" {
  let a = checkpoint("a", "a", 1, "k", "source")
  let b = { ..a, outputs: [{ ..a.outputs[0], evidence_refs: [] }] }
  assert_true(compare_goal_checkpoints(a, b).outcome == InsufficientEvidence)
}

///|
test "producer ids budgets and local evidence ids are ignored" {
  let a = checkpoint("a", "a", 1, "k", "source")
  let b0 = checkpoint("b", "b", 1, "k", "source")
  let b = {
    ..b0,
    evidence: [
      { ..b0.evidence[0], evidence_id: "x" },
      { ..b0.evidence[1], evidence_id: "y" },
      { ..b0.evidence[2], evidence_id: "z" },
    ],
    requirements: [{ ..b0.requirements[0], evidence_refs: ["x"] }],
    outputs: [{ ..b0.outputs[0], evidence_refs: ["y"] }],
    verification: {
      checks: [{ ..b0.verification.checks[0], evidence_refs: ["z"] }],
    },
    budget: { ..b0.budget, tokens_used: 999 },
  }
  assert_true(compare_goal_checkpoints(a, b).outcome == Exact)
}

///|
test "source difference after acceptance is functionally equivalent" {
  let a = checkpoint("a", "a", 1, "k", "source-a")
  let b = checkpoint("b", "b", 1, "k", "source-b")
  assert_true(compare_goal_checkpoints(a, b).outcome == FunctionallyEquivalent)
}

///|
test "duplicate key is insufficient" {
  let a = checkpoint("a", "a", 1, "k", "source")
  let duplicate = { ..a, identity: { ..a.identity, checkpoint_id: "a2" } }
  let reports = compare_goal_checkpoint_sequences([a, duplicate], [a])
  assert_true(reports[0].outcome == InsufficientEvidence)
}

///|
test "mismatched local cadence aligns shared epoch key" {
  let a = checkpoint("a", "a", 7, "shared", "source")
  let unrelated = checkpoint("b", "b0", 6, "local", "source")
  let b = checkpoint("b", "b", 7, "shared", "source")
  let reports = compare_goal_checkpoint_sequences([a], [unrelated, b])
  assert_eq(reports.length(), 2)
  assert_true(reports[0].outcome == InsufficientEvidence)
  assert_eq(reports[0].left_checkpoint_id, "")
  assert_eq(reports[0].right_checkpoint_id, "b0")
  assert_true(reports[1].outcome == Exact)
  assert_eq(reports[1].left_checkpoint_id, "a")
  assert_eq(reports[1].right_checkpoint_id, "b")
}

///|
test "convergence gap then disagreement is regression" {
  let first = checkpoint("a", "a1", 1, "one", "source")
  let gap = checkpoint("a", "a2", 2, "two", "source")
  let last = checkpoint("a", "a3", 3, "three", "source")
  let rfirst = checkpoint("b", "b1", 1, "one", "source")
  let checks = last.verification.checks.copy()
  checks[0] = { ..checks[0], result_digest: "different" }
  let rlast = {
    ..checkpoint("b", "b3", 3, "three", "source"),
    verification: { checks, },
  }
  let reports = compare_goal_checkpoint_sequences([first, gap, last], [
    rfirst, rlast,
  ])
  assert_true(reports[1].outcome == InsufficientEvidence)
  assert_true(reports[2].outcome == Disagreed)
  assert_true(reports[2].regression)
}
