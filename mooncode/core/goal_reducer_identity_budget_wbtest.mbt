///|
test "goal reducer event identity no-op" {
  let goal = test_goal()
  let empty = reduce_goal(
    goal,
    RequirementUpdated("", goal.updated_at, "requirement", Proven, ["proof"]),
  )
  assert_true(empty == goal)
  let padded = reduce_goal(
    goal,
    RequirementUpdated(" padded ", goal.updated_at, "requirement", Proven, [
      "proof",
    ]),
  )
  assert_true(padded == goal)
  let stale = reduce_goal(
    goal,
    RequirementUpdated("normal", goal.updated_at - 1, "requirement", Proven, [
      "proof",
    ]),
  )
  assert_true(stale == goal)
}

///|
test "goal reducer budget exhaustion identity and retry" {
  let goal = test_goal()
  let early = reduce_goal(goal, BudgetExhausted("early", goal.updated_at))
  assert_true(early == goal)
  let limited = { ..goal, budget: { ..goal.budget, token_limit: Some(1) } }
  let used = reduce_goal(
    limited,
    BudgetUsageRecorded("usage", limited.updated_at, 1, 0, 0),
  )
  assert_true(used.run_state == AwaitingBudget)
  let asserted = reduce_goal(used, BudgetExhausted("assert", used.updated_at))
  assert_true(asserted.run_state == AwaitingBudget)
  assert_true(asserted.revision == used.revision + 1)
  let retried = reduce_goal(
    asserted,
    BudgetExhausted("assert", used.updated_at),
  )
  assert_true(retried == asserted)
}
