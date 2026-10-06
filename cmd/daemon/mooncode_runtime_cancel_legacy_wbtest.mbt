///|
async test "legacy untagged active cancellation replay matches explicit event identities" {
  @fsx.with_temporary_directory("mooncode-legacy-cancel-replay-XXXXXX", async fn(
    root,
  ) {
    let daemon = mooncode_control_test_daemon(root)
    defer daemon.httpx.close()
    let cancel = mooncode_pending_cancel_test_control(root, "legacy-cancel", "")
    if cancel is Object(fields) {
      fields["model"] = "fixture/mooncode"
    }
    mooncode_pending_cancel_test_queue(root, [
      mooncode_pending_cancel_test_prompt(root, "withdrawn"),
      mooncode_pending_cancel_test_prompt(root, "retained"),
      cancel,
    ])
    ignore(
      mooncode_runtime_claim_atomic(
        root,
        "pending-cancel",
        {},
        @clock.Timestamp::from_ms(10L),
      ),
    )
    ignore(
      daemon.mooncode_submit_cancel_control("pending-cancel", root, cancel),
    )
    let records = mooncode_read_session_journal(root, "pending-cancel")
    let prefix : Array[String] = []
    let mut saw_legacy_receipt = false
    for record in records {
      let payload = mooncode_json_object_field_or_empty(record, "payload")
      let status = mooncode_json_string(payload, "status", default="")
      if mooncode_json_string(payload, "command_id", default="") ==
        "legacy-cancel" &&
        status == "runtime-completed" {
        break
      }
      if status == "runtime-cancelled" && payload is Object(fields) {
        fields.remove("control_command_id")
        fields.remove("interrupted_runtime")
        fields["events"] = Json::array([])
        saw_legacy_receipt = true
      }
      prefix.push(mooncode_journal_canonical_line(record))
    }
    assert_true(saw_legacy_receipt)
    @fsx.write_to_file(
      mooncode_session_journal_path(root, "pending-cancel"),
      prefix.join("\n") + "\n",
    )
    @fsx.remove(mooncode_session_snapshot_path(root, "pending-cancel"))
    let legacy_journal = mooncode_read_session_journal(root, "pending-cancel")
    let legacy_receipt = mooncode_journal_entries(
        legacy_journal,
        mooncode_journal_runtime_receipt(),
      ).filter(receipt => {
        mooncode_json_string(receipt, "status", default="") ==
        "runtime-cancelled"
      })[0]
    let legacy_event = mooncode_journal_entries(
        legacy_journal,
        mooncode_journal_event(),
      ).filter(event => {
        mooncode_json_string(event, "kind", default="") ==
        @moonlib_conversation.cancellation_event_kind()
      })[0]
    assert_eq(
      mooncode_json_string(legacy_receipt, "control_command_id", default=""),
      "",
    )
    assert_true(
      mooncode_runtime_legacy_cancel_matches(
        "pending-cancel", root, "legacy-cancel", legacy_event, legacy_receipt,
      ),
    )
    for
      field in [
        "session_id", "command_id", "target_command_id", "control_id", "control_command_id",
        "kind", "source", "contract_id",
      ] {
      assert_false(
        mooncode_runtime_legacy_cancel_matches(
          "pending-cancel",
          root,
          "legacy-cancel",
          mooncode_json_object_with_field(legacy_event, field, "unrelated"),
          legacy_receipt,
        ),
      )
    }
    for
      field in [
        "session_id", "book_root", "command_id", "status", "control_command_id",
        "runtime_mode",
      ] {
      assert_false(
        mooncode_runtime_legacy_cancel_matches(
          "pending-cancel",
          root,
          "legacy-cancel",
          legacy_event,
          mooncode_json_object_with_field(legacy_receipt, field, "unrelated"),
        ),
      )
    }
    let reloaded = mooncode_control_test_daemon(root)
    defer reloaded.httpx.close()
    @async.with_task_group(group => {
      let result = reloaded.mooncode_submit_turn_response(
        group~,
        "pending-cancel",
        cancel,
      )
      let control = mooncode_json_object_field_or_empty(result, "service")
      assert_false(
        mooncode_json_bool(control, "interrupted_runtime", default=true),
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
    let receipts = mooncode_journal_entries(
      mooncode_read_session_journal(root, "pending-cancel"),
      mooncode_journal_runtime_receipt(),
    )
    let control = receipts.filter(receipt => {
        mooncode_json_string(receipt, "command_id", default="") ==
        "legacy-cancel"
      })[0]
    assert_eq(
      mooncode_json_string(control, "target_command_id", default=""),
      "withdrawn",
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
  })
}
