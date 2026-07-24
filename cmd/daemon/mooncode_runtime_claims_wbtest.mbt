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
    journal_path="/tmp/book/journal.jsonl",
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
    journal_path="/tmp/book/journal.jsonl",
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
    "kind": mooncode_kind_runtime_receipt(),
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
    journal_path="/tmp/book/journal.jsonl",
  )
  let claimed_items = mooncode_json_array_items(
    claimed_state, "claimed_commands",
  )
  let delivered : Json = {
    "kind": mooncode_kind_runtime_receipt(),
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": "session-deliver",
    "book_root": "/tmp/book",
    "command_id": mooncode_json_string(
      claimed_items[0],
      "command_id",
      default="",
    ),
    "status": "runtime-completed",
    "runtime_mode": "moonclaw-native-runtime-turn",
    "claim_id": "claim-1",
    "consumer_id": "test-consumer",
    "completed_at": @clock.Timestamp::from_ms(120L),
    "command": mooncode_json_object_field_or_empty(claimed_items[0], "command"),
  }
  assert_eq(
    mooncode_json_string(delivered, "status", default=""),
    "runtime-completed",
  )
  assert_eq(mooncode_json_string(delivered, "claim_id", default=""), "claim-1")
  let after = mooncode_runtime_claim_state_from_logs(
    "session-deliver",
    "/tmp/book",
    commands,
    [claimed, delivered],
    journal_path="/tmp/book/journal.jsonl",
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
test "mooncode runtime cancelled receipt is terminal" {
  let receipt : Json = {
    "kind": mooncode_kind_runtime_receipt(),
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": "session-cancel",
    "book_root": "/tmp/book",
    "command_id": "cmd-cancel",
    "status": "runtime-cancelled",
    "runtime_mode": "moonclaw-native-runtime-turn",
    "claim_id": "claim-cancel",
    "consumer_id": "test-consumer",
    "completed_at": @clock.Timestamp::from_ms(160L),
    "control": "cancel",
  }
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

///|
async test "16 concurrent legacy runtime claimers append one parseable receipt" {
  @fsx.with_temporary_directory("runtime-claim-atomic-XXXXXX", async fn(root) {
    let session_id = "session-atomic-claim"
    ignore(
      mooncode_append_session_journal(
        root,
        session_id,
        mooncode_journal_command(),
        {
          "kind": "mooncode-command",
          "protocol": mooncode_protocol_version(),
          "session_id": session_id,
          "command_id": "cmd-atomic",
          "created_at": 100,
          "command": {
            "protocol": mooncode_protocol_version(),
            "session_id": session_id,
            "book_root": root,
            "command": "prompt",
            "packet": { "command_id": "cmd-atomic" },
          },
        },
      ),
    )
    let tasks = Array::makei(16, fn(i) {
      async fn() {
        mooncode_runtime_claim_atomic(
          root,
          session_id,
          { "consumer_id": "consumer-\{i}" },
          @clock.Timestamp::from_ms(100L),
        )
      }
    })
    let results = @async.all(tasks)
    let mut claimed = 0
    for result in results {
      if result.receipts.length() == 1 {
        claimed += 1
      }
    }
    assert_eq(claimed, 1)
    let journal = mooncode_read_session_journal(root, session_id)
    let commands = mooncode_journal_entries(journal, mooncode_journal_command())
    let receipts = mooncode_journal_entries(
      journal,
      mooncode_journal_runtime_receipt(),
    )
    assert_eq(commands.length(), 1)
    assert_eq(receipts.length(), 1)
    assert_eq(
      mooncode_json_string(receipts[0], "status", default=""),
      "runtime-claimed",
    )
  })
}
