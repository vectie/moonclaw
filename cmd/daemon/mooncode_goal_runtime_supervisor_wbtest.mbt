///|
async test "goal runtime supervisor is a no-op without runtime authority" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-none-XXXXXX", async fn(
    root,
  ) {
    let result = mooncode_goal_runtime_append_supervisor_event(
      root,
      "session",
      @mooncode_core.PhaseChanged("phase-running", @mooncode_core.Running),
      1L,
    )
    assert_true(result is NoRuntimeGoal)
    assert_false(@fsx.exists(mooncode_session_journal_path(root, "session")))
  })
}

///|
async test "goal runtime supervisor append is durable and timestamp-idempotent" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-append-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    goal_gate_write_snapshot(
      root,
      session_id,
      false,
      goal_gate_snapshot(session_id, root),
    )
    assert_eq(
      mooncode_goal_runtime_api_put_internal(
        root,
        session_id,
        goal_runtime_test_body(session_id),
        1L,
      ).status_code,
      201,
    )
    let first = mooncode_goal_runtime_append_supervisor_event(
      root,
      session_id,
      @mooncode_core.PhaseChanged("phase-running", @mooncode_core.Running),
      2L,
    )
    assert_true(first is Appended)
    let journal = mooncode_session_journal_path(root, session_id)
    let bytes = @fsx.read_file(journal)
    let retry = mooncode_goal_runtime_append_supervisor_event(
      root,
      session_id,
      @mooncode_core.PhaseChanged("phase-running", @mooncode_core.Running),
      99L,
    )
    assert_true(retry is Idempotent)
    assert_eq(@fsx.read_file(journal), bytes)
    let response = mooncode_goal_runtime_api_get_internal(root, session_id)
    assert_eq(response.status_code, 200)
    guard response.body is Object(body) && body["status"] is Object(status) else {
      abort("goal runtime status")
    }
    assert_eq(status["phase"], ("running" : Json))
    assert_eq(status["handled_count"], 1)
  })
}

///|
async test "goal runtime supervisor rejects semantic reuse of one event id" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-conflict-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    goal_gate_write_snapshot(
      root,
      session_id,
      false,
      goal_gate_snapshot(session_id, root),
    )
    ignore(
      mooncode_goal_runtime_api_put_internal(
        root,
        session_id,
        goal_runtime_test_body(session_id),
        1L,
      ),
    )
    ignore(
      mooncode_goal_runtime_append_supervisor_event(
        root,
        session_id,
        @mooncode_core.PhaseChanged("stable-event", @mooncode_core.Running),
        2L,
      ),
    )
    let journal = mooncode_session_journal_path(root, session_id)
    let before = @fsx.read_file(journal)
    let rejected = try {
      ignore(
        mooncode_goal_runtime_append_supervisor_event(
          root,
          session_id,
          @mooncode_core.PhaseChanged(
            "stable-event",
            @mooncode_core.WaitingApproval,
          ),
          3L,
        ),
      )
      false
    } catch {
      MoonCodeGoalRuntimeStoreError::IdentityConflict(_, _, _) => true
      _ => false
    }
    assert_true(rejected)
    assert_eq(@fsx.read_file(journal), before)
  })
}

///|
async test "goal runtime supervisor permits terminal retry and suppresses fresh work" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-terminal-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    goal_gate_write_snapshot(
      root,
      session_id,
      false,
      goal_gate_snapshot(session_id, root),
    )
    ignore(
      mooncode_goal_runtime_api_put_internal(
        root,
        session_id,
        goal_runtime_test_body(session_id),
        1L,
      ),
    )
    let terminal = mooncode_goal_runtime_append_supervisor_event(
      root,
      session_id,
      @mooncode_core.Cancelled("cancelled-event", "operator cancelled"),
      2L,
    )
    assert_true(terminal is Appended)
    let journal = mooncode_session_journal_path(root, session_id)
    let bytes = @fsx.read_file(journal)
    let retry = mooncode_goal_runtime_append_supervisor_event(
      root,
      session_id,
      @mooncode_core.Cancelled("cancelled-event", "operator cancelled"),
      9L,
    )
    assert_true(retry is Idempotent)
    let suppressed = mooncode_goal_runtime_append_supervisor_event(
      root,
      session_id,
      @mooncode_core.PhaseChanged("late-running", @mooncode_core.Running),
      10L,
    )
    assert_true(suppressed is Terminal)
    assert_eq(@fsx.read_file(journal), bytes)
  })
}

///|
async test "goal runtime supervisor fails closed on legacy authority" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-legacy-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    goal_gate_write_snapshot(
      root,
      session_id,
      false,
      goal_gate_snapshot(session_id, root),
    )
    assert_eq(
      mooncode_goal_api_put_internal(
        root,
        session_id,
        goal_api_body((7).to_json()),
        1L,
      ).status_code,
      201,
    )
    let before = @fsx.read_file(mooncode_session_journal_path(root, session_id))
    let rejected = try {
      ignore(
        mooncode_goal_runtime_append_supervisor_event(
          root,
          session_id,
          @mooncode_core.PhaseChanged("phase-running", @mooncode_core.Running),
          2L,
        ),
      )
      false
    } catch {
      MoonCodeGoalRuntimeStoreError::CorruptStore(_) => true
      _ => false
    }
    assert_true(rejected)
    assert_eq(
      @fsx.read_file(mooncode_session_journal_path(root, session_id)),
      before,
    )
  })
}

///|
test "goal runtime supervisor source mapping is stable and selective" {
  let started : Json = {
    "id": "source-started",
    "kind": "runtime.turn_started",
  }
  let first = mooncode_goal_runtime_events_from_source(started)
  let second = mooncode_goal_runtime_events_from_source(started)
  assert_eq(first.length(), 1)
  assert_eq(second.length(), 1)
  guard first[0]
    is @mooncode_core.PhaseChanged(first_id, @mooncode_core.Running) &&
    second[0] is @mooncode_core.PhaseChanged(second_id, @mooncode_core.Running) else {
    abort("running phase mapping")
  }
  assert_eq(first_id, second_id)
  assert_true(first_id.has_prefix("goal-runtime-phase-running-"))
  assert_eq(
    mooncode_goal_runtime_events_from_source({
      "id": "failed-tool",
      "kind": "tool_result",
      "tool": "shell",
      "status": "failed",
    }).length(),
    0,
  )
  assert_eq(
    mooncode_goal_runtime_events_from_source({
      "id": "done-tool",
      "kind": "tool_result",
      "tool": "shell",
      "status": "done",
    }).length(),
    1,
  )
}

///|
async test "goal runtime supervisor reconciles committed source facts exactly once" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-reconcile-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    goal_gate_write_snapshot(
      root,
      session_id,
      false,
      goal_gate_snapshot(session_id, root),
    )
    assert_eq(
      mooncode_goal_runtime_api_put_internal(
        root,
        session_id,
        goal_runtime_test_body(session_id),
        1L,
      ).status_code,
      201,
    )
    let started = mooncode_event(
      session_id~,
      command_id="command-1",
      lane="runtime",
      kind="runtime.turn_started",
      title="started",
      status="running",
      detail="started",
      now=@clock.Timestamp::from_ms(2000L),
    )
    let tool = mooncode_tool_result_event(
      session_id,
      root,
      "command-1",
      "write",
      mooncode_tool_ok_result("write", message="done", output="", metadata={}),
      now=@clock.Timestamp::from_ms(3000L),
    )
    let checkpoint = mooncode_runtime_planner_continuation_event(
      session_id,
      "command-1",
      { "planner_mode": "model-tool-calls", "tool_calls": [] },
      [],
      [],
      [],
      next_step_index=8,
      now=@clock.Timestamp::from_ms(4000L),
    )
    for source in [started, tool, checkpoint] {
      mooncode_append_session_journal(
        root,
        session_id,
        mooncode_journal_event(),
        source,
      )
    }
    let sources = mooncode_journal_entries(
      mooncode_read_session_journal(root, session_id),
      mooncode_journal_event(),
    )
    mooncode_goal_runtime_reconcile_supervisor_events(
      root, session_id, sources, 5L,
    )
    let journal = mooncode_session_journal_path(root, session_id)
    let bytes = @fsx.read_file(journal)
    mooncode_goal_runtime_reconcile_supervisor_events(
      root, session_id, sources, 99L,
    )
    assert_eq(@fsx.read_file(journal), bytes)
    let response = mooncode_goal_runtime_api_get_internal(root, session_id)
    assert_eq(response.status_code, 200)
    guard response.body is Object(body) && body["status"] is Object(status) else {
      abort("goal runtime status")
    }
    assert_eq(status["phase"], ("paused_external" : Json))
    assert_eq(status["handled_count"], 4)
    assert_eq(status["operation_count"], 1)
    assert_eq(status["checkpoint_count"], 1)
    assert_eq(status["terminal"], false)
  })
}

///|
async test "runtime turn projects running and accepted operations without settling goal" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-turn-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    let command_id = "command-1"
    @fsx.write_to_file(@pathx.join(root, "README.md"), "hello")
    goal_gate_write_snapshot(
      root,
      session_id,
      false,
      goal_gate_snapshot(session_id, root),
    )
    assert_eq(
      mooncode_goal_runtime_api_put_internal(
        root,
        session_id,
        goal_runtime_test_body(session_id),
        1L,
      ).status_code,
      201,
    )
    let command : Json = {
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": root,
      "command": "prompt",
      "model": "codex/gpt-5.6-sol",
      "packet": { "command_id": command_id },
      "runtime_tool_calls": [
        { "tool": "read", "arguments": { "path": "README.md" } },
        { "tool": "finish", "arguments": { "answer": "done" } },
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
        "created_at": @clock.Timestamp::from_ms(2L),
        "command": command,
      },
    )
    let daemon = mooncode_runtime_quantum_test_daemon(root)
    let result = daemon.mooncode_runtime_turn_execute(session_id, root, {
      "consumer_id": "goal-supervisor-test",
    })
    assert_true(mooncode_json_bool(result, "accepted", default=false))
    let response = mooncode_goal_runtime_api_get_internal(root, session_id)
    assert_eq(response.status_code, 200)
    guard response.body is Object(body) && body["status"] is Object(status) else {
      abort("goal runtime status")
    }
    assert_eq(status["phase"], ("running" : Json))
    assert_eq(status["handled_count"], 3)
    assert_eq(status["operation_count"], 2)
    assert_eq(status["checkpoint_count"], 0)
    assert_eq(status["terminal"], false)
    assert_eq(status["outcome"], ("none" : Json))
  })
}

///|
async test "active goal runtime service treats max_turns as a local quantum" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-service-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    goal_gate_write_snapshot(
      root,
      session_id,
      false,
      goal_gate_snapshot(session_id, root),
    )
    assert_eq(
      mooncode_goal_runtime_api_put_internal(
        root,
        session_id,
        goal_runtime_test_body(session_id),
        1L,
      ).status_code,
      201,
    )
    for index in 0..<2 {
      let command_id = "command-" + index.to_string()
      let command : Json = {
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "book_root": root,
        "command": "prompt",
        "model": "codex/gpt-5.6-sol",
        "packet": { "command_id": command_id },
        "runtime_tool_calls": [
          {
            "tool": "finish",
            "arguments": { "answer": "done " + index.to_string() },
          },
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
    let result = daemon.mooncode_runtime_service_execute(session_id, root, {
      "consumer_id": "goal-supervisor-service-test",
      "service_id": "service-1",
      "max_turns": 1,
      "live_wait_ms": 0,
    })
    assert_true(mooncode_json_bool(result, "accepted", default=false))
    let runtime_loop = mooncode_json_object_field_or_empty(
      result, "runtime_loop",
    )
    assert_eq(
      mooncode_json_string(runtime_loop, "stopped_by", default=""),
      "idle",
    )
    let claim_state = mooncode_json_object_field_or_empty(
      runtime_loop, "claim_state",
    )
    assert_eq(
      mooncode_json_int(claim_state, "delivered_command_count", default=0),
      2,
    )
    let response = mooncode_goal_runtime_api_get_internal(root, session_id)
    assert_eq(response.status_code, 200)
    guard response.body is Object(body) && body["status"] is Object(status) else {
      abort("goal runtime status")
    }
    assert_eq(status["phase"], ("running" : Json))
    assert_eq(status["handled_count"], 4)
    assert_eq(status["operation_count"], 2)
    assert_eq(status["terminal"], false)
  })
}

///|
async test "direct tool execution cannot enter supervised goal progress" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-direct-tool-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    goal_gate_write_snapshot(
      root,
      session_id,
      false,
      goal_gate_snapshot(session_id, root),
    )
    assert_eq(
      mooncode_goal_runtime_api_put_internal(
        root,
        session_id,
        goal_runtime_test_body(session_id),
        1L,
      ).status_code,
      201,
    )
    let direct = mooncode_tool_result_event(
      session_id,
      root,
      "direct-command",
      "write",
      mooncode_tool_ok_result("write", message="done", output="", metadata={}),
      now=@clock.Timestamp::from_ms(2000L),
    )
    mooncode_append_session_journal(
      root,
      session_id,
      mooncode_journal_event(),
      direct,
    )
    let sources = mooncode_journal_entries(
      mooncode_read_session_journal(root, session_id),
      mooncode_journal_event(),
    )
    mooncode_goal_runtime_reconcile_supervisor_events(
      root, session_id, sources, 3L,
    )
    let response = mooncode_goal_runtime_api_get_internal(root, session_id)
    assert_eq(response.status_code, 200)
    guard response.body is Object(body) && body["status"] is Object(status) else {
      abort("goal runtime status")
    }
    assert_eq(status["handled_count"], 0)
    assert_eq(status["operation_count"], 0)
    assert_eq(status["terminal"], false)
  })
}
