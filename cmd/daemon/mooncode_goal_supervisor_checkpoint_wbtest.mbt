///|
fn checkpoint_replay_envelope(
  id : String,
  basis_sequence : Int,
  goal_revision : Int,
  current_goal_turn : Int,
  owner_id : String,
  fence_token : Int,
  acquisition_event_id : String,
  expected_lease_expires_at : Int,
  recorded_at : Int,
) -> Json raise {
  checkpoint_replay_envelope_with_terminal(
    id,
    basis_sequence,
    goal_revision,
    current_goal_turn,
    owner_id,
    fence_token,
    acquisition_event_id,
    expected_lease_expires_at,
    recorded_at,
    None,
    None,
    None,
  )
}

///|
fn checkpoint_replay_envelope_with_terminal(
  id : String,
  basis_sequence : Int,
  goal_revision : Int,
  current_goal_turn : Int,
  owner_id : String,
  fence_token : Int,
  acquisition_event_id : String,
  expected_lease_expires_at : Int,
  recorded_at : Int,
  last_command : String?,
  last_claim : String?,
  last_receipt : String?,
) -> Json raise {
  let payload = mooncode_goal_supervisor_checkpoint_v1(
    id,
    mooncode_protocol_version(),
    "session",
    "goal",
    0,
    goal_revision,
    current_goal_turn,
    owner_id,
    fence_token,
    acquisition_event_id,
    expected_lease_expires_at,
    basis_sequence,
    last_command,
    last_claim,
    last_receipt,
    recorded_at,
  )
  {
    "record_kind": mooncode_journal_event(),
    "record_id": "event:" + id,
    "session_id": "session",
    "recorded_at": recorded_at,
    "sequence": basis_sequence + 1,
    "payload": payload,
  }
}

///|
fn checkpoint_test_envelope(
  id : String,
  last_command : String?,
  last_claim : String?,
  last_receipt : String?,
) -> Json raise {
  let payload = mooncode_goal_supervisor_checkpoint_v1(
    id,
    mooncode_protocol_version(),
    "session",
    "goal",
    0,
    3,
    2,
    "owner",
    1,
    "lease-1",
    120,
    7,
    last_command,
    last_claim,
    last_receipt,
    100,
  )
  {
    "record_kind": mooncode_journal_event(),
    "record_id": "event:" + id,
    "session_id": "session",
    "recorded_at": 100,
    "sequence": 8,
    "payload": payload,
  }
}

///|
test "checkpoint codec decodes an all-null terminal triple" {
  let decoded = mooncode_goal_supervisor_checkpoint_decode(
    checkpoint_test_envelope("checkpoint-1", None, None, None),
  )
  assert_eq(decoded.id, "checkpoint-1")
  assert_eq(decoded.session_id, "session")
  assert_eq(decoded.goal_id, "goal")
  assert_eq(decoded.goal_run_id, 0)
  assert_eq(decoded.goal_revision, 3)
  assert_eq(decoded.current_goal_turn, 2)
  assert_eq(decoded.owner_id, "owner")
  assert_eq(decoded.fence_token, 1)
  assert_eq(decoded.acquisition_event_id, "lease-1")
  assert_eq(decoded.expected_lease_expires_at, 120)
  assert_eq(decoded.basis_sequence, 7)
  assert_eq(decoded.recorded_at, 100)
  assert_eq(decoded.last_terminal_command_id, None)
  assert_eq(decoded.last_terminal_claim_id, None)
  assert_eq(decoded.last_terminal_receipt_record_id, None)
}

///|
test "checkpoint codec decodes an all-present terminal triple" {
  let decoded = mooncode_goal_supervisor_checkpoint_decode(
    checkpoint_test_envelope(
      "checkpoint-2",
      Some("command-1"),
      Some("claim-1"),
      Some("receipt-1"),
    ),
  )
  assert_eq(decoded.last_terminal_command_id, Some("command-1"))
  assert_eq(decoded.last_terminal_claim_id, Some("claim-1"))
  assert_eq(decoded.last_terminal_receipt_record_id, Some("receipt-1"))
}

///|
test "checkpoint replay accepts matching goal snapshot and active lease" {
  let lease_id = "lease-checkpoint-valid"
  let lease_payload = mooncode_goal_supervisor_lease_v1(
    lease_id,
    mooncode_protocol_version(),
    "session",
    "goal",
    0,
    "owner",
    124,
    134,
    1,
  )
  let records = [
    goal_store_replay_genesis(),
    supervisor_lease_test_envelope(lease_id, lease_payload),
    checkpoint_replay_envelope(
      "checkpoint-valid", 2, 0, 0, "owner", 1, lease_id, 134, 125,
    ),
  ]
  let goal = mooncode_replay_goal_records(records, "session").unwrap()
  let (active_lease, max_fence_token) = mooncode_goal_supervisor_lease_replay(
    records, goal,
  )
  let active_lease = active_lease.unwrap()
  assert_eq(active_lease.event_id, lease_id)
  assert_eq(active_lease.fence_token, 1)
  assert_eq(max_fence_token, 1)
  let detailed = mooncode_replay_goal_records_detailed(records, "session").unwrap()
  assert_eq(detailed.current.revision, 0)
  assert_eq(detailed.current.current_goal_turn, 0)
}

///|
fn checkpoint_decode_is_invalid(envelope : Json) -> Bool {
  try {
    let _ = mooncode_goal_supervisor_checkpoint_decode(envelope)
    false
  } catch {
    InvalidGoalGenesis(_) => true
    _ => false
  }
}

///|
fn checkpoint_json_object_put(json : Json, key : String, value : Json) -> Json {
  match json {
    Object(fields) => {
      let copied = fields.copy()
      copied[key] = value
      Json::object(copied)
    }
    _ => json
  }
}

///|
fn checkpoint_json_payload_put(
  envelope : Json,
  key : String,
  value : Json,
) -> Json {
  match envelope {
    Object(fields) =>
      match fields.get("payload") {
        Some(payload) =>
          checkpoint_json_object_put(
            envelope,
            "payload",
            checkpoint_json_object_put(payload, key, value),
          )
        None => envelope
      }
    _ => envelope
  }
}

///|
test "checkpoint decoder rejects inconsistent envelopes and payloads" {
  let wrong_id = checkpoint_json_object_put(
    checkpoint_test_envelope("checkpoint-3", None, None, None),
    "record_id",
    "event:wrong",
  )
  assert_true(checkpoint_decode_is_invalid(wrong_id))

  let wrong_session = checkpoint_json_object_put(
    checkpoint_test_envelope("checkpoint-3", None, None, None),
    "session_id",
    "other-session",
  )
  assert_true(checkpoint_decode_is_invalid(wrong_session))

  let wrong_timestamp = checkpoint_json_object_put(
    checkpoint_test_envelope("checkpoint-3", None, None, None),
    "recorded_at",
    101,
  )
  assert_true(checkpoint_decode_is_invalid(wrong_timestamp))

  let wrong_basis = checkpoint_json_payload_put(
    checkpoint_test_envelope("checkpoint-3", None, None, None),
    "basis_sequence",
    8,
  )
  assert_true(checkpoint_decode_is_invalid(wrong_basis))

  let extra_key = checkpoint_json_payload_put(
    checkpoint_test_envelope("checkpoint-3", None, None, None),
    "extra",
    true,
  )
  assert_true(checkpoint_decode_is_invalid(extra_key))

  let fractional_revision = checkpoint_json_payload_put(
    checkpoint_test_envelope("checkpoint-3", None, None, None),
    "goal_revision",
    3.5,
  )
  assert_true(checkpoint_decode_is_invalid(fractional_revision))
}

///|
fn checkpoint_constructor_is_invalid(
  current_turn : Int,
  command : String?,
  claim : String?,
  receipt : String?,
) -> Bool {
  try {
    let _ = mooncode_goal_supervisor_checkpoint_v1(
      "checkpoint-4",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      3,
      current_turn,
      "owner",
      1,
      "lease-1",
      120,
      7,
      command,
      claim,
      receipt,
      100,
    )
    false
  } catch {
    InvalidGoalGenesis(_) => true
    _ => false
  }
}

///|
test "checkpoint constructor rejects partial terminal triples and excessive turn" {
  assert_true(
    checkpoint_constructor_is_invalid(2, Some("command-1"), None, None),
  )
  assert_true(
    checkpoint_constructor_is_invalid(
      2,
      Some("command-1"),
      Some("claim-1"),
      None,
    ),
  )
  assert_true(checkpoint_constructor_is_invalid(4, None, None, None))
}
