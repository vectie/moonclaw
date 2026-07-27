///|
test "mooncode runtime control starts pending prompt and queues controls" {
  let commands : Array[Json] = [
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": "session-runtime-control",
      "command_id": "cmd-1",
      "created_at": "2026-06-17T00:00:00Z",
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-runtime-control",
        "book_root": "/tmp/book",
        "command": "prompt",
        "text": "build a tool",
        "packet": { "command_id": "cmd-1" },
      },
    },
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": "session-runtime-control",
      "command_id": "cmd-2",
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-runtime-control",
        "book_root": "/tmp/book",
        "command": "steer",
        "text": "also add tests",
        "packet": { "command_id": "cmd-2" },
      },
    },
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": "session-runtime-control",
      "command_id": "cmd-3",
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-runtime-control",
        "book_root": "/tmp/book",
        "command": "cancel",
        "packet": { "command_id": "cmd-3" },
      },
    },
  ]
  let state = mooncode_runtime_control_state_from_logs(
    "session-runtime-control",
    "/tmp/book",
    commands,
    [],
    journal_path="/tmp/book/journal.jsonl",
  )
  assert_eq(
    mooncode_json_string(state, "kind", default=""),
    "mooncode-runtime-control-state",
  )
  assert_eq(mooncode_json_string(state, "active_turn_id", default=""), "")
  assert_true(state.stringify().contains("\"pending_turn_count\":1"))
  let decisions = mooncode_json_array_items(state, "decisions")
  assert_eq(
    mooncode_json_string(decisions[0], "effect", default=""),
    "start-turn",
  )
  assert_eq(
    mooncode_json_string(decisions[1], "effect", default=""),
    "queue-steer",
  )
  assert_eq(
    mooncode_json_string(decisions[1], "target_command_id", default=""),
    "cmd-1",
  )
  assert_eq(
    mooncode_json_string(decisions[2], "effect", default=""),
    "withdraw-pending",
  )
}

///|
test "mooncode runtime control targets active claimed prompt" {
  let commands : Array[Json] = [
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": "session-active",
      "command_id": "cmd-1",
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-active",
        "book_root": "/tmp/book",
        "command": "prompt",
        "text": "implement app",
        "packet": { "command_id": "cmd-1" },
      },
    },
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": "session-active",
      "command_id": "cmd-2",
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-active",
        "book_root": "/tmp/book",
        "command": "steer",
        "text": "prefer MoonBit",
        "packet": { "command_id": "cmd-2" },
      },
    },
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": "session-active",
      "command_id": "cmd-3",
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-active",
        "book_root": "/tmp/book",
        "command": "cancel",
        "packet": { "command_id": "cmd-3" },
      },
    },
  ]
  let claimed = {
    "kind": mooncode_kind_runtime_receipt(),
    "protocol": mooncode_protocol_version(),
    "session_id": "session-active",
    "book_root": "/tmp/book",
    "command_id": "cmd-1",
    "status": "runtime-claimed",
    "claim_id": "claim-1",
  }
  let state = mooncode_runtime_control_state_from_logs(
    "session-active",
    "/tmp/book",
    commands,
    [claimed],
    journal_path="/tmp/book/journal.jsonl",
  )
  assert_eq(mooncode_json_string(state, "active_turn_id", default=""), "cmd-1")
  let decisions = mooncode_json_array_items(state, "decisions")
  assert_eq(
    mooncode_json_string(decisions[0], "effect", default=""),
    "active-turn",
  )
  assert_eq(
    mooncode_json_string(decisions[1], "effect", default=""),
    "deliver-steer",
  )
  assert_eq(
    mooncode_json_string(decisions[2], "effect", default=""),
    "cancel-active",
  )
}

///|
test "mooncode runtime selects live steering in journal order" {
  let commands : Array[Json] = [
    {
      "command_id": "prompt-1",
      "command": {
        "command": "prompt",
        "text": "implement",
        "packet": { "command_id": "prompt-1" },
      },
    },
    {
      "command_id": "steer-1",
      "created_at": "2026-07-27T10:00:01Z",
      "command": {
        "command": "steer",
        "text": "first correction",
        "packet": { "command_id": "steer-1" },
      },
    },
    {
      "command_id": "steer-2",
      "created_at": "2026-07-27T10:00:02Z",
      "command": {
        "command": "steer",
        "text": "second correction",
        "packet": { "command_id": "steer-2" },
      },
    },
    {
      "command_id": "cancel-1",
      "command": { "command": "cancel", "packet": { "command_id": "cancel-1" } },
    },
  ]
  let state = mooncode_runtime_control_state_from_logs(
    "session-live-steer",
    "/tmp/book",
    commands,
    [{ "command_id": "prompt-1", "status": "runtime-claimed" }],
    journal_path="/tmp/book/journal.jsonl",
  )
  let live = mooncode_runtime_turn_pending_live_steering(state, "prompt-1")
  assert_eq(live.length(), 2)
  assert_eq(mooncode_json_string(live[0], "command_id", default=""), "steer-1")
  assert_eq(
    mooncode_json_string(live[0], "steering_text", default=""),
    "first correction",
  )
  assert_eq(mooncode_json_string(live[1], "command_id", default=""), "steer-2")
  assert_eq(
    mooncode_json_string(live[1], "applied_to_command_id", default=""),
    "prompt-1",
  )
  assert_eq(
    mooncode_runtime_turn_pending_live_steering(state, "other-turn").length(),
    0,
  )
}

///|
test "mooncode runtime control treats delivered prompt as terminal and defers idle steer" {
  let commands : Array[Json] = [
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": "session-terminal",
      "command_id": "cmd-1",
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-terminal",
        "book_root": "/tmp/book",
        "command": "prompt",
        "text": "done",
        "packet": { "command_id": "cmd-1" },
      },
    },
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": "session-terminal",
      "command_id": "cmd-2",
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-terminal",
        "book_root": "/tmp/book",
        "command": "steer",
        "text": "too late",
        "packet": { "command_id": "cmd-2" },
      },
    },
  ]
  let delivered = {
    "kind": mooncode_kind_runtime_receipt(),
    "protocol": mooncode_protocol_version(),
    "session_id": "session-terminal",
    "book_root": "/tmp/book",
    "command_id": "cmd-1",
    "status": "runtime-delivered",
  }
  let state = mooncode_runtime_control_state_from_logs(
    "session-terminal",
    "/tmp/book",
    commands,
    [delivered],
    journal_path="/tmp/book/journal.jsonl",
  )
  let decisions = mooncode_json_array_items(state, "decisions")
  assert_eq(
    mooncode_json_string(decisions[0], "effect", default=""),
    "already-completed",
  )
  assert_eq(
    mooncode_json_string(decisions[1], "effect", default=""),
    "defer-steer",
  )
}
