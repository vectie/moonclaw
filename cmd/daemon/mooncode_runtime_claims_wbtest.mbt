///|
test "mooncode runtime claim state leases next durable command" {
  let commands : Array[Json] = [
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": "session-claim",
      "command_id": "cmd-1",
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-claim",
        "book_root": "/tmp/book",
        "command": "prompt",
        "packet": { "command_id": "cmd-1" },
      },
    },
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": "session-claim",
      "command_id": "cmd-2",
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-claim",
        "book_root": "/tmp/book",
        "command": "steer",
        "packet": { "command_id": "cmd-2" },
      },
    },
  ]
  let state = mooncode_runtime_claim_state_from_logs(
    "session-claim",
    "/tmp/book",
    commands,
    [],
    commands_path="/tmp/book/commands.jsonl",
    dispatches_path="/tmp/book/runtime-dispatches.jsonl",
  )
  assert_eq(
    mooncode_json_string(state, "kind", default=""),
    "mooncode-runtime-claim-state",
  )
  assert_true(mooncode_json_bool(state, "claim_ready", default=false))
  assert_true(state.stringify().contains("\"claimable_command_count\":1"))
  assert_true(state.stringify().contains("\"order_blocked_command_count\":1"))
  let claimable = mooncode_json_array_items(state, "claimable_commands")
  assert_eq(
    mooncode_json_string(claimable[0], "command_id", default=""),
    "cmd-1",
  )
  let blocked = mooncode_json_array_items(state, "order_blocked_commands")
  assert_eq(
    mooncode_json_string(blocked[0], "order_blocked_by", default=""),
    "cmd-1",
  )
  let receipts = mooncode_runtime_claim_receipts(
    "session-claim",
    "/tmp/book",
    state,
    { "consumer_id": "test-consumer" },
    now=@clock.Timestamp::from_ms(100L),
  )
  assert_eq(receipts.length(), 1)
  assert_eq(
    mooncode_json_string(receipts[0], "status", default=""),
    "runtime-claimed",
  )
  assert_eq(
    mooncode_json_string(receipts[0], "consumer_id", default=""),
    "test-consumer",
  )
  let claimed_state = mooncode_runtime_claim_state_from_logs(
    "session-claim",
    "/tmp/book",
    commands,
    receipts,
    commands_path="/tmp/book/commands.jsonl",
    dispatches_path="/tmp/book/runtime-dispatches.jsonl",
  )
  assert_true(claimed_state.stringify().contains("\"claimed_command_count\":1"))
  assert_true(
    claimed_state.stringify().contains("\"claimable_command_count\":0"),
  )
}

///|
test "mooncode runtime delivery receipt resolves claimed command" {
  let commands : Array[Json] = [
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": "session-deliver",
      "command_id": "cmd-1",
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-deliver",
        "book_root": "/tmp/book",
        "command": "prompt",
        "packet": { "command_id": "cmd-1" },
      },
    },
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": "session-deliver",
      "command_id": "cmd-2",
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-deliver",
        "book_root": "/tmp/book",
        "command": "run_tests",
        "packet": { "command_id": "cmd-2" },
      },
    },
  ]
  let claimed = {
    "kind": mooncode_kind_runtime_dispatch(),
    "protocol": mooncode_protocol_version(),
    "session_id": "session-deliver",
    "book_root": "/tmp/book",
    "command_id": "cmd-1",
    "status": "runtime-claimed",
    "claim_id": "claim-1",
    "consumer_id": "test-consumer",
  }
  let claimed_state = mooncode_runtime_claim_state_from_logs(
    "session-deliver",
    "/tmp/book",
    commands,
    [claimed],
    commands_path="/tmp/book/commands.jsonl",
    dispatches_path="/tmp/book/runtime-dispatches.jsonl",
  )
  let claimed_items = mooncode_json_array_items(
    claimed_state, "claimed_commands",
  )
  let delivered = mooncode_runtime_dispatch_receipt(
    "session-deliver",
    "/tmp/book",
    claimed_items[0],
    {
      "accepted": true,
      "command_id": "cmd-1",
      "task_id": "task-1",
      "message_id": "message-1",
      "control": "prompt",
      "message": "accepted",
      "events": [{ "kind": "command.accepted" }],
    },
    consumer_id="test-consumer",
    now=@clock.Timestamp::from_ms(120L),
  )
  assert_eq(
    mooncode_json_string(delivered, "status", default=""),
    "runtime-delivered",
  )
  assert_eq(mooncode_json_string(delivered, "claim_id", default=""), "claim-1")
  let after = mooncode_runtime_claim_state_from_logs(
    "session-deliver",
    "/tmp/book",
    commands,
    [claimed, delivered],
    commands_path="/tmp/book/commands.jsonl",
    dispatches_path="/tmp/book/runtime-dispatches.jsonl",
  )
  assert_true(after.stringify().contains("\"delivered_command_count\":1"))
  assert_true(after.stringify().contains("\"claimable_command_count\":1"))
  let claimable = mooncode_json_array_items(after, "claimable_commands")
  assert_eq(
    mooncode_json_string(claimable[0], "command_id", default=""),
    "cmd-2",
  )
}

///|
test "mooncode runtime dispatch receipt classifies cancel as terminal" {
  let item : Json = {
    "kind": "mooncode-runtime-claim-item",
    "protocol": mooncode_protocol_version(),
    "command_id": "cmd-cancel",
    "command": {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-cancel",
      "book_root": "/tmp/book",
      "command": "cancel",
      "packet": { "command_id": "cmd-cancel" },
    },
    "receipt": {
      "kind": mooncode_kind_runtime_dispatch(),
      "status": "runtime-claimed",
      "claim_id": "claim-cancel",
    },
  }
  let receipt = mooncode_runtime_dispatch_receipt(
    "session-cancel",
    "/tmp/book",
    item,
    {
      "accepted": true,
      "command_id": "cmd-cancel",
      "task_id": "task-cancel",
      "control": "cancel",
      "message": "MoonClaw MoonCode runtime accepted `cancel`",
      "events": [{ "kind": "cancel.requested" }],
    },
    consumer_id="test-consumer",
    now=@clock.Timestamp::from_ms(160L),
  )
  assert_eq(
    mooncode_json_string(receipt, "status", default=""),
    "runtime-cancelled",
  )
  assert_true(
    mooncode_runtime_receipt_status_delivered(
      mooncode_json_string(receipt, "status", default=""),
    ),
  )
  assert_eq(mooncode_json_string(receipt, "control", default=""), "cancel")
}
