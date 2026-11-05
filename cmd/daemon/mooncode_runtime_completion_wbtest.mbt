///|
test "finish requires current checks without manufacturing a mutation or checkpoint" {
  let command = completion_test_command()
  let evidence = completion_test_evidence()
  let finish = completion_test_finish()
  assert_true(
    mooncode_runtime_turn_completion_verdict(command, evidence + [finish]).accepted,
  )
  assert_false(
    mooncode_runtime_turn_completion_verdict(command, [finish]).accepted,
  )
  let failed = completion_test_metadata(evidence[1], "exit_code", Json(1))
  assert_false(
    mooncode_runtime_turn_completion_verdict(command, [
      evidence[0],
      failed,
      finish,
    ]).accepted,
  )
  let stale = evidence + [completion_test_edit("old", "new"), finish]
  assert_false(
    mooncode_runtime_turn_completion_verdict(command, stale).accepted,
  )
  let repaired = evidence +
    [
      completion_test_edit("old", "new"),
      evidence[1],
      {
        "tool": "finish",
        "accepted": true,
        "arguments": { "answer": "Repaired and tested." },
      },
    ]
  assert_true(
    mooncode_runtime_turn_completion_verdict(command, repaired).accepted,
  )
}

///|
test "checkpoint is editable progress and does not grant completion" {
  let command = completion_test_command()
  let done : Json = {
    "horizon_id": "completion-command",
    "milestones": [{ "id": "work", "status": "done" }],
  }
  let reopened : Json = {
    "horizon_id": "completion-command",
    "milestones": [{ "id": "work", "status": "active" }],
  }
  assert_eq(mooncode_runtime_horizon_checkpoint_error(command, done), "")
  let saved = mooncode_runtime_horizon_checkpoint_execution(
    command,
    "completion-session",
    "/synthetic/source",
    "completion-command",
    { "arguments": done },
    now=@clock.epoch.now(),
  )
  assert_eq(mooncode_runtime_horizon_checkpoint_error(command, reopened), "")
  assert_false(
    mooncode_runtime_turn_completion_verdict(command, [
      saved,
      completion_test_finish(),
    ]).accepted,
  )
  let active = mooncode_runtime_horizon_checkpoint_execution(
    command,
    "completion-session",
    "/synthetic/source",
    "completion-command",
    { "arguments": reopened },
    now=@clock.epoch.now(),
  )
  assert_true(
    mooncode_runtime_turn_completion_verdict(
      command,
      completion_test_evidence() + [active, completion_test_finish()],
    ).accepted,
  )
}

///|
test "negative steering revises context without triggering a mutation heuristic" {
  let command : Json = {
    "command": "prompt",
    "text": "Answer after applying live steering",
    "packet": { "command_id": "reply" },
  }
  let revised = mooncode_runtime_task_with_update(command, {
    "command_id": "correction",
    "steering_text": "Do not execute the prior mutation.",
  })
  assert_eq(
    mooncode_json_array_items(
      mooncode_runtime_horizon_contract(revised),
      "updates",
    ).length(),
    1,
  )
  assert_true(
    mooncode_runtime_horizon_contract(revised) !=
    mooncode_runtime_horizon_contract(command),
  )
}

///|
test "provider tool calls preserve names and return invalid arguments for repair" {
  for raw in ["{\"cmd\":\"echo ok\"}{\"path\":\"secret\"}", "{\"cmd\":", "[]"] {
    let calls = mooncode_runtime_turn_tool_calls_from_model_response({
      "choices": [
        {
          "finish_reason": "tool_calls",
          "message": {
            "content": "must not hide invalid calls",
            "tool_calls": [
              {
                "id": "original-id",
                "function": { "name": "read", "arguments": raw },
              },
            ],
          },
        },
      ],
    })
    assert_eq(calls.length(), 1)
    assert_eq(mooncode_json_string(calls[0], "tool", default=""), "read")
    assert_eq(
      mooncode_json_string(calls[0], "tool_call_id", default=""),
      "original-id",
    )
    assert_true(
      mooncode_json_string(calls[0], "validation_error", default="") != "",
    )
  }
  let calls = mooncode_runtime_turn_tool_calls_from_model_response({
    "choices": [
      {
        "finish_reason": "length",
        "message": {
          "tool_calls": [
            {
              "id": "truncated",
              "function": {
                "name": "write",
                "arguments": "{\"path\":\"x\",\"content\":\"x\"}",
              },
            },
          ],
        },
      },
    ],
  })
  assert_true(
    mooncode_json_string(calls[0], "validation_error", default="") != "",
  )
}

///|
test "package verification needs a real verification tool after the final change" {
  let observation : Json = {
    "tool": "shell",
    "accepted": true,
    "arguments": { "cmd": "git status" },
  }
  let checked : Json = {
    "tool": "moon_cmd",
    "accepted": true,
    "arguments": { "command": "test" },
  }
  assert_false(
    mooncode_runtime_turn_package_verified({ "tool_results": [observation] }),
  )
  assert_true(
    mooncode_runtime_turn_package_verified({ "tool_results": [checked] }),
  )
  assert_false(
    mooncode_runtime_turn_package_verified({
      "tool_results": [checked, completion_test_edit("a", "b")],
    }),
  )
}

///|
async test "verification captures touched inputs and detects external changes before finish" {
  @fsx.with_temporary_directory("mooncode-verification-inputs-XXXXXX", async fn(
    root,
  ) {
    @fsx.write_to_file(root + "/source.mbt", "old")
    let command : Json = {
      "command": "prompt",
      "text": "Fix source",
      "packet": { "command_id": "inputs" },
    }
    let change : Json = {
      "tool": "edit",
      "accepted": true,
      "result": {
        "metadata": {
          "path": "source.mbt",
          "changed": true,
          "before_fingerprint": "a",
          "after_fingerprint": "b",
        },
      },
    }
    let inputs = mooncode_runtime_check_inputs(root, command, [change])
    let shell_change : Json = {
      "tool": "shell",
      "accepted": true,
      "result": {
        "metadata": {
          "cmd": "moon run generate.mbtx",
          "sandbox_evidence": { "changed_paths": ["source.mbt"] },
        },
      },
    }
    assert_eq(
      mooncode_runtime_check_inputs(root, command, [shell_change]),
      inputs,
    )
    let checked = mooncode_runtime_bind_check_inputs(
      {
        "tool": "moon_cmd",
        "accepted": true,
        "arguments": { "command": "test" },
        "result": {},
      },
      inputs,
      command,
    )
    assert_eq(inputs.length(), 1)
    assert_eq(
      mooncode_runtime_finish_input_error(root, command, [change, checked]),
      "",
    )
    @fsx.write_to_file(root + "/source.mbt", "external change")
    assert_true(
      mooncode_runtime_finish_input_error(root, command, [change, checked]).contains(
        "stale",
      ),
    )
    let revised = mooncode_json_object_with_field(command, "task_contract", {
      "revision": "r2",
    })
    assert_true(
      mooncode_runtime_finish_input_error(root, revised, [change, checked]).contains(
        "revision",
      ),
    )
  })
}

///|
test "operation recovery reuses committed results and never replays an unknown effect" {
  let call : Json = {
    "tool": "write",
    "arguments": { "path": "a", "content": "value" },
  }
  let now = @clock.Timestamp::from_ms(1L)
  let plan : Json = { "tool_calls": [call] }
  let checkpoint = mooncode_runtime_continuation_event(
    "s",
    "c",
    plan,
    [plan],
    [],
    [],
    {},
    step_index=0,
    tool_index=0,
    planner_turn_end_step=0,
    now~,
  )
  let intent = mooncode_runtime_checkpoint_with_intent(
    checkpoint, "c:0:0", call,
  )
  let unknown = mooncode_runtime_operation_recovery(
    [intent],
    "s",
    "/tmp/book",
    "c",
    "c:0:0",
    call,
    now~,
  ).unwrap()
  assert_false(mooncode_json_bool(unknown, "accepted", default=true))
  assert_true(unknown.stringify().contains("outcome_unknown"))
  let result = mooncode_tool_ok_result("write", message="written", output="", metadata={})
  let execution : Json = {
    "accepted": true,
    "tool": "write",
    "arguments": mooncode_json_object_field_or_empty(call, "arguments"),
    "result": result,
    "event": mooncode_tool_result_event(
      "s",
      "/tmp/book",
      "c",
      "write",
      result,
      now~,
    ),
  }
  let committed = mooncode_runtime_operation_finished("c:0:0", call, execution)
  let replay = mooncode_runtime_operation_recovery(
    [intent, mooncode_json_object_field_or_empty(committed, "event")],
    "s",
    "/tmp/book",
    "c",
    "c:0:0",
    call,
    now~,
  ).unwrap()
  assert_eq(replay, committed)
  let changed = mooncode_json_object_with_field(call, "arguments", {
    "path": "b",
    "content": "value",
  })
  let rejected = try {
    ignore(
      mooncode_runtime_operation_recovery(
        [intent],
        "s",
        "/tmp/book",
        "c",
        "c:0:0",
        changed,
        now~,
      ),
    )
    false
  } catch {
    InvalidJournal(_) => true
    _ => false
  }
  assert_true(rejected)
  assert_true(
    mooncode_runtime_continuation_is_active(
      mooncode_runtime_continuation_for_command([intent], "c"),
    ),
  )
}

///|
async test "restart before planning or after a read intent resumes without another user request" {
  for interrupted_read in [false, true] {
    @fsx.with_temporary_directory("mooncode-claim-before-plan-XXXXXX", async fn(
      root,
    ) {
      @fsx.write_to_file(root + "/answer.txt", "retained input")
      let command : Json = {
        "protocol": mooncode_protocol_version(),
        "session_id": "claim-restart",
        "book_root": root,
        "command": "prompt",
        "text": "Read answer.txt",
        "model": "fixture/mooncode",
        "packet": { "command_id": "before-plan" },
        "runtime_tool_calls": [
          { "tool": "read", "arguments": { "path": "answer.txt" } },
          { "tool": "finish", "arguments": { "answer": "retained input" } },
        ],
      }
      mooncode_append_session_journal(
        root,
        "claim-restart",
        mooncode_journal_command(),
        {
          "kind": "mooncode-command",
          "protocol": mooncode_protocol_version(),
          "session_id": "claim-restart",
          "command_id": "before-plan",
          "command": command,
          "created_at": @clock.Timestamp::from_ms(1L),
        },
      )
      ignore(
        mooncode_runtime_claim_atomic(
          root,
          "claim-restart",
          {},
          @clock.Timestamp::from_ms(2L),
        ),
      )
      if interrupted_read {
        let calls = mooncode_json_array_items(command, "runtime_tool_calls")
        let plan : Json = {
          "planner_mode": "explicit-tool-calls",
          "tool_calls": Json::array(calls),
        }
        let checkpoint = mooncode_runtime_continuation_event(
          "claim-restart",
          "before-plan",
          plan,
          [plan],
          [],
          [],
          {},
          step_index=0,
          tool_index=0,
          planner_turn_end_step=0,
          now=@clock.Timestamp::from_ms(3L),
        )
        mooncode_append_session_journal(
          root,
          "claim-restart",
          mooncode_journal_event(),
          mooncode_runtime_checkpoint_with_intent(
            checkpoint,
            "before-plan:0:0",
            calls[0],
          ),
        )
      }
      let daemon = mooncode_control_test_daemon(root)
      let result = daemon.mooncode_runtime_turn_execute("claim-restart", root, {})
      assert_true(
        mooncode_json_bool(result, "accepted", default=false),
        msg=result.stringify(),
      )
      let events = mooncode_journal_entries(
        mooncode_read_session_journal(root, "claim-restart"),
        mooncode_journal_event(),
      )
      let completed = events.filter(e => {
        mooncode_json_string(e, "operation_state", default="") == "completed"
      })
      assert_eq(completed.length(), 2)
      let intents = events.filter(e => {
        mooncode_json_string(e, "operation_state", default="") == "started"
      })
      assert_eq(intents.length(), 2)
      assert_true(
        intents.all(e => {
          mooncode_json_string(e, "kind", default="") ==
          mooncode_runtime_continuation_kind()
        }),
      )
    })
  }
}

///|
test "optional observation failures do not require a manufactured recovery action" {
  let command = completion_test_command()
  let evidence = completion_test_evidence()
  let failed_read : Json = {
    "tool": "read",
    "accepted": false,
    "arguments": { "path": "missing.mbt" },
    "result": { "ok": false },
  }
  let finish = completion_test_finish()
  assert_true(
    mooncode_runtime_turn_completion_verdict(
      command,
      evidence + [failed_read, finish],
    ).accepted,
  )
  let recovered = evidence + [failed_read, evidence[0], finish]
  assert_eq(
    mooncode_runtime_required_check_evidence(command, recovered).length(),
    1,
  )
  assert_true(
    mooncode_runtime_turn_completion_verdict(command, recovered).accepted,
  )
  let failed_test = mooncode_json_object_with_field(
    evidence[1],
    "accepted",
    Json(false),
  )
  assert_false(
    mooncode_runtime_turn_completion_verdict(
      command,
      evidence + [failed_test, evidence[0], finish],
    ).accepted,
  )
  let rejected_finish : Json = {
    "tool": "finish",
    "accepted": false,
    "result": { "ok": false },
  }
  let rejected_note : Json = {
    "tool": "checkpoint",
    "accepted": false,
    "result": { "ok": false },
  }
  assert_true(
    mooncode_runtime_turn_completion_verdict(
      command,
      evidence + [rejected_finish, rejected_note, finish],
    ).accepted,
  )
  let unknown = mooncode_json_object_with_field(failed_read, "result", {
    "ok": false,
    "metadata": { "outcome_unknown": true },
  })
  assert_false(
    mooncode_runtime_turn_completion_verdict(
      command,
      evidence + [unknown, evidence[0], finish],
    ).accepted,
  )
  let commit : Json = {
    "tool": "commit",
    "accepted": true,
    "result": { "metadata": { "evidence_kind": "runtime.commit_created" } },
  }
  assert_true(
    mooncode_runtime_turn_completion_verdict(
      command,
      evidence + [commit, finish],
    ).accepted,
  )
}
