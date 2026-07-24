///|
fn audit_continue(event_id : String, operation_id : String) -> GoalRuntimeEvent {
  PlannerDecision(
    event_id,
    Continue(
      [
        {
          operation_id,
          kind: "test",
          input: "",
          policy: { max_output_bytes: 8, timeout_milliseconds: 8 },
        },
      ],
      "progress",
      "open",
    ),
  )
}

///|
fn assert_noop(
  state : GoalRuntimeState,
  event : GoalRuntimeEvent,
) -> Unit raise {
  assert_true(reduce_goal_runtime(state, event) == state)
}

///|
test "audit rejects noncanonical achieved and blocked payload strings" {
  let root = new_goal_runtime_state()
  let bad = [
    PlannerDecision(
      "a1",
      Achieved(" done", [{ criterion: "criterion", evidence_refs: ["proof"] }]),
    ),
    PlannerDecision(
      "a2",
      Achieved("done", [{ criterion: " criterion", evidence_refs: ["proof"] }]),
    ),
    PlannerDecision(
      "a3",
      Achieved("done", [{ criterion: "criterion", evidence_refs: [" proof"] }]),
    ),
    PlannerDecision(
      "a4",
      Achieved("done", [
        { criterion: "criterion", evidence_refs: ["proof", "proof"] },
      ]),
    ),
    PlannerDecision(
      "b1",
      Blocked({ code: "", detail: "detail" }, ["alternative"], None),
    ),
    PlannerDecision(
      "b2",
      Blocked({ code: " code", detail: "detail" }, ["alternative"], None),
    ),
    PlannerDecision(
      "b3",
      Blocked({ code: "code", detail: " detail" }, ["alternative"], None),
    ),
    PlannerDecision(
      "b4",
      Blocked({ code: "code", detail: "detail" }, [" alternative"], None),
    ),
    PlannerDecision(
      "b5",
      Blocked(
        { code: "code", detail: "detail" },
        ["alternative", "alternative"],
        None,
      ),
    ),
  ]
  for event in bad {
    assert_noop(root, event)
  }
}

///|
test "invalid planner event is no-op and its id remains reusable" {
  let populated = reduce_goal_runtime(
    new_goal_runtime_state(),
    audit_continue("seed", "op-seed"),
  )
  let invalid = PlannerDecision(
    "reusable",
    Achieved(" ", [{ criterion: "criterion", evidence_refs: ["proof"] }]),
  )
  assert_noop(populated, invalid)
  let valid = reduce_goal_runtime(
    populated,
    audit_continue("reusable", "op-next"),
  )
  assert_eq(
    goal_runtime_handled_count(valid),
    goal_runtime_handled_count(populated) + 1,
  )
  assert_eq(
    goal_runtime_operation_count(valid),
    goal_runtime_operation_count(populated) + 1,
  )
}

///|
fn terminal_roots() -> Array[GoalRuntimeState] {
  [
    reduce_goal_runtime(
      new_goal_runtime_state(),
      PlannerDecision(
        "achieve",
        Achieved("done", [{ criterion: "criterion", evidence_refs: ["proof"] }]),
      ),
    ),
    reduce_goal_runtime(
      new_goal_runtime_state(),
      PlannerDecision(
        "block",
        Blocked({ code: "blocked", detail: "detail" }, ["alternative"], None),
      ),
    ),
    reduce_goal_runtime(new_goal_runtime_state(), Cancelled("cancel", "reason")),
  ]
}

///|
test "all seven event categories are absorbed by every terminal root" {
  let events = [
    audit_continue("continue", "op"),
    PlannerDecision(
      "achieved",
      Achieved("done", [{ criterion: "criterion", evidence_refs: ["proof"] }]),
    ),
    PlannerDecision(
      "blocked",
      Blocked({ code: "blocked", detail: "detail" }, ["alternative"], None),
    ),
    OperationAccepted("operation", "op"),
    CheckpointAccepted("checkpoint", "cp"),
    PhaseChanged("phase", Running),
    Cancelled("cancelled", "reason"),
  ]
  for root in terminal_roots() {
    for event in events {
      assert_noop(root, event)
    }
  }
}

///|
test "canonical ids kinds checkpoint idempotency and cross variant collision" {
  let root = new_goal_runtime_state()
  assert_noop(root, audit_continue(" padded", "op"))
  assert_noop(root, audit_continue("event", " padded"))
  assert_noop(
    root,
    PlannerDecision(
      "event",
      Continue(
        [
          {
            operation_id: "op",
            kind: " padded",
            input: "",
            policy: { max_output_bytes: 8, timeout_milliseconds: 8 },
          },
        ],
        "progress",
        "open",
      ),
    ),
  )
  let once = reduce_goal_runtime(root, CheckpointAccepted("cp-event", "cp"))
  assert_true(
    reduce_goal_runtime(once, CheckpointAccepted("cp-event", "cp")) == once,
  )
  let distinct = reduce_goal_runtime(
    once,
    CheckpointAccepted("cp-event-2", "cp"),
  )
  assert_eq(goal_runtime_checkpoint_count(distinct), 1)
  assert_eq(
    goal_runtime_handled_count(distinct),
    goal_runtime_handled_count(once) + 1,
  )
  let collision = reduce_goal_runtime(root, OperationAccepted("shared", "op"))
  assert_noop(collision, CheckpointAccepted("shared", "cp"))
}

///|
test "terminal payloads are deeply copied in and out" {
  let refs = ["proof"]
  let evidence = [{ criterion: "criterion", evidence_refs: refs }]
  let achieved = reduce_goal_runtime(
    new_goal_runtime_state(),
    PlannerDecision("achieve-copy", Achieved("done", evidence)),
  )
  refs[0] = "mutated-in"
  evidence[0] = { criterion: "mutated", evidence_refs: ["mutated"] }
  match goal_runtime_outcome(achieved) {
    Some(AchievedOutcome(_, first)) => {
      assert_eq(first[0].criterion, "criterion")
      assert_eq(first[0].evidence_refs[0], "proof")
      first[0].evidence_refs[0] = "mutated-out"
    }
    _ => abort("expected achieved")
  }
  match goal_runtime_outcome(achieved) {
    Some(AchievedOutcome(_, second)) =>
      assert_eq(second[0].evidence_refs[0], "proof")
    _ => abort("expected achieved")
  }
  let alternatives = ["alternative"]
  let blocked = reduce_goal_runtime(
    new_goal_runtime_state(),
    PlannerDecision(
      "block-copy",
      Blocked({ code: "blocked", detail: "detail" }, alternatives, None),
    ),
  )
  alternatives[0] = "mutated-in"
  match goal_runtime_outcome(blocked) {
    Some(BlockedOutcome(_, first, _)) => {
      assert_eq(first[0], "alternative")
      first[0] = "mutated-out"
    }
    _ => abort("expected blocked")
  }
  match goal_runtime_outcome(blocked) {
    Some(BlockedOutcome(_, second, _)) => assert_eq(second[0], "alternative")
    _ => abort("expected blocked")
  }
}
