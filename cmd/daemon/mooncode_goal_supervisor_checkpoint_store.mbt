///|
/// Outcomes from attempting to durably record a goal-supervisor checkpoint.
priv enum MoonCodeGoalSupervisorCheckpointResult {
  CheckpointRecorded(MoonCodeGoalSupervisorCheckpointPayload)
  CheckpointIdempotent(MoonCodeGoalSupervisorCheckpointPayload)
  CheckpointConflict(MoonCodeGoalSupervisorLease?)
  CheckpointBlockedAmbiguous(MoonCodeGoalSupervisorLease?)
} derive(Eq, Debug)

///|
/// Return whether a decoded checkpoint exactly matches every immutable field
/// supplied by a checkpoint request.
fn mooncode_goal_supervisor_checkpoint_matches_request(
  existing : MoonCodeGoalSupervisorCheckpointPayload,
  id : String,
  protocol : String,
  session_id : String,
  goal_id : String,
  goal_run_id : Int,
  goal_revision : Int,
  current_goal_turn : Int,
  owner_id : String,
  fence_token : Int,
  acquisition_event_id : String,
  expected_lease_expires_at : Int,
  basis_sequence : Int,
  last_terminal_command_id : String?,
  last_terminal_claim_id : String?,
  last_terminal_receipt_record_id : String?,
  recorded_at : Int,
) -> Bool {
  existing.id == id &&
  existing.protocol == protocol &&
  existing.session_id == session_id &&
  existing.goal_id == goal_id &&
  existing.goal_run_id == goal_run_id &&
  existing.goal_revision == goal_revision &&
  existing.current_goal_turn == current_goal_turn &&
  existing.owner_id == owner_id &&
  existing.fence_token == fence_token &&
  existing.acquisition_event_id == acquisition_event_id &&
  existing.expected_lease_expires_at == expected_lease_expires_at &&
  existing.basis_sequence == basis_sequence &&
  existing.last_terminal_command_id == last_terminal_command_id &&
  existing.last_terminal_claim_id == last_terminal_claim_id &&
  existing.last_terminal_receipt_record_id == last_terminal_receipt_record_id &&
  existing.recorded_at == recorded_at
}

///|
/// Atomically records a goal-supervisor checkpoint.
async fn mooncode_goal_supervisor_checkpoint_record(
  book_root : String,
  session_id : String,
  goal_id : String,
  goal_run_id : Int,
  goal_revision : Int,
  current_goal_turn : Int,
  owner_id : String,
  acquisition_event_id : String,
  event_id : String,
  fence_token : Int,
  expected_lease_expires_at : Int,
  basis_sequence : Int,
  last_terminal_command_id : String?,
  last_terminal_claim_id : String?,
  last_terminal_receipt_record_id : String?,
  now : Int,
) -> MoonCodeGoalSupervisorCheckpointResult {
  let protocol = mooncode_protocol_version()
  let payload = mooncode_goal_supervisor_checkpoint_v1(
    event_id, protocol, session_id, goal_id, goal_run_id, goal_revision, current_goal_turn,
    owner_id, fence_token, acquisition_event_id, expected_lease_expires_at, basis_sequence,
    last_terminal_command_id, last_terminal_claim_id, last_terminal_receipt_record_id,
    now,
  )
  mooncode_session_journal_transaction(book_root, session_id, fn(
    records,
  ) raise {
    let detailed = match
      mooncode_replay_goal_records_detailed(records, session_id) {
      Some(value) => value
      None => raise InvalidGoalGenesis("missing goal genesis")
    }
    let goal = detailed.current
    let (current, _) = mooncode_goal_supervisor_lease_replay(records, goal)
    match mooncode_goal_supervisor_event_find(records, event_id) {
      Some(ReplayCheckpoint(existing)) =>
        if mooncode_goal_supervisor_checkpoint_matches_request(
            existing, event_id, protocol, session_id, goal_id, goal_run_id, goal_revision,
            current_goal_turn, owner_id, fence_token, acquisition_event_id, expected_lease_expires_at,
            basis_sequence, last_terminal_command_id, last_terminal_claim_id, last_terminal_receipt_record_id,
            now,
          ) {
          NoAppend(CheckpointIdempotent(existing))
        } else {
          NoAppend(CheckpointConflict(current))
        }
      Some(_) => NoAppend(CheckpointConflict(current))
      None =>
        if mooncode_goal_supervisor_event_record_exists(records, event_id) {
          NoAppend(CheckpointConflict(current))
        } else if !mooncode_goal_supervisor_terminal_boundary_matches(
            records, session_id, last_terminal_command_id, last_terminal_claim_id,
            last_terminal_receipt_record_id,
          ) {
          NoAppend(CheckpointBlockedAmbiguous(current))
        } else {
          match
            mooncode_goal_supervisor_lease_validate_owner_fence(
              current, owner_id, fence_token, expected_lease_expires_at, now,
            ) {
            false => NoAppend(CheckpointConflict(current))
            true =>
              match current {
                None => NoAppend(CheckpointConflict(current))
                Some(active) =>
                  if goal.id != goal_id ||
                    goal.run_id != goal_run_id ||
                    goal.revision != goal_revision ||
                    goal.current_goal_turn != current_goal_turn ||
                    active.event_id != acquisition_event_id ||
                    active.lease_expires_at != expected_lease_expires_at ||
                    basis_sequence != mooncode_journal_last_sequence(records) ||
                    active.goal_run_id != goal_run_id ||
                    now < active.recorded_at {
                    NoAppend(CheckpointConflict(current))
                  } else {
                    let checkpoint : MoonCodeGoalSupervisorCheckpointPayload = {
                      id: event_id,
                      kind: mooncode_goal_supervisor_checkpoint_v1_kind(),
                      protocol,
                      session_id,
                      goal_id,
                      goal_run_id,
                      goal_revision,
                      current_goal_turn,
                      owner_id,
                      fence_token,
                      acquisition_event_id,
                      expected_lease_expires_at,
                      basis_sequence,
                      last_terminal_command_id,
                      last_terminal_claim_id,
                      last_terminal_receipt_record_id,
                      recorded_at: now,
                    }
                    Append(
                      mooncode_journal_goal_event(),
                      payload,
                      CheckpointRecorded(checkpoint),
                    )
                  }
              }
          }
        }
    }
  })
}
