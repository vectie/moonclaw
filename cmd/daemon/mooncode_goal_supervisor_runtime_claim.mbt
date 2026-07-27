///|
priv enum MoonCodeGoalSupervisorRuntimeClaimOutcome {
  Recorded(Json)
  Idempotent(Json)
  Idle
  Conflict(MoonCodeGoalSupervisorLease?)
  BlockedAmbiguous(MoonCodeGoalSupervisorLease?)
}

///|
fn mooncode_goal_supervisor_runtime_claim_command_matches(
  prefix : Array[Json],
  payload : Json,
  book_root : String,
  session_id : String,
) -> Bool raise {
  let command_id = mooncode_json_string(payload, "command_id", default="")
  guard command_id != "" else { return false }
  let entries = mooncode_journal_entries(prefix, mooncode_journal_command())
  let matching : Array[Json] = []
  for entry in entries {
    if mooncode_json_string(entry, "command_id", default="") == command_id {
      matching.push(entry)
    }
  }
  guard matching.length() == 1 else { return false }
  let entry = matching[0]
  let command = mooncode_json_object_field_or_empty(entry, "command")
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  mooncode_json_object_field_or_empty(payload, "command_entry") == entry &&
  mooncode_json_object_field_or_empty(payload, "command") == command &&
  mooncode_json_string(entry, "kind", default="") == "mooncode-command" &&
  mooncode_json_string(entry, "protocol", default="") ==
  mooncode_protocol_version() &&
  mooncode_json_string(entry, "session_id", default="") == session_id &&
  mooncode_json_string(entry, "command_id", default="") == command_id &&
  mooncode_json_string(command, "protocol", default="") ==
  mooncode_protocol_version() &&
  mooncode_json_string(command, "session_id", default="") == session_id &&
  mooncode_json_string(command, "book_root", default="") == book_root &&
  mooncode_json_string(packet, "command_id", default="") == command_id
}

///|
/// Existing claim receipts are untrusted journal input. A malformed timestamp
/// is an immutable-request mismatch, not a reason to abort the transaction.
fn mooncode_goal_supervisor_runtime_claim_optional_int64(
  json : Json,
  key : String,
) -> Int64? {
  try goal_json_int64(json, key) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
// Exact retries are accepted only after the transaction validates the current
// goal, active lease, checkpoint, command lineage, wrapper sequence, and the
// absence of a later terminal receipt for the same command/claim.
fn mooncode_goal_supervisor_runtime_claim_request_matches(
  receipt : Json,
  book_root : String,
  session_id : String,
  goal_id : String,
  goal_run_id : Int,
  owner_id : String,
  acquisition_event_id : String,
  checkpoint_event_id : String,
  claim_id : String,
  consumer_id : String,
  fence_token : Int,
  expected_lease_expires_at : Int64,
  now : Int64,
) -> Bool {
  let payload = mooncode_json_object_field_or_empty(receipt, "payload")
  mooncode_json_string(receipt, "session_id", default="") == session_id &&
  mooncode_json_string(receipt, "record_id", default="") ==
  "runtime-receipt:\{mooncode_json_string(payload, "command_id", default="")}:runtime-claimed:\{claim_id}" &&
  mooncode_json_string(receipt, "command_id", default="") ==
  mooncode_json_string(payload, "command_id", default="") &&
  mooncode_json_string(receipt, "record_kind", default="") ==
  mooncode_journal_runtime_receipt() &&
  mooncode_json_string(payload, "kind", default="") ==
  mooncode_kind_runtime_receipt() &&
  mooncode_json_string(payload, "protocol", default="") ==
  mooncode_protocol_version() &&
  mooncode_json_string(payload, "owner", default="") == "moonclaw" &&
  mooncode_json_string(payload, "runtime_mode", default="") ==
  "moonclaw-native-runtime-claim" &&
  mooncode_json_string(payload, "status", default="") == "runtime-claimed" &&
  mooncode_json_string(payload, "book_root", default="") == book_root &&
  mooncode_json_string(payload, "session_id", default="") == session_id &&
  mooncode_json_string(payload, "goal_id", default="") == goal_id &&
  mooncode_json_int(payload, "goal_run_id", default=-1) == goal_run_id &&
  mooncode_json_string(payload, "owner_id", default="") == owner_id &&
  mooncode_json_string(payload, "acquisition_event_id", default="") ==
  acquisition_event_id &&
  mooncode_json_string(payload, "checkpoint_event_id", default="") ==
  checkpoint_event_id &&
  mooncode_json_string(payload, "claim_id", default="") == claim_id &&
  mooncode_json_string(payload, "consumer_id", default="") == consumer_id &&
  mooncode_json_int(payload, "fence_token", default=-1) == fence_token &&
  mooncode_goal_supervisor_runtime_claim_optional_int64(
    payload, "expected_lease_expires_at",
  ) ==
  Some(expected_lease_expires_at) &&
  mooncode_goal_supervisor_runtime_claim_optional_int64(payload, "claimed_at") ==
  Some(now)
}

///|
async fn mooncode_goal_supervisor_runtime_claim_record(
  book_root : String,
  session_id : String,
  goal_id : String,
  goal_run_id : Int,
  owner_id : String,
  acquisition_event_id : String,
  checkpoint_event_id : String,
  claim_id : String,
  consumer_id : String,
  fence_token : Int,
  expected_lease_expires_at : Int64,
  now : Int64,
) -> MoonCodeGoalSupervisorRuntimeClaimOutcome {
  mooncode_goal_require_canonical_identity("session id", session_id)
  mooncode_goal_require_canonical_identity("goal id", goal_id)
  mooncode_goal_require_canonical_identity("owner id", owner_id)
  mooncode_goal_require_canonical_identity(
    "acquisition event id", acquisition_event_id,
  )
  mooncode_goal_require_canonical_identity(
    "checkpoint event id", checkpoint_event_id,
  )
  mooncode_goal_require_canonical_identity("claim id", claim_id)
  mooncode_goal_require_canonical_identity("consumer id", consumer_id)
  guard goal_run_id >= 0 &&
    fence_token > 0 &&
    expected_lease_expires_at > 0 &&
    now >= 0 else {
    raise InvalidGoalGenesis("invalid supervised runtime claim")
  }
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
    let matches : Array[Json] = []
    for record in records {
      if mooncode_json_string(record, "record_kind", default="") ==
        mooncode_journal_runtime_receipt() {
        let payload = mooncode_json_object_field_or_empty(record, "payload")
        if mooncode_json_string(payload, "claim_id", default="") == claim_id &&
          mooncode_json_string(payload, "status", default="") ==
          "runtime-claimed" {
          matches.push(record)
        }
      }
    }
    if matches.length() > 1 {
      NoAppend(Conflict(current))
    } else if matches.length() == 1 {
      let receipt = matches[0]
      match current {
        None => NoAppend(Conflict(current))
        Some(active) =>
          if goal.id != goal_id ||
            goal.run_id != goal_run_id ||
            active.session_id != session_id ||
            active.goal_id != goal_id ||
            active.goal_run_id != goal_run_id ||
            active.owner_id != owner_id ||
            active.event_id != acquisition_event_id ||
            active.fence_token != fence_token ||
            active.lease_expires_at != expected_lease_expires_at ||
            now < active.recorded_at ||
            now >= active.lease_expires_at {
            NoAppend(Conflict(current))
          } else {
            match
              mooncode_goal_supervisor_event_find(records, checkpoint_event_id) {
              Some(ReplayCheckpoint(checkpoint)) => {
                let payload = mooncode_json_object_field_or_empty(
                  receipt, "payload",
                )
                let basis_sequence = mooncode_json_int(
                  payload,
                  "basis_sequence",
                  default=-1,
                )
                let claim_sequence = mooncode_journal_sequence(receipt)
                let prefix : Array[Json] = records.filter(fn(record) {
                  mooncode_journal_sequence(record) <= basis_sequence
                })
                if checkpoint.session_id != session_id ||
                  checkpoint.goal_id != goal_id ||
                  checkpoint.goal_run_id != goal_run_id ||
                  checkpoint.goal_revision != goal.revision ||
                  checkpoint.current_goal_turn != goal.current_goal_turn ||
                  checkpoint.owner_id != owner_id ||
                  checkpoint.fence_token != fence_token ||
                  checkpoint.acquisition_event_id != acquisition_event_id ||
                  checkpoint.expected_lease_expires_at !=
                  expected_lease_expires_at ||
                  basis_sequence < 0 ||
                  claim_sequence != basis_sequence + 1 ||
                  !mooncode_goal_supervisor_terminal_boundary_matches(
                    prefix,
                    session_id,
                    checkpoint.last_terminal_command_id,
                    checkpoint.last_terminal_claim_id,
                    checkpoint.last_terminal_receipt_record_id,
                  ) ||
                  !mooncode_goal_supervisor_runtime_claim_command_matches(
                    prefix, payload, book_root, session_id,
                  ) {
                  NoAppend(BlockedAmbiguous(current))
                } else {
                  let command_id = mooncode_json_string(
                    payload,
                    "command_id",
                    default="",
                  )
                  let mut after_claim = false
                  let mut terminal_receipt = false
                  for record in records {
                    if after_claim &&
                      mooncode_json_string(record, "record_kind", default="") ==
                      mooncode_journal_runtime_receipt() {
                      let later_payload = mooncode_json_object_field_or_empty(
                        record, "payload",
                      )
                      let status = mooncode_json_string(
                        later_payload,
                        "status",
                        default="",
                      )
                      if mooncode_json_string(
                          later_payload,
                          "command_id",
                          default="",
                        ) ==
                        command_id &&
                        mooncode_json_string(
                          later_payload,
                          "claim_id",
                          default="",
                        ) ==
                        claim_id &&
                        (
                          status == "runtime-completed" ||
                          status == "runtime-failed" ||
                          status == "runtime-cancelled" ||
                          status == "runtime-aborted"
                        ) {
                        terminal_receipt = true
                      }
                    }
                    if record == receipt {
                      after_claim = true
                    }
                  }
                  if terminal_receipt {
                    NoAppend(BlockedAmbiguous(current))
                  } else if mooncode_goal_supervisor_runtime_claim_request_matches(
                      receipt, book_root, session_id, goal_id, goal_run_id, owner_id,
                      acquisition_event_id, checkpoint_event_id, claim_id, consumer_id,
                      fence_token, expected_lease_expires_at, now,
                    ) {
                    NoAppend(Idempotent(payload))
                  } else {
                    NoAppend(Conflict(current))
                  }
                }
              }
              _ => NoAppend(BlockedAmbiguous(current))
            }
          }
      }
    } else {
      match current {
        None => NoAppend(Conflict(current))
        Some(active) =>
          if goal.id != goal_id ||
            goal.run_id != goal_run_id ||
            active.session_id != session_id ||
            active.goal_id != goal_id ||
            active.goal_run_id != goal_run_id ||
            active.owner_id != owner_id ||
            active.event_id != acquisition_event_id ||
            active.fence_token != fence_token ||
            active.lease_expires_at != expected_lease_expires_at ||
            now < active.recorded_at ||
            now >= active.lease_expires_at {
            NoAppend(Conflict(current))
          } else {
            match
              mooncode_goal_supervisor_event_find(records, checkpoint_event_id) {
              Some(ReplayCheckpoint(checkpoint)) =>
                if checkpoint.session_id != session_id ||
                  checkpoint.goal_id != goal_id ||
                  checkpoint.goal_run_id != goal_run_id ||
                  checkpoint.goal_revision != goal.revision ||
                  checkpoint.current_goal_turn != goal.current_goal_turn ||
                  checkpoint.owner_id != owner_id ||
                  checkpoint.fence_token != fence_token ||
                  checkpoint.acquisition_event_id != acquisition_event_id ||
                  checkpoint.expected_lease_expires_at !=
                  expected_lease_expires_at ||
                  !mooncode_goal_supervisor_terminal_boundary_matches(
                    records,
                    session_id,
                    checkpoint.last_terminal_command_id,
                    checkpoint.last_terminal_claim_id,
                    checkpoint.last_terminal_receipt_record_id,
                  ) {
                  NoAppend(BlockedAmbiguous(current))
                } else {
                  let commands = mooncode_journal_entries(
                    records,
                    mooncode_journal_command(),
                  )
                  let receipts = mooncode_journal_entries(
                    records,
                    mooncode_journal_runtime_receipt(),
                  )
                  let state = mooncode_runtime_claim_state_from_logs(
                    session_id,
                    book_root,
                    commands,
                    receipts,
                    journal_path=mooncode_session_journal_path(
                      book_root, session_id,
                    ),
                  )
                  let claimable = mooncode_json_array_items(
                    state, "claimable_commands",
                  )
                  if claimable.length() == 0 {
                    if mooncode_json_int(
                        state,
                        "claimed_command_count",
                        default=0,
                      ) >
                      0 {
                      NoAppend(BlockedAmbiguous(current))
                    } else {
                      NoAppend(Idle)
                    }
                  } else {
                    let item = claimable[0]
                    guard mooncode_goal_supervisor_runtime_claim_command_matches(
                      records, item, book_root, session_id,
                    ) else {
                      return NoAppend(BlockedAmbiguous(current))
                    }
                    let command_id = mooncode_json_string(
                      item,
                      "command_id",
                      default="",
                    )
                    let command_entry = mooncode_json_object_field_or_empty(
                      item, "command_entry",
                    )
                    let command = mooncode_json_object_field_or_empty(
                      item, "command",
                    )
                    let payload : Json = {
                      "kind": mooncode_kind_runtime_receipt(),
                      "protocol": mooncode_protocol_version(),
                      "owner": "moonclaw",
                      "runtime_mode": "moonclaw-native-runtime-claim",
                      "status": "runtime-claimed",
                      "book_root": book_root,
                      "session_id": session_id,
                      "goal_id": goal_id,
                      "goal_run_id": goal_run_id,
                      "owner_id": owner_id,
                      "acquisition_event_id": acquisition_event_id,
                      "checkpoint_event_id": checkpoint_event_id,
                      "claim_id": claim_id,
                      "consumer_id": consumer_id,
                      "fence_token": fence_token,
                      "expected_lease_expires_at": goal_json_int64_value(
                        expected_lease_expires_at,
                      ),
                      "claimed_at": goal_json_int64_value(now),
                      "basis_sequence": mooncode_journal_last_sequence(records),
                      "command_id": command_id,
                      "command": command,
                      "command_entry": command_entry,
                    }
                    Append(
                      mooncode_journal_runtime_receipt(),
                      payload,
                      Recorded(payload),
                    )
                  }
                }
              _ => NoAppend(Conflict(current))
            }
          }
      }
    }
  })
}
