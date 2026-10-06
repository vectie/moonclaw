///|
async fn mooncode_cancel_replay_test_prefix(
  root : String,
  retain_event : Bool,
) -> Json {
  let daemon = mooncode_control_test_daemon(root)
  defer daemon.httpx.close()
  let cancel = mooncode_pending_cancel_test_control(root, "replayed-cancel", "")
  if cancel is Object(fields) {
    fields["model"] = "fixture/mooncode"
  }
  mooncode_pending_cancel_test_queue(root, [
    mooncode_pending_cancel_test_prompt(root, "withdrawn"),
    mooncode_pending_cancel_test_prompt(root, "retained"),
    cancel,
  ])
  ignore(daemon.mooncode_submit_cancel_control("pending-cancel", root, cancel))
  // Preserve the exact validated durable prefix at either multi-append boundary:
  // three accepted commands, target receipt, and optionally its event.
  let path = mooncode_session_journal_path(root, "pending-cancel")
  let lines = @fsx.read_file(path).split("\n").collect()
  let keep = if retain_event { 5 } else { 4 }
  @fsx.write_to_file(
    path,
    lines[:keep].map(line => line.to_owned()).join("\n") + "\n",
  )
  @fsx.remove(mooncode_session_snapshot_path(root, "pending-cancel"))
  let journal = mooncode_read_session_journal(root, "pending-cancel")
  assert_eq(
    mooncode_journal_entries(journal, mooncode_journal_runtime_receipt()).length(),
    1,
  )
  cancel
}

///|
async test "partial pending cancellation replay settles original target after reload" {
  for retain_event in [false, true] {
    @fsx.with_temporary_directory("mooncode-cancel-partial-XXXXXX", async fn(
      root,
    ) {
      let cancel = mooncode_cancel_replay_test_prefix(root, retain_event)
      let reloaded = mooncode_control_test_daemon(root)
      defer reloaded.httpx.close()
      let replay = reloaded.mooncode_submit_cancel_control(
        "pending-cancel", root, cancel,
      )
      ignore(
        reloaded.mooncode_runtime_service_execute("pending-cancel", root, {
          "live_wait_ms": 0,
        }),
      )
      assert_false(@fsx.exists(@pathx.join(root, "withdrawn.txt")))
      assert_eq(@fsx.read_file(@pathx.join(root, "retained.txt")), "retained")
      assert_eq(
        mooncode_json_string(replay, "target_command_id", default=""),
        "withdrawn",
      )
      let journal = mooncode_read_session_journal(root, "pending-cancel")
      let receipts = mooncode_journal_entries(
        journal,
        mooncode_journal_runtime_receipt(),
      )
      assert_eq(
        receipts
        .filter(receipt => {
          mooncode_json_string(receipt, "status", default="") ==
          "runtime-cancelled"
        })
        .length(),
        1,
      )
      let events = mooncode_journal_entries(journal, mooncode_journal_event())
      assert_eq(
        events
        .filter(event => {
          mooncode_json_string(event, "kind", default="") ==
          @moonlib_conversation.cancellation_event_kind()
        })
        .length(),
        1,
      )
    })
  }
}

///|
async test "public duplicate cancel settles command-only and target-receipt prefixes" {
  for target_receipt in [false, true] {
    @fsx.with_temporary_directory("mooncode-submit-cancel-replay-XXXXXX", async fn(
      root,
    ) {
      let cancel = if target_receipt {
        mooncode_cancel_replay_test_prefix(root, false)
      } else {
        let cancel = mooncode_pending_cancel_test_control(
          root, "replayed-cancel", "",
        )
        if cancel is Object(fields) {
          fields["model"] = "fixture/mooncode"
        }
        mooncode_pending_cancel_test_queue(root, [
          mooncode_pending_cancel_test_prompt(root, "withdrawn"),
          mooncode_pending_cancel_test_prompt(root, "retained"),
          cancel,
        ])
        cancel
      }
      let reloaded = mooncode_control_test_daemon(root)
      defer reloaded.httpx.close()
      @async.with_task_group(group => {
        let result = reloaded.mooncode_submit_turn_response(
          group~,
          "pending-cancel",
          cancel,
        )
        assert_true(
          mooncode_json_bool(
            mooncode_json_object_field_or_empty(result, "queue"),
            "duplicate",
            default=false,
          ),
        )
        group.return_immediately(())
      })
      let state = reloaded.mooncode_runtime_claim_state_payload(
        "pending-cancel", root,
      )
      assert_false(mooncode_runtime_command_pending(state, "replayed-cancel"))
      ignore(
        reloaded.mooncode_runtime_service_execute("pending-cancel", root, {
          "live_wait_ms": 0,
        }),
      )
      assert_false(@fsx.exists(@pathx.join(root, "withdrawn.txt")))
      assert_eq(@fsx.read_file(@pathx.join(root, "retained.txt")), "retained")
    })
  }
}

///|
async test "partial active cancel replay preserves target and actual interruption flag" {
  for was_running in [false, true] {
    @fsx.with_temporary_directory("mooncode-active-cancel-replay-XXXXXX", async fn(
      root,
    ) {
      let daemon = mooncode_control_test_daemon(root)
      defer daemon.httpx.close()
      let cancel = mooncode_pending_cancel_test_control(
        root, "replayed-active-cancel", "",
      )
      if cancel is Object(fields) {
        fields["model"] = "fixture/mooncode"
      }
      let prompt = mooncode_pending_cancel_test_prompt(root, "withdrawn")
      if was_running && prompt is Object(fields) {
        fields["runtime_tool_calls"] = [
          {
            "tool": "write",
            "requires_approval": true,
            "arguments": { "path": "withdrawn.txt", "content": "forbidden" },
          },
          { "tool": "finish", "arguments": { "answer": "finished" } },
        ]
      }
      @async.with_task_group(group => {
        if was_running {
          ignore(
            daemon.mooncode_submit_turn_response(
              group~,
              "pending-cancel",
              prompt,
            ),
          )
          let binding = daemon.mooncode_binding_for_session("pending-cancel")
          let mut attempts = 0
          while binding.active_command_id == "" && attempts < 200 {
            @async.sleep(10)
            attempts += 1
          }
          assert_eq(binding.active_command_id, "withdrawn")
          assert_true(binding.runtime_service_running)
        } else {
          mooncode_pending_cancel_test_queue(root, [prompt])
          ignore(
            mooncode_runtime_claim_atomic(
              root,
              "pending-cancel",
              {},
              @clock.Timestamp::from_ms(10L),
            ),
          )
        }
        mooncode_pending_cancel_test_queue(root, [
          mooncode_pending_cancel_test_prompt(root, "retained"),
          cancel,
        ])
        let settled = daemon.mooncode_submit_cancel_control(
          "pending-cancel", root, cancel,
        )
        assert_eq(
          mooncode_json_bool(
            settled,
            "interrupted_runtime",
            default=!was_running,
          ),
          was_running,
        )
        group.return_immediately(())
      })
      let path = mooncode_session_journal_path(root, "pending-cancel")
      let records = mooncode_read_session_journal(root, "pending-cancel")
      let mut keep = -1
      for index, record in records {
        let payload = mooncode_json_object_field_or_empty(record, "payload")
        if mooncode_json_string(record, "record_kind", default="") ==
          mooncode_journal_runtime_receipt() &&
          mooncode_json_string(payload, "command_id", default="") ==
          "replayed-active-cancel" &&
          mooncode_json_string(payload, "status", default="") ==
          "runtime-completed" {
          keep = index
          break
        }
      }
      assert_true(keep > 0)
      let lines = @fsx.read_file(path).split("\n").collect()
      @fsx.write_to_file(
        path,
        lines[:keep].map(line => line.to_owned()).join("\n") + "\n",
      )
      @fsx.remove(mooncode_session_snapshot_path(root, "pending-cancel"))
      let reloaded = mooncode_control_test_daemon(root)
      defer reloaded.httpx.close()
      @async.with_task_group(group => {
        let result = reloaded.mooncode_submit_turn_response(
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
          mooncode_json_bool(
            control,
            "interrupted_runtime",
            default=!was_running,
          ),
          was_running,
        )
        group.return_immediately(())
      })
      ignore(
        reloaded.mooncode_runtime_service_execute("pending-cancel", root, {
          "live_wait_ms": 0,
        }),
      )
      assert_false(@fsx.exists(@pathx.join(root, "withdrawn.txt")))
      assert_eq(@fsx.read_file(@pathx.join(root, "retained.txt")), "retained")
    })
  }
}
