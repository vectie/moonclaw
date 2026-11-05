///|
test "runtime service recovers only an unresolved valid approval checkpoint" {
  let session_id = "session-service-approval-recovery"
  let command_id = "command-service-approval-recovery"
  let tool_call : Json = {
    "tool": "shell",
    "arguments": { "cmd": "rm -rf _build/js" },
    "tool_call_id": "shell-rebuild",
    "planner": "model-tool-call",
  }
  let plan : Json = {
    "planner_mode": mooncode_planner_mode_model_tool_calls(),
    "tool_calls": [tool_call],
  }
  let approval_id = mooncode_runtime_tool_approval_id(
    command_id,
    tool_call,
    occurrence=0,
  )
  let request : Json = {
    "approval_id": approval_id,
    "target_command_id": command_id,
    "state": "pending",
  }
  let checkpoint = mooncode_runtime_continuation_event(
    session_id,
    command_id,
    plan,
    [plan],
    [],
    [],
    request,
    step_index=0,
    tool_index=0,
    planner_turn_end_step=0,
    now=@clock.Timestamp::from_ms(1L),
  )
  assert_true(
    mooncode_runtime_service_pending_approval([request, checkpoint]) is Some(_),
  )
  let approved : Json = {
    "approval_id": approval_id,
    "target_command_id": command_id,
    "state": "approved",
  }
  assert_true(
    mooncode_runtime_service_pending_approval([request, checkpoint, approved])
    is None,
  )
  let records : Array[(String, Json)] = [
    (
      mooncode_journal_command(),
      {
        "command_id": command_id,
        "command": {
          "command": "prompt",
          "packet": { "command_id": command_id },
        },
      },
    ),
    (mooncode_journal_event(), request),
    (mooncode_journal_event(), checkpoint),
    (
      mooncode_journal_event(),
      {
        "kind": "runtime.service_finished",
        "stopped_by": "approval",
        "auto_drain": true,
      },
    ),
  ]
  assert_true(
    mooncode_runtime_service_restore_payload(
      session_id,
      "/book",
      mooncode_service_restore_test_journal(records),
    )
    is None,
  )
  records.push((mooncode_journal_event(), approved))
  assert_true(
    mooncode_runtime_service_restore_payload(
      session_id,
      "/book",
      mooncode_service_restore_test_journal(records),
    )
    is Some(_),
  )
  assert_true(
    mooncode_runtime_service_pending_approval([
      request,
      mooncode_json_object_with_field(
        checkpoint,
        "tool_index",
        Json::number(1.0),
      ),
    ])
    is None,
  )
}

///|
test "runtime service journal errors retain their diagnostic payload" {
  inspect(
    mooncode_runtime_service_error_detail(InvalidJournal("bad checkpoint")),
    content="MoonCode journal invalid: bad checkpoint",
  )
}

///|
fn mooncode_service_restore_test_journal(
  entries : Array[(String, Json)],
) -> Array[Json] raise {
  entries.mapi((index, entry) => {
    let (record_kind, payload) = entry
    mooncode_journal_record_v2(
      session_id="restore",
      sequence=MoonCodeJournalSequence::parse((index + 1).to_string()),
      record_id="restore-" + index.to_string(),
      record_kind~,
      command_id="",
      client_turn_id="",
      recorded_at=Json::number(1.0),
      payload~,
    )
  })
}

///|
test "boot selection follows unresolved commands and service stop boundaries" {
  let command : Json = {
    "command_id": "prompt",
    "command": { "command": "prompt", "packet": { "command_id": "prompt" } },
  }
  let command_record = (mooncode_journal_command(), command)
  let cancel_boundary : Json = {
    "kind": @moonlib_conversation.cancellation_event_kind(),
    "event": @moonlib_conversation.cancellation_event_kind(),
    "command_id": "cancelled",
    "target_command_id": "cancelled",
    "control_id": "stop",
    "control_command_id": "stop",
    "control_kind": "turn-cancellation",
    "status": "cancelled",
    "state": "cancelled",
    "source": "moonclaw-native-runtime-control",
  }
  for
    (event, resume) in (
      [
        (
          {
            "kind": "runtime.service_started",
            "auto_drain": false,
            "max_turns": 2,
          },
          true,
        ),
        (
          {
            "kind": "runtime.service_finished",
            "stopped_by": "cancelled",
            "ran_turn_count": 0,
          },
          true,
        ),
        (
          {
            "kind": "runtime.service_finished",
            "stopped_by": "cancelled",
            "ran_turn_count": 1,
          },
          false,
        ),
        (
          {
            "kind": "runtime.service_finished",
            "stopped_by": "max_turns",
            "auto_drain": false,
          },
          false,
        ),
        (
          {
            "kind": "runtime.service_finished",
            "stopped_by": "idle",
            "auto_drain": true,
          },
          true,
        ),
        (
          {
            "kind": "runtime.service_finished",
            "stopped_by": "approval",
            "auto_drain": false,
          },
          false,
        ),
        ({ "kind": "runtime.service_failed" }, false),
        (cancel_boundary, false),
      ] : Array[(Json, Bool)]) {
    let records = mooncode_service_restore_test_journal([
      command_record,
      (mooncode_journal_event(), event),
    ])
    let payload = mooncode_runtime_service_restore_payload(
      "restore", "/book", records,
    )
    assert_eq(payload is Some(_), resume, msg=event.stringify())
    if mooncode_json_string(event, "kind", default="") ==
      "runtime.service_started" {
      assert_eq(mooncode_json_int(payload.unwrap(), "max_turns", default=0), 2)
      let completed = mooncode_service_restore_test_journal([
        command_record,
        (mooncode_journal_event(), event),
        (
          mooncode_journal_runtime_receipt(),
          { "command_id": "prompt", "status": "runtime-completed" },
        ),
      ])
      assert_true(
        mooncode_runtime_service_restore_payload("restore", "/book", completed)
        is None,
      )
    }
  }
  for
    entries in [
      [command_record],
      [(mooncode_journal_event(), cancel_boundary), command_record],
      [
        (
          mooncode_journal_event(),
          ({ "kind": "runtime.service_finished", "stopped_by": "idle" } : Json),
        ),
        command_record,
      ],
    ] {
    assert_true(
      mooncode_runtime_service_restore_payload(
        "restore",
        "/book",
        mooncode_service_restore_test_journal(entries),
      )
      is Some(_),
    )
  }
}

///|
async test "daemon boot consumes accepted prompts in trusted Books and skips a corrupt neighbor" {
  with_integration_http_fixture(async fn(fixture) {
    for index, book in [fixture.book, fixture.other, fixture.untrusted] {
      let session_id = "accepted-before-service-" + index.to_string()
      fixture.daemon.mooncode_bind_integration_session(book, session_id)
      mooncode_append_session_journal(
        book,
        session_id,
        mooncode_journal_command(),
        {
          "created_at": @clock.Timestamp::from_ms(1L),
          "command_id": "accepted",
          "command": {
            "protocol": mooncode_protocol_version(),
            "session_id": session_id,
            "book_root": book,
            "command": "prompt",
            "model": "fixture",
            "packet": { "command_id": "accepted" },
            "runtime_tool_calls": [
              {
                "tool": "write",
                "arguments": { "path": "boot.txt", "content": "resumed" },
              },
              { "tool": "finish", "arguments": { "answer": "done" } },
            ],
          },
        },
      )
    }
    // A corrupt active neighbor must not abort the rest of this Book's scan.
    let bad = mooncode_session_snapshot_path(fixture.book, "broken")
    @fsx.make_directory(@pathx.dirname(bad), recursive=true, exists_ok=true)
    @fsx.write_to_file(bad, "{")
    @fsx.write_to_file(
      mooncode_session_journal_path(fixture.book, "broken"),
      "{}\n",
    )
    let daemon = integration_fixture_daemon(fixture.workspace)
    defer daemon.httpx.close()
    @async.with_task_group(group => {
      group.spawn_bg(() => daemon.serve(), no_wait=true)
      for _ in 0..<500 {
        let first = daemon.mooncode_runtime_claim_state_payload(
          "accepted-before-service-0",
          fixture.book,
        )
        let second = daemon.mooncode_runtime_claim_state_payload(
          "accepted-before-service-1",
          fixture.other,
        )
        if mooncode_json_int(first, "delivered_command_count", default=0) == 1 &&
          mooncode_json_int(second, "delivered_command_count", default=0) == 1 {
          break
        }
        @async.sleep(10)
      }
      assert_eq(@fsx.read_file(fixture.book + "/boot.txt"), "resumed")
      assert_eq(@fsx.read_file(fixture.other + "/boot.txt"), "resumed")
      assert_false(@fsx.exists(fixture.untrusted + "/boot.txt"))
      for index, book in [fixture.book, fixture.other] {
        let session_id = "accepted-before-service-" + index.to_string()
        assert_eq(
          mooncode_json_int(
            daemon.mooncode_runtime_claim_state_payload(session_id, book),
            "delivered_command_count",
            default=0,
          ),
          1,
        )
      }
      group.return_immediately(())
    })
  })
}
