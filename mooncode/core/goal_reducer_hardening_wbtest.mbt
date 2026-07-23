///|
test "invalid requirement updates leave goal unchanged" {
  let goal = test_goal()
  for refs in [[""], ["   "], ["proof", "proof"], []] {
    assert_true(
      reduce_goal(
        goal,
        RequirementUpdated(
          "invalid",
          goal.updated_at,
          goal.requirements[0].id,
          Proven,
          refs,
        ),
      ) ==
      goal,
    )
  }
}

///|
test "proven evidence is canonicalized" {
  let goal = test_goal()
  let proven = reduce_goal(
    goal,
    RequirementUpdated(
      "proven",
      goal.updated_at,
      goal.requirements[0].id,
      Proven,
      ["a", "b"],
    ),
  )
  assert_true(proven.requirements[0].state == Proven)
  assert_true(proven.requirements[0].evidence_refs == ["a", "b"])
  let padded = reduce_goal(
    goal,
    RequirementUpdated(
      "padded-proof",
      goal.updated_at,
      goal.requirements[0].id,
      Proven,
      [" padded-proof "],
    ),
  )
  assert_true(padded.requirements[0].state == Proven)
  assert_true(padded.requirements[0].evidence_refs == ["padded-proof"])
}

///|
test "proven requirement can be reset to unproven" {
  let goal = test_goal()
  let proven = reduce_goal(
    goal,
    RequirementUpdated(
      "proven-before-reset",
      goal.updated_at,
      goal.requirements[0].id,
      Proven,
      ["proof"],
    ),
  )
  let reset = reduce_goal(
    proven,
    RequirementUpdated(
      "reset",
      proven.updated_at,
      goal.requirements[0].id,
      Unproven,
      [],
    ),
  )
  assert_true(reset.requirements[0].state == Unproven)
  assert_true(reset.requirements[0].evidence_refs == [])
}

///|
test "unproven update rejects evidence" {
  let goal = test_goal()
  assert_true(
    reduce_goal(
      goal,
      RequirementUpdated(
        "invalid-unproven-evidence",
        goal.updated_at,
        goal.requirements[0].id,
        Unproven,
        ["proof"],
      ),
    ) ==
    goal,
  )
}

///|
test "unknown requirement id leaves goal unchanged" {
  let goal = test_goal()
  assert_true(
    reduce_goal(
      goal,
      RequirementUpdated(
        "unknown-requirement",
        goal.updated_at,
        "missing",
        Proven,
        ["proof"],
      ),
    ) ==
    goal,
  )
}

///|
test "contradicted requirement requires canonical evidence" {
  let goal = test_goal()
  let contradicted = reduce_goal(
    goal,
    RequirementUpdated(
      "contradicted",
      goal.updated_at,
      goal.requirements[0].id,
      Contradicted,
      [" counterexample "],
    ),
  )
  assert_true(contradicted.requirements[0].state == Contradicted)
  assert_true(contradicted.requirements[0].evidence_refs == ["counterexample"])
}
