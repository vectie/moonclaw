///|
/// Focused durable goal restart/replay coverage.
fn goal_store_replay_event_record(event : @mooncode_core.GoalEvent) -> Json {
  {
    "record_kind": mooncode_journal_event(),
    "record_id": mooncode_journal_goal_event() +
    ":" +
    @mooncode_core.goal_event_id(event),
    "session_id": "session",
    "recorded_at": goal_json_int64_value(
      @mooncode_core.goal_event_recorded_at(event),
    ),
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
fn goal_strict_field(object : Json, key : String) -> Json raise {
  goal_json_object(object, key)
}

///|
fn goal_strict_first(array : Json) -> Json {
  match array {
    Array(items) => items[0]
    _ => abort("expected JSON array")
  }
}

///|
fn goal_store_replay_requirement_event(
  timestamp : Int64,
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
    let mutation = mooncode_apply_goal_event(
      directory,
      "session",
      "goal",
      @mooncode_core.goal_event_to_json(event),
    )
    let next = match mutation {
      GoalMutationApplied(next) => next
      GoalMutationIdempotent(_) => fail("goal mutation was idempotent")
      GoalMutationConflict(_) => fail("goal mutation conflicted")
      GoalMutationRejected(_) => fail("goal mutation was rejected")
    }
    assert_eq(next.revision, 1)
    let detailed = mooncode_replay_goal_detailed(directory, "session").unwrap()
    assert_true(detailed.current == next)
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

///|
fn goal_strict_put(object : Json, key : String, value : Json) -> Json {
  match object {
    Object(fields) => {
      let copy = fields.copy()
      copy[key] = value
      Json::object(copy)
    }
    _ => abort("expected JSON object")
  }
}

///|
fn goal_strict_substitute(
  object : Json,
  removed_key : String,
  added_key : String,
  value : Json,
) -> Json {
  match object {
    Object(fields) => {
      let copy = fields.copy()
      copy.remove(removed_key)
      copy[added_key] = value
      Json::object(copy)
    }
    _ => abort("expected JSON object")
  }
}

///|
fn goal_strict_reject_records(records : Array[Json]) -> Unit raise {
  let mut rejected = false
  ignore(mooncode_replay_goal_records_detailed(records, "session")) catch {
    InvalidGoalGenesis(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}

///|
test "mooncode_goal_store strict replay: rejects top-level extra and substituted keys" {
  let genesis = goal_store_replay_genesis()
  let payload = goal_strict_field(genesis, "payload")
  for
    changed_payload in [
      goal_strict_put(payload, "extra", 1),
      goal_strict_substitute(payload, "objective", "subject", "objective"),
    ] {
    goal_strict_reject_records([
      goal_strict_put(genesis, "payload", changed_payload),
    ])
  }
}

///|
test "mooncode_goal_store strict replay: rejects budget and requirement key drift" {
  let genesis = goal_store_replay_genesis()
  let payload = goal_strict_field(genesis, "payload")
  let budget = goal_strict_field(payload, "budget")
  let requirement = goal_strict_first(
    goal_strict_field(payload, "requirements"),
  )
  for
    changed_budget in [
      goal_strict_put(budget, "extra", 1),
      goal_strict_substitute(budget, "turn_limit", "turn_cap", 4),
    ] {
    goal_strict_reject_records([
      goal_strict_put(
        genesis,
        "payload",
        goal_strict_put(payload, "budget", changed_budget),
      ),
    ])
  }
  for
    changed_requirement in [
      goal_strict_put(requirement, "extra", 1),
      goal_strict_substitute(requirement, "id", "unexpected", "r1"),
    ] {
    goal_strict_reject_records([
      goal_strict_put(
        genesis,
        "payload",
        goal_strict_put(payload, "requirements", [changed_requirement]),
      ),
    ])
  }
}

///|
test "mooncode_goal_store strict replay: rejects padded semantic strings" {
  let genesis = goal_store_replay_genesis()
  let payload = goal_strict_field(genesis, "payload")
  let requirement = goal_strict_first(
    goal_strict_field(payload, "requirements"),
  )
  for
    changed_payload in [
      goal_strict_put(payload, "objective", " objective "),
      goal_strict_put(payload, "requirements", [
        goal_strict_put(requirement, "id", " r1 "),
      ]),
      goal_strict_put(payload, "requirements", [
        goal_strict_put(requirement, "criterion", " done "),
      ]),
    ] {
    goal_strict_reject_records([
      goal_strict_put(genesis, "payload", changed_payload),
    ])
  }
}

///|
test "mooncode_goal_store strict replay: rejects timestamps and outer recorded_at mismatches" {
  let genesis = goal_store_replay_genesis()
  let payload = goal_strict_field(genesis, "payload")
  let mut constructor_rejected = false
  ignore(
    mooncode_goal_genesis(
      mooncode_protocol_version(),
      "session",
      "goal",
      "objective",
      -1,
      goal_store_test_budget(),
      goal_store_test_requirements(),
    ),
  ) catch {
    InvalidGoalGenesis(_) => constructor_rejected = true
    _ => ()
  }
  assert_true(constructor_rejected)
  let negative_payload = goal_strict_put(
    goal_strict_put(payload, "timestamp", -1),
    "recorded_at",
    -1,
  )
  goal_strict_reject_records([
    goal_strict_put(genesis, "payload", negative_payload),
  ])
  goal_strict_reject_records([goal_strict_put(genesis, "recorded_at", 124)])
  let event = goal_store_replay_requirement_event(
    124,
    "r1",
    @mooncode_core.Proven,
    ["evidence:r1"],
  )
  goal_strict_reject_records([
    genesis,
    goal_strict_put(goal_store_replay_event_record(event), "recorded_at", 125),
  ])
}
