///|
/// Reserved journal namespace for durable goal-supervisor lease records.
///
/// This file intentionally owns the namespace independently from the core Goal
/// reducer: leases are daemon-store coordination state, not Goal state.
fn mooncode_goal_supervisor_lease_v1_kind() -> String {
  "mooncode.goal.supervisor.lease.v1"
}

///|
priv struct MoonCodeGoalSupervisorLease {
  session_id : String
  goal_id : String
  goal_run_id : Int
  owner_id : String
  recorded_at : Int
  lease_expires_at : Int
  fence_token : Int
  event_id : String
} derive(Eq, Debug)

///|
/// Store-level outcomes always carry the projection that made the decision.
priv enum MoonCodeGoalSupervisorLeaseResult {
  SupervisorLeaseAcquired(MoonCodeGoalSupervisorLease)
  SupervisorLeaseIdempotent(MoonCodeGoalSupervisorLease)
  SupervisorLeaseConflict(MoonCodeGoalSupervisorLease)
  SupervisorLeaseRejected(MoonCodeGoalSupervisorLease?)
} derive(Eq, Debug)

///|
/// Canonical durable supervisor lease payload.
fn mooncode_goal_supervisor_lease_v1(
  id : String,
  protocol : String,
  session_id : String,
  goal_id : String,
  goal_run_id : Int,
  owner_id : String,
  recorded_at : Int,
  lease_expires_at : Int,
  fence_token : Int,
) -> Json raise {
  mooncode_goal_require_canonical_identity("lease id", id)
  guard protocol == mooncode_protocol_version() else {
    raise InvalidGoalGenesis("unsupported protocol")
  }
  mooncode_goal_require_canonical_identity("session id", session_id)
  mooncode_goal_require_canonical_identity("goal id", goal_id)
  mooncode_goal_require_canonical_identity("owner id", owner_id)
  guard goal_run_id >= 0 else {
    raise InvalidGoalGenesis("invalid goal run id: must be nonnegative")
  }
  guard recorded_at >= 0 else {
    raise InvalidGoalGenesis("invalid timestamp: must be nonnegative")
  }
  guard fence_token > 0 else {
    raise InvalidGoalGenesis("invalid fence token: must be positive")
  }
  guard lease_expires_at > recorded_at else {
    raise InvalidGoalGenesis("invalid lease expiry")
  }
  {
    "id": id,
    "kind": mooncode_goal_supervisor_lease_v1_kind(),
    "protocol": protocol,
    "session_id": session_id,
    "goal_id": goal_id,
    "goal_run_id": goal_run_id,
    "owner_id": owner_id,
    "recorded_at": recorded_at,
    "lease_expires_at": lease_expires_at,
    "fence_token": fence_token,
  }
}

///|
fn mooncode_goal_supervisor_lease_decode(
  envelope : Json,
) -> MoonCodeGoalSupervisorLease raise {
  let payload = goal_json_object(envelope, "payload")
  guard mooncode_json_string(envelope, "record_kind", default="") ==
    mooncode_journal_event() else {
    raise InvalidGoalGenesis("invalid supervisor lease record kind")
  }
  let id = mooncode_json_string(payload, "id", default="")
  let envelope_record_id = mooncode_json_string(
    envelope,
    "record_id",
    default="",
  )
  guard envelope_record_id == mooncode_journal_goal_event() + ":" + id else {
    raise InvalidGoalGenesis("invalid supervisor lease record id")
  }
  let envelope_session_id = mooncode_json_string(
    envelope,
    "session_id",
    default="",
  )
  let envelope_recorded_at = goal_json_int(envelope, "recorded_at")
  goal_json_require_exact_keys(
    payload,
    [
      "id", "kind", "protocol", "session_id", "goal_id", "goal_run_id", "owner_id",
      "recorded_at", "lease_expires_at", "fence_token",
    ],
    "supervisor lease",
  )
  let kind = mooncode_json_string(payload, "kind", default="")
  let protocol = mooncode_json_string(payload, "protocol", default="")
  let session_id = mooncode_json_string(payload, "session_id", default="")
  let goal_id = mooncode_json_string(payload, "goal_id", default="")
  let goal_run_id = goal_json_int(payload, "goal_run_id")
  let owner_id = mooncode_json_string(payload, "owner_id", default="")
  let recorded_at = goal_json_int(payload, "recorded_at")
  let lease_expires_at = goal_json_int(payload, "lease_expires_at")
  let fence_token = goal_json_int(payload, "fence_token")
  ignore(
    mooncode_goal_supervisor_lease_v1(
      id, protocol, session_id, goal_id, goal_run_id, owner_id, recorded_at, lease_expires_at,
      fence_token,
    ),
  )
  guard kind == mooncode_goal_supervisor_lease_v1_kind() else {
    raise InvalidGoalGenesis("invalid supervisor lease kind")
  }
  guard envelope_record_id == mooncode_journal_goal_event() + ":" + id else {
    raise InvalidGoalGenesis("supervisor lease record identity mismatch")
  }
  guard envelope_session_id == session_id else {
    raise InvalidGoalGenesis("supervisor lease session mismatch")
  }
  guard envelope_recorded_at == recorded_at else {
    raise InvalidGoalGenesis("supervisor lease timestamp mismatch")
  }
  {
    session_id,
    goal_id,
    goal_run_id,
    owner_id,
    recorded_at,
    lease_expires_at,
    fence_token,
    event_id: id,
  }
}

///|
/// Pure replay of supervisor leases. The journal order is authoritative.
/// Replays durable lease acquisitions. Duplicate event identities are checked
/// globally (not merely against the adjacent record), so transaction retries
/// cannot conceal a conflicting acquisition later in the journal.
fn mooncode_goal_supervisor_lease_replay(
  records : Array[Json],
  goal : @mooncode_core.Goal,
) -> (MoonCodeGoalSupervisorLease?, Int) raise {
  let mut genesis_seen = false
  let mut current : MoonCodeGoalSupervisorLease? = None
  let mut maximum_fence = 0
  let seen : Map[String, MoonCodeGoalSupervisorLease] = {}
  for envelope in records {
    if mooncode_json_string(envelope, "record_kind", default="") !=
      mooncode_journal_event() {
      continue
    }
    let payload = goal_json_object(envelope, "payload")
    let kind = mooncode_json_string(payload, "kind", default="")
    if kind == mooncode_goal_genesis_kind() {
      genesis_seen = true
    } else if kind == mooncode_goal_supervisor_lease_v1_kind() {
      guard genesis_seen else {
        raise InvalidGoalGenesis("supervisor event before goal genesis")
      }
      let lease = mooncode_goal_supervisor_lease_decode(envelope)
      guard lease.session_id == goal.session_id else {
        raise InvalidGoalGenesis("supervisor lease session mismatch")
      }
      guard lease.goal_id == goal.id else {
        raise InvalidGoalGenesis("supervisor lease goal mismatch")
      }
      if lease.goal_run_id > goal.run_id {
        raise InvalidGoalGenesis("supervisor lease goal run mismatch")
      }
      match seen.get(lease.event_id) {
        Some(previous) =>
          if previous == lease {
            continue
          } else {
            raise InvalidGoalGenesis(
              "conflicting duplicate supervisor lease event",
            )
          }
        None => ()
      }
      guard maximum_fence != 2147483647 &&
        lease.fence_token == maximum_fence + 1 else {
        raise InvalidGoalGenesis("invalid supervisor lease fence token")
      }
      seen[lease.event_id] = lease
      maximum_fence = lease.fence_token
      if lease.goal_run_id == goal.run_id {
        current = Some(lease)
      }
    }
  }
  (current, maximum_fence)
}

///|
fn mooncode_goal_supervisor_lease_find(
  records : Array[Json],
  event_id : String,
) -> MoonCodeGoalSupervisorLease? raise {
  for envelope in records {
    if mooncode_json_string(envelope, "record_kind", default="") ==
      mooncode_journal_event() {
      let payload = goal_json_object(envelope, "payload")
      if mooncode_json_string(payload, "kind", default="") ==
        mooncode_goal_supervisor_lease_v1_kind() &&
        mooncode_json_string(payload, "id", default="") == event_id {
        return Some(mooncode_goal_supervisor_lease_decode(envelope))
      }
    }
  }
  None
}

///|
fn mooncode_goal_supervisor_lease_matches_request(
  lease : MoonCodeGoalSupervisorLease,
  session_id : String,
  goal_id : String,
  goal_run_id : Int,
  owner_id : String,
  event_id : String,
  recorded_at : Int,
  lease_expires_at : Int,
) -> Bool {
  lease.event_id == event_id &&
  lease.owner_id == owner_id &&
  lease.session_id == session_id &&
  lease.goal_id == goal_id &&
  lease.goal_run_id == goal_run_id &&
  lease.recorded_at == recorded_at &&
  lease.lease_expires_at == lease_expires_at
}

///|
async fn mooncode_goal_supervisor_lease_acquire(
  book_root : String,
  session_id : String,
  goal_id : String,
  owner_id : String,
  event_id : String,
  now : Int,
  lease_expires_at : Int,
) -> MoonCodeGoalSupervisorLeaseResult {
  mooncode_goal_require_canonical_identity("session id", session_id)
  mooncode_goal_require_canonical_identity("goal id", goal_id)
  mooncode_goal_require_canonical_identity("owner id", owner_id)
  mooncode_goal_require_canonical_identity("event id", event_id)
  guard event_id != mooncode_goal_genesis_id() else {
    raise InvalidGoalGenesis("reserved event id")
  }
  guard now >= 0 else {
    raise InvalidGoalGenesis("invalid timestamp: must be nonnegative")
  }
  guard lease_expires_at > now else {
    raise InvalidGoalGenesis("invalid lease expiry")
  }
  let preflight = mooncode_replay_goal_detailed(book_root, session_id)
  let preflight_goal = match preflight {
    Some(value) => value.current
    None => raise InvalidGoalGenesis("missing goal genesis")
  }
  guard preflight_goal.id == goal_id else {
    raise InvalidGoalGenesis("goal id mismatch")
  }
  mooncode_session_journal_transaction(book_root, session_id, fn(
    records,
  ) raise {
    let locked = mooncode_replay_goal_records_detailed(records, session_id)
    let goal = match locked {
      Some(value) => value.current
      None => raise InvalidGoalGenesis("missing goal genesis")
    }
    guard goal.id == goal_id else {
      raise InvalidGoalGenesis("goal id mismatch")
    }
    let (current, maximum_fence) = mooncode_goal_supervisor_lease_replay(
      records, goal,
    )
    match mooncode_goal_supervisor_lease_find(records, event_id) {
      Some(existing) =>
        if mooncode_goal_supervisor_lease_matches_request(
            existing,
            session_id,
            goal_id,
            goal.run_id,
            owner_id,
            event_id,
            now,
            lease_expires_at,
          ) {
          return NoAppend(SupervisorLeaseIdempotent(existing))
        } else {
          return NoAppend(SupervisorLeaseConflict(existing))
        }
      None => ()
    }
    match current {
      Some(lease) if lease.lease_expires_at > now =>
        NoAppend(SupervisorLeaseConflict(lease))
      _ => {
        guard maximum_fence != 2147483647 else {
          raise InvalidGoalGenesis("invalid fence token: overflow")
        }
        let fence_token = maximum_fence + 1
        let payload = mooncode_goal_supervisor_lease_v1(
          event_id,
          mooncode_protocol_version(),
          session_id,
          goal_id,
          goal.run_id,
          owner_id,
          now,
          lease_expires_at,
          fence_token,
        )
        let lease = MoonCodeGoalSupervisorLease::{
          session_id,
          goal_id,
          goal_run_id: goal.run_id,
          owner_id,
          recorded_at: now,
          lease_expires_at,
          fence_token,
          event_id,
        }
        Append(
          mooncode_journal_goal_event(),
          payload,
          SupervisorLeaseAcquired(lease),
        )
      }
    }
  })
}
