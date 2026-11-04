///|
async fn mooncode_task_test_prompt(
  root : String,
  session : String,
  id : String,
  text : String,
) -> Unit {
  mooncode_append_session_journal(root, session, mooncode_journal_command(), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session,
    "command_id": id,
    "created_at": @clock.epoch.now(),
    "command": {
      "session_id": session,
      "command": "prompt",
      "text": text,
      "packet": { "command_id": id, "message": text },
    },
  })
}

///|
async test "task queue edits and reorder survive reload and control runtime claims" {
  @fsx.with_temporary_directory("mooncode-task-queue-XXXXXX", async fn(root) {
    let daemon = mooncode_control_test_daemon(root)
    defer daemon.httpx.close()
    let session = "task-queue"
    mooncode_management_test_create_session(daemon, root, session)
    mooncode_task_test_prompt(root, session, "cmd-2", "second")
    mooncode_task_test_prompt(root, session, "cmd-3", "third")
    ignore(
      daemon.mooncode_task_controls_response(session, {
        "book_root": root,
        "action": "edit",
        "target_command_id": "cmd-2",
        "message": "edited second",
      }),
    )
    ignore(
      daemon.mooncode_task_controls_response(session, {
        "book_root": root,
        "action": "reorder",
        "order": ["cmd-3", "cmd-2", "cmd-1"],
      }),
    )
    ignore(
      daemon.mooncode_task_controls_response(session, {
        "book_root": root,
        "action": "remove",
        "target_command_id": "cmd-1",
      }),
    )
    let records = mooncode_read_session_journal(root, session)
    let pending = mooncode_task_controls_pending(records)
    assert_eq(pending.length(), 2)
    assert_eq(mooncode_runtime_command_entry_id(pending[0]), "cmd-3")
    assert_eq(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(pending[1], "command"),
        "text",
        default="",
      ),
      "edited second",
    )
    let state = daemon.mooncode_runtime_claim_state_payload(session, root)
    assert_true(state.stringify().contains("cmd-3"))
    mooncode_append_session_journal(
      root,
      session,
      mooncode_journal_runtime_receipt(),
      {
        "session_id": session,
        "command_id": "cmd-3",
        "status": "runtime-claimed",
        "created_at": @clock.epoch.now(),
      },
    )
    let mut rejected = false
    ignore(
      daemon.mooncode_task_controls_response(session, {
        "book_root": root,
        "action": "edit",
        "target_command_id": "cmd-3",
        "message": "too late",
      }),
    ) catch {
      InvalidJournal(_) => rejected = true
      error => raise error
    }
    assert_true(rejected)
    ignore(
      daemon.mooncode_task_controls_response(session, {
        "book_root": root,
        "action": "guide_now",
        "target_command_id": "cmd-2",
        "message": "Focus on the editor",
      }),
    )
    let control = daemon.mooncode_runtime_control_payload(session, root)
    let steering = mooncode_runtime_turn_pending_live_steering(control, "cmd-3")
    assert_eq(steering.length(), 1)
    assert_eq(
      mooncode_json_string(steering[0], "steering_text", default=""),
      "Focus on the editor",
    )
    assert_eq(
      mooncode_task_controls_pending(
        mooncode_read_session_journal(root, session),
      ).length(),
      0,
    )
  })
}

///|
async test "task plan enters model context and fork inherits settled history without replay" {
  @fsx.with_temporary_directory("mooncode-task-fork-XXXXXX", async fn(root) {
    let daemon = mooncode_control_test_daemon(root)
    defer daemon.httpx.close()
    let session = "task-fork"
    mooncode_management_test_create_session(daemon, root, session)
    mooncode_append_session_journal(
      root,
      session,
      mooncode_journal_runtime_receipt(),
      {
        "session_id": session,
        "command_id": "cmd-1",
        "status": "runtime-completed",
        "created_at": @clock.epoch.now(),
      },
    )
    mooncode_task_test_prompt(root, session, "cmd-2", "still queued")
    ignore(
      daemon.mooncode_task_controls_response(session, {
        "book_root": root,
        "action": "set_plan",
        "plan": "Improve the source navigator",
      }),
    )
    let command = mooncode_task_attach_context(root, session, {
      "packet": { "command_id": "new" },
    })
    assert_true(command.stringify().contains("Improve the source navigator"))
    let fork = daemon.mooncode_task_controls_response(session, {
      "book_root": root,
      "action": "fork",
      "title": "Alternative implementation",
    })
    let fork_id = mooncode_json_string(fork, "session_id", default="")
    assert_true(fork_id.has_prefix("fork-"))
    assert_eq(mooncode_json_array_items(fork, "queue").length(), 0)
    let copied = mooncode_journal_entries(
      mooncode_read_session_journal(root, fork_id),
      mooncode_journal_command(),
    )
    assert_eq(copied.length(), 1)
    assert_eq(
      mooncode_json_string(copied[0], "session_id", default=""),
      fork_id,
    )
    assert_true(daemon.mooncode_session_record(fork_id, root) is Some(_))
    assert_eq(
      mooncode_task_controls_pending(
        mooncode_read_session_journal(root, session),
      ).length(),
      1,
    )
  })
}

///|
async test "task question waits for a durable answer and personal preferences persist" {
  @fsx.with_temporary_directory("mooncode-task-question-XXXXXX", async fn(
    root,
  ) {
    let daemon = mooncode_control_test_daemon(root)
    defer daemon.httpx.close()
    let session = "task-question"
    mooncode_management_test_create_session(daemon, root, session)
    @async.with_task_group(async fn(group) {
      let answering = group.spawn(async fn() {
        for ;; {
          let pending = mooncode_task_pending_questions(
            mooncode_read_session_journal(root, session),
          )
          if pending.length() > 0 {
            break
          }
          @async.sleep(10)
        }
        ignore(
          daemon.mooncode_task_controls_response(session, {
            "book_root": root,
            "action": "answer_question",
            "question_id": "cmd-1:design",
            "answer": "Use the compact layout",
          }),
        )
      })
      let result = mooncode_task_ask_user(
        session,
        root,
        "cmd-1",
        {
          "id": "design",
          "question": "Which layout?",
          "options": ["Compact", "Spacious"],
        },
        daemon.clock.now(),
      )
      assert_eq(
        mooncode_json_string(result, "output", default=""),
        "Use the compact layout",
      )
      answering.wait()
    })
    assert_eq(
      mooncode_task_pending_questions(
        mooncode_read_session_journal(root, session),
      ).length(),
      0,
    )
    ignore(
      daemon.mooncode_task_controls_response(session, {
        "book_root": root,
        "action": "save_memory",
        "memory": "Prefer concise summaries",
      }),
    )
    assert_eq(
      mooncode_personal_memory_read(daemon.home),
      "Prefer concise summaries",
    )
    ignore(
      daemon.mooncode_task_controls_response(session, {
        "book_root": root,
        "action": "save_memory",
        "memory": "",
      }),
    )
    assert_eq(mooncode_personal_memory_read(daemon.home), "")
  })
}
