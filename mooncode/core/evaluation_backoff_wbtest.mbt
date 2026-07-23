///|
fn started_evaluation_for_backoff_test() -> Goal raise {
  reduce_goal(test_goal(), EvaluationStarted("start-eval", 0, "eval", "d"))
}

///|
fn first_backoff_for_test() -> Goal raise {
  reduce_goal(
    started_evaluation_for_backoff_test(),
    EvaluationFailed("failure-1", 10, "eval", 0, 0, "d", 1, "transient", 20),
  )
}

///|
test "evaluation failure stores every canonical backoff field" {
  let failed = first_backoff_for_test()
  assert_true(failed.run_state == EvaluationBackoff)
  assert_true(failed.active_evaluation == None)
  assert_true(
    failed.evaluation_backoff ==
    Some({
      evaluation_id: "eval",
      run_id: 0,
      basis_revision: 0,
      evidence_digest: "d",
      attempt: 1,
      category: "transient",
      next_retry_at: 20,
    }),
  )
}

///|
test "evaluation failure rejects every invalid binding as an exact goal no-op" {
  let started = started_evaluation_for_backoff_test()
  let invalid : Array[GoalEvent] = [
    EvaluationFailed("bad-eval", 10, "wrong", 0, 0, "d", 1, "transient", 20),
    EvaluationFailed("bad-run", 10, "eval", 1, 0, "d", 1, "transient", 20),
    EvaluationFailed("bad-basis", 10, "eval", 0, 1, "d", 1, "transient", 20),
    EvaluationFailed(
      "bad-digest", 10, "eval", 0, 0, "wrong", 1, "transient", 20,
    ),
    EvaluationFailed("zero-attempt", 10, "eval", 0, 0, "d", 0, "transient", 20),
    EvaluationFailed(
      "negative-attempt", 10, "eval", 0, 0, "d", -1, "transient", 20,
    ),
    EvaluationFailed("blank-category", 10, "eval", 0, 0, "d", 1, "   ", 20),
    EvaluationFailed("past-deadline", 10, "eval", 0, 0, "d", 1, "transient", 9),
  ]
  for event in invalid {
    assert_true(reduce_goal(started, event) == started)
  }
}

///|
test "resume and early retry cannot bypass evaluation backoff" {
  let backoff = first_backoff_for_test()
  assert_true(reduce_goal(backoff, Resume("resume", 19)) == backoff)
  assert_true(
    reduce_goal(backoff, EvaluationRetryDue("retry-early", 19, "eval", 0, 1)) ==
    backoff,
  )
}

///|
test "due retry recreates exact request and duplicate retry id is non-vacuous" {
  let backoff = first_backoff_for_test()
  let evaluating = reduce_goal(
    backoff,
    EvaluationRetryDue("retry-1", 20, "eval", 0, 1),
  )
  assert_true(evaluating.run_state == Evaluating)
  assert_true(evaluating.evaluation_backoff == None)
  assert_true(
    evaluating.active_evaluation ==
    Some({ id: "eval", run_id: 0, revision: 0, evidence_digest: "d" }),
  )
  let second_backoff = reduce_goal(
    evaluating,
    EvaluationFailed("failure-2", 21, "eval", 0, 0, "d", 2, "transient", 30),
  )
  assert_true(second_backoff.run_state == EvaluationBackoff)
  assert_true(
    reduce_goal(second_backoff, EvaluationRetryDue("retry-1", 30, "eval", 0, 2)) ==
    second_backoff,
  )
}

///|
test "evaluation backoff explicit event replay is deterministic" {
  let events : Array[GoalEvent] = [
    EvaluationStarted("start-eval", 0, "eval", "d"),
    EvaluationFailed("failure-1", 10, "eval", 0, 0, "d", 1, "transient", 20),
    EvaluationRetryDue("retry-1", 20, "eval", 0, 1),
    EvaluationFailed("failure-2", 21, "eval", 0, 0, "d", 2, "transient", 30),
    EvaluationRetryDue("retry-2", 30, "eval", 0, 2),
  ]
  let mut left = test_goal()
  let mut right = test_goal()
  for event in events {
    left = reduce_goal(left, event)
    right = reduce_goal(right, event)
  }
  assert_true(left == right)
}

///|
test "evaluation bundle exposes current run and backoff while status stays safe" {
  let backed_off = first_backoff_for_test()
  let bundle = goal_evaluation_bundle_json(backed_off).stringify()
  assert_true(bundle.contains("\"run_id\":0"))
  assert_true(bundle.contains("\"evaluation_backoff\""))
  assert_true(bundle.contains("\"evaluation_id\":\"eval\""))
  assert_true(bundle.contains("\"basis_revision\":0"))
  assert_true(bundle.contains("\"evidence_digest\":\"d\""))
  assert_true(bundle.contains("\"attempt\":1"))
  assert_true(bundle.contains("\"category\":\"transient\""))
  assert_true(bundle.contains("\"next_retry_at\":20"))
  let status = goal_status_json(backed_off).stringify()
  assert_false(status.contains("evidence_digest"))
  assert_false(status.contains("category"))
  assert_false(status.contains("transient"))
}

///|
test "starting evaluation clears stale convergence from status and evaluator JSON" {
  let converged = evaluated_goal(Converged)
  let started = reduce_goal(
    converged,
    EvaluationStarted(
      "start-fresh",
      converged.updated_at + 1,
      "fresh-eval",
      "fresh-digest",
    ),
  )
  assert_true(started.convergence == None)
  let old_outcome = "converged"
  assert_true(!goal_status_json(started).stringify().contains(old_outcome))
  assert_true(
    !goal_evaluation_bundle_json(started).stringify().contains(old_outcome),
  )
  let request = match started.active_evaluation {
    Some(request) => request
    None => abort("expected active evaluation")
  }
  let backed_off = reduce_goal(
    started,
    EvaluationFailed(
      "fresh-failure",
      started.updated_at + 1,
      request.id,
      request.run_id,
      request.revision,
      request.evidence_digest,
      1,
      "transient",
      started.updated_at + 2,
    ),
  )
  assert_true(backed_off.convergence == None)
  assert_true(!goal_status_json(backed_off).stringify().contains(old_outcome))
  assert_true(
    !goal_evaluation_bundle_json(backed_off).stringify().contains(old_outcome),
  )
}

///|
test "restored active evaluation from an old run rejects matching failure" {
  let started = started_evaluation_for_backoff_test()
  let restored = { ..started, run_id: started.run_id + 1 }
  let request = match restored.active_evaluation {
    Some(request) => request
    None => abort("expected active evaluation")
  }
  assert_true(
    reduce_goal(
      restored,
      EvaluationFailed(
        "stale-failure",
        restored.updated_at + 1,
        request.id,
        request.run_id,
        request.revision,
        request.evidence_digest,
        1,
        "transient",
        restored.updated_at + 2,
      ),
    ) ==
    restored,
  )
}

///|
test "restored backoff from an old run rejects matching due retry" {
  let backoff = first_backoff_for_test()
  let restored = { ..backoff, run_id: backoff.run_id + 1 }
  let record = match restored.evaluation_backoff {
    Some(record) => record
    None => abort("expected evaluation backoff")
  }
  assert_true(
    reduce_goal(
      restored,
      EvaluationRetryDue(
        "stale-retry",
        record.next_retry_at,
        record.evaluation_id,
        record.run_id,
        record.attempt,
      ),
    ) ==
    restored,
  )
}
