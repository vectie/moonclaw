///|
/// Reserved journal namespace for durable goal-supervisor checkpoint records.
///
/// This file intentionally owns the namespace independently from the core Goal
/// reducer: checkpoints are daemon-store coordination state, not Goal state.
fn mooncode_goal_supervisor_checkpoint_v1_kind() -> String {
  "mooncode.goal.supervisor.checkpoint.v1"
}

///|
/// Canonical durable checkpoint payload.
priv struct MoonCodeGoalSupervisorCheckpointPayload {
  id : String
  kind : String
  protocol : String
  session_id : String
  goal_id : String
  goal_run_id : Int
  goal_revision : Int
  current_goal_turn : Int
  owner_id : String
  fence_token : Int
  acquisition_event_id : String
  expected_lease_expires_at : Int
  basis_sequence : Int
  last_terminal_command_id : String?
  last_terminal_claim_id : String?
  last_terminal_receipt_record_id : String?
  recorded_at : Int
} derive(Eq, Debug, ToJson)

///|
/// Decode a nullable string field without accepting coercions.
fn mooncode_goal_supervisor_checkpoint_optional_string(
  object : Json,
  key : String,
) -> String? raise {
  match object {
    Object(map) =>
      match map.get(key) {
        Some(Null) | None => None
        Some(String(value)) => Some(value)
        _ =>
          raise InvalidGoalGenesis(
            "invalid " + key + ": expected string or null",
          )
      }
    _ => raise InvalidGoalGenesis("invalid supervisor checkpoint payload")
  }
}

///|
/// Strictly decode a canonical checkpoint journal envelope.
fn mooncode_goal_supervisor_checkpoint_decode(
  envelope : Json,
) -> MoonCodeGoalSupervisorCheckpointPayload raise {
  let record_kind = mooncode_json_string(envelope, "record_kind", default="")
  guard record_kind == mooncode_journal_event() else {
    raise InvalidGoalGenesis("invalid checkpoint record kind")
  }
  let record_id = mooncode_json_string(envelope, "record_id", default="")
  let envelope_session_id = mooncode_json_string(
    envelope,
    "session_id",
    default="",
  )
  let envelope_recorded_at = goal_json_int(envelope, "recorded_at")
  let envelope_sequence = goal_json_int(envelope, "sequence")
  let payload = goal_json_object(envelope, "payload")
  goal_json_require_exact_keys(
    payload,
    [
      "id", "kind", "protocol", "session_id", "goal_id", "goal_run_id", "goal_revision",
      "current_goal_turn", "owner_id", "fence_token", "acquisition_event_id", "expected_lease_expires_at",
      "basis_sequence", "last_terminal_command_id", "last_terminal_claim_id", "last_terminal_receipt_record_id",
      "recorded_at",
    ],
    "supervisor checkpoint",
  )
  let id = mooncode_json_string(payload, "id", default="")
  guard record_id == mooncode_journal_goal_event() + ":" + id else {
    raise InvalidGoalGenesis("checkpoint record id mismatch")
  }
  let kind = mooncode_json_string(payload, "kind", default="")
  guard kind == mooncode_goal_supervisor_checkpoint_v1_kind() else {
    raise InvalidGoalGenesis("invalid checkpoint kind")
  }
  let protocol = mooncode_json_string(payload, "protocol", default="")
  let session_id = mooncode_json_string(payload, "session_id", default="")
  guard session_id == envelope_session_id else {
    raise InvalidGoalGenesis("checkpoint session id mismatch")
  }
  let goal_id = mooncode_json_string(payload, "goal_id", default="")
  let goal_run_id = goal_json_int(payload, "goal_run_id")
  let goal_revision = goal_json_int(payload, "goal_revision")
  let current_goal_turn = goal_json_int(payload, "current_goal_turn")
  let owner_id = mooncode_json_string(payload, "owner_id", default="")
  let fence_token = goal_json_int(payload, "fence_token")
  let acquisition_event_id = mooncode_json_string(
    payload,
    "acquisition_event_id",
    default="",
  )
  let expected_lease_expires_at = goal_json_int(
    payload, "expected_lease_expires_at",
  )
  let basis_sequence = goal_json_int(payload, "basis_sequence")
  guard envelope_sequence > 0 && basis_sequence == envelope_sequence - 1 else {
    raise InvalidGoalGenesis("invalid checkpoint basis sequence")
  }
  let last_terminal_command_id = mooncode_goal_supervisor_checkpoint_optional_string(
    payload, "last_terminal_command_id",
  )
  let last_terminal_claim_id = mooncode_goal_supervisor_checkpoint_optional_string(
    payload, "last_terminal_claim_id",
  )
  let last_terminal_receipt_record_id = mooncode_goal_supervisor_checkpoint_optional_string(
    payload, "last_terminal_receipt_record_id",
  )
  let recorded_at = goal_json_int(payload, "recorded_at")
  guard recorded_at == envelope_recorded_at else {
    raise InvalidGoalGenesis("checkpoint recorded_at mismatch")
  }
  ignore(
    mooncode_goal_supervisor_checkpoint_v1(
      id, protocol, session_id, goal_id, goal_run_id, goal_revision, current_goal_turn,
      owner_id, fence_token, acquisition_event_id, expected_lease_expires_at, basis_sequence,
      last_terminal_command_id, last_terminal_claim_id, last_terminal_receipt_record_id,
      recorded_at,
    ),
  )
  MoonCodeGoalSupervisorCheckpointPayload::{
    id,
    kind,
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
    recorded_at,
  }
}

///|
/// Canonical durable checkpoint payload. The constructor returns the payload
/// object only; envelope construction remains the caller's responsibility.
fn mooncode_goal_supervisor_checkpoint_v1(
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
) -> Json raise {
  mooncode_goal_require_canonical_identity("checkpoint id", id)
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
  guard goal_revision >= 0 else {
    raise InvalidGoalGenesis("invalid goal revision: must be nonnegative")
  }
  guard current_goal_turn >= 0 else {
    raise InvalidGoalGenesis("invalid current goal turn: must be nonnegative")
  }
  guard current_goal_turn <= goal_revision else {
    raise InvalidGoalGenesis("invalid current goal turn: exceeds goal revision")
  }
  guard basis_sequence >= 0 else {
    raise InvalidGoalGenesis("invalid basis sequence: must be nonnegative")
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
  match
    (
      last_terminal_command_id, last_terminal_claim_id, last_terminal_receipt_record_id,
    ) {
    (None, None, None) => ()
    (Some(command_id), Some(claim_id), Some(receipt_record_id)) => {
      mooncode_goal_require_canonical_identity(
        "last terminal command id", command_id,
      )
      mooncode_goal_require_canonical_identity(
        "last terminal claim id", claim_id,
      )
      mooncode_goal_require_canonical_identity(
        "last terminal receipt record id", receipt_record_id,
      )
    }
    _ =>
      raise InvalidGoalGenesis(
        "invalid terminal checkpoint: ids must be all absent or all present",
      )
  }
  {
    "id": id,
    "kind": mooncode_goal_supervisor_checkpoint_v1_kind(),
    "protocol": protocol,
    "session_id": session_id,
    "goal_id": goal_id,
    "goal_run_id": goal_run_id,
    "goal_revision": goal_revision,
    "current_goal_turn": current_goal_turn,
    "owner_id": owner_id,
    "fence_token": fence_token,
    "acquisition_event_id": acquisition_event_id,
    "expected_lease_expires_at": expected_lease_expires_at,
    "basis_sequence": basis_sequence,
    "last_terminal_command_id": match last_terminal_command_id {
      Some(value) => value.to_json()
      None => null
    },
    "last_terminal_claim_id": match last_terminal_claim_id {
      Some(value) => value.to_json()
      None => null
    },
    "last_terminal_receipt_record_id": match last_terminal_receipt_record_id {
      Some(value) => value.to_json()
      None => null
    },
    "recorded_at": recorded_at,
  }
}
