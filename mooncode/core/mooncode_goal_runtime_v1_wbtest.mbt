///|
fn runtime_continue(id : String, operation_id : String) -> GoalRuntimeEvent {
  PlannerDecision(
    id,
    Continue(
      [
        {
          operation_id,
          kind: "test",
          input: "",
          policy: { max_output_bytes: 1024, timeout_milliseconds: 10 },
        },
      ],
      "one quantum of progress",
      "criterion remains open",
    ),
  )
}

///|
test "more than 32 and more than 20 continuation quanta remain unbounded" {
  let mut state = new_goal_runtime_state()
  for i = 0; i < 41; i = i + 1 {
    state = reduce_goal_runtime(
      state,
      runtime_continue(
        "decision-" + i.to_string(),
        "operation-" + i.to_string(),
      ),
    )
    state = reduce_goal_runtime(
      state,
      CheckpointAccepted(
        "checkpoint-event-" + i.to_string(),
        "checkpoint-" + i.to_string(),
      ),
    )
  }
  assert_eq(state.operation_ids.length(), 41)
  assert_eq(state.checkpoint_ids.length(), 41)
  state = reduce_goal_runtime(
    state,
    PlannerDecision(
      "settle",
      Achieved("done", [{ criterion: "all work", evidence_refs: ["proof-1"] }]),
    ),
  )
  assert_true(state.outcome is Some(AchievedOutcome(_, _)))
}

///|
test "blocked and cancelled are explicit terminal decisions" {
  let blocked = reduce_goal_runtime(
    new_goal_runtime_state(),
    PlannerDecision(
      "blocked",
      Blocked(
        { code: "approval", detail: "owner unavailable" },
        ["requested owner approval"],
        Some("owner approves"),
      ),
    ),
  )
  assert_true(blocked.outcome is Some(BlockedOutcome(_, _, _)))
  let cancelled = reduce_goal_runtime(
    new_goal_runtime_state(),
    Cancelled("cancel", "operator request"),
  )
  assert_true(cancelled.outcome is Some(CancelledOutcome(_)))
}

///|
test "stable event and operation ids are idempotent" {
  let event = runtime_continue("same-event", "same-operation")
  let once = reduce_goal_runtime(new_goal_runtime_state(), event)
  let twice = reduce_goal_runtime(once, event)
  assert_true(once == twice)
  let another = reduce_goal_runtime(
    twice,
    OperationAccepted("another-event", "same-operation"),
  )
  assert_eq(another.operation_ids.length(), 1)
}

///|
test "settlement is absorbing and cannot be replaced" {
  let achieved = reduce_goal_runtime(
    new_goal_runtime_state(),
    PlannerDecision(
      "achieve",
      Achieved("done", [{ criterion: "complete", evidence_refs: ["proof"] }]),
    ),
  )
  assert_true(goal_runtime_is_terminal(achieved))
  let invalid_second = reduce_goal_runtime(
    achieved,
    PlannerDecision(
      "block-after-achieve",
      Blocked(
        { code: "late", detail: "late" },
        ["valid alternative"],
        Some("valid event"),
      ),
    ),
  )
  assert_true(achieved == invalid_second)
}

///|
test "invalid achieved and blocked decisions are exact no-ops" {
  let initial = new_goal_runtime_state()
  let invalid = [
    PlannerDecision("a1", Achieved("done", [])),
    PlannerDecision(
      "a2",
      Achieved("done", [{ criterion: " ", evidence_refs: ["proof"] }]),
    ),
    PlannerDecision(
      "a3",
      Achieved("done", [{ criterion: "criterion", evidence_refs: [] }]),
    ),
    PlannerDecision(
      "a4",
      Achieved("done", [{ criterion: "criterion", evidence_refs: [" "] }]),
    ),
    PlannerDecision(
      "a5",
      Achieved("done", [
        { criterion: "duplicate", evidence_refs: ["proof-1"] },
        { criterion: "duplicate", evidence_refs: ["proof-2"] },
      ]),
    ),
    PlannerDecision(
      "b1",
      Blocked({ code: "code", detail: " " }, ["alternative"], None),
    ),
    PlannerDecision("b2", Blocked({ code: "code", detail: "detail" }, [], None)),
    PlannerDecision(
      "b3",
      Blocked({ code: "code", detail: "detail" }, [" "], None),
    ),
    PlannerDecision(
      "b4",
      Blocked({ code: "code", detail: "detail" }, ["alternative"], Some(" ")),
    ),
  ]
  for event in invalid {
    assert_true(reduce_goal_runtime(initial, event) == initial)
  }
}

///|
test "aggregate budget and deadline fields are rejected, not clamped" {
  let forbidden = [
    "max_tokens", "token_budget", "max_turns", "turn_budget", "deadline", "deadline_ms",
    "wall_time_limit", "max_loc", "loc_budget", "token_limit", "turn_limit", "max_steps",
    "step_limit", "planner_max_steps", "max_continuations", "max_iterations", "iteration_limit",
    "time_budget", "max_time", "expires_at", "max_operations", "operation_limit",
    "loc_limit",
  ]
  for field in forbidden {
    assert_true(goal_runtime_rejects_aggregate_field(field))
  }
  assert_true(!goal_runtime_rejects_aggregate_field("max_output_bytes"))
  assert_true(!goal_runtime_rejects_aggregate_field("timeout_milliseconds"))
  let serialized_shape = goal_runtime_status_json(new_goal_runtime_state()).stringify()
  for field in forbidden {
    assert_true(!serialized_shape.contains(field))
  }
}

///|
test "timeouts empty responses and counters cannot infer terminal state" {
  let state = reduce_goal_runtime(
    new_goal_runtime_state(),
    PhaseChanged("provider-timeout", RetryBackoff),
  )
  let state = reduce_goal_runtime(
    state,
    PhaseChanged("empty-response", PausedNoProgress),
  )
  assert_true(state.outcome is None)
}

///|
test "continue validation rejects missing intent and invalid or duplicate operations" {
  let valid : GoalRuntimeOperation = {
    operation_id: "op",
    kind: "test",
    input: "",
    policy: { max_output_bytes: 1, timeout_milliseconds: 1 },
  }
  assert_true(!validate_goal_planner_decision(Continue([], "progress", "why")))
  assert_true(!validate_goal_planner_decision(Continue([valid], " ", "why")))
  assert_true(
    !validate_goal_planner_decision(Continue([valid], "progress", " ")),
  )
  assert_true(
    !validate_goal_planner_decision(Continue([valid, valid], "progress", "why")),
  )
  assert_true(
    !validate_goal_planner_decision(
      Continue(
        [
          {
            operation_id: " ",
            kind: "test",
            input: "",
            policy: { max_output_bytes: 1, timeout_milliseconds: 1 },
          },
        ],
        "progress",
        "why",
      ),
    ),
  )
  assert_true(
    !validate_goal_planner_decision(
      Continue(
        [
          {
            operation_id: "op",
            kind: "test",
            input: "",
            policy: { max_output_bytes: 0, timeout_milliseconds: 1 },
          },
        ],
        "progress",
        "why",
      ),
    ),
  )
  assert_true(
    !validate_goal_planner_decision(
      Continue(
        [
          {
            operation_id: "op",
            kind: "test",
            input: "",
            policy: { max_output_bytes: 1, timeout_milliseconds: 0 },
          },
        ],
        "progress",
        "why",
      ),
    ),
  )
}

///|
test "blank event and payload identifiers are exact no-ops" {
  let events = [
    OperationAccepted("event", " "),
    CheckpointAccepted("event", " "),
    Cancelled("event", " "),
    OperationAccepted(" ", "operation"),
    CheckpointAccepted(" ", "checkpoint"),
    PhaseChanged(" ", Running),
    Cancelled(" ", "reason"),
    runtime_continue(" ", "operation"),
  ]
  for event in events {
    assert_true(
      reduce_goal_runtime(new_goal_runtime_state(), event) ==
      new_goal_runtime_state(),
    )
  }
}

///|
test "all six nonterminal phases occur in sequence without settlement" {
  let phases = [
    Queued,
    Running,
    WaitingApproval,
    RetryBackoff,
    PausedNoProgress,
    PausedExternal,
  ]
  let mut state = new_goal_runtime_state()
  for i, phase in phases {
    state = reduce_goal_runtime(
      state,
      PhaseChanged("phase-" + i.to_string(), phase),
    )
    assert_true(state.phase == phase)
    assert_true(state.outcome is None)
  }
}

///|
test "canonical status is bounded counts and names only" {
  let state = reduce_goal_runtime(
    new_goal_runtime_state(),
    runtime_continue("event", "operation"),
  )
  let text = goal_runtime_status_json(state).stringify()
  assert_true(text.contains("phase"))
  assert_true(text.contains("terminal"))
  assert_true(text.contains("outcome"))
  assert_true(text.contains("handled_count"))
  assert_true(text.contains("operation_count"))
  assert_true(text.contains("checkpoint_count"))
  assert_true(!text.contains("handled_ids"))
  assert_true(!text.contains("operation_ids"))
  assert_true(!text.contains("checkpoint_ids"))
}

///|
test "padded identities and blank operation kinds are exact no-ops" {
  let initial = new_goal_runtime_state()
  let padded_operation = reduce_goal_runtime(
    initial,
    OperationAccepted("padded-operation-event", " padded-operation "),
  )
  assert_true(padded_operation == initial)
  let padded_checkpoint = reduce_goal_runtime(
    initial,
    CheckpointAccepted("padded-checkpoint-event", " padded-checkpoint "),
  )
  assert_true(padded_checkpoint == initial)
  let blank_kind = reduce_goal_runtime(
    initial,
    PlannerDecision(
      "blank-kind",
      Continue(
        [
          {
            operation_id: "operation",
            kind: " ",
            input: "",
            policy: { max_output_bytes: 1, timeout_milliseconds: 1 },
          },
        ],
        "progress",
        "reason",
      ),
    ),
  )
  assert_true(blank_kind == initial)
}

///|
test "terminal arrays are isolated from caller mutation" {
  let refs = ["proof-1"]
  let evidence = [{ criterion: "criterion", evidence_refs: refs }]
  let achieved = reduce_goal_runtime(
    new_goal_runtime_state(),
    PlannerDecision("event-a", Achieved("done", evidence)),
  )
  refs.push("caller-mutation")
  evidence.push({ criterion: "other", evidence_refs: ["proof-2"] })
  match goal_runtime_outcome(achieved) {
    Some(AchievedOutcome(_, stored)) =>
      assert_eq(stored[0].evidence_refs.length(), 1)
    _ => fail("expected achieved")
  }
  let alternatives = ["attempt-1"]
  let blocked = reduce_goal_runtime(
    new_goal_runtime_state(),
    PlannerDecision(
      "event-b",
      Blocked(
        { code: "external", detail: "waiting" },
        alternatives,
        Some("approval"),
      ),
    ),
  )
  alternatives.push("caller-mutation")
  match goal_runtime_outcome(blocked) {
    Some(BlockedOutcome(_, stored, _)) => assert_eq(stored.length(), 1)
    _ => fail("expected blocked")
  }
}
