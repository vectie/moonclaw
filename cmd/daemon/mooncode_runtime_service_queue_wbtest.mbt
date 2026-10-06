///|
test "ordinary native service drains a second queued prompt" {
  let root = "/test-book"
  let session_id = "service-queue"
  let commands : Array[Json] = [
    {
      "command_id": "prompt-a",
      "command": { "command": "prompt", "packet": { "command_id": "prompt-a" } },
    },
    {
      "command_id": "prompt-b",
      "command": { "command": "prompt", "packet": { "command_id": "prompt-b" } },
    },
  ]
  let state = mooncode_runtime_claim_state_from_logs(
    session_id,
    root,
    commands,
    [{ "command_id": "prompt-a", "status": "runtime-delivered" }],
    journal_path="",
  )
  assert_true(mooncode_json_bool(state, "claim_ready", default=false))
  assert_eq(mooncode_runtime_loop_max_turns({}), 1)
  let result : Json = {
    "stopped_by": "max_turns",
    "failed_turn_count": 0,
    "turns": [{ "execution": { "completed": true, "paused": false } }],
    "claim_state": state,
  }
  assert_true(mooncode_runtime_service_continues_queued_work(result, state))
}

///|
async fn mooncode_service_queue_output_test(max_turns : Int?) -> Unit {
  @fsx.with_temporary_directory("mooncode-service-output-XXXXXX", async fn(
    root,
  ) {
    let session_id = "service-output"
    for index in 0..<2 {
      let command_id = "prompt-" + index.to_string()
      let command : Json = {
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "book_root": root,
        "command": "prompt",
        "model": "fixture/mooncode",
        "packet": { "command_id": command_id },
        "runtime_tool_calls": [
          {
            "tool": "write",
            "arguments": { "path": command_id + ".txt", "content": command_id },
          },
          { "tool": "finish", "arguments": { "answer": "done " + command_id } },
        ],
      }
      mooncode_append_session_journal(
        root,
        session_id,
        mooncode_journal_command(),
        {
          "kind": "mooncode-command",
          "protocol": mooncode_protocol_version(),
          "session_id": session_id,
          "command_id": command_id,
          "created_at": @clock.Timestamp::from_ms(2L + index.to_int64()),
          "command": command,
        },
      )
    }
    let daemon = mooncode_runtime_quantum_test_daemon(root)
    defer daemon.httpx.close()
    let payload : Json = match max_turns {
      Some(limit) => { "live_wait_ms": 0, "max_turns": limit }
      None => { "live_wait_ms": 0 }
    }
    let expected_count = max_turns.unwrap_or(2)
    let result = daemon.mooncode_runtime_service_execute(
      session_id, root, payload,
    )
    assert_true(mooncode_json_bool(result, "accepted", default=false))
    for index in 0..<expected_count {
      let command_id = "prompt-" + index.to_string()
      assert_eq(
        @fsx.read_file(@pathx.join(root, command_id + ".txt")),
        command_id,
      )
    }
    let claim_state = daemon.mooncode_runtime_claim_state_payload(
      session_id, root,
    )
    assert_eq(
      mooncode_json_int(claim_state, "delivered_command_count", default=0),
      expected_count,
    )
    assert_eq(
      mooncode_json_int(claim_state, "claimed_command_count", default=0),
      0,
    )
    assert_eq(
      mooncode_json_bool(claim_state, "claim_ready", default=true),
      expected_count < 2,
    )
    if expected_count < 2 {
      assert_false(@fsx.exists(@pathx.join(root, "prompt-1.txt")))
    }
    let events = daemon.mooncode_runtime_service_events(session_id, root)
    assert_eq(events.length(), 1)
    assert_eq(
      mooncode_json_string(events[0], "kind", default=""),
      "runtime.service_finished",
    )
  })
}

///|
async test "ordinary native service writes outputs for two queued prompts" {
  mooncode_service_queue_output_test(None)
}

///|
async test "explicit manual service max_turns remains bounded" {
  mooncode_service_queue_output_test(Some(1))
  mooncode_service_queue_output_test(Some(2))
}

///|
test "ordinary service queue drain preserves stop and pause boundaries" {
  assert_true(mooncode_runtime_service_auto_drains_queue({}))
  assert_false(mooncode_runtime_service_auto_drains_queue({ "max_turns": 1 }))
  assert_false(mooncode_runtime_service_auto_drains_queue({ "max_turns": 2 }))
  let ready : Json = { "claim_ready": true, "claimed_command_count": 0 }
  for stopped_by in ["max_turns", "idle"] {
    let result : Json = { "stopped_by": stopped_by, "turns": [] }
    assert_true(mooncode_runtime_service_continues_queued_work(result, ready))
    assert_true(mooncode_runtime_service_rearm_requested(result, true))
    assert_false(mooncode_runtime_service_rearm_requested(result, false))
    assert_false(
      mooncode_runtime_service_continues_queued_work(result, {
        "claim_ready": false,
        "claimed_command_count": 0,
      }),
    )
    assert_false(
      mooncode_runtime_service_continues_queued_work(result, {
        "claim_ready": true,
        "claimed_command_count": 1,
      }),
    )
  }
  for stopped_by in ["approval", "cancelled", "failed", "retryable", "busy"] {
    let result : Json = { "stopped_by": stopped_by, "turns": [] }
    assert_false(mooncode_runtime_service_continues_queued_work(result, ready))
    assert_false(mooncode_runtime_service_rearm_requested(result, true))
  }
  for execution in [{ "paused": true }, { "waiting_approval": true }] {
    let result : Json = {
      "stopped_by": "max_turns",
      "turns": [{ "execution": execution }],
    }
    assert_false(mooncode_runtime_service_continues_queued_work(result, ready))
    assert_false(mooncode_runtime_service_rearm_requested(result, true))
  }
  assert_false(
    mooncode_runtime_service_continues_queued_work(
      { "stopped_by": "max_turns", "failed_turn_count": 1, "turns": [] },
      ready,
    ),
  )
}

///|
test "service rearm lifecycle events have distinct IDs within one clock tick" {
  let event : Json = { "id": "service-finished-1", "service_id": "service" }
  assert_eq(mooncode_runtime_service_rearm_event(event, 0), event)
  let first = mooncode_runtime_service_rearm_event(event, 1)
  let second = mooncode_runtime_service_rearm_event(event, 2)
  assert_true(first != second)
  assert_eq(mooncode_json_string(first, "service_id", default=""), "service")
}

///|
async test "already running native service records a pending wake" {
  @fsx.with_temporary_directory("mooncode-service-wake-XXXXXX", async fn(root) {
    let daemon = mooncode_runtime_quantum_test_daemon(root)
    defer daemon.httpx.close()
    let session_id = "service-wake"
    let binding = daemon.mooncode_binding_for_session(session_id)
    assert_true(binding.bind_book_root(root))
    binding.runtime_service_running = true
    assert_false(binding.runtime_service_wake_pending)
    @async.with_task_group(group => {
      let response = daemon.mooncode_start_runtime_service(
        group~,
        session_id,
        root,
        {},
      )
      assert_false(mooncode_json_bool(response, "started", default=true))
      assert_eq(mooncode_json_string(response, "status", default=""), "running")
      assert_true(binding.runtime_service_wake_pending)
    })
    // This fixture does not start a service task or model request.
    binding.runtime_service_running = false
  })
}
