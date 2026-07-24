///|
fn goal_comparison_fixture(
  summary? : String = "alpha beta gamma delta",
  checkpoint? : Int = 7,
  artifact_digest? : String = "artifact",
  verification_passed? : Bool = true,
  requirements? : Array[GoalRunRequirementResult] = [
    { id: "r1", passed: true },
    { id: "r2", passed: false },
  ],
) -> GoalRunResult {
  {
    runner: "runner",
    checkpoint,
    completed: true,
    verification_passed,
    requirements,
    artifact_digest,
    summary,
  }
}

///|
test "equivalent ignores ASCII case punctuation and requirement order" {
  let reference = goal_comparison_fixture(summary="Ship, ALPHA! beta.")
  let candidate = goal_comparison_fixture(summary="ship alpha beta", requirements=[
    { id: "r2", passed: false },
    { id: "r1", passed: true },
  ])
  let comparison = goal_comparison_compare(reference, candidate, 7000)
  assert_true(comparison.verdict == Equivalent)
  assert_true(comparison.exact_invariants_match)
  assert_eq(comparison.lexical_similarity_bps, 10000)
  assert_eq(comparison.mismatches.length(), 0)
}

///|
test "similar preserves exact invariants at unique-token Dice 7500" {
  let comparison = goal_comparison_compare(
    goal_comparison_fixture(summary="alpha beta gamma"),
    goal_comparison_fixture(summary="alpha beta gamma delta epsilon"),
    7000,
  )
  assert_true(comparison.verdict == Similar)
  assert_true(comparison.exact_invariants_match)
  assert_eq(comparison.lexical_similarity_bps, 7500)
  assert_true(comparison.mismatches == ["summary.mismatch"])
}

///|
test "diverged reports deterministic artifact and verification mismatches" {
  let comparison = goal_comparison_compare(
    goal_comparison_fixture(),
    goal_comparison_fixture(
      artifact_digest="other-artifact",
      verification_passed=false,
    ),
    7000,
  )
  assert_true(comparison.verdict == Diverged)
  assert_true(!comparison.exact_invariants_match)
  assert_eq(comparison.lexical_similarity_bps, 10000)
  assert_true(
    comparison.mismatches ==
    ["verification.mismatch", "artifact_digest.mismatch"],
  )
}

///|
test "insufficient mismatch codes are ordered for threshold reference and checkpoint" {
  let comparison = goal_comparison_compare(
    goal_comparison_fixture(summary=" "),
    goal_comparison_fixture(checkpoint=8),
    10001,
  )
  assert_true(comparison.verdict == Insufficient)
  assert_true(
    comparison.mismatches ==
    ["threshold.invalid", "reference.invalid", "checkpoint.mismatch"],
  )
}

///|
test "duplicate requirement ID makes candidate invalid" {
  let comparison = goal_comparison_compare(
    goal_comparison_fixture(),
    goal_comparison_fixture(requirements=[
      { id: "r1", passed: true },
      { id: "r1", passed: false },
    ]),
    7000,
  )
  assert_true(comparison.verdict == Insufficient)
  assert_true(comparison.mismatches == ["candidate.invalid"])
}

///|
test "trend over equivalent and similar is stable with average 8750" {
  let equivalent = goal_comparison_compare(
    goal_comparison_fixture(summary="alpha beta gamma"),
    goal_comparison_fixture(summary="ALPHA, beta gamma!"),
    7000,
  )
  let similar = goal_comparison_compare(
    goal_comparison_fixture(summary="alpha beta gamma"),
    goal_comparison_fixture(summary="alpha beta gamma delta epsilon"),
    7000,
  )
  let trend = goal_comparison_trend([equivalent, similar])
  assert_true(trend.stable)
  assert_eq(trend.sample_count, 2)
  assert_eq(trend.equivalent_count, 1)
  assert_eq(trend.similar_count, 1)
  assert_eq(trend.diverged_count, 0)
  assert_eq(trend.insufficient_count, 0)
  assert_eq(trend.average_similarity_bps, 8750)
}

///|
test "trend with diverged and insufficient is unstable and counts exactly" {
  let diverged = goal_comparison_compare(
    goal_comparison_fixture(),
    goal_comparison_fixture(artifact_digest="other"),
    7000,
  )
  let insufficient = goal_comparison_compare(
    goal_comparison_fixture(),
    goal_comparison_fixture(),
    -1,
  )
  let trend = goal_comparison_trend([diverged, insufficient])
  assert_true(!trend.stable)
  assert_eq(trend.sample_count, 2)
  assert_eq(trend.equivalent_count, 0)
  assert_eq(trend.similar_count, 0)
  assert_eq(trend.diverged_count, 1)
  assert_eq(trend.insufficient_count, 1)
}
