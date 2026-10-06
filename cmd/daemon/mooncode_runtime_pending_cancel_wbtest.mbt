///|
fn mooncode_pending_cancel_test_prompt(
  root : String,
  command_id : String,
) -> Json {
  {
    "protocol": mooncode_protocol_version(),
    "session_id": "pending-cancel",
    "book_root": root,
    "command": "prompt",
    "text": command_id,
    "model": "fixture/mooncode",
    "packet": {
      "command_id": command_id,
      "client_turn_id": "client-" + command_id,
    },
    "runtime_tool_calls": [
      {
        "tool": "write",
        "arguments": { "path": command_id + ".txt", "content": command_id },
      },
      { "tool": "finish", "arguments": { "answer": "done " + command_id } },
    ],
  }
}

///|
fn mooncode_pending_cancel_test_control(
  root : String,
  command_id : String,
  target : String,
) -> Json {
  {
    "protocol": mooncode_protocol_version(),
    "session_id": "pending-cancel",
    "book_root": root,
    "command": "cancel",
    "packet": { "command_id": command_id },
    "payload": { "target_command_id": target },
  }
}

///|
async fn mooncode_pending_cancel_test_queue(
  root : String,
  commands : Array[Json],
) -> Unit {
  for index, command in commands {
    mooncode_append_session_journal(
      root,
      "pending-cancel",
      mooncode_journal_command(),
      {
        "kind": "mooncode-command",
        "protocol": mooncode_protocol_version(),
        "session_id": "pending-cancel",
        "command_id": mooncode_command_id(command),
        "created_at": @clock.Timestamp::from_ms(index.to_int64() + 1L),
        "command": command,
      },
    )
  }
}

///|
async test "untargeted pending cancel prevents native output and preserves next prompt after reload" {
  @fsx.with_temporary_directory("mooncode-pending-cancel-XXXXXX", async fn(
    root,
  ) {
    let daemon = mooncode_runtime_quantum_test_daemon(root)
    defer daemon.httpx.close()
    let cancel = mooncode_pending_cancel_test_control(root, "cancel-first", "")
    mooncode_pending_cancel_test_queue(root, [
      mooncode_pending_cancel_test_prompt(root, "withdrawn"),
      mooncode_pending_cancel_test_prompt(root, "retained"),
      cancel,
    ])
    let before = daemon.mooncode_runtime_claim_state_payload(
      "pending-cancel", root,
    )
    assert_eq(mooncode_json_int(before, "claimed_command_count", default=-1), 0)
    let result = daemon.mooncode_submit_cancel_control(
      "pending-cancel", root, cancel,
    )
    // Real native execution is the primary assertion, not the response label.
    let reloaded = mooncode_runtime_quantum_test_daemon(root)
    defer reloaded.httpx.close()
    ignore(
      reloaded.mooncode_runtime_service_execute("pending-cancel", root, {
        "live_wait_ms": 0,
      }),
    )
    assert_false(@fsx.exists(@pathx.join(root, "withdrawn.txt")))
    assert_eq(@fsx.read_file(@pathx.join(root, "retained.txt")), "retained")
    assert_eq(
      mooncode_json_string(result, "target_command_id", default=""),
      "withdrawn",
    )
    assert_eq(mooncode_json_string(result, "status", default=""), "cancelled")
    let record = reloaded
      .mooncode_session_record("pending-cancel", root)
      .unwrap()
    let turns = mooncode_json_array_items(
      mooncode_json_object_field_or_empty(record, "mooncode_conversation"),
      "turns",
    )
    assert_eq(turns.length(), 2)
    assert_eq(mooncode_json_string(turns[0], "status", default=""), "cancelled")
    let state = reloaded.mooncode_runtime_claim_state_payload(
      "pending-cancel", root,
    )
    assert_eq(
      mooncode_json_int(state, "delivered_command_count", default=-1),
      3,
    )
    assert_eq(
      mooncode_json_int(state, "claimable_command_count", default=-1),
      0,
    )
  })
}

///|
async test "targeted pending cancel withdraws exact order blocked prompt" {
  @fsx.with_temporary_directory("mooncode-targeted-pending-XXXXXX", async fn(
    root,
  ) {
    let daemon = mooncode_runtime_quantum_test_daemon(root)
    defer daemon.httpx.close()
    let cancel = mooncode_pending_cancel_test_control(
      root, "cancel-second", "withdrawn",
    )
    mooncode_pending_cancel_test_queue(root, [
      mooncode_pending_cancel_test_prompt(root, "first"),
      mooncode_pending_cancel_test_prompt(root, "withdrawn"),
      mooncode_pending_cancel_test_prompt(root, "third"),
      cancel,
    ])
    let result = daemon.mooncode_submit_cancel_control(
      "pending-cancel", root, cancel,
    )
    ignore(
      daemon.mooncode_runtime_service_execute("pending-cancel", root, {
        "live_wait_ms": 0,
      }),
    )
    assert_false(@fsx.exists(@pathx.join(root, "withdrawn.txt")))
    assert_eq(@fsx.read_file(@pathx.join(root, "first.txt")), "first")
    assert_eq(@fsx.read_file(@pathx.join(root, "third.txt")), "third")
    assert_eq(
      mooncode_json_string(result, "target_command_id", default=""),
      "withdrawn",
    )
  })
}

///|
async test "repeating a pending cancel identity does not withdraw another prompt" {
  @fsx.with_temporary_directory("mooncode-repeated-pending-XXXXXX", async fn(
    root,
  ) {
    let daemon = mooncode_runtime_quantum_test_daemon(root)
    defer daemon.httpx.close()
    let cancel = mooncode_pending_cancel_test_control(root, "cancel-once", "")
    mooncode_pending_cancel_test_queue(root, [
      mooncode_pending_cancel_test_prompt(root, "withdrawn"),
      mooncode_pending_cancel_test_prompt(root, "retained"),
      cancel,
    ])
    let first = daemon.mooncode_submit_cancel_control(
      "pending-cancel", root, cancel,
    )
    let second = daemon.mooncode_submit_cancel_control(
      "pending-cancel", root, cancel,
    )
    assert_eq(
      mooncode_json_string(first, "target_command_id", default=""),
      mooncode_json_string(second, "target_command_id", default=""),
    )
    ignore(
      daemon.mooncode_runtime_service_execute("pending-cancel", root, {
        "live_wait_ms": 0,
      }),
    )
    assert_false(@fsx.exists(@pathx.join(root, "withdrawn.txt")))
    assert_eq(@fsx.read_file(@pathx.join(root, "retained.txt")), "retained")
  })
}

///|
async test "idle cancel remains an idempotent no-op when work arrives later" {
  @fsx.with_temporary_directory("mooncode-idle-cancel-XXXXXX", async fn(root) {
    let daemon = mooncode_runtime_quantum_test_daemon(root)
    defer daemon.httpx.close()
    let cancel = mooncode_pending_cancel_test_control(root, "idle-cancel", "")
    mooncode_pending_cancel_test_queue(root, [cancel])
    let result = daemon.mooncode_submit_cancel_control(
      "pending-cancel", root, cancel,
    )
    assert_eq(mooncode_json_string(result, "status", default=""), "idle")
    assert_eq(
      mooncode_json_string(result, "target_command_id", default="unexpected"),
      "",
    )
    mooncode_pending_cancel_test_queue(root, [
      mooncode_pending_cancel_test_prompt(root, "later"),
    ])
    let reloaded = mooncode_runtime_quantum_test_daemon(root)
    defer reloaded.httpx.close()
    let repeated = reloaded.mooncode_submit_cancel_control(
      "pending-cancel", root, cancel,
    )
    assert_eq(mooncode_json_string(repeated, "status", default=""), "idle")
    ignore(
      reloaded.mooncode_runtime_service_execute("pending-cancel", root, {
        "live_wait_ms": 0,
      }),
    )
    assert_eq(@fsx.read_file(@pathx.join(root, "later.txt")), "later")
  })
}

///|
async test "cancel and claim barriers preserve both settlement orderings" {
  for cancel_first in [true, false] {
    @fsx.with_temporary_directory("mooncode-cancel-barrier-XXXXXX", async fn(
      root,
    ) {
      let daemon = mooncode_runtime_quantum_test_daemon(root)
      defer daemon.httpx.close()
      let cancel = mooncode_pending_cancel_test_control(
        root, "barrier-cancel", "withdrawn",
      )
      mooncode_pending_cancel_test_queue(root, [
        mooncode_pending_cancel_test_prompt(root, "withdrawn"),
        mooncode_pending_cancel_test_prompt(root, "retained"),
        cancel,
      ])
      let barrier : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
      let tasks : Array[async () -> Unit] = [
        async fn() {
          if cancel_first {
            ignore(
              daemon.mooncode_submit_cancel_control(
                "pending-cancel", root, cancel,
              ),
            )
          } else {
            let claim = mooncode_runtime_claim_atomic(
              root,
              "pending-cancel",
              {},
              @clock.Timestamp::from_ms(10L),
            )
            assert_eq(claim.receipts.length(), 1)
            assert_eq(
              mooncode_json_string(claim.receipts[0], "command_id", default=""),
              "withdrawn",
            )
          }
          barrier.put(())
        },
        async fn() {
          barrier.get()
          if cancel_first {
            ignore(
              daemon.mooncode_runtime_service_execute("pending-cancel", root, {
                "live_wait_ms": 0,
              }),
            )
          } else {
            let result = daemon.mooncode_submit_cancel_control(
              "pending-cancel", root, cancel,
            )
            assert_eq(
              mooncode_json_string(result, "target_command_id", default=""),
              "withdrawn",
            )
          }
        },
      ]
      ignore(@async.all(tasks))
      if !cancel_first {
        ignore(
          daemon.mooncode_runtime_service_execute("pending-cancel", root, {
            "live_wait_ms": 0,
          }),
        )
      }
      assert_false(@fsx.exists(@pathx.join(root, "withdrawn.txt")))
      assert_eq(@fsx.read_file(@pathx.join(root, "retained.txt")), "retained")
      let receipts = mooncode_journal_entries(
        mooncode_read_session_journal(root, "pending-cancel"),
        mooncode_journal_runtime_receipt(),
      )
      let target_receipts = receipts.filter(item => {
        mooncode_json_string(item, "command_id", default="") == "withdrawn"
      })
      assert_eq(target_receipts.length(), if cancel_first { 1 } else { 2 })
      assert_eq(
        mooncode_json_string(
          target_receipts.last().unwrap(),
          "status",
          default="",
        ),
        "runtime-cancelled",
      )
    })
  }
}

///|
async test "pending withdrawal preserves an active approval claim and its eventual resume" {
  @fsx.with_temporary_directory("mooncode-pending-approval-XXXXXX", async fn(
    root,
  ) {
    let daemon = mooncode_control_test_daemon(root)
    defer daemon.httpx.close()
    let active = mooncode_pending_cancel_test_prompt(root, "active")
    if active is Object(fields) {
      fields["payload"] = { "approval_wait_ms": 0 }
      fields["runtime_tool_calls"] = [
        {
          "tool": "write",
          "requires_approval": true,
          "arguments": { "path": "active.txt", "content": "active" },
        },
        { "tool": "finish", "arguments": { "answer": "active completed" } },
      ]
    }
    let cancel = mooncode_pending_cancel_test_control(
      root, "cancel-pending", "withdrawn",
    )
    mooncode_pending_cancel_test_queue(root, [
      active,
      mooncode_pending_cancel_test_prompt(root, "withdrawn"),
      mooncode_pending_cancel_test_prompt(root, "retained"),
      cancel,
    ])
    let waiting = daemon.mooncode_runtime_turn_execute("pending-cancel", root, {})
    assert_true(
      mooncode_json_bool(
        mooncode_json_object_field_or_empty(waiting, "execution"),
        "waiting_approval",
        default=false,
      ),
    )
    let result = daemon.mooncode_submit_cancel_control(
      "pending-cancel", root, cancel,
    )
    assert_false(
      mooncode_json_bool(result, "interrupted_runtime", default=true),
    )
    assert_false(
      mooncode_goal_runtime_is_active_cancel_source(
        mooncode_json_object_field_or_empty(result, "cancelled_event"),
      ),
    )
    let claim_state = daemon.mooncode_runtime_claim_state_payload(
      "pending-cancel", root,
    )
    let claimed = mooncode_json_array_items(claim_state, "claimed_commands")
    assert_eq(claimed.length(), 1)
    assert_eq(
      mooncode_json_string(claimed[0], "command_id", default=""),
      "active",
    )
    let request = mooncode_control_test_approval_request(
      mooncode_journal_entries(
        mooncode_read_session_journal(root, "pending-cancel"),
        mooncode_journal_event(),
      ),
    )
    @async.with_task_group(group => {
      let approved = daemon.mooncode_submit_turn_response(
        group~,
        "pending-cancel",
        {
          "protocol": mooncode_protocol_version(),
          "session_id": "pending-cancel",
          "book_root": root,
          "command": "approve_tool",
          "model": "fixture/mooncode",
          "packet": { "command_id": "approve-active" },
          "payload": {
            "approval_id": mooncode_json_string(
              request,
              "approval_id",
              default="",
            ),
            "target_command_id": "active",
            "tool_call_id": mooncode_json_string(
              request,
              "tool_call_id",
              default="",
            ),
          },
        },
      )
      assert_true(mooncode_json_bool(approved, "accepted", default=false))
      let binding = daemon.mooncode_binding_for_session("pending-cancel")
      let mut attempts = 0
      while binding.runtime_service_running && attempts < 200 {
        @async.sleep(10)
        attempts += 1
      }
      assert_false(binding.runtime_service_running)
      group.return_immediately(())
    })
    assert_false(@fsx.exists(@pathx.join(root, "withdrawn.txt")))
    assert_eq(@fsx.read_file(@pathx.join(root, "active.txt")), "active")
    assert_eq(@fsx.read_file(@pathx.join(root, "retained.txt")), "retained")
  })
}

///|
async test "pending cancellation preserves deferred steering for the next surviving turn" {
  @fsx.with_temporary_directory("mooncode-pending-cancel-steer-XXXXXX", async fn(
    root,
  ) {
    let daemon = mooncode_runtime_quantum_test_daemon(root)
    defer daemon.httpx.close()
    let steer : Json = {
      "protocol": mooncode_protocol_version(),
      "session_id": "pending-cancel",
      "book_root": root,
      "command": "steer",
      "text": "Keep the answer concise",
      "packet": { "command_id": "deferred-steer" },
    }
    mooncode_pending_cancel_test_queue(root, [steer])
    let deferred = daemon.mooncode_runtime_turn_execute(
      "pending-cancel",
      root,
      {},
    )
    assert_eq(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(deferred, "execution"),
        "control",
        default="",
      ),
      "steer_deferred",
    )
    let cancel = mooncode_pending_cancel_test_control(
      root, "cancel-after-steer", "",
    )
    mooncode_pending_cancel_test_queue(root, [
      mooncode_pending_cancel_test_prompt(root, "withdrawn"),
      mooncode_pending_cancel_test_prompt(root, "retained"),
      cancel,
    ])
    ignore(
      daemon.mooncode_submit_cancel_control("pending-cancel", root, cancel),
    )
    ignore(
      daemon.mooncode_runtime_service_execute("pending-cancel", root, {
        "live_wait_ms": 0,
      }),
    )
    assert_false(@fsx.exists(@pathx.join(root, "withdrawn.txt")))
    assert_eq(@fsx.read_file(@pathx.join(root, "retained.txt")), "retained")
    let events = mooncode_journal_entries(
      mooncode_read_session_journal(root, "pending-cancel"),
      mooncode_journal_event(),
    )
    let applied = events.filter(event => {
      mooncode_json_string(event, "kind", default="") ==
      mooncode_event_steer_applied()
    })
    assert_eq(applied.length(), 1)
    assert_eq(
      mooncode_json_string(applied[0], "applied_to_command_id", default=""),
      "retained",
    )
  })
}
