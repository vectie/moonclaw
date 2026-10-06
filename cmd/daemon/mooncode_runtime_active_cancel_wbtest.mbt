///|
test "active cancel replay does not certify cancellation of an already terminal target" {
  let response = mooncode_runtime_cancel_response({
    "session_id": "pending-cancel",
    "book_root": "/fixture",
    "command_id": "cancel",
    "target_command_id": "completed",
    "cancel_status": "already-terminal",
    "target_status": "runtime-completed",
    "interrupted_runtime": false,
  })
  assert_eq(
    mooncode_json_string(response, "status", default=""),
    "already-terminal",
  )
  assert_false(
    mooncode_json_bool(response, "interrupted_runtime", default=true),
  )
}

///|
async fn mooncode_active_cancel_test_select(
  root : String,
  cancel : Json,
) -> Json {
  mooncode_pending_cancel_test_queue(root, [
    mooncode_pending_cancel_test_prompt(root, "original"),
    mooncode_pending_cancel_test_prompt(root, "unrelated"),
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
  match
    mooncode_runtime_cancel_pending_atomic(
      "pending-cancel",
      root,
      cancel,
      now=@clock.Timestamp::from_ms(20L),
    ) {
    Active(item) => item
    Settled(_) => fail("expected an active original target")
  }
}

///|
async fn mooncode_active_cancel_test_terminal(
  root : String,
  item : Json,
  status : String,
) -> Json {
  let receipt : Json = {
    "kind": mooncode_kind_runtime_receipt(),
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": "pending-cancel",
    "book_root": root,
    "command_id": "original",
    "status": status,
    "completed_at": @clock.Timestamp::from_ms(30L),
    "command": mooncode_json_object_field_or_empty(item, "command"),
    "execution": {
      "output": "committed output",
      "engineering_receipt": { "outcome": "nochange" },
    },
  }
  mooncode_append_session_journal(
    root,
    "pending-cancel",
    mooncode_journal_runtime_receipt(),
    receipt,
  )
  receipt
}

///|
async test "active cancel selection pins target across completion and retry" {
  @fsx.with_temporary_directory("mooncode-active-pin-XXXXXX", async fn(root) {
    let cancel = mooncode_pending_cancel_test_control(
      root, "cancel-original", "",
    )
    let item = mooncode_active_cancel_test_select(root, cancel)
    ignore(
      mooncode_active_cancel_test_terminal(root, item, "runtime-completed"),
    )
    let replay = mooncode_runtime_cancel_pending_atomic(
      "pending-cancel",
      root,
      cancel,
      now=@clock.Timestamp::from_ms(40L),
    )
    let target = match replay {
      Active(item) => mooncode_json_string(item, "command_id", default="")
      Settled(response) =>
        mooncode_json_string(response, "target_command_id", default="")
    }
    assert_eq(target, "original")
    let receipts = mooncode_journal_entries(
      mooncode_read_session_journal(root, "pending-cancel"),
      mooncode_journal_runtime_receipt(),
    )
    assert_eq(
      receipts
      .filter(receipt => {
        mooncode_json_string(receipt, "status", default="") ==
        "runtime-cancelled"
      })
      .length(),
      0,
    )
  })
}

///|
async test "active cancel replay reconciles a goal after a completed-control crash prefix" {
  @fsx.with_temporary_directory("mooncode-active-goal-replay-XXXXXX", async fn(
    root,
  ) {
    let session = "pending-cancel"
    goal_gate_write_snapshot(
      root,
      session,
      false,
      goal_gate_snapshot(session, root),
    )
    assert_eq(
      mooncode_goal_runtime_api_put_internal(
        root,
        session,
        goal_runtime_test_body(session),
        1L,
      ).status_code,
      201,
    )
    let cancel = mooncode_pending_cancel_test_control(
      root, "cancel-original", "original",
    )
    let item = mooncode_active_cancel_test_select(root, cancel)
    // The native target, source event, and completed control are durable, but
    // the process stops before the goal supervisor consumes the source event.
    ignore(
      mooncode_runtime_cancel_active_atomic(
        session,
        root,
        cancel,
        item,
        interrupted_runtime=false,
        now=@clock.Timestamp::from_ms(20L),
      ),
    )
    let before = mooncode_goal_runtime_api_get_internal(root, session)
    assert_false(
      mooncode_json_bool(
        mooncode_json_object_field_or_empty(before.body, "status"),
        "terminal",
        default=true,
      ),
    )
    let replay = mooncode_runtime_cancel_pending_atomic(
      session,
      root,
      cancel,
      now=@clock.Timestamp::from_ms(30L),
    )
    guard replay is Settled(_) else {
      fail("completed control must replay its durable settlement")
    }
    let response = mooncode_runtime_cancel_settle_selection(
      session,
      root,
      cancel,
      replay,
      None,
      () => @clock.Timestamp::from_ms(30L),
    )
    assert_eq(mooncode_json_string(response, "status", default=""), "cancelled")
    let after = mooncode_goal_runtime_api_get_internal(root, session)
    let status = mooncode_json_object_field_or_empty(after.body, "status")
    assert_true(mooncode_json_bool(status, "terminal", default=false))
    assert_eq(mooncode_json_string(status, "outcome", default=""), "cancelled")
    let journal = mooncode_read_session_journal(root, session)
    ignore(
      mooncode_runtime_cancel_settle_selection(
        session,
        root,
        cancel,
        replay,
        None,
        () => @clock.Timestamp::from_ms(40L),
      ),
    )
    assert_eq(mooncode_read_session_journal(root, session), journal)
  })
}

///|
async test "pending cancellation settlement and replay preserve the active goal" {
  @fsx.with_temporary_directory("mooncode-pending-goal-replay-XXXXXX", async fn(
    root,
  ) {
    let session = "pending-cancel"
    goal_gate_write_snapshot(
      root,
      session,
      false,
      goal_gate_snapshot(session, root),
    )
    assert_eq(
      mooncode_goal_runtime_api_put_internal(
        root,
        session,
        goal_runtime_test_body(session),
        1L,
      ).status_code,
      201,
    )
    let cancel = mooncode_pending_cancel_test_control(
      root, "cancel-pending", "unrelated",
    )
    mooncode_pending_cancel_test_queue(root, [
      mooncode_pending_cancel_test_prompt(root, "original"),
      mooncode_pending_cancel_test_prompt(root, "unrelated"),
      cancel,
    ])
    ignore(
      mooncode_runtime_claim_atomic(
        root,
        session,
        {},
        @clock.Timestamp::from_ms(10L),
      ),
    )
    for timestamp in [20L, 30L] {
      let selection = mooncode_runtime_cancel_pending_atomic(
        session,
        root,
        cancel,
        now=@clock.Timestamp::from_ms(timestamp),
      )
      guard selection is Settled(_) else {
        fail("pending withdrawal must settle")
      }
      let before = mooncode_read_session_journal(root, session)
      let response = mooncode_runtime_cancel_settle_selection(
        session,
        root,
        cancel,
        selection,
        None,
        () => @clock.Timestamp::from_ms(timestamp),
      )
      assert_eq(
        mooncode_json_string(response, "status", default=""),
        "cancelled",
      )
      assert_eq(
        mooncode_json_string(response, "target_command_id", default=""),
        "unrelated",
      )
      let goal = mooncode_goal_runtime_api_get_internal(root, session)
      assert_false(
        mooncode_json_bool(
          mooncode_json_object_field_or_empty(goal.body, "status"),
          "terminal",
          default=true,
        ),
      )
      assert_eq(mooncode_read_session_journal(root, session), before)
    }
  })
}

///|
fn mooncode_active_cancel_test_response_bytes(value : Json) -> String raise {
  let copy = @json.parse(value.stringify())
  if mooncode_json_object_field_or_empty(copy, "control_receipt")
    is Object(fields) {
    fields.remove("journal_sequence")
  }
  copy.stringify()
}

///|
async test "active cancel preserves committed success and failure through durable no-op replay" {
  for status in ["runtime-completed", "runtime-failed"] {
    @fsx.with_temporary_directory("mooncode-active-terminal-XXXXXX", async fn(
      root,
    ) {
      let cancel = mooncode_pending_cancel_test_control(
        root, "cancel-original", "original",
      )
      let item = mooncode_active_cancel_test_select(root, cancel)
      ignore(mooncode_active_cancel_test_terminal(root, item, status))
      let original = mooncode_journal_entries(
          mooncode_read_session_journal(root, "pending-cancel"),
          mooncode_journal_runtime_receipt(),
        )
        .last()
        .unwrap()
      let response = mooncode_runtime_cancel_active_atomic(
        "pending-cancel",
        root,
        cancel,
        item,
        interrupted_runtime=true,
        now=@clock.Timestamp::from_ms(40L),
      )
      assert_eq(
        mooncode_json_string(response, "status", default=""),
        "already-terminal",
      )
      assert_eq(
        mooncode_json_string(response, "target_status", default=""),
        status,
      )
      assert_false(
        mooncode_json_bool(response, "interrupted_runtime", default=true),
      )
      let before = mooncode_read_session_journal(root, "pending-cancel")
      let replay = mooncode_runtime_cancel_pending_atomic(
        "pending-cancel",
        root,
        cancel,
        now=@clock.Timestamp::from_ms(50L),
      )
      guard replay is Settled(replayed) else { fail("expected durable no-op") }
      assert_eq(
        mooncode_active_cancel_test_response_bytes(replayed),
        mooncode_active_cancel_test_response_bytes(response),
      )
      let after = mooncode_read_session_journal(root, "pending-cancel")
      assert_eq(before, after)
      let target_receipts = mooncode_journal_entries(
        after,
        mooncode_journal_runtime_receipt(),
      ).filter(receipt => {
        mooncode_json_string(receipt, "command_id", default="") == "original"
      })
      assert_eq(target_receipts.length(), 2)
      assert_eq(target_receipts.last().unwrap(), original)
      assert_eq(
        mooncode_journal_entries(after, mooncode_journal_event()).length(),
        0,
      )
    })
  }
}

///|
async test "active cancel held execution lease remains pending and retries the exact target" {
  @fsx.with_temporary_directory("mooncode-active-lease-XXXXXX", async fn(root) {
    let cancel = mooncode_pending_cancel_test_control(
      root, "cancel-original", "",
    )
    let item = mooncode_active_cancel_test_select(root, cancel)
    let lease = mooncode_open_session_execution_lease(root, "pending-cancel")
    defer lease.close()
    lease.lock(Exclusive)
    let before = mooncode_read_session_journal(root, "pending-cancel")
    let busy = mooncode_runtime_cancel_active_atomic(
      "pending-cancel",
      root,
      cancel,
      item,
      interrupted_runtime=false,
      now=@clock.Timestamp::from_ms(30L),
    )
    assert_eq(mooncode_json_string(busy, "status", default=""), "busy")
    assert_true(mooncode_json_bool(busy, "retryable", default=false))
    assert_eq(
      mooncode_json_string(busy, "target_command_id", default=""),
      "original",
    )
    assert_eq(mooncode_read_session_journal(root, "pending-cancel"), before)
    let replay = mooncode_runtime_cancel_pending_atomic(
      "pending-cancel",
      root,
      cancel,
      now=@clock.Timestamp::from_ms(40L),
    )
    guard replay is Active(reselected) else {
      fail("busy cancel must stay unresolved")
    }
    assert_eq(reselected, item)
    lease.unlock()
    let settled = mooncode_runtime_cancel_active_atomic(
      "pending-cancel",
      root,
      cancel,
      reselected,
      interrupted_runtime=false,
      now=@clock.Timestamp::from_ms(50L),
    )
    assert_eq(mooncode_json_string(settled, "status", default=""), "cancelled")
    let journal = mooncode_read_session_journal(root, "pending-cancel")
    let cancelled = mooncode_journal_entries(
      journal,
      mooncode_journal_runtime_receipt(),
    ).filter(receipt => {
      mooncode_json_string(receipt, "status", default="") == "runtime-cancelled"
    })
    assert_eq(cancelled.length(), 1)
    assert_eq(
      mooncode_json_string(cancelled[0], "command_id", default=""),
      "original",
    )
    assert_eq(
      mooncode_json_string(cancelled[0], "control_command_id", default=""),
      "cancel-original",
    )
    let retried = mooncode_runtime_cancel_pending_atomic(
      "pending-cancel",
      root,
      cancel,
      now=@clock.Timestamp::from_ms(60L),
    )
    guard retried is Settled(response) else { fail("expected settled replay") }
    assert_eq(
      mooncode_active_cancel_test_response_bytes(response),
      mooncode_active_cancel_test_response_bytes(settled),
    )
    assert_eq(mooncode_read_session_journal(root, "pending-cancel"), journal)
  })
}

///|
async test "pending withdrawal keeps unrelated active lease and replays without further withdrawal" {
  @fsx.with_temporary_directory("mooncode-pending-direct-XXXXXX", async fn(
    root,
  ) {
    let cancel = mooncode_pending_cancel_test_control(
      root, "cancel-pending", "unrelated",
    )
    mooncode_pending_cancel_test_queue(root, [
      mooncode_pending_cancel_test_prompt(root, "original"),
      mooncode_pending_cancel_test_prompt(root, "unrelated"),
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
    let lease = mooncode_open_session_execution_lease(root, "pending-cancel")
    defer lease.close()
    lease.lock(Exclusive)
    defer lease.unlock()
    let result = mooncode_runtime_cancel_pending_atomic(
      "pending-cancel",
      root,
      cancel,
      now=@clock.Timestamp::from_ms(20L),
    )
    guard result is Settled(response) else {
      fail("pending target must withdraw without execution lease")
    }
    assert_eq(
      mooncode_json_string(response, "target_command_id", default=""),
      "unrelated",
    )
    assert_eq(mooncode_json_string(response, "status", default=""), "cancelled")
    assert_false(
      mooncode_json_bool(response, "interrupted_runtime", default=true),
    )
    let before = mooncode_read_session_journal(root, "pending-cancel")
    let receipts = mooncode_journal_entries(
      before,
      mooncode_journal_runtime_receipt(),
    )
    assert_eq(
      receipts
      .filter(receipt => {
        mooncode_json_string(receipt, "command_id", default="") == "original"
      })
      .length(),
      1,
    )
    assert_eq(
      mooncode_json_string(receipts[0], "status", default=""),
      "runtime-claimed",
    )
    ignore(
      mooncode_runtime_cancel_pending_atomic(
        "pending-cancel",
        root,
        cancel,
        now=@clock.Timestamp::from_ms(30L),
      ),
    )
    assert_eq(mooncode_read_session_journal(root, "pending-cancel"), before)
  })
}

///|
async test "idle cancellation remains idle when unrelated work arrives" {
  @fsx.with_temporary_directory("mooncode-idle-direct-XXXXXX", async fn(root) {
    let cancel = mooncode_pending_cancel_test_control(root, "idle-cancel", "")
    mooncode_pending_cancel_test_queue(root, [cancel])
    let settled = mooncode_runtime_cancel_pending_atomic(
      "pending-cancel",
      root,
      cancel,
      now=@clock.Timestamp::from_ms(10L),
    )
    guard settled is Settled(first) else {
      fail("idle cancellation must settle")
    }
    assert_eq(mooncode_json_string(first, "status", default=""), "idle")
    mooncode_pending_cancel_test_queue(root, [
      mooncode_pending_cancel_test_prompt(root, "unrelated"),
    ])
    let before = mooncode_read_session_journal(root, "pending-cancel")
    let repeated = mooncode_runtime_cancel_pending_atomic(
      "pending-cancel",
      root,
      cancel,
      now=@clock.Timestamp::from_ms(20L),
    )
    guard repeated is Settled(replay) else {
      fail("idle cancellation must replay")
    }
    assert_eq(mooncode_json_string(replay, "status", default=""), "idle")
    assert_eq(mooncode_read_session_journal(root, "pending-cancel"), before)
  })
}

///|
async test "partial active settlement retains exact target and interruption evidence" {
  for retain_event in [false, true] {
    @fsx.with_temporary_directory("mooncode-active-prefix-XXXXXX", async fn(
      root,
    ) {
      let cancel = mooncode_pending_cancel_test_control(
        root, "cancel-original", "",
      )
      let item = mooncode_active_cancel_test_select(root, cancel)
      ignore(
        mooncode_runtime_cancel_active_atomic(
          "pending-cancel",
          root,
          cancel,
          item,
          interrupted_runtime=true,
          now=@clock.Timestamp::from_ms(30L),
        ),
      )
      let journal = mooncode_read_session_journal(root, "pending-cancel")
      let mut keep = 0
      for index, record in journal {
        let payload = mooncode_json_object_field_or_empty(record, "payload")
        if mooncode_json_string(payload, "command_id", default="") == "original" &&
          mooncode_json_string(payload, "status", default="") ==
          "runtime-cancelled" {
          keep = index + (if retain_event { 2 } else { 1 })
          break
        }
      }
      assert_true(keep > 0)
      let path = mooncode_session_journal_path(root, "pending-cancel")
      let lines = @fsx.read_file(path).split("\n").to_array()
      @fsx.write_to_file(path, lines[:keep].join("\n") + "\n")
      let replay = mooncode_runtime_cancel_pending_atomic(
        "pending-cancel",
        root,
        cancel,
        now=@clock.Timestamp::from_ms(40L),
      )
      guard replay is Settled(response) else {
        fail("partial cancellation must settle its original target")
      }
      assert_eq(
        mooncode_json_string(response, "target_command_id", default=""),
        "original",
      )
      assert_eq(
        mooncode_json_string(response, "status", default=""),
        "cancelled",
      )
      assert_true(
        mooncode_json_bool(response, "interrupted_runtime", default=false),
      )
      let after = mooncode_read_session_journal(root, "pending-cancel")
      assert_eq(
        mooncode_journal_entries(after, mooncode_journal_runtime_receipt())
        .filter(receipt => {
          mooncode_json_string(receipt, "status", default="") ==
          "runtime-cancelled"
        })
        .length(),
        1,
      )
      assert_eq(
        mooncode_journal_entries(after, mooncode_journal_event()).length(),
        1,
      )
    })
  }
}

///|
async test "active cancel waits for local task terminal write before settling" {
  @fsx.with_temporary_directory("mooncode-active-wait-XXXXXX", async fn(root) {
    let cancel = mooncode_pending_cancel_test_control(
      root, "cancel-original", "original",
    )
    let item = mooncode_active_cancel_test_select(root, cancel)
    let started : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
    let blocked : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
    @async.with_task_group(group => {
      let task = group.spawn(
        async fn() {
          let gate = mooncode_open_session_lifecycle_gate(
            root, "pending-cancel",
          )
          defer gate.close()
          gate.lock(Shared)
          defer gate.unlock()
          let lease = mooncode_open_session_execution_lease(
            root, "pending-cancel",
          )
          defer lease.close()
          lease.lock(Exclusive)
          defer lease.unlock()
          started.put(())
          blocked.get() catch {
            _ =>
              @async.protect_from_cancel(
                async fn() {
                  ignore(
                    mooncode_active_cancel_test_terminal(
                      root, item, "runtime-completed",
                    ),
                  )
                },
                resume_on_cancel=true,
              )
          }
        },
        no_wait=true,
        allow_failure=true,
      )
      started.get()
      let result = mooncode_runtime_cancel_settle_selection(
        "pending-cancel",
        root,
        cancel,
        Active(item),
        Some(task),
        () => @clock.Timestamp::from_ms(40L),
      )
      assert_eq(
        mooncode_json_string(result, "status", default=""),
        "already-terminal",
      )
      let receipts = mooncode_journal_entries(
        mooncode_read_session_journal(root, "pending-cancel"),
        mooncode_journal_runtime_receipt(),
      )
      assert_eq(
        receipts
        .filter(receipt => {
          mooncode_json_string(receipt, "status", default="") ==
          "runtime-cancelled"
        })
        .length(),
        0,
      )
      group.return_immediately(())
    })
  })
}

///|
async test "active cancel rejects a changed selected target or control body" {
  @fsx.with_temporary_directory("mooncode-active-identity-XXXXXX", async fn(
    root,
  ) {
    let cancel = mooncode_pending_cancel_test_control(
      root, "cancel-original", "original",
    )
    let item = mooncode_active_cancel_test_select(root, cancel)
    let before = mooncode_read_session_journal(root, "pending-cancel")
    let wrong = mooncode_pending_cancel_test_control(
      root, "cancel-original", "unrelated",
    )
    let rejected = try {
      ignore(
        mooncode_runtime_cancel_active_atomic(
          "pending-cancel",
          root,
          wrong,
          item,
          interrupted_runtime=false,
          now=@clock.Timestamp::from_ms(30L),
        ),
      )
      false
    } catch {
      InvalidJournal(_) => true
      error => raise error
    }
    assert_true(rejected)
    let state = mooncode_runtime_claim_state_from_logs(
      "pending-cancel",
      root,
      mooncode_journal_entries(before, mooncode_journal_command()),
      mooncode_journal_entries(before, mooncode_journal_runtime_receipt()),
      journal_path=mooncode_session_journal_path(root, "pending-cancel"),
    )
    let unrelated = mooncode_json_array_items(state, "order_blocked_commands")[0]
    let changed = try {
      ignore(
        mooncode_runtime_cancel_active_atomic(
          "pending-cancel",
          root,
          cancel,
          unrelated,
          interrupted_runtime=false,
          now=@clock.Timestamp::from_ms(40L),
        ),
      )
      false
    } catch {
      InvalidJournal(_) => true
      error => raise error
    }
    assert_true(changed)
    assert_eq(mooncode_read_session_journal(root, "pending-cancel"), before)
  })
}
