///|
fn terminal_boundary_command(
  sequence : Int,
  session_id : String,
  command_id : String,
) -> Json {
  @moonlib_conversation.journal_record(
    sequence~,
    record_kind=mooncode_journal_command(),
    record_id="command:\{command_id}",
    session_id~,
    command_id~,
    client_turn_id="",
    recorded_at="2026-08-01T00:00:00Z",
    payload={
      "kind": "mooncode-command",
      "protocol": "mooncode.v1",
      "session_id": session_id,
      "command_id": command_id,
    },
  )
}

///|
fn terminal_boundary_receipt(
  sequence : Int,
  session_id : String,
  command_id : String,
  status : String,
  runtime_mode : String,
  claim_id : String,
  record_id : String,
) -> Json {
  let payload : Json = if status == "runtime-claimed" {
    {
      "kind": mooncode_kind_runtime_receipt(),
      "protocol": "mooncode.v1",
      "owner": "moonclaw",
      "session_id": session_id,
      "command_id": command_id,
      "status": status,
      "runtime_mode": runtime_mode,
      "claim_id": claim_id,
      "claimed_at": "2026-08-01T00:00:01Z",
    }
  } else {
    {
      "kind": mooncode_kind_runtime_receipt(),
      "protocol": "mooncode.v1",
      "owner": "moonclaw",
      "session_id": session_id,
      "command_id": command_id,
      "status": status,
      "runtime_mode": runtime_mode,
      "claim_id": claim_id,
      "completed_at": "2026-08-01T00:00:02Z",
    }
  }
  @moonlib_conversation.journal_record(
    sequence~,
    record_kind=mooncode_journal_runtime_receipt(),
    record_id~,
    session_id~,
    command_id~,
    client_turn_id="",
    recorded_at="2026-08-01T00:00:03Z",
    payload~,
  )
}

///|
test "terminal boundary accepts command with no receipts as all-null" {
  let records = [terminal_boundary_command(1, "session-1", "command-1")]
  assert_true(
    mooncode_goal_supervisor_terminal_boundary_matches(
      records,
      "session-1",
      None,
      None,
      None,
    ),
  )
}

///|
test "terminal boundary matches native claim and completion IDs exactly" {
  let command = terminal_boundary_command(1, "session-2", "command-2")
  let claim = terminal_boundary_receipt(
    2, "session-2", "command-2", "runtime-claimed", "moonclaw-native-runtime-claim",
    "claim-2", "runtime-receipt:command-2:runtime-claimed:claim-2",
  )
  let terminal_id = "runtime-receipt:command-2:runtime-completed:claim-2"
  let terminal = terminal_boundary_receipt(
    3, "session-2", "command-2", "runtime-completed", "moonclaw-native-runtime-turn",
    "claim-2", terminal_id,
  )
  let records = [command, claim, terminal]
  assert_true(
    mooncode_goal_supervisor_terminal_boundary_matches(
      records,
      "session-2",
      Some("command-2"),
      Some("claim-2"),
      Some(terminal_id),
    ),
  )
  assert_false(
    mooncode_goal_supervisor_terminal_boundary_matches(
      records,
      "session-2",
      Some("command-2"),
      Some("claim-2"),
      Some("runtime-receipt:wrong"),
    ),
  )
}

///|
test "terminal boundary selects only the latest valid chain tuple" {
  let old_terminal_id = "runtime-receipt:command-old:runtime-completed:claim-old"
  let latest_terminal_id = "runtime-receipt:command-latest:runtime-completed:claim-latest"
  let records = [
    terminal_boundary_command(10, "session-chains", "command-old"),
    terminal_boundary_receipt(
      11, "session-chains", "command-old", "runtime-claimed", "moonclaw-native-runtime-claim",
      "claim-old", "runtime-receipt:command-old:runtime-claimed:claim-old",
    ),
    terminal_boundary_receipt(
      12, "session-chains", "command-old", "runtime-completed", "moonclaw-native-runtime-turn",
      "claim-old", old_terminal_id,
    ),
    terminal_boundary_command(13, "session-chains", "command-latest"),
    terminal_boundary_receipt(
      14, "session-chains", "command-latest", "runtime-claimed", "moonclaw-native-runtime-claim",
      "claim-latest", "runtime-receipt:command-latest:runtime-claimed:claim-latest",
    ),
    terminal_boundary_receipt(
      15, "session-chains", "command-latest", "runtime-completed", "moonclaw-native-runtime-turn",
      "claim-latest", latest_terminal_id,
    ),
  ]
  assert_true(
    mooncode_goal_supervisor_terminal_boundary_matches(
      records,
      "session-chains",
      Some("command-latest"),
      Some("claim-latest"),
      Some(latest_terminal_id),
    ),
  )
  assert_false(
    mooncode_goal_supervisor_terminal_boundary_matches(
      records,
      "session-chains",
      Some("command-old"),
      Some("claim-old"),
      Some(old_terminal_id),
    ),
  )
}

///|
test "terminal boundary accepts native runtime control cancellation" {
  let terminal_id = "runtime-receipt:command-cancel:runtime-cancelled:claim-cancel"
  let records = [
    terminal_boundary_command(20, "session-cancel", "command-cancel"),
    terminal_boundary_receipt(
      21, "session-cancel", "command-cancel", "runtime-claimed", "moonclaw-native-runtime-claim",
      "claim-cancel", "runtime-receipt:command-cancel:runtime-claimed:claim-cancel",
    ),
    terminal_boundary_receipt(
      22, "session-cancel", "command-cancel", "runtime-cancelled", "moonclaw-native-runtime-control",
      "claim-cancel", terminal_id,
    ),
  ]
  assert_true(
    mooncode_goal_supervisor_terminal_boundary_matches(
      records,
      "session-cancel",
      Some("command-cancel"),
      Some("claim-cancel"),
      Some(terminal_id),
    ),
  )
}

///|
test "terminal boundary rejects terminal before claim" {
  let terminal_id = "runtime-receipt:command-order:runtime-completed:claim-order"
  let records = [
    terminal_boundary_command(30, "session-order", "command-order"),
    terminal_boundary_receipt(
      31, "session-order", "command-order", "runtime-completed", "moonclaw-native-runtime-turn",
      "claim-order", terminal_id,
    ),
    terminal_boundary_receipt(
      32, "session-order", "command-order", "runtime-claimed", "moonclaw-native-runtime-claim",
      "claim-order", "runtime-receipt:command-order:runtime-claimed:claim-order",
    ),
  ]
  assert_false(
    mooncode_goal_supervisor_terminal_boundary_matches(
      records,
      "session-order",
      Some("command-order"),
      Some("claim-order"),
      Some(terminal_id),
    ),
  )
}

///|
test "terminal boundary rejects duplicate claim" {
  let terminal_id = "runtime-receipt:command-duplicate:runtime-completed:claim-duplicate"
  let records = [
    terminal_boundary_command(40, "session-duplicate", "command-duplicate"),
    terminal_boundary_receipt(
      41, "session-duplicate", "command-duplicate", "runtime-claimed", "moonclaw-native-runtime-claim",
      "claim-duplicate", "runtime-receipt:command-duplicate:runtime-claimed:claim-duplicate",
    ),
    terminal_boundary_receipt(
      42, "session-duplicate", "command-duplicate", "runtime-claimed", "moonclaw-native-runtime-claim",
      "claim-duplicate", "runtime-receipt:command-duplicate:runtime-claimed:claim-duplicate-2",
    ),
    terminal_boundary_receipt(
      43, "session-duplicate", "command-duplicate", "runtime-completed", "moonclaw-native-runtime-turn",
      "claim-duplicate", terminal_id,
    ),
  ]
  assert_false(
    mooncode_goal_supervisor_terminal_boundary_matches(
      records,
      "session-duplicate",
      Some("command-duplicate"),
      Some("claim-duplicate"),
      Some(terminal_id),
    ),
  )
}

///|
test "terminal boundary rejects second terminal for one claim" {
  let first_terminal_id = "runtime-receipt:command-twice:runtime-completed:claim-twice"
  let records = [
    terminal_boundary_command(50, "session-twice", "command-twice"),
    terminal_boundary_receipt(
      51, "session-twice", "command-twice", "runtime-claimed", "moonclaw-native-runtime-claim",
      "claim-twice", "runtime-receipt:command-twice:runtime-claimed:claim-twice",
    ),
    terminal_boundary_receipt(
      52, "session-twice", "command-twice", "runtime-completed", "moonclaw-native-runtime-turn",
      "claim-twice", first_terminal_id,
    ),
    terminal_boundary_receipt(
      53, "session-twice", "command-twice", "runtime-cancelled", "moonclaw-native-runtime-control",
      "claim-twice", "runtime-receipt:command-twice:runtime-cancelled:claim-twice",
    ),
  ]
  assert_false(
    mooncode_goal_supervisor_terminal_boundary_matches(
      records,
      "session-twice",
      Some("command-twice"),
      Some("claim-twice"),
      Some(first_terminal_id),
    ),
  )
}

///|
test "terminal boundary rejects wrong receipt wrapper record id" {
  let terminal_id = "runtime-receipt:command-wrapper:runtime-completed:claim-wrapper"
  let records = [
    terminal_boundary_command(60, "session-wrapper", "command-wrapper"),
    terminal_boundary_receipt(
      61, "session-wrapper", "command-wrapper", "runtime-claimed", "moonclaw-native-runtime-claim",
      "claim-wrapper", "runtime-receipt:wrong",
    ),
    terminal_boundary_receipt(
      62, "session-wrapper", "command-wrapper", "runtime-completed", "moonclaw-native-runtime-turn",
      "claim-wrapper", terminal_id,
    ),
  ]
  assert_false(
    mooncode_goal_supervisor_terminal_boundary_matches(
      records,
      "session-wrapper",
      Some("command-wrapper"),
      Some("claim-wrapper"),
      Some(terminal_id),
    ),
  )
}

///|
test "terminal boundary rejects unresolved claim as all-null" {
  let records = [
    terminal_boundary_command(1, "session-3", "command-3"),
    terminal_boundary_receipt(
      2, "session-3", "command-3", "runtime-claimed", "moonclaw-native-runtime-claim",
      "claim-3", "runtime-receipt:command-3:runtime-claimed:claim-3",
    ),
  ]
  assert_false(
    mooncode_goal_supervisor_terminal_boundary_matches(
      records,
      "session-3",
      None,
      None,
      None,
    ),
  )
}

///|
test "terminal boundary ignores unregistered native control completion" {
  let records = [
    terminal_boundary_receipt(
      1, "session-4", "command-4", "runtime-completed", "moonclaw-native-runtime-control",
      "claim-4", "runtime-receipt:command-4:runtime-completed:claim-4",
    ),
  ]
  assert_true(
    mooncode_goal_supervisor_terminal_boundary_matches(
      records,
      "session-4",
      None,
      None,
      None,
    ),
  )
}

///|
test "terminal boundary rejects forged terminal receipt payload kind" {
  let command_id = "command-forged-terminal-kind"
  let claim_id = "claim-forged-terminal-kind"
  let session_id = "session-forged-terminal-kind"
  let terminal_id = "runtime-receipt:command-forged-terminal-kind:runtime-completed:claim-forged-terminal-kind"
  let command = terminal_boundary_command(60, session_id, command_id)
  let claim = terminal_boundary_receipt(
    61, session_id, command_id, "runtime-claimed", "moonclaw-native-runtime-claim",
    claim_id, "runtime-receipt:command-forged-terminal-kind:runtime-claimed:claim-forged-terminal-kind",
  )
  let valid_terminal = terminal_boundary_receipt(
    62, session_id, command_id, "runtime-completed", "moonclaw-native-runtime-turn",
    claim_id, terminal_id,
  )
  let forged_terminal : Json = match valid_terminal {
    Object(envelope) => {
      let envelope_copy = envelope.copy()
      let forged_payload = match envelope_copy["payload"] {
        Object(payload) => {
          let payload_copy = payload.copy()
          payload_copy["kind"] = ("forged-receipt" : Json)
          Json::object(payload_copy)
        }
        _ => abort("expected payload object")
      }
      envelope_copy["payload"] = forged_payload
      Json::object(envelope_copy)
    }
    _ => abort("expected envelope object")
  }
  assert_false(
    mooncode_goal_supervisor_terminal_boundary_matches(
      [command, claim, forged_terminal],
      session_id,
      Some(command_id),
      Some(claim_id),
      Some(terminal_id),
    ),
  )
}
