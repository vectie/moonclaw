///|
fn child_delegation_test_digest(fill : String) -> String {
  "sha256:" + fill.repeat(64)
}

///|
test "child delegation requires an agent and enforces metered ceilings" {
  let parent = @capability.principal_ref_v1(
    "runtime-parent",
    @capability.Service,
    "local",
    "runtime-parent",
  )
  let child = @capability.principal_ref_v1(
    "runtime-child",
    @capability.Agent,
    "local",
    "runtime-child",
  )
  let authority = @capability.authority_decision_ref_v1(
    "authority-child",
    child,
    child_delegation_test_digest("a"),
    "2026-07-31T01:00:00Z",
    "2026-07-31T03:00:00Z",
  )
  let operation = @capability.operation_ref(
    "moonclaw",
    "job.delegate",
    "1.0.0",
  )
  let budget = @capability.handover_budget_ceilings_v1(
    max_cost_micro_usd=1000L,
    max_runtime_ms=60000L,
    max_tokens=2000L,
    max_artifacts=2,
  )
  let delegation = issue_child_delegation_v1(
    "delegation-one",
    "run-parent",
    "run-child",
    parent,
    child,
    [operation],
    ["artifacts/child"],
    Draft,
    budget,
    authority,
    "2026-07-31T01:00:00Z",
    "2026-07-31T02:00:00Z",
  )
  let evidence = @capability.content_addressed_evidence_ref(
    "evidence/usage.json",
    child_delegation_test_digest("b"),
  )
  let within = child_delegation_consumption_v1(
    accumulated_cost_micro_usd=100L,
    requested_cost_micro_usd=200L,
    accumulated_runtime_ms=1000L,
    requested_runtime_ms=2000L,
    accumulated_tokens=100L,
    requested_tokens=200L,
    accumulated_artifacts=0,
    requested_artifacts=1,
    evidence,
  )
  assert_true(
    authorize_child_delegation_use_v1(
      delegation,
      child,
      "run-child",
      operation,
      ["artifacts/child/result.json"],
      Draft,
      within,
      "2026-07-31T01:10:00Z",
    ) is Ok(_),
  )
  let over = child_delegation_consumption_v1(
    accumulated_cost_micro_usd=900L,
    requested_cost_micro_usd=200L,
    accumulated_runtime_ms=1000L,
    requested_runtime_ms=2000L,
    accumulated_tokens=100L,
    requested_tokens=200L,
    accumulated_artifacts=0,
    requested_artifacts=1,
    evidence,
  )
  assert_true(
    authorize_child_delegation_use_v1(
      delegation,
      child,
      "run-child",
      operation,
      ["artifacts/child/result.json"],
      Draft,
      over,
      "2026-07-31T01:10:00Z",
    ) is Err(_),
  )
  let human_child = @capability.principal_ref_v1(
    "human-child",
    @capability.Human,
    "local",
    "human-child",
  )
  let human_authority = @capability.authority_decision_ref_v1(
    "authority-human-child",
    human_child,
    child_delegation_test_digest("c"),
    "2026-07-31T01:00:00Z",
    "2026-07-31T03:00:00Z",
  )
  let human_rejected = try {
    ignore(
      issue_child_delegation_v1(
        "delegation-human",
        "run-parent",
        "run-human",
        parent,
        human_child,
        [operation],
        ["artifacts/human"],
        EvidenceOnly,
        budget,
        human_authority,
        "2026-07-31T01:00:00Z",
        "2026-07-31T02:00:00Z",
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(human_rejected)
}
