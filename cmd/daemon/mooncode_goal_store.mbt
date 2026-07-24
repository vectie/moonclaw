///|
fn mooncode_goal_require_canonical_identity(
  field : String,
  raw : String,
) -> Unit raise {
  if raw.is_empty() || raw.trim() != raw {
    raise InvalidGoalGenesis(
      "invalid " + field + ": must be nonempty canonical identity",
    )
  }
}

///|
/// Result of creating a daemon-local durable goal genesis.
priv enum MoonCodeGoalCreateResult {
  Created(@mooncode_core.Goal)
  Idempotent(@mooncode_core.Goal)
  Conflict(@mooncode_core.Goal)
}

///|
/// Result of atomically applying a daemon-local durable goal event.
priv enum MoonCodeGoalMutationResult {
  GoalMutationApplied(@mooncode_core.Goal)
  GoalMutationIdempotent(@mooncode_core.Goal)
  GoalMutationConflict(@mooncode_core.Goal)
  GoalMutationRejected(@mooncode_core.Goal)
}

///|
priv suberror MoonCodeGoalStoreError {
  InvalidGoalGenesis(String)
}

///|
fn mooncode_goal_genesis_id() -> String {
  "goal-genesis-v1"
}

///|
fn mooncode_goal_genesis_kind() -> String {
  "mooncode.goal.created.v1"
}

///|
fn mooncode_goal_genesis(
  protocol : String,
  session_id : String,
  goal_id : String,
  objective : String,
  created_at : Int,
  budget : @mooncode_core.GoalBudget,
  requirements : Array[@mooncode_core.GoalRequirement],
) -> Json raise {
  guard protocol == mooncode_protocol_version() else {
    raise InvalidGoalGenesis("unsupported protocol")
  }
  mooncode_goal_require_canonical_identity("objective", objective)
  if created_at < 0 {
    raise InvalidGoalGenesis("invalid timestamp: must be nonnegative")
  }
  let budget = { ..budget, tokens_used: 0, turns_used: 0, wall_time_used: 0 }
  let requirements = requirements.map(fn(r) raise {
    mooncode_goal_require_canonical_identity("requirement id", r.id)
    mooncode_goal_require_canonical_identity("criterion", r.criterion)
    { ..r, state: @mooncode_core.Unproven, evidence_refs: [] }
  })
  let goal = @mooncode_core.new_goal(
    goal_id, session_id, objective, created_at, budget, requirements,
  ) catch {
    _ => raise InvalidGoalGenesis("invalid goal genesis")
  }
  {
    "id": mooncode_goal_genesis_id(),
    "kind": mooncode_goal_genesis_kind(),
    "protocol": protocol,
    "session_id": goal.session_id,
    "goal_id": goal.id,
    "objective": goal.objective,
    "recorded_at": created_at,
    "timestamp": created_at,
    "budget": {
      "token_limit": match goal.budget.token_limit {
        Some(v) => v.to_json()
        None => Json::null()
      },
      "turn_limit": match goal.budget.turn_limit {
        Some(v) => v.to_json()
        None => Json::null()
      },
      "wall_time_limit": match goal.budget.wall_time_limit {
        Some(v) => v.to_json()
        None => Json::null()
      },
      "tokens_used": 0,
      "turns_used": 0,
      "wall_time_used": 0,
    },
    "requirements": requirements.map(fn(r) {
      (
        {
          "id": r.id,
          "criterion": r.criterion,
          "state": "unproven",
          "evidence": Json::array([]),
        } : Json)
    }),
  }
}

///|
fn goal_checked_int(n : Double, key : String) -> Int raise {
  // Check the value in floating point before the deliberately-last conversion:
  // Number::to_int truncates and saturates, which is not valid journal decoding.
  // NaN fails equality; infinities necessarily fail the bounded-range checks.
  if n != n || n.trunc() != n || n < -2147483648.0 || n > 2147483647.0 {
    raise InvalidGoalGenesis("invalid integer `\{key}`")
  }
  n.to_int()
}

///|
fn goal_json_int(json : Json, key : String) -> Int raise {
  match mooncode_journal_json_field(json, key) {
    Some(Number(n, ..)) => goal_checked_int(n, key)
    _ => raise InvalidGoalGenesis("missing integer `\{key}`")
  }
}

///|
fn goal_json_optional_int(json : Json, key : String) -> Int? raise {
  match mooncode_journal_json_field(json, key) {
    Some(Null) => None
    Some(Number(n, ..)) => Some(goal_checked_int(n, key))
    _ => raise InvalidGoalGenesis("invalid limit `\{key}`")
  }
}

///|
fn goal_json_object(json : Json, key : String) -> Json raise {
  match mooncode_journal_json_field(json, key) {
    Some(value) => value
    None => raise InvalidGoalGenesis("missing `\{key}`")
  }
}

///|
fn goal_json_require_exact_keys(
  json : Json,
  expected : Array[String],
  label : String,
) -> Unit raise {
  match json {
    Object(entries) => {
      guard entries.length() == expected.length() else {
        raise InvalidGoalGenesis("invalid " + label + " object membership")
      }
      for key in expected {
        guard entries.get(key) is Some(_) else {
          raise InvalidGoalGenesis("invalid " + label + " object membership")
        }
      }
    }
    _ => raise InvalidGoalGenesis("invalid " + label + " object")
  }
}

///|
priv struct MoonCodeGoalReplayState {
  genesis : @mooncode_core.Goal
  current : @mooncode_core.Goal
  events : Map[String, @mooncode_core.GoalEvent]
}

///|
fn mooncode_replay_goal_records_detailed(
  records : Array[Json],
  session_id : String,
  expected_goal_id? : String? = None,
) -> MoonCodeGoalReplayState? raise {
  mooncode_goal_require_canonical_identity("session_id", session_id)
  // Reduce ordinary Goal state first. Supervisor records are validated against
  // the resulting Goal below, avoiding recursive detailed replay.
  let mut replay : MoonCodeGoalReplayState? = None
  for envelope in records {
    if mooncode_json_string(envelope, "record_kind", default="") !=
      mooncode_journal_event() {
      continue
    }
    let payload = goal_json_object(envelope, "payload")
    let envelope_record_id = mooncode_json_string(
      envelope,
      "record_id",
      default="",
    )
    let canonical_record_id = mooncode_journal_goal_event() +
      ":" +
      mooncode_goal_genesis_id()
    let envelope_session = mooncode_json_string(
      envelope,
      "session_id",
      default="",
    )
    let payload_session = mooncode_json_string(
      payload,
      "session_id",
      default="",
    )
    let kind = mooncode_json_string(payload, "kind", default="")
    let reserved_id = mooncode_json_string(payload, "id", default="") ==
      mooncode_goal_genesis_id()
    let goal_kind = kind.has_prefix("mooncode.goal.")
    let reserved_envelope_id = envelope_record_id == canonical_record_id
    if !reserved_envelope_id && !reserved_id && !goal_kind {
      continue
    }
    if kind.has_prefix("mooncode.goal.supervisor.") {
      let state = match replay {
        Some(state) => state
        None => raise InvalidGoalGenesis("supervisor event before genesis")
      }
      if kind == mooncode_goal_supervisor_lease_v1_kind() {
        let lease = mooncode_goal_supervisor_lease_decode(envelope)
        if lease.session_id != state.current.session_id ||
          lease.goal_id != state.current.id ||
          lease.goal_run_id != state.current.run_id {
          raise InvalidGoalGenesis("supervisor lease goal mismatch")
        }
        continue
      }
      if kind == mooncode_goal_supervisor_lease_renewed_v1_kind() {
        let renewal = mooncode_goal_supervisor_lease_renewal_decode(envelope)
        if renewal.session_id != state.current.session_id ||
          renewal.goal_id != state.current.id ||
          renewal.goal_run_id != state.current.run_id {
          raise InvalidGoalGenesis("supervisor lease renewal goal mismatch")
        }
        continue
      }
      raise InvalidGoalGenesis("unknown supervisor event kind")
    }
    if goal_kind && kind != mooncode_goal_genesis_kind() {
      mooncode_goal_require_canonical_identity(
        "envelope_session", envelope_session,
      )
      if envelope_session != session_id {
        raise InvalidGoalGenesis("goal event session mismatch")
      }
      let state = match replay {
        Some(state) => state
        None => raise InvalidGoalGenesis("goal event before genesis")
      }
      let event = match @mooncode_core.decode_goal_event_v1(payload) {
        Ok(event) => event
        Err(_) => raise InvalidGoalGenesis("invalid goal event")
      }
      if goal_json_int(envelope, "recorded_at") !=
        @mooncode_core.goal_event_recorded_at(event) {
        raise InvalidGoalGenesis("goal event recorded_at mismatch")
      }
      let event_id = @mooncode_core.goal_event_id(event)
      if envelope_record_id != mooncode_journal_goal_event() + ":" + event_id {
        raise InvalidGoalGenesis("invalid goal event identity")
      }
      match state.events.get(event_id) {
        Some(mapped) => {
          if mapped == event {
            continue
          }
          raise InvalidGoalGenesis("conflicting duplicate goal event")
        }
        None => ()
      }
      let next = @mooncode_core.reduce_goal(state.current, event)
      if next == state.current {
        raise InvalidGoalGenesis("invalid goal event transition")
      }
      state.events[event_id] = event
      replay = Some({ ..state, current: next })
      continue
    }
    mooncode_goal_require_canonical_identity(
      "envelope_session", envelope_session,
    )
    mooncode_goal_require_canonical_identity("payload_session", payload_session)
    goal_json_require_exact_keys(
      payload,
      [
        "id", "kind", "protocol", "session_id", "goal_id", "objective", "recorded_at",
        "timestamp", "budget", "requirements",
      ],
      "goal genesis payload",
    )
    if kind != mooncode_goal_genesis_kind() {
      raise InvalidGoalGenesis("unsupported goal event")
    }
    if !reserved_id || envelope_record_id != canonical_record_id {
      raise InvalidGoalGenesis("invalid goal genesis identity")
    }
    if envelope_session != session_id ||
      payload_session != session_id ||
      envelope_session != payload_session {
      raise InvalidGoalGenesis("goal genesis session mismatch")
    }
    if replay is Some(_) {
      raise InvalidGoalGenesis("duplicate goal genesis")
    }
    let gid = mooncode_json_string(payload, "goal_id", default="")
    mooncode_goal_require_canonical_identity("gid", gid)
    if gid.is_empty() {
      raise InvalidGoalGenesis("goal genesis identity mismatch")
    }
    match expected_goal_id {
      Some(expected) if gid != expected =>
        raise InvalidGoalGenesis("goal genesis identity mismatch")
      _ => ()
    }
    if mooncode_json_string(payload, "protocol", default="") !=
      mooncode_protocol_version() {
      raise InvalidGoalGenesis("protocol mismatch")
    }
    let timestamp = goal_json_int(payload, "timestamp")
    if timestamp < 0 {
      raise InvalidGoalGenesis("timestamp must be nonnegative")
    }
    if goal_json_int(payload, "recorded_at") != timestamp ||
      goal_json_int(envelope, "recorded_at") != timestamp {
      raise InvalidGoalGenesis("recorded_at/timestamp mismatch")
    }
    let objective = mooncode_json_string(payload, "objective", default="")
    mooncode_goal_require_canonical_identity("objective", objective)
    let budget_json = goal_json_object(payload, "budget")
    goal_json_require_exact_keys(
      budget_json,
      [
        "token_limit", "turn_limit", "wall_time_limit", "tokens_used", "turns_used",
        "wall_time_used",
      ],
      "goal genesis budget",
    )
    let budget : @mooncode_core.GoalBudget = {
      token_limit: goal_json_optional_int(budget_json, "token_limit"),
      turn_limit: goal_json_optional_int(budget_json, "turn_limit"),
      wall_time_limit: goal_json_optional_int(budget_json, "wall_time_limit"),
      tokens_used: goal_json_int(budget_json, "tokens_used"),
      turns_used: goal_json_int(budget_json, "turns_used"),
      wall_time_used: goal_json_int(budget_json, "wall_time_used"),
    }
    if budget.tokens_used != 0 ||
      budget.turns_used != 0 ||
      budget.wall_time_used != 0 {
      raise InvalidGoalGenesis("genesis usage must be zero")
    }
    let requirements : Array[@mooncode_core.GoalRequirement] = []
    match goal_json_object(payload, "requirements") {
      Array(items) =>
        for item in items {
          goal_json_require_exact_keys(
            item,
            ["id", "criterion", "state", "evidence"],
            "goal requirement",
          )
          let requirement_id = mooncode_json_string(item, "id", default="")
          let criterion = mooncode_json_string(item, "criterion", default="")
          mooncode_goal_require_canonical_identity(
            "requirement id", requirement_id,
          )
          mooncode_goal_require_canonical_identity("criterion", criterion)
          if mooncode_json_string(item, "state", default="") != "unproven" {
            raise InvalidGoalGenesis("requirement state")
          }
          match goal_json_object(item, "evidence") {
            Array(e) if e.is_empty() => ()
            _ => raise InvalidGoalGenesis("requirement evidence")
          }
          requirements.push({
            id: requirement_id,
            criterion,
            state: @mooncode_core.Unproven,
            evidence_refs: [],
          })
        }
      _ => raise InvalidGoalGenesis("requirements must be array")
    }
    let goal = @mooncode_core.new_goal(
      gid, payload_session, objective, timestamp, budget, requirements,
    ) catch {
      _ => raise InvalidGoalGenesis("invalid durable goal genesis")
    }
    replay = Some({ genesis: goal, current: goal, events: {} })
  }
  match replay {
    Some(state) => {
      let _ = mooncode_goal_supervisor_lease_replay(records, state.current)
    }
    None => ()
  }
  replay
}

///|
fn mooncode_replay_goal_records(
  records : Array[Json],
  session_id : String,
  expected_goal_id? : String? = None,
) -> @mooncode_core.Goal? raise {
  mooncode_replay_goal_records_detailed(records, session_id, expected_goal_id~).map(fn(
      state,
    ) {
      state.current
    },
  )
}

///|
async fn mooncode_replay_goal_detailed(
  book_root : String,
  session_id : String,
) -> MoonCodeGoalReplayState? {
  mooncode_goal_require_canonical_identity("session_id", session_id)
  mooncode_replay_goal_records_detailed(
    mooncode_read_session_journal(book_root, session_id),
    session_id,
  )
}

///|
async fn mooncode_replay_goal(
  book_root : String,
  session_id : String,
) -> @mooncode_core.Goal? {
  mooncode_replay_goal_detailed(book_root, session_id).map(fn(state) {
    state.current
  })
}

///|
fn mooncode_same_creation_intent(
  winner : @mooncode_core.Goal,
  expected : @mooncode_core.Goal,
) -> Bool {
  winner.id == expected.id &&
  winner.session_id == expected.session_id &&
  winner.objective == expected.objective &&
  winner.budget == expected.budget &&
  winner.requirements == expected.requirements
}

///|
async fn mooncode_apply_goal_event(
  book_root : String,
  session_id : String,
  goal_id : String,
  raw : Json,
) -> MoonCodeGoalMutationResult {
  mooncode_goal_require_canonical_identity("session id", session_id)
  mooncode_goal_require_canonical_identity("goal id", goal_id)
  let event = match @mooncode_core.decode_goal_event_v1(raw) {
    Ok(event) => event
    Err(_) => raise InvalidGoalGenesis("invalid goal event")
  }
  let canonical_payload = @mooncode_core.goal_event_to_json(event)
  let event_id = @mooncode_core.goal_event_id(event)
  if event_id == mooncode_goal_genesis_id() {
    raise InvalidGoalGenesis("reserved goal event identity")
  }
  guard mooncode_replay_goal_detailed(book_root, session_id) is Some(_) else {
    raise InvalidGoalGenesis("goal genesis is missing")
  }
  mooncode_session_journal_transaction(book_root, session_id, fn(
    records,
  ) raise {
    let state = match
      mooncode_replay_goal_records_detailed(
        records,
        session_id,
        expected_goal_id=Some(goal_id),
      ) {
      Some(state) => state
      None => raise InvalidGoalGenesis("goal genesis is missing")
    }
    let current = state.current
    match state.events.get(event_id) {
      Some(existing) =>
        if existing == event {
          NoAppend(GoalMutationIdempotent(current))
        } else {
          NoAppend(GoalMutationConflict(current))
        }
      None => {
        if mooncode_goal_supervisor_event_record_exists(records, event_id) {
          return NoAppend(GoalMutationConflict(current))
        }
        let next = @mooncode_core.reduce_goal(current, event)
        if next == current {
          NoAppend(GoalMutationRejected(current))
        } else {
          Append(
            mooncode_journal_goal_event(),
            canonical_payload,
            GoalMutationApplied(next),
          )
        }
      }
    }
  })
}

///|
async fn mooncode_create_goal(
  book_root : String,
  protocol : String,
  session_id : String,
  goal_id : String,
  objective : String,
  created_at : Int,
  budget : @mooncode_core.GoalBudget,
  requirements : Array[@mooncode_core.GoalRequirement],
) -> MoonCodeGoalCreateResult {
  mooncode_goal_require_canonical_identity("session_id", session_id)
  mooncode_goal_require_canonical_identity("goal_id", goal_id)
  let genesis = mooncode_goal_genesis(
    protocol, session_id, goal_id, objective, created_at, budget, requirements,
  )
  let envelope : Json = {
    "record_kind": mooncode_journal_goal_event(),
    "record_id": mooncode_journal_goal_event() +
    ":" +
    mooncode_goal_genesis_id(),
    "session_id": session_id,
    "recorded_at": created_at,
    "payload": genesis,
  }
  guard mooncode_replay_goal_records(
      [envelope],
      session_id,
      expected_goal_id=Some(goal_id),
    )
    is Some(expected) else {
    raise InvalidGoalGenesis("invalid expected genesis")
  }
  mooncode_session_journal_transaction(book_root, session_id, fn(
    records,
  ) raise {
    match mooncode_replay_goal_records_detailed(records, session_id) {
      Some(existing) =>
        if mooncode_same_creation_intent(existing.genesis, expected) {
          NoAppend(Idempotent(existing.current))
        } else {
          NoAppend(Conflict(existing.current))
        }
      None => Append(mooncode_journal_goal_event(), genesis, Created(expected))
    }
  })
}
