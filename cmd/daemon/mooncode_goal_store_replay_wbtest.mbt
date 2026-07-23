///|
/// Focused durable goal restart/replay coverage.
fn goal_store_replay_event_record(event : @mooncode_core.GoalEvent) -> Json {
  {
    "record_kind": mooncode_journal_event(),
    "record_id": mooncode_journal_goal_event() +
    ":" +
    @mooncode_core.goal_event_id(event),
    "session_id": "session",
    "payload": @mooncode_core.goal_event_to_json(event),
  }
}

///|
fn goal_store_replay_genesis() -> Json raise {
  goal_store_test_record(
    mooncode_goal_genesis(
      mooncode_protocol_version(),
      "session",
      "goal",
      "objective",
      123,
      goal_store_test_budget(),
      goal_store_test_requirements(),
    ),
  )
}

///|
fn goal_store_replay_requirement_event(
  timestamp : Int,
  requirement_id : String,
  state : @mooncode_core.RequirementState,
  evidence_refs : Array[String],
) -> @mooncode_core.GoalEvent {
  @mooncode_core.RequirementUpdated(
    "event-1", timestamp, requirement_id, state, evidence_refs,
  )
}

///|
test "mooncode_goal_store replay: mutation applies and compatibility returns current" {
  let event = goal_store_replay_requirement_event(
    124,
    "r1",
    @mooncode_core.Proven,
    ["evidence:r1"],
  )
  let records = [
    goal_store_replay_genesis(),
    goal_store_replay_event_record(event),
  ]
  let detailed = mooncode_replay_goal_records_detailed(records, "session").unwrap()
  assert_eq(detailed.genesis.revision, 0)
  assert_true(detailed.genesis.requirements[0].state == @mooncode_core.Unproven)
  assert_eq(detailed.current.revision, 1)
  assert_true(detailed.current.requirements[0].state == @mooncode_core.Proven)
  assert_true(detailed.events.get("event-1") == Some(event))
  assert_true(
    mooncode_replay_goal_records(records, "session") == Some(detailed.current),
  )
}

///|
test "mooncode_goal_store replay: duplicate is idempotent and conflict fails closed" {
  let event = goal_store_replay_requirement_event(
    124,
    "r1",
    @mooncode_core.Proven,
    ["evidence:r1"],
  )
  let record = goal_store_replay_event_record(event)
  let detailed = mooncode_replay_goal_records_detailed(
    [goal_store_replay_genesis(), record, record],
    "session",
  ).unwrap()
  assert_eq(detailed.current.revision, 1)

  for
    conflicting in [
      goal_store_replay_requirement_event(125, "r1", @mooncode_core.Proven, [
        "evidence:r1",
      ]),
      goal_store_replay_requirement_event(124, "r1", @mooncode_core.Proven, [
        "evidence:changed",
      ]),
    ] {
    let mut rejected = false
    ignore(
      mooncode_replay_goal_records_detailed(
        [
          goal_store_replay_genesis(),
          record,
          goal_store_replay_event_record(conflicting),
        ],
        "session",
      ),
    ) catch {
      InvalidGoalGenesis(_) => rejected = true
      _ => ()
    }
    assert_true(rejected)
  }
}

///|
test "mooncode_goal_store replay: ordering malformed reserved and ordinary records" {
  let event = goal_store_replay_requirement_event(
    124,
    "r1",
    @mooncode_core.Proven,
    ["evidence:r1"],
  )
  let ordinary : Json = {
    "record_kind": mooncode_journal_event(),
    "record_id": "ordinary",
    "session_id": "session",
    "payload": { "id": "ordinary", "kind": "runtime.started.v1" },
  }
  let malformed : Json = {
    "record_kind": mooncode_journal_event(),
    "record_id": mooncode_journal_goal_event() + ":bad",
    "session_id": "session",
    "payload": { "id": "bad", "kind": "mooncode.goal.unknown.v1" },
  }
  for
    records in [
      [goal_store_replay_event_record(event)],
      [goal_store_replay_genesis(), malformed],
    ] {
    let mut rejected = false
    ignore(mooncode_replay_goal_records_detailed(records, "session")) catch {
      InvalidGoalGenesis(_) => rejected = true
      _ => ()
    }
    assert_true(rejected)
  }
  let detailed = mooncode_replay_goal_records_detailed(
    [
      ordinary,
      goal_store_replay_genesis(),
      ordinary,
      goal_store_replay_event_record(event),
    ],
    "session",
  ).unwrap()
  assert_eq(detailed.current.revision, 1)
}

///|
test "mooncode_goal_store replay: unseen reducer no-op fails closed" {
  let event = goal_store_replay_requirement_event(
    124,
    "missing",
    @mooncode_core.Proven,
    ["evidence:missing"],
  )
  let mut rejected = false
  ignore(
    mooncode_replay_goal_records_detailed(
      [goal_store_replay_genesis(), goal_store_replay_event_record(event)],
      "session",
    ),
  ) catch {
    InvalidGoalGenesis(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}

///|
async test "mooncode_goal_store disk restart: create replay and idempotency" {
  @fsx.with_temporary_directory("moonclaw-goal-replay-XXXXXX", async fn(
    directory,
  ) {
    let created = mooncode_create_goal(
      directory,
      mooncode_protocol_version(),
      "session",
      "goal",
      "objective",
      123,
      goal_store_test_budget(),
      goal_store_test_requirements(),
    )
    let genesis = match created {
      Created(goal) => goal
      Idempotent(_) => fail("initial goal creation was idempotent")
      Conflict(_) => fail("initial goal creation conflicted")
    }
    assert_eq(genesis.revision, 0)
    assert_eq(genesis.created_at, 123)
    let event = goal_store_replay_requirement_event(
      124,
      "r1",
      @mooncode_core.Proven,
      ["evidence:r1"],
    )
    let appended = mooncode_append_session_journal_once(
      directory,
      "session",
      mooncode_journal_event(),
      @mooncode_core.goal_event_to_json(event),
    )
    assert_true(appended)
    let detailed = mooncode_replay_goal_detailed(directory, "session").unwrap()
    assert_eq(detailed.genesis.revision, 0)
    assert_eq(detailed.genesis.created_at, 123)
    assert_eq(detailed.current.revision, 1)
    assert_true(detailed.current.requirements[0].state == @mooncode_core.Proven)
    assert_true(
      mooncode_replay_goal(directory, "session") == Some(detailed.current),
    )
    match
      mooncode_create_goal(
        directory,
        mooncode_protocol_version(),
        "session",
        "goal",
        "objective",
        999,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ) {
      Idempotent(current) => assert_true(current == detailed.current)
      Created(_) => fail("retry unexpectedly created a goal")
      Conflict(_) => fail("unchanged retry unexpectedly conflicted")
    }
    match
      mooncode_create_goal(
        directory,
        mooncode_protocol_version(),
        "session",
        "goal",
        "changed objective",
        999,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ) {
      Conflict(current) => assert_true(current == detailed.current)
      Created(_) => fail("changed objective unexpectedly created a goal")
      Idempotent(_) => fail("changed objective unexpectedly was idempotent")
    }
    let records = mooncode_read_session_journal(directory, "session")
    assert_eq(records.length(), 2)
  })
}
