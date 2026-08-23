///|
/// Reserved journal namespace for durable goal-supervisor lease records.
///
/// This file intentionally owns the namespace independently from the core Goal
/// reducer: leases are daemon-store coordination state, not Goal state.
fn mooncode_goal_supervisor_lease_v1_kind() -> String {
  "mooncode.goal.supervisor.lease.v1"
}

///|
/// Reserved lifecycle record kinds. Keeping these in the lease namespace makes
/// generic journal append reject them while lifecycle mutations remain under
/// the session-journal transaction lock.
fn mooncode_goal_supervisor_lease_renewed_v1_kind() -> String {
  "mooncode.goal.supervisor.lease-renewed.v1"
}

///|
fn mooncode_goal_supervisor_lease_validate_owner_fence(
  lease : MoonCodeGoalSupervisorLease?,
  owner_id : String,
  fence_token : Int,
  presented_lease_expires_at : Int64,
  now : Int64,
) -> Bool {
  match lease {
    Some(active) =>
      active.owner_id == owner_id &&
      active.fence_token == fence_token &&
      presented_lease_expires_at == active.lease_expires_at &&
      now >= 0 &&
      now < active.lease_expires_at
    None => false
  }
}

///|
priv struct MoonCodeGoalSupervisorLease {
  session_id : String
  goal_id : String
  goal_run_id : Int
  owner_id : String
  recorded_at : Int64
  lease_expires_at : Int64
  fence_token : Int
  event_id : String
} derive(Eq, Debug)

///|
/// A decoded durable renewal. Renewals retain the acquisition fence token and
/// identify the acquisition event they extend.
priv struct MoonCodeGoalSupervisorLeaseRenewal {
  session_id : String
  goal_id : String
  goal_run_id : Int
  owner_id : String
  recorded_at : Int64
  expected_lease_expires_at : Int64
  lease_expires_at : Int64
  fence_token : Int
  acquisition_event_id : String
  event_id : String
} derive(Eq, Debug)

///|
/// Canonical event identities are shared by acquisitions and renewals. Replay
/// keeps this tagged payload so nonadjacent exact duplicates can be ignored,
/// while changed or cross-kind reuse of an event id is rejected.
#warnings("-unused_value")
priv enum MoonCodeGoalSupervisorLeaseReplayEvent {
  ReplayAcquisition(MoonCodeGoalSupervisorLease)
  ReplayRenewal(MoonCodeGoalSupervisorLeaseRenewal)
  ReplayCheckpoint(MoonCodeGoalSupervisorCheckpointPayload)
} derive(Eq, Debug)

///|
/// Canonical durable renewal payload. The acquisition event and fence are
/// immutable request intent; only the expiry advances.
fn mooncode_goal_supervisor_lease_renewed_v1(
  id : String,
  protocol : String,
  session_id : String,
  goal_id : String,
  goal_run_id : Int,
  owner_id : String,
  recorded_at : Int64,
  expected_lease_expires_at : Int64,
  lease_expires_at : Int64,
  fence_token : Int,
  acquisition_event_id : String,
) -> Json raise {
  mooncode_goal_require_canonical_identity("renewal id", id)
  guard protocol == mooncode_protocol_version() else {
    raise InvalidGoalGenesis("unsupported protocol")
  }
  mooncode_goal_require_canonical_identity("session id", session_id)
  mooncode_goal_require_canonical_identity("goal id", goal_id)
  mooncode_goal_require_canonical_identity("owner id", owner_id)
  mooncode_goal_require_canonical_identity(
    "acquisition event id", acquisition_event_id,
  )
  guard goal_run_id >= 0 else {
    raise InvalidGoalGenesis("invalid goal run id: must be nonnegative")
  }
  guard recorded_at >= 0 else {
    raise InvalidGoalGenesis("invalid timestamp: must be nonnegative")
  }
  guard fence_token > 0 else {
    raise InvalidGoalGenesis("invalid fence token: must be positive")
  }
  guard expected_lease_expires_at > recorded_at else {
    raise InvalidGoalGenesis("invalid expected lease expiry")
  }
  guard lease_expires_at > expected_lease_expires_at else {
    raise InvalidGoalGenesis("invalid lease expiry")
  }
  {
    "id": id,
    "kind": mooncode_goal_supervisor_lease_renewed_v1_kind(),
    "protocol": protocol,
    "session_id": session_id,
    "goal_id": goal_id,
    "goal_run_id": goal_run_id,
    "owner_id": owner_id,
    "recorded_at": goal_json_int64_value(recorded_at),
    "expected_lease_expires_at": goal_json_int64_value(
      expected_lease_expires_at,
    ),
    "lease_expires_at": goal_json_int64_value(lease_expires_at),
    "fence_token": fence_token,
    "acquisition_event_id": acquisition_event_id,
  }
}

///|
/// Strictly decode the journal envelope and its canonical renewal payload.
fn mooncode_goal_supervisor_lease_renewal_decode(
  envelope : Json,
) -> MoonCodeGoalSupervisorLeaseRenewal raise {
  guard mooncode_json_string(envelope, "record_kind", default="") ==
    mooncode_journal_event() else {
    raise InvalidGoalGenesis("invalid renewal envelope record kind")
  }
  let payload = goal_json_object(envelope, "payload")
  goal_json_require_exact_keys(
    payload,
    [
      "id", "kind", "protocol", "session_id", "goal_id", "goal_run_id", "owner_id",
      "recorded_at", "expected_lease_expires_at", "lease_expires_at", "fence_token",
      "acquisition_event_id",
    ],
    "supervisor lease renewal",
  )
  let id = mooncode_json_string(payload, "id", default="")
  guard mooncode_json_string(envelope, "record_id", default="") ==
    mooncode_journal_goal_event() + ":" + id else {
    raise InvalidGoalGenesis("renewal envelope record id mismatch")
  }
  guard mooncode_json_string(payload, "kind", default="") ==
    mooncode_goal_supervisor_lease_renewed_v1_kind() else {
    raise InvalidGoalGenesis("invalid renewal kind")
  }
  let protocol = mooncode_json_string(payload, "protocol", default="")
  let session_id = mooncode_json_string(payload, "session_id", default="")
  guard mooncode_json_string(envelope, "session_id", default="") == session_id else {
    raise InvalidGoalGenesis("renewal envelope session id mismatch")
  }
  let goal_id = mooncode_json_string(payload, "goal_id", default="")
  let goal_run_id = goal_json_int(payload, "goal_run_id")
  let owner_id = mooncode_json_string(payload, "owner_id", default="")
  let recorded_at = goal_json_int64(payload, "recorded_at")
  guard goal_json_int64(envelope, "recorded_at") == recorded_at else {
    raise InvalidGoalGenesis("renewal envelope recorded at mismatch")
  }
  let expected_lease_expires_at = goal_json_int64(
    payload, "expected_lease_expires_at",
  )
  let lease_expires_at = goal_json_int64(payload, "lease_expires_at")
  let fence_token = goal_json_int(payload, "fence_token")
  let acquisition_event_id = mooncode_json_string(
    payload,
    "acquisition_event_id",
    default="",
  )
  ignore(
    mooncode_goal_supervisor_lease_renewed_v1(
      id, protocol, session_id, goal_id, goal_run_id, owner_id, recorded_at, expected_lease_expires_at,
      lease_expires_at, fence_token, acquisition_event_id,
    ),
  )
  {
    session_id,
    goal_id,
    goal_run_id,
    owner_id,
    recorded_at,
    expected_lease_expires_at,
    lease_expires_at,
    fence_token,
    acquisition_event_id,
    event_id: id,
  }
}

///|
/// Store-level outcomes always carry the projection that made the decision.
#warnings("-unused_value-unused_constructor-unused_field")
priv enum MoonCodeGoalSupervisorLeaseResult {
  SupervisorLeaseAcquired(MoonCodeGoalSupervisorLease)
  SupervisorLeaseIdempotent(MoonCodeGoalSupervisorLease)
  SupervisorLeaseConflict(MoonCodeGoalSupervisorLease?)
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
  recorded_at : Int64,
  lease_expires_at : Int64,
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
    "recorded_at": goal_json_int64_value(recorded_at),
    "lease_expires_at": goal_json_int64_value(lease_expires_at),
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
  let envelope_recorded_at = goal_json_int64(envelope, "recorded_at")
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
  let recorded_at = goal_json_int64(payload, "recorded_at")
  let lease_expires_at = goal_json_int64(payload, "lease_expires_at")
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
  let mut maximum_fence = 0
  let seen : Map[String, MoonCodeGoalSupervisorLeaseReplayEvent] = Map([])
  let mut active : MoonCodeGoalSupervisorLease? = None
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
      let event = MoonCodeGoalSupervisorLeaseReplayEvent::ReplayAcquisition(
        lease,
      )
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
          if previous == event {
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
      match active {
        Some(current) =>
          if lease.recorded_at < current.lease_expires_at {
            raise InvalidGoalGenesis("early supervisor lease takeover")
          }
        None => ()
      }
      seen[lease.event_id] = event
      active = Some(lease)
      maximum_fence = lease.fence_token
    } else if kind == mooncode_goal_supervisor_lease_renewed_v1_kind() {
      guard genesis_seen else {
        raise InvalidGoalGenesis("supervisor event before goal genesis")
      }
      let renewal = mooncode_goal_supervisor_lease_renewal_decode(envelope)
      let event = MoonCodeGoalSupervisorLeaseReplayEvent::ReplayRenewal(renewal)
      guard renewal.session_id == goal.session_id else {
        raise InvalidGoalGenesis("supervisor lease renewal session mismatch")
      }
      guard renewal.goal_id == goal.id else {
        raise InvalidGoalGenesis("supervisor lease renewal goal mismatch")
      }
      if renewal.goal_run_id > goal.run_id {
        raise InvalidGoalGenesis("supervisor lease renewal goal run mismatch")
      }
      match seen.get(renewal.event_id) {
        Some(previous) =>
          if previous == event {
            continue
          } else {
            raise InvalidGoalGenesis(
              "conflicting duplicate supervisor lease event",
            )
          }
        None => ()
      }
      let current = match active {
        Some(current) => current
        None =>
          raise InvalidGoalGenesis(
            "supervisor lease renewal without acquisition",
          )
      }
      guard renewal.goal_run_id == current.goal_run_id &&
        renewal.owner_id == current.owner_id &&
        renewal.fence_token == current.fence_token else {
        raise InvalidGoalGenesis("supervisor lease renewal identity mismatch")
      }
      guard renewal.acquisition_event_id == current.event_id else {
        raise InvalidGoalGenesis(
          "supervisor lease renewal acquisition mismatch",
        )
      }
      guard renewal.expected_lease_expires_at == current.lease_expires_at else {
        raise InvalidGoalGenesis("supervisor lease renewal expiry mismatch")
      }
      guard renewal.recorded_at >= current.recorded_at &&
        renewal.recorded_at < current.lease_expires_at else {
        raise InvalidGoalGenesis(
          "supervisor lease renewal outside lease window",
        )
      }
      seen[renewal.event_id] = event
      active = Some({
        session_id: current.session_id,
        goal_id: current.goal_id,
        goal_run_id: current.goal_run_id,
        owner_id: current.owner_id,
        fence_token: current.fence_token,
        recorded_at: renewal.recorded_at,
        lease_expires_at: renewal.lease_expires_at,
        event_id: current.event_id,
      })
    } else if kind == mooncode_goal_supervisor_checkpoint_v1_kind() {
      guard genesis_seen else {
        raise InvalidGoalGenesis("supervisor event before goal genesis")
      }
      let checkpoint = mooncode_goal_supervisor_checkpoint_decode(envelope)
      let event = MoonCodeGoalSupervisorLeaseReplayEvent::ReplayCheckpoint(
        checkpoint,
      )
      guard checkpoint.session_id == goal.session_id else {
        raise InvalidGoalGenesis("supervisor checkpoint session mismatch")
      }
      guard checkpoint.goal_id == goal.id else {
        raise InvalidGoalGenesis("supervisor checkpoint goal mismatch")
      }
      if checkpoint.goal_run_id > goal.run_id {
        raise InvalidGoalGenesis("supervisor checkpoint goal run mismatch")
      }
      match seen.get(checkpoint.id) {
        Some(previous) =>
          if previous == event {
            continue
          } else {
            raise InvalidGoalGenesis(
              "conflicting duplicate supervisor checkpoint event",
            )
          }
        None => ()
      }
      let current = match active {
        Some(current) => current
        None =>
          raise InvalidGoalGenesis("supervisor checkpoint without active lease")
      }
      guard checkpoint.goal_run_id == current.goal_run_id else {
        raise InvalidGoalGenesis("supervisor checkpoint goal run mismatch")
      }
      guard checkpoint.owner_id == current.owner_id else {
        raise InvalidGoalGenesis("supervisor checkpoint owner mismatch")
      }
      guard checkpoint.fence_token == current.fence_token else {
        raise InvalidGoalGenesis("supervisor checkpoint fence token mismatch")
      }
      guard checkpoint.acquisition_event_id == current.event_id else {
        raise InvalidGoalGenesis(
          "supervisor checkpoint acquisition event mismatch",
        )
      }
      guard checkpoint.expected_lease_expires_at == current.lease_expires_at else {
        raise InvalidGoalGenesis("supervisor checkpoint lease expiry mismatch")
      }
      guard checkpoint.recorded_at >= current.recorded_at else {
        raise InvalidGoalGenesis("supervisor checkpoint predates active lease")
      }
      guard checkpoint.recorded_at < current.lease_expires_at else {
        raise InvalidGoalGenesis("supervisor checkpoint outside active lease")
      }
      seen[checkpoint.id] = event
    }
  }
  (active, maximum_fence)
}

///|
fn mooncode_goal_supervisor_event_record_exists(
  records : Array[Json],
  event_id : String,
) -> Bool {
  let record_id = "event:\{event_id}"
  for envelope in records {
    if mooncode_json_string(envelope, "record_kind", default="") ==
      mooncode_journal_event() &&
      mooncode_json_string(envelope, "record_id", default="") == record_id {
      return true
    }
  }
  false
}

///|
fn mooncode_goal_supervisor_event_find(
  records : Array[Json],
  event_id : String,
) -> MoonCodeGoalSupervisorLeaseReplayEvent? raise {
  for envelope in records {
    if mooncode_json_string(envelope, "record_kind", default="") ==
      mooncode_journal_event() {
      let payload = goal_json_object(envelope, "payload")
      if mooncode_json_string(payload, "id", default="") == event_id {
        let kind = mooncode_json_string(payload, "kind", default="")
        if kind == mooncode_goal_supervisor_lease_v1_kind() {
          return Some(
            ReplayAcquisition(mooncode_goal_supervisor_lease_decode(envelope)),
          )
        } else if kind == mooncode_goal_supervisor_lease_renewed_v1_kind() {
          return Some(
            ReplayRenewal(
              mooncode_goal_supervisor_lease_renewal_decode(envelope),
            ),
          )
        } else if kind == mooncode_goal_supervisor_checkpoint_v1_kind() {
          return Some(
            ReplayCheckpoint(
              mooncode_goal_supervisor_checkpoint_decode(envelope),
            ),
          )
        } else if kind.has_prefix("mooncode.goal.supervisor.") {
          return None
        }
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
  recorded_at : Int64,
  lease_expires_at : Int64,
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
#warnings("-unused_value")
async fn mooncode_goal_supervisor_lease_acquire(
  book_root : String,
  session_id : String,
  goal_id : String,
  owner_id : String,
  event_id : String,
  now : Int64,
  lease_expires_at : Int64,
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
    match mooncode_goal_supervisor_event_find(records, event_id) {
      Some(ReplayAcquisition(existing)) =>
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
          return NoAppend(SupervisorLeaseConflict(Some(existing)))
        }
      Some(ReplayRenewal(_)) | Some(ReplayCheckpoint(_)) =>
        match current {
          Some(active) => return NoAppend(SupervisorLeaseConflict(Some(active)))
          None => raise InvalidGoalGenesis("renewal without active acquisition")
        }
      None => ()
    }
    if mooncode_goal_supervisor_event_record_exists(records, event_id) {
      return NoAppend(SupervisorLeaseConflict(current))
    }
    match current {
      Some(lease) if lease.lease_expires_at > now =>
        NoAppend(SupervisorLeaseConflict(Some(lease)))
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
