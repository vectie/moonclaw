///|
/// Outcome of an atomic durable supervisor-lease renewal attempt.
priv enum MoonCodeGoalSupervisorLeaseRenewalResult {
  Renewed(MoonCodeGoalSupervisorLeaseRenewal)
  RenewalIdempotent(MoonCodeGoalSupervisorLeaseRenewal)
  RenewalConflict(MoonCodeGoalSupervisorLease?)
} derive(Eq, Debug)

///|
async fn mooncode_goal_supervisor_lease_renew(
  book_root : String,
  session_id : String,
  goal_id : String,
  owner_id : String,
  acquisition_event_id : String,
  event_id : String,
  fence_token : Int,
  expected_lease_expires_at : Int,
  now : Int,
  lease_expires_at : Int,
) -> MoonCodeGoalSupervisorLeaseRenewalResult {
  mooncode_goal_require_canonical_identity("session id", session_id)
  mooncode_goal_require_canonical_identity("goal id", goal_id)
  mooncode_goal_require_canonical_identity("owner id", owner_id)
  mooncode_goal_require_canonical_identity(
    "acquisition event id", acquisition_event_id,
  )
  mooncode_goal_require_canonical_identity("renewal id", event_id)
  guard event_id != mooncode_goal_genesis_id() else {
    raise InvalidGoalGenesis("reserved event id")
  }
  let preflight = mooncode_replay_goal_detailed(book_root, session_id)
  let preflight_goal = match preflight {
    Some(value) => value.current
    None => raise InvalidGoalGenesis("missing goal genesis")
  }
  guard preflight_goal.id == goal_id else {
    raise InvalidGoalGenesis("goal id mismatch")
  }
  ignore(
    mooncode_goal_supervisor_lease_renewed_v1(
      event_id,
      mooncode_protocol_version(),
      session_id,
      goal_id,
      preflight_goal.run_id,
      owner_id,
      now,
      expected_lease_expires_at,
      lease_expires_at,
      fence_token,
      acquisition_event_id,
    ),
  )
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
    let (current, _) = mooncode_goal_supervisor_lease_replay(records, goal)
    match mooncode_goal_supervisor_event_find(records, event_id) {
      Some(ReplayRenewal(existing)) =>
        if existing.session_id == session_id &&
          existing.goal_id == goal_id &&
          existing.goal_run_id == goal.run_id &&
          existing.owner_id == owner_id &&
          existing.recorded_at == now &&
          existing.expected_lease_expires_at == expected_lease_expires_at &&
          existing.lease_expires_at == lease_expires_at &&
          existing.fence_token == fence_token &&
          existing.acquisition_event_id == acquisition_event_id &&
          existing.event_id == event_id {
          return NoAppend(RenewalIdempotent(existing))
        } else {
          return NoAppend(RenewalConflict(current))
        }
      Some(ReplayAcquisition(_)) => return NoAppend(RenewalConflict(current))
      None => ()
    }
    if mooncode_goal_supervisor_event_record_exists(records, event_id) {
      return NoAppend(RenewalConflict(current))
    }
    guard mooncode_goal_supervisor_lease_validate_owner_fence(
      current, owner_id, fence_token, expected_lease_expires_at, now,
    ) else {
      return NoAppend(RenewalConflict(current))
    }
    let active = match current {
      Some(value) => value
      None => return NoAppend(RenewalConflict(None))
    }
    guard active.goal_run_id == goal.run_id else {
      return NoAppend(RenewalConflict(current))
    }
    guard now >= active.recorded_at else {
      return NoAppend(RenewalConflict(current))
    }
    guard active.event_id == acquisition_event_id else {
      return NoAppend(RenewalConflict(current))
    }
    let payload = mooncode_goal_supervisor_lease_renewed_v1(
      event_id,
      mooncode_protocol_version(),
      session_id,
      goal_id,
      goal.run_id,
      owner_id,
      now,
      expected_lease_expires_at,
      lease_expires_at,
      fence_token,
      acquisition_event_id,
    )
    let renewal = MoonCodeGoalSupervisorLeaseRenewal::{
      session_id,
      goal_id,
      goal_run_id: goal.run_id,
      owner_id,
      recorded_at: now,
      expected_lease_expires_at,
      lease_expires_at,
      fence_token,
      acquisition_event_id,
      event_id,
    }
    Append(mooncode_journal_goal_event(), payload, Renewed(renewal))
  })
}
