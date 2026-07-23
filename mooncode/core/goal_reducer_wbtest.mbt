///|
fn test_goal() -> Goal raise {
  new_goal(
    "g",
    "s",
    "ship",
    10,
    {
      token_limit: None,
      turn_limit: None,
      wall_time_limit: None,
      tokens_used: 0,
      turns_used: 0,
      wall_time_used: 0,
    },
    [
      {
        id: "r1",
        criterion: "the artifact ships",
        state: Unproven,
        evidence_refs: [],
      },
    ],
  )
}

///|
fn completion_proof(
  revision : Int,
  basis : Int,
  digest : String,
) -> CompletionProof {
  {
    projection: {
      revision,
      evaluation_basis_revision: basis,
      journal_digest: "journal",
      workspace_digest: "workspace",
      evaluation_digest: digest,
      pending_approvals: false,
      active_or_retryable_commands: false,
      open_claims: false,
      command_evidence_complete_and_passing: true,
      mutations_have_later_passing_checks: true,
    },
  }
}

///|
fn evaluated_goal(outcome : Convergence) -> Goal raise {
  let proven = reduce_goal(
    test_goal(),
    RequirementUpdated("prove", 11, "r1", Proven, ["evidence"]),
  )
  let started = reduce_goal(
    proven,
    EvaluationStarted("start", 12, "evaluation", "digest"),
  )
  reduce_goal(
    started,
    Evaluated("evaluated", 13, "evaluation", proven.revision, "digest", {
      evaluation_id: "evaluation",
      evaluated_revision: proven.revision,
      evidence_digest: "digest",
      outcome,
      requirement_deltas: [],
      residual_risks: [],
    }),
  )
}

///|
test "completion accepts immutable evaluation basis" {
  let goal = evaluated_goal(Converged)
  guard goal.convergence is Some(convergence) else {
    fail("missing convergence")
  }
  assert_eq(convergence.accepted_revision, goal.revision)
  let completed = reduce_goal(
    goal,
    CompleteRequested(
      "complete",
      14,
      completion_proof(
        goal.revision,
        convergence.report.evaluated_revision,
        "digest",
      ),
    ),
  )
  assert_true(completed.status == Complete)
}

///|
test "completion rejects empty evidence" {
  let goal = evaluated_goal(Converged)
  let empty = {
    ..goal,
    requirements: [{ ..goal.requirements[0], evidence_refs: [] }],
  }
  assert_true(
    reduce_goal(
      empty,
      CompleteRequested(
        "complete-empty",
        14,
        completion_proof(
          empty.revision,
          empty.convergence.unwrap().report.evaluated_revision,
          "digest",
        ),
      ),
    ).status !=
    Complete,
  )
}

///|
test "completion rejects disagreement stale basis and accepted mutation" {
  let disagreed = evaluated_goal(Disagreed)
  assert_true(
    reduce_goal(
      disagreed,
      CompleteRequested(
        "complete-disagreed",
        14,
        completion_proof(disagreed.revision, disagreed.revision - 1, "digest"),
      ),
    ).status !=
    Complete,
  )
  let goal = evaluated_goal(Converged)
  assert_true(
    reduce_goal(
      goal,
      CompleteRequested(
        "complete-stale",
        14,
        completion_proof(
          goal.revision,
          goal.convergence.unwrap().report.evaluated_revision - 1,
          "digest",
        ),
      ),
    ).status !=
    Complete,
  )
  let mutated = reduce_goal(
    goal,
    RequirementUpdated("mutation", 15, "r1", Proven, ["new-evidence"]),
  )
  assert_true(
    reduce_goal(
      mutated,
      CompleteRequested(
        "complete-mutated",
        16,
        completion_proof(
          mutated.revision,
          goal.convergence.unwrap().report.evaluated_revision,
          "digest",
        ),
      ),
    ).status !=
    Complete,
  )
}

///|
test "v2 constructor creates an active durable goal" {
  let goal = test_goal()
  assert_true(goal.status == Active)
  assert_true(goal.run_state == Runnable)
  assert_true(goal.run_id == 0)
  assert_true(goal.revision == 0)
}

///|
test "unlimited budget exhaustion is exact no-op" {
  let goal = test_goal()
  assert_true(reduce_goal(goal, BudgetExhausted("budget", 11)) == goal)
}

///|
test "stale run and ordinal events are exact no-ops" {
  let goal = test_goal()
  assert_true(
    reduce_goal(goal, ContinuationAccepted("stale-run", 11, 1, 0)) == goal,
  )
  assert_true(
    reduce_goal(goal, ContinuationAccepted("stale-ordinal", 11, 0, 2)) == goal,
  )
  assert_true(
    reduce_goal(goal, TurnFinished("stale-turn", 11, 1, 0, None, true)) == goal,
  )
}

///|
test "constructor starts at exact budget limit awaiting budget" {
  let goal = new_goal(
    "g",
    "s",
    "ship",
    10,
    {
      token_limit: Some(4),
      turn_limit: None,
      wall_time_limit: None,
      tokens_used: 4,
      turns_used: 0,
      wall_time_used: 0,
    },
    [{ id: "r1", criterion: "done", state: Unproven, evidence_refs: [] }],
  )
  assert_true(goal.run_state == AwaitingBudget)
}

///|
test "constructor rejects empty criterion" {
  try
    new_goal(
      "g",
      "s",
      "ship",
      10,
      {
        token_limit: None,
        turn_limit: None,
        wall_time_limit: None,
        tokens_used: 0,
        turns_used: 0,
        wall_time_used: 0,
      },
      [{ id: "r1", criterion: " ", state: Unproven, evidence_refs: [] }],
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected new_goal to raise")
  }
}

///|
test "constructor rejects duplicate requirement ids" {
  try
    new_goal(
      "g",
      "s",
      "ship",
      10,
      {
        token_limit: None,
        turn_limit: None,
        wall_time_limit: None,
        tokens_used: 0,
        turns_used: 0,
        wall_time_used: 0,
      },
      [
        { id: "r", criterion: "one", state: Unproven, evidence_refs: [] },
        { id: "r", criterion: "two", state: Unproven, evidence_refs: [] },
      ],
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected new_goal to raise")
  }
}

///|
test "constructor rejects negative and over-limit budget" {
  try
    new_goal(
      "g",
      "s",
      "ship",
      10,
      {
        token_limit: None,
        turn_limit: None,
        wall_time_limit: None,
        tokens_used: -1,
        turns_used: 0,
        wall_time_used: 0,
      },
      [{ id: "r", criterion: "done", state: Unproven, evidence_refs: [] }],
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected negative budget to raise")
  }
  try
    new_goal(
      "g",
      "s",
      "ship",
      10,
      {
        token_limit: Some(1),
        turn_limit: None,
        wall_time_limit: None,
        tokens_used: 2,
        turns_used: 0,
        wall_time_used: 0,
      },
      [{ id: "r", criterion: "done", state: Unproven, evidence_refs: [] }],
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected over-limit budget to raise")
  }
}

///|
fn blocker(label : String) -> BlockerIdentity {
  { kind: "tool", authority: label, resource: label, required_change: label }
}

///|
test "continuation and turn correlation accepts valid events and rejects mismatches" {
  let goal = test_goal()
  let continued = reduce_goal(goal, ContinuationAccepted("continue", 11, 0, 0))
  assert_eq(continued.current_goal_turn, 0)
  assert_eq(continued.continuation_count, 1)
  let turned = reduce_goal(
    continued,
    TurnFinished("turn", 12, 0, 0, None, true),
  )
  assert_eq(turned.current_goal_turn, 1)
  assert_true(
    reduce_goal(goal, ContinuationAccepted("wrong-run", 11, 1, 0)) == goal,
  )
  assert_true(
    reduce_goal(goal, ContinuationAccepted("wrong-ordinal", 11, 0, 1)) == goal,
  )
  assert_true(
    reduce_goal(goal, TurnFinished("wrong-run-turn", 11, 1, 0, None, true)) ==
    goal,
  )
  assert_true(
    reduce_goal(goal, TurnFinished("wrong-ordinal-turn", 11, 0, 1, None, true)) ==
    goal,
  )
  let duplicate = reduce_goal(goal, ContinuationAccepted("duplicate", 11, 0, 0))
  assert_true(
    reduce_goal(duplicate, TurnFinished("duplicate", 12, 0, 0, None, true)) ==
    duplicate,
  )
}

///|
test "blocker streak clears on progress and no blocker" {
  let b = blocker("b")
  let one = reduce_goal(
    test_goal(),
    TurnFinished("b1", 11, 0, 0, Some(b), false),
  )
  assert_true(one.blocker is Some(_))
  let progress = reduce_goal(
    one,
    TurnFinished("progress", 12, 0, one.current_goal_turn, Some(b), true),
  )
  assert_true(progress.blocker is None)
  let cleared = reduce_goal(
    one,
    TurnFinished("clear", 12, 0, one.current_goal_turn, None, false),
  )
  assert_true(cleared.blocker is None)
}

///|
test "identical blocker transitions exactly on third and different blocker resets" {
  let b = blocker("b")
  let c = blocker("c")
  let one = reduce_goal(
    test_goal(),
    TurnFinished("b1", 11, 0, 0, Some(b), false),
  )
  let two = reduce_goal(
    one,
    TurnFinished("b2", 12, 0, one.current_goal_turn, Some(b), false),
  )
  assert_true(two.status == Active)
  let reset = reduce_goal(
    two,
    TurnFinished("c1", 13, 0, two.current_goal_turn, Some(c), false),
  )
  assert_true(reset.status == Active)
  assert_true(reset.run_state == Runnable)
  assert_true(reset.blocker.unwrap().identity == c)
  assert_eq(reset.blocker.unwrap().count, 1)
  let three = reduce_goal(
    two,
    TurnFinished("b3", 13, 0, two.current_goal_turn, Some(b), false),
  )
  assert_true(three.status == Blocked)
  assert_true(three.run_state == AwaitingInput)
}

///|
test "resume starts fresh correlation and blocker streak" {
  let b = blocker("b")
  let one = reduce_goal(
    test_goal(),
    TurnFinished("b1", 11, 0, 0, Some(b), false),
  )
  let two = reduce_goal(
    one,
    TurnFinished("b2", 12, 0, one.current_goal_turn, Some(b), false),
  )
  let blocked = reduce_goal(
    two,
    TurnFinished("b3", 13, 0, two.current_goal_turn, Some(b), false),
  )
  let resumed = reduce_goal(blocked, Resume("resume", 14))
  assert_eq(resumed.run_id, blocked.run_id + 1)
  assert_true(resumed.blocker is None)
  assert_true(
    reduce_goal(
      resumed,
      TurnFinished(
        "old",
        15,
        blocked.run_id,
        resumed.current_goal_turn,
        Some(b),
        false,
      ),
    ) ==
    resumed,
  )
  let fresh_one = reduce_goal(
    resumed,
    TurnFinished(
      "fresh1",
      16,
      resumed.run_id,
      resumed.current_goal_turn,
      Some(b),
      false,
    ),
  )
  let fresh_two = reduce_goal(
    fresh_one,
    TurnFinished(
      "fresh2",
      17,
      resumed.run_id,
      fresh_one.current_goal_turn,
      Some(b),
      false,
    ),
  )
  assert_true(fresh_two.status == Active)
  guard fresh_two.blocker is Some(blocker) else {
    fail("missing blocker after second fresh run turn")
  }
  assert_true(blocker.identity == b)
  assert_eq(blocker.count, 2)
  assert_eq(blocker.run_id, resumed.run_id)
}

///|
test "duplicate event is exact no-op" {
  let goal = test_goal()
  let once = reduce_goal(goal, ContinuationAccepted("same", 11, 0, 0))
  assert_true(reduce_goal(once, ContinuationAccepted("same", 11, 0, 1)) == once)
}
