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
  AuthorityConflict
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
  let budget = { ..budget, tokens_used: 0, turns_used: 0, wall_time_used: 0 }
  let requirements = requirements.map(fn(r) {
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
fn mooncode_replay_goal_records(
  records : Array[Json],
  session_id : String,
  expected_goal_id? : String? = None,
) -> @mooncode_core.Goal? raise {
  mooncode_goal_require_canonical_identity("session_id", session_id)
  let mut winner = None
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
    mooncode_goal_require_canonical_identity(
      "envelope_session", envelope_session,
    )
    mooncode_goal_require_canonical_identity("payload_session", payload_session)
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
    if winner is Some(_) {
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
    if goal_json_int(payload, "recorded_at") != timestamp {
      raise InvalidGoalGenesis("recorded_at/timestamp mismatch")
    }
    let budget_json = goal_json_object(payload, "budget")
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
          if mooncode_json_string(item, "state", default="") != "unproven" {
            raise InvalidGoalGenesis("requirement state")
          }
          match goal_json_object(item, "evidence") {
            Array(e) if e.is_empty() => ()
            _ => raise InvalidGoalGenesis("requirement evidence")
          }
          requirements.push({
            id: mooncode_json_string(item, "id", default=""),
            criterion: mooncode_json_string(item, "criterion", default=""),
            state: @mooncode_core.Unproven,
            evidence_refs: [],
          })
        }
      _ => raise InvalidGoalGenesis("requirements must be array")
    }
    let goal = @mooncode_core.new_goal(
      gid,
      payload_session,
      mooncode_json_string(payload, "objective", default=""),
      timestamp,
      budget,
      requirements,
    ) catch {
      _ => raise InvalidGoalGenesis("invalid durable goal genesis")
    }
    winner = Some(goal)
  }
  winner
}

///|
async fn mooncode_replay_goal(
  book_root : String,
  session_id : String,
) -> @mooncode_core.Goal? {
  mooncode_goal_require_canonical_identity("session_id", session_id)
  mooncode_replay_goal_records(
    mooncode_read_session_journal(book_root, session_id),
    session_id,
  )
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
  let lifecycle_gate = mooncode_open_session_lifecycle_gate(
    book_root, session_id,
  )
  defer lifecycle_gate.close()
  lifecycle_gate.lock(Shared)
  defer lifecycle_gate.unlock()
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Exclusive)
  defer session_lock.unlock()
  mooncode_require_active_session_state_locked(
    book_root,
    session_id,
    allow_create=true,
  )
  let records = mooncode_goal_authority_records_locked(book_root, session_id)
  let authority = mooncode_goal_authority_snapshot(records, session_id)
  if mooncode_goal_authority_is_dual(authority) ||
    authority.runtime.genesis is Some(_) {
    return AuthorityConflict
  }
  match authority.legacy {
    Some(existing) =>
      if mooncode_same_creation_intent(existing, expected) {
        return Idempotent(existing)
      } else {
        return Conflict(existing)
      }
    None => ()
  }
  let appended = mooncode_append_session_journal_once_locked(
    book_root,
    session_id,
    mooncode_journal_goal_event(),
    genesis,
  )
  let committed = mooncode_goal_authority_records_locked(book_root, session_id)
  let winner = mooncode_goal_authority_snapshot(committed, session_id)
  if mooncode_goal_authority_is_dual(winner) ||
    winner.runtime.genesis is Some(_) {
    return AuthorityConflict
  }
  guard winner.legacy is Some(goal) else {
    raise InvalidGoalGenesis("genesis disappeared")
  }
  if mooncode_same_creation_intent(goal, expected) {
    if appended {
      Created(goal)
    } else {
      Idempotent(goal)
    }
  } else {
    Conflict(goal)
  }
}
