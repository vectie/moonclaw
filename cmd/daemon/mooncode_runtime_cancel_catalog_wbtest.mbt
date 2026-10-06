///|
async test "cancel bypasses absent catalog without changing session model" {
  for requested_model in ["missing/unavailable-model", "invalid-model"] {
    @fsx.with_temporary_directory("mooncode-cancel-catalog-XXXXXX", async fn(
      root,
    ) {
      let daemon = mooncode_runtime_quantum_test_daemon(root)
      defer daemon.httpx.close()
      let binding = daemon.mooncode_binding_for_session("pending-cancel")
      ignore(binding.bind_book_root(root))
      binding.model = "preserved/selection"
      let cancel = mooncode_pending_cancel_test_control(
        root, "cancel-no-catalog", "withdrawn",
      )
      if cancel is Object(fields) {
        fields["model"] = requested_model.to_json()
      }
      mooncode_pending_cancel_test_queue(root, [
        mooncode_pending_cancel_test_prompt(root, "withdrawn"),
        mooncode_pending_cancel_test_prompt(root, "retained"),
      ])
      daemon.mooncode_persist_session(binding)
      @async.with_task_group(group => {
        let result = daemon.mooncode_submit_turn_response(
          group~,
          "pending-cancel",
          cancel,
        )
        let control = mooncode_json_object_field_or_empty(result, "service")
        assert_eq(
          mooncode_json_string(control, "target_command_id", default=""),
          "withdrawn",
        )
        assert_eq(
          mooncode_json_string(control, "status", default=""),
          "cancelled",
        )
        assert_eq(binding.model, "preserved/selection")
        let repeated = daemon.mooncode_submit_turn_response(
          group~,
          "pending-cancel",
          cancel,
        )
        assert_true(
          mooncode_json_bool(
            mooncode_json_object_field_or_empty(repeated, "queue"),
            "duplicate",
            default=false,
          ),
        )
        group.return_immediately(())
      })
      let reloaded = mooncode_runtime_quantum_test_daemon(root)
      defer reloaded.httpx.close()
      let reloaded_binding = reloaded.mooncode_binding_for_session(
        "pending-cancel",
      )
      ignore(reloaded_binding.bind_book_root(root))
      reloaded_binding.restore_session_metadata()
      assert_eq(reloaded_binding.model, "preserved/selection")
      ignore(
        reloaded.mooncode_runtime_service_execute("pending-cancel", root, {
          "live_wait_ms": 0,
        }),
      )
      assert_false(@fsx.exists(@pathx.join(root, "withdrawn.txt")))
      assert_eq(@fsx.read_file(@pathx.join(root, "retained.txt")), "retained")
      let commands = mooncode_journal_entries(
        mooncode_read_session_journal(root, "pending-cancel"),
        mooncode_journal_command(),
      )
      assert_eq(commands.length(), 3)
    })
  }
}

///|
async test "cancel without any selected model is accepted while prompt and steer still require catalog" {
  @fsx.with_temporary_directory("mooncode-cancel-no-model-XXXXXX", async fn(
    root,
  ) {
    let daemon = mooncode_runtime_quantum_test_daemon(root)
    defer daemon.httpx.close()
    @async.with_task_group(group => {
      let idle = daemon.mooncode_submit_turn_response(
        group~,
        "pending-cancel",
        mooncode_pending_cancel_test_control(root, "idle-no-model", ""),
      )
      assert_eq(
        mooncode_json_string(
          mooncode_json_object_field_or_empty(idle, "service"),
          "status",
          default="",
        ),
        "idle",
      )
      for action in ["prompt", "steer"] {
        let command : Json = {
          "protocol": mooncode_protocol_version(),
          "session_id": "pending-cancel",
          "book_root": root,
          "command": action,
          "model": "missing/unavailable-model",
          "packet": { "command_id": action + "-unavailable" },
        }
        let rejected = try {
          ignore(
            daemon.mooncode_submit_turn_response(
              group~,
              "pending-cancel",
              command,
            ),
          )
          false
        } catch {
          _ => true
        }
        assert_true(rejected)
      }
      group.return_immediately(())
    })
    let commands = mooncode_journal_entries(
      mooncode_read_session_journal(root, "pending-cancel"),
      mooncode_journal_command(),
    )
    assert_eq(commands.length(), 1)
    assert_eq(daemon.mooncode_binding_for_session("pending-cancel").model, "")
  })
}

///|
async test "unavailable cancel model cannot prevent stopping an active native request" {
  @fsx.with_temporary_directory("mooncode-cancel-running-catalog-XXXXXX", async fn(
    root,
  ) {
    let daemon = mooncode_control_test_daemon(root)
    defer daemon.httpx.close()
    @async.with_task_group(group => {
      let command : Json = {
        "protocol": mooncode_protocol_version(),
        "session_id": "pending-cancel",
        "book_root": root,
        "command": "prompt",
        "model": "fixture/mooncode",
        "packet": { "command_id": "running" },
        "runtime_tool_calls": [
          {
            "tool": "shell",
            "arguments": {
              "cmd": "printf started > running-started.txt; sleep 20; printf forbidden > running-forbidden.txt",
              "timeout_ms": 30000,
            },
          },
          { "tool": "finish", "arguments": { "answer": "finished" } },
        ],
      }
      ignore(
        daemon.mooncode_submit_turn_response(group~, "pending-cancel", command),
      )
      let binding = daemon.mooncode_binding_for_session("pending-cancel")
      let mut attempts = 0
      while binding.active_command_id == "" && attempts < 200 {
        @async.sleep(10)
        attempts += 1
      }
      assert_eq(binding.active_command_id, "running")
      assert_true(binding.runtime_service_running)
      let cancel = mooncode_pending_cancel_test_control(
        root, "stop-unavailable", "running",
      )
      if cancel is Object(fields) {
        fields["model"] = "missing/unavailable-model"
      }
      let result = daemon.mooncode_submit_turn_response(
        group~,
        "pending-cancel",
        cancel,
      )
      let control = mooncode_json_object_field_or_empty(result, "service")
      assert_true(
        mooncode_json_bool(control, "interrupted_runtime", default=false),
      )
      assert_eq(
        mooncode_json_string(control, "target_command_id", default=""),
        "running",
      )
      assert_eq(
        daemon.mooncode_binding_for_session("pending-cancel").model,
        "fixture/mooncode",
      )
      group.return_immediately(())
    })
    assert_false(@fsx.exists(@pathx.join(root, "running-forbidden.txt")))
    let state = daemon.mooncode_runtime_claim_state_payload(
      "pending-cancel", root,
    )
    assert_eq(mooncode_json_int(state, "claimed_command_count", default=-1), 0)
    assert_eq(
      mooncode_json_int(state, "delivered_command_count", default=-1),
      2,
    )
  })
}
