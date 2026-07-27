///|
/// Durable goal genesis validation, including pure replay and disk-backed integration.
/// Repair ledger:
/// - Tuple destructuring is not accepted in the for binder and was moved into the loop body.
/// - Incomparable: the prior read-only design turn stopped at inspection; recovery required mutation.
/// - Optional limits are emitted as explicit JSON null. The compiler issue was that the read-only
///   Null constructor cannot be used for emission; the fix is Json::null().
/// - The torn journal sentinel proves padded replay rejected before the path was opened or repaired.
/// - Create now replays existing durable state before mutation; canonical concurrent creates remain
///   reconciled by append_once and post-replay. The preflight read and append are not one atomic lock
///   transaction, so a concurrent corrupt writer between them is explicitly deferred.
fn goal_store_test_budget() -> @mooncode_core.GoalBudget {
  {
    token_limit: None,
    turn_limit: Some(4),
    wall_time_limit: None,
    tokens_used: 0,
    turns_used: 0,
    wall_time_used: 0,
  }
}

///|
fn goal_store_test_requirements() -> Array[@mooncode_core.GoalRequirement] {
  [
    {
      id: "r1",
      criterion: "done",
      state: @mooncode_core.Unproven,
      evidence_refs: [],
    },
  ]
}

///|
fn goal_store_test_record(payload : Json) -> Json raise {
  {
    "record_kind": mooncode_journal_goal_event(),
    "record_id": mooncode_journal_goal_event() +
    ":" +
    mooncode_goal_genesis_id(),
    "session_id": "session",
    "recorded_at": goal_json_int64_value(
      goal_json_int64(payload, "recorded_at"),
    ),
    "payload": payload,
  }
}

///|
test "mooncode_goal_store: durable counters are strict and bounded" {
  let labels = [
    "token_limit", "turn_limit", "wall_time_limit", "tokens_used", "turns_used",
    "wall_time_used",
  ]
  for label in labels {
    let mut rejected = false
    ignore(goal_checked_int(0.5, label)) catch {
      InvalidGoalGenesis(_) => rejected = true
      _ => ()
    }
    assert_true(rejected)
  }

  for value in [1.0e20, -1.0e20] {
    let mut rejected = false
    ignore(goal_checked_int(value, "timestamp")) catch {
      InvalidGoalGenesis(_) => rejected = true
      _ => ()
    }
    assert_true(rejected)
  }

  for value in [0.0, 1.0, -1.0, 2147483647.0, -2147483648.0] {
    let mut accepted = true
    ignore(goal_checked_int(value, "timestamp")) catch {
      _ => accepted = false
    }
    assert_true(accepted)
  }

  let fractional : Json = { "value": 0.5 }
  let mut required_rejected = false
  ignore(goal_json_int(fractional, "value")) catch {
    InvalidGoalGenesis(_) => required_rejected = true
    _ => ()
  }
  assert_true(required_rejected)

  let mut optional_rejected = false
  ignore(goal_json_optional_int(fractional, "value")) catch {
    InvalidGoalGenesis(_) => optional_rejected = true
    _ => ()
  }
  assert_true(optional_rejected)
}

///|
test "mooncode_goal_store: durable timestamps preserve exact Int64 values" {
  let timestamp = 9007199254740993L
  let encoded = goal_json_int64_value(timestamp)
  assert_true(encoded is Number(_, repr=Some("9007199254740993")))
  assert_eq(goal_json_int64({ "value": encoded }, "value"), timestamp)
  assert_eq(goal_json_int64({ "value": Json::number(123.0) }, "value"), 123L)
  for
    value in [
      Json::number(0.0, repr="9223372036854775808"),
      Json::number(0.0, repr="-9223372036854775809"),
      Json::number(0.0, repr="1.5"),
      Json::number(0.5),
    ] {
    let mut rejected = false
    ignore(goal_json_int64({ "value": value }, "value")) catch {
      InvalidGoalGenesis(_) => rejected = true
      _ => ()
    }
    assert_true(rejected)
  }
  let payload = mooncode_goal_genesis(
    mooncode_protocol_version(),
    "session",
    "goal",
    "objective",
    timestamp,
    goal_store_test_budget(),
    goal_store_test_requirements(),
  )
  assert_eq(goal_json_int64(payload, "recorded_at"), timestamp)
  assert_eq(goal_json_int64(payload, "timestamp"), timestamp)
  assert_eq(
    mooncode_replay_goal_records([goal_store_test_record(payload)], "session").unwrap().created_at,
    timestamp,
  )
}

///|
test "mooncode_goal_store: reserved envelope id with ordinary payload is rejected" {
  let record : Json = {
    "record_kind": mooncode_journal_event(),
    "record_id": mooncode_journal_goal_event() +
    ":" +
    mooncode_goal_genesis_id(),
    "session_id": "session",
    "payload": { "id": "ordinary", "kind": "runtime.started.v1" },
  }
  let mut rejected = false
  ignore(mooncode_replay_goal_records([record], "session")) catch {
    InvalidGoalGenesis(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}

///|
test "mooncode_goal_store: genesis payload under other envelope id is rejected" {
  let payload = mooncode_goal_genesis(
    mooncode_protocol_version(),
    "session",
    "goal",
    "objective",
    123,
    goal_store_test_budget(),
    goal_store_test_requirements(),
  )
  let record : Json = {
    "record_kind": mooncode_journal_event(),
    "record_id": "event:other",
    "session_id": "session",
    "payload": payload,
  }
  let mut rejected = false
  ignore(mooncode_replay_goal_records([record], "session")) catch {
    InvalidGoalGenesis(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}

///|
test "mooncode_goal_store: create payload replays equally and deterministically" {
  let budget = goal_store_test_budget()
  let requirements = goal_store_test_requirements()
  let payload = mooncode_goal_genesis(
    mooncode_protocol_version(),
    "session",
    "goal",
    "objective",
    123,
    budget,
    requirements,
  )
  let records = [goal_store_test_record(payload)]
  let first = mooncode_replay_goal_records(
    records,
    "session",
    expected_goal_id=Some("goal"),
  ) catch {
    InvalidGoalGenesis(message) => fail(message)
    _ => fail("unexpected goal replay error")
  }
  let second = mooncode_replay_goal_records(
    records,
    "session",
    expected_goal_id=Some("goal"),
  )
  assert_true(first == second)
  let expected = @mooncode_core.new_goal(
    "goal", "session", "objective", 123, budget, requirements,
  )
  assert_true(first == Some(expected))
}

///|
test "mooncode_goal_store: unrelated ordinary event before genesis is ignored" {
  let unrelated : Json = {
    "record_kind": mooncode_journal_event(),
    "session_id": "session",
    "payload": { "id": "runtime-event", "kind": "runtime.started.v1" },
  }
  let genesis = mooncode_goal_genesis(
    mooncode_protocol_version(),
    "session",
    "goal",
    "objective",
    123,
    goal_store_test_budget(),
    goal_store_test_requirements(),
  )
  let replayed = mooncode_replay_goal_records(
    [unrelated, goal_store_test_record(genesis)],
    "session",
    expected_goal_id=Some("goal"),
  )
  assert_true(replayed is Some(_))
}

///|
test "mooncode_goal_store: requested goal mismatch fails closed" {
  let payload = mooncode_goal_genesis(
    mooncode_protocol_version(),
    "session",
    "winner",
    "objective",
    123,
    goal_store_test_budget(),
    goal_store_test_requirements(),
  )
  try {
    ignore(
      mooncode_replay_goal_records(
        [goal_store_test_record(payload)],
        "session",
        expected_goal_id=Some("requested"),
      ),
    )
    fail("expected identity rejection")
  } catch {
    InvalidGoalGenesis(_) => ()
    _ => fail("unexpected error")
  }
}

///|
test "mooncode_goal_store: duplicate genesis fails closed" {
  let payload = mooncode_goal_genesis(
    mooncode_protocol_version(),
    "session",
    "goal",
    "objective",
    123,
    goal_store_test_budget(),
    goal_store_test_requirements(),
  )
  let record = goal_store_test_record(payload)
  try {
    ignore(mooncode_replay_goal_records([record, record], "session"))
    fail("expected duplicate rejection")
  } catch {
    InvalidGoalGenesis(_) => ()
    _ => fail("unexpected error")
  }
}

///|
test "mooncode_goal_store: mutated genesis fields fail closed" {
  let cases : Array[(Json, String)] = [
    (
      @json.parse(
        "{\"id\":\"goal-genesis-v1\",\"kind\":\"mooncode.goal.unknown.v1\",\"protocol\":\"mooncode.v1\",\"session_id\":\"session\",\"goal_id\":\"goal\",\"objective\":\"objective\",\"recorded_at\":123,\"timestamp\":123,\"budget\":{\"token_limit\":null,\"turn_limit\":4,\"wall_time_limit\":null,\"tokens_used\":0,\"turns_used\":0,\"wall_time_used\":0},\"requirements\":[{\"id\":\"r1\",\"criterion\":\"done\",\"state\":\"unproven\",\"evidence\":[]}]}",
      ),
      "session",
    ),
    (
      @json.parse(
        "{\"id\":\"goal-genesis-v1\",\"kind\":\"mooncode.goal.created.v1\",\"protocol\":\"bad-protocol\",\"session_id\":\"session\",\"goal_id\":\"goal\",\"objective\":\"objective\",\"recorded_at\":123,\"timestamp\":123,\"budget\":{\"token_limit\":null,\"turn_limit\":4,\"wall_time_limit\":null,\"tokens_used\":0,\"turns_used\":0,\"wall_time_used\":0},\"requirements\":[{\"id\":\"r1\",\"criterion\":\"done\",\"state\":\"unproven\",\"evidence\":[]}]}",
      ),
      "session",
    ),
    (
      @json.parse(
        "{\"id\":\"goal-genesis-v1\",\"kind\":\"mooncode.goal.created.v1\",\"protocol\":\"mooncode.v1\",\"session_id\":\"session\",\"goal_id\":\"goal\",\"objective\":\"objective\",\"recorded_at\":123,\"timestamp\":124,\"budget\":{\"token_limit\":null,\"turn_limit\":4,\"wall_time_limit\":null,\"tokens_used\":0,\"turns_used\":0,\"wall_time_used\":0},\"requirements\":[{\"id\":\"r1\",\"criterion\":\"done\",\"state\":\"unproven\",\"evidence\":[]}]}",
      ),
      "session",
    ),
    (
      @json.parse(
        "{\"id\":\"goal-genesis-v1\",\"kind\":\"mooncode.goal.created.v1\",\"protocol\":\"mooncode.v1\",\"session_id\":\"other\",\"goal_id\":\"goal\",\"objective\":\"objective\",\"recorded_at\":123,\"timestamp\":123,\"budget\":{\"token_limit\":null,\"turn_limit\":4,\"wall_time_limit\":null,\"tokens_used\":0,\"turns_used\":0,\"wall_time_used\":0},\"requirements\":[{\"id\":\"r1\",\"criterion\":\"done\",\"state\":\"unproven\",\"evidence\":[]}]}",
      ),
      "session",
    ),
  ]
  for case in cases {
    let (payload, session) = case
    try {
      ignore(
        mooncode_replay_goal_records([goal_store_test_record(payload)], session),
      )
      fail("expected mutated payload rejection")
    } catch {
      InvalidGoalGenesis(_) => ()
      _ => fail("unexpected error")
    }
  }
}

///|
test "mooncode_goal_store: reserved genesis identities fail closed" {
  let payloads : Array[Json] = [
    { "id": "goal-genesis-v1" },
    { "id": "goal-genesis-v1", "kind": 1 },
    { "id": "goal-genesis-v1", "kind": "runtime.started.v1" },
    { "id": "mooncode.goal.unknown", "kind": "mooncode.goal.unknown.v1" },
  ]
  for payload in payloads {
    let record : Json = {
      "record_kind": mooncode_journal_event(),
      "session_id": "session",
      "payload": payload,
    }
    let mut rejected = false
    ignore(mooncode_replay_goal_records([record], "session")) catch {
      InvalidGoalGenesis(_) => rejected = true
      _ => fail("unexpected reserved genesis replay error")
    }
    assert_true(rejected)
  }
}

///|
test "mooncode_goal_store: envelope session mismatch fails closed" {
  let payload = mooncode_goal_genesis(
    mooncode_protocol_version(),
    "session",
    "goal",
    "objective",
    123,
    goal_store_test_budget(),
    goal_store_test_requirements(),
  )
  let record : Json = {
    "record_kind": mooncode_journal_goal_event(),
    "record_id": mooncode_journal_goal_event() +
    ":" +
    mooncode_goal_genesis_id(),
    "session_id": "other",
    "payload": payload,
  }
  try {
    ignore(mooncode_replay_goal_records([record], "session"))
    fail("expected envelope session rejection")
  } catch {
    InvalidGoalGenesis(_) => ()
    _ => fail("unexpected error")
  }
}

///|
async test "mooncode_goal_store: blank identities are rejected before append" {
  let cases = [(" session ", "goal"), ("session", " goal ")]
  for item in cases {
    let (session_id, goal_id) = item
    @fsx.with_temporary_directory("moonclaw-goal-store-blank-XXXXXX", async fn(
      root,
    ) {
      let mut rejected = false
      ignore(
        mooncode_create_goal(
          root,
          mooncode_protocol_version(),
          session_id,
          goal_id,
          "objective",
          123,
          goal_store_test_budget(),
          goal_store_test_requirements(),
        ),
      ) catch {
        InvalidGoalGenesis(_) => rejected = true
        _ => fail("unexpected goal create error")
      }
      assert_true(rejected)
      assert_true(mooncode_read_session_journal(root, session_id).is_empty())
    })
  }
}

///|
fn goal_store_replace_string(
  value : Json,
  field : String,
  replacement : String,
) -> Json {
  match value {
    Object(fields) => {
      let copied = fields.copy()
      copied[field] = replacement.to_json()
      Json::object(copied)
    }
    _ => value
  }
}

///|
test "mooncode_goal_store: fourth audit canonical identities reject padding" {
  let payload = mooncode_goal_genesis(
    mooncode_protocol_version(),
    "session",
    "goal",
    "objective",
    123,
    goal_store_test_budget(),
    goal_store_test_requirements(),
  )
  let canonical = goal_store_test_record(payload)
  let padded_envelope = goal_store_replace_string(
    canonical, "session_id", " session ",
  )
  let padded_payload = goal_store_replace_string(
    payload, "session_id", " session ",
  )
  let padded_goal = goal_store_replace_string(payload, "goal_id", " goal ")
  let cases = [
    (canonical, " session "),
    (padded_envelope, "session"),
    (goal_store_test_record(padded_payload), "session"),
    (goal_store_test_record(padded_goal), "session"),
  ]
  for item in cases {
    let (record, requested_session) = item
    try {
      ignore(mooncode_replay_goal_records([record], requested_session))
      fail("expected canonical identity rejection")
    } catch {
      InvalidGoalGenesis(_) => ()
      _ => fail("unexpected canonical identity error")
    }
  }
}

///|
async test "mooncode_goal_store: fourth audit create failures normalize before append" {
  let invalid_cases = [
    ("", goal_store_test_budget(), goal_store_test_requirements()),
    (
      "objective",
      {
        token_limit: None,
        turn_limit: Some(-1),
        wall_time_limit: None,
        tokens_used: 0,
        turns_used: 0,
        wall_time_used: 0,
      },
      goal_store_test_requirements(),
    ),
    ("objective", goal_store_test_budget(), []),
  ]
  for invalid_case in invalid_cases {
    let (objective, budget, requirements) = invalid_case
    @fsx.with_temporary_directory("moonclaw-goal-store-fourth-create-XXXXXX", async fn(
      root,
    ) {
      try {
        ignore(
          mooncode_create_goal(
            root,
            mooncode_protocol_version(),
            "session",
            "goal",
            objective,
            123,
            budget,
            requirements,
          ),
        )
        fail("expected invalid goal genesis")
      } catch {
        InvalidGoalGenesis(_) => ()
        _ => fail("unexpected goal create error")
      }
      assert_true(mooncode_read_session_journal(root, "session").is_empty())
    })
  }
}

///|
async test "mooncode_goal_store: fourth audit padded replay rejects before path access" {
  @fsx.with_temporary_directory("moonclaw-goal-store-fourth-replay-XXXXXX", async fn(
    root,
  ) {
    let path = mooncode_session_journal_path(root, "session")
    @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
    let sentinel = "{\"torn\":true"
    @fsx.write_to_file(path, sentinel)
    try {
      ignore(mooncode_replay_goal(root, " session "))
      fail("expected padded requested session rejection")
    } catch {
      InvalidGoalGenesis(message) =>
        assert_eq(
          message, "invalid session_id: must be nonempty canonical identity",
        )
      _ => fail("unexpected goal replay error")
    }
    assert_eq(@fsx.read_file(path), sentinel)
  })
}

///|
async test "mooncode_goal_store: corrupt existing journal rejects before append" {
  @fsx.with_temporary_directory("moonclaw-goal-store-preflight-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    let protocol = mooncode_protocol_version()
    let budget = goal_store_test_budget()
    let requirements = goal_store_test_requirements()
    let payload = mooncode_goal_genesis(
      protocol, session_id, "goal", "objective", 123, budget, requirements,
    )
    let path = mooncode_session_journal_path(root, session_id)
    @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
    let envelope = @moonlib_conversation.journal_record(
      sequence=1,
      record_kind=mooncode_journal_event(),
      record_id="event:other",
      session_id~,
      command_id="goal-genesis-v1",
      client_turn_id="",
      recorded_at=123,
      payload~,
    )
    @fsx.write_to_file(path, envelope.stringify() + "\n")
    let before = @fsx.read_file(path)
    assert_eq(mooncode_read_session_journal(root, session_id).length(), 1)
    try {
      ignore(
        mooncode_create_goal(
          root, protocol, session_id, "goal", "objective", 123, budget, requirements,
        ),
      )
      fail("expected corrupt existing journal rejection")
    } catch {
      InvalidGoalGenesis(_) => ()
      _ => fail("unexpected goal create error")
    }
    assert_eq(@fsx.read_file(path), before)
    assert_eq(mooncode_read_session_journal(root, session_id).length(), 1)
  })
}

///|
async test "mooncode_goal_store: durable create is created idempotent then conflict" {
  @fsx.with_temporary_directory("moonclaw-goal-store-XXXXXX", async fn(root) {
    let protocol = mooncode_protocol_version()
    let budget = goal_store_test_budget()
    let requirements = goal_store_test_requirements()
    let first = mooncode_create_goal(
      root, protocol, "session", "goal", "objective", 123, budget, requirements,
    )
    let goal = match first {
      Created(goal) => goal
      Idempotent(_) => abort("first create was idempotent")
      Conflict(_) => abort("first create conflicted")
      AuthorityConflict => abort("first create hit opposite authority")
    }
    assert_true(mooncode_replay_goal(root, "session") == Some(goal))
    let path = mooncode_session_journal_path(root, "session")
    let after_created = @fsx.read_file(path)
    let retry = mooncode_create_goal(
      root, protocol, "session", "goal", "objective", 124, budget, requirements,
    )
    match retry {
      Idempotent(retried) => {
        assert_true(retried == goal)
        assert_eq(retried.created_at, 123)
        assert_eq(retried.id, "goal")
      }
      Created(_) => abort("retry created another goal")
      Conflict(_) => abort("identical retry conflicted")
      AuthorityConflict => abort("retry hit opposite authority")
    }
    assert_eq(@fsx.read_file(path), after_created)
    let records = mooncode_read_session_journal(root, "session")
    assert_eq(
      mooncode_journal_entries(records, mooncode_journal_goal_event()).length(),
      1,
    )
    let conflict = mooncode_create_goal(
      root, protocol, "session", "other", "different", 124, budget, requirements,
    )
    match conflict {
      Conflict(existing) => assert_true(existing == goal)
      Created(_) => abort("conflict created another goal")
      Idempotent(_) => abort("different goal was idempotent")
      AuthorityConflict => abort("conflict hit opposite authority")
    }
    assert_eq(@fsx.read_file(path), after_created)
    let records = mooncode_read_session_journal(root, "session")
    assert_eq(
      mooncode_journal_entries(records, mooncode_journal_goal_event()).length(),
      1,
    )
    assert_true(mooncode_replay_goal(root, "session") == Some(goal))
  })
}

///|
async test "mooncode_goal_store: focused atomic mutation succeeds" {
  @fsx.with_temporary_directory("moonclaw-goal-atomic-applied-XXXXXX", async fn(
    root,
  ) {
    let created = mooncode_create_goal(
      root,
      mooncode_protocol_version(),
      "session",
      "goal",
      "objective",
      123,
      goal_store_test_budget(),
      goal_store_test_requirements(),
    )
    match created {
      Created(_) => ()
      Idempotent(_) => fail("expected created")
      Conflict(_) => fail("expected created")
      AuthorityConflict => fail("expected created")
    }
    let event : @mooncode_core.GoalEvent = @mooncode_core.RequirementUpdated(
      "atomic-applied",
      124,
      "r1",
      @mooncode_core.Proven,
      ["evidence"],
    )
    let next = match
      mooncode_apply_goal_event(
        root,
        "session",
        "goal",
        @mooncode_core.goal_event_to_json(event),
      ) {
      GoalMutationApplied(next) => next
      GoalMutationIdempotent(_) => fail("expected applied")
      GoalMutationConflict(_) => fail("expected applied")
      GoalMutationRejected(_) => fail("expected applied")
    }
    assert_eq(next.revision, 1)
    assert_true(mooncode_replay_goal(root, "session") == Some(next))
    let records = mooncode_read_session_journal(root, "session")
    assert_eq(records.length(), 2)
    assert_eq(goal_json_int(records[1], "recorded_at"), 124)
    assert_eq(
      goal_json_int(goal_json_object(records[1], "payload"), "recorded_at"),
      124,
    )
  })
}

///|

///|
async test "mooncode_goal_store: focused atomic mutation duplicate is idempotent" {
  @fsx.with_temporary_directory("moonclaw-goal-atomic-idempotent-XXXXXX", async fn(
    root,
  ) {
    let created = mooncode_create_goal(
      root,
      mooncode_protocol_version(),
      "session",
      "goal",
      "objective",
      123,
      goal_store_test_budget(),
      goal_store_test_requirements(),
    )
    match created {
      Created(_) => ()
      Idempotent(_) => fail("expected created")
      Conflict(_) => fail("expected created")
      AuthorityConflict => fail("expected created")
    }
    let event : @mooncode_core.GoalEvent = @mooncode_core.RequirementUpdated(
      "atomic-idempotent",
      124,
      "r1",
      @mooncode_core.Proven,
      ["evidence"],
    )
    let canonical_event = @mooncode_core.goal_event_to_json(event)
    let next = match
      mooncode_apply_goal_event(root, "session", "goal", canonical_event) {
      GoalMutationApplied(next) => next
      GoalMutationIdempotent(_) => fail("expected applied")
      GoalMutationConflict(_) => fail("expected applied")
      GoalMutationRejected(_) => fail("expected applied")
    }
    let path = mooncode_session_journal_path(root, "session")
    let before_retry = @fsx.read_file(path)
    let current = match
      mooncode_apply_goal_event(root, "session", "goal", canonical_event) {
      GoalMutationApplied(_) => fail("expected idempotent")
      GoalMutationIdempotent(current) => current
      GoalMutationConflict(_) => fail("expected idempotent")
      GoalMutationRejected(_) => fail("expected idempotent")
    }
    assert_true(current == next)
    assert_eq(@fsx.read_file(path), before_retry)
    assert_true(mooncode_replay_goal(root, "session") == Some(next))
  })
}

///|
async test "mooncode_goal_store: append_once stable retry ignores omitted timestamp" {
  @fsx.with_temporary_directory("moonclaw-goal-store-retry-XXXXXX", async fn(
    root,
  ) {
    let first : Json = {
      "id": "stable-retry",
      "kind": "runtime.test.v1",
      "recorded_at": 1,
    }
    assert_true(
      mooncode_append_session_journal_once(
        root,
        "session",
        mooncode_journal_event(),
        first,
      ),
    )
    let path = mooncode_session_journal_path(root, "session")
    let before_retry = @fsx.read_file(path)
    let retry : Json = { "id": "stable-retry", "kind": "runtime.test.v1" }
    assert_true(
      !mooncode_append_session_journal_once(
        root,
        "session",
        mooncode_journal_event(),
        retry,
      ),
    )
    assert_eq(@fsx.read_file(path), before_retry)
    assert_eq(mooncode_read_session_journal(root, "session").length(), 1)
  })
}
