///|
priv struct MoonCodeServiceGoalWakeClock {
  binding : MoonCodeSessionBinding
  mut saw_active : Bool
  mut woke : Bool
}

///|
impl @clock.Clock for MoonCodeServiceGoalWakeClock with fn now(self) {
  if self.binding.active_command_id != "" {
    self.saw_active = true
  } else if self.saw_active && !self.woke {
    // Wake after the completed turn has released its active-command binding.
    // With one goal turn this is service finalization, after the drain check.
    self.binding.runtime_service_wake_pending = true
    self.woke = true
  }
  @clock.epoch.now()
}

///|
impl @clock.Clock for MoonCodeServiceGoalWakeClock with fn now_str(self) {
  ignore(self)
  @clock.epoch.now_str()
}

///|
async fn mooncode_service_goal_queue_command(
  root : String,
  session_id : String,
  index : Int,
  tools : Array[Json],
) -> Unit {
  let command_id = "goal-queue-" + index.to_string()
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
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "book_root": root,
        "command": "prompt",
        "model": "fixture/mooncode",
        "packet": { "command_id": command_id },
        "runtime_tool_calls": Json::array(tools),
      },
    },
  )
}

///|
fn mooncode_service_goal_queue_write(path : String) -> Json {
  { "tool": "write", "arguments": { "path": path, "content": path } }
}

///|
async fn mooncode_service_goal_queue_test(
  max_turns : Int?,
  blocked? : Bool = false,
  wake_on_finish? : Bool = false,
  run_later_ordinary? : Bool = false,
) -> Unit {
  @fsx.with_temporary_directory("mooncode-service-goal-queue-XXXXXX", async fn(
    root,
  ) {
    let session_id = "goal-queue"
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
    let first_count = if wake_on_finish { 1 } else { 2 }
    if !wake_on_finish {
      mooncode_service_goal_queue_command(root, session_id, 0, [
        mooncode_service_goal_queue_write("progress.txt"),
        { "tool": "finish", "arguments": { "answer": "progress" } },
      ])
    }
    let decision : Json = if blocked {
      {
        "type": "blocked",
        "reason": { "code": "external", "detail": "awaiting input" },
        "attempted_alternatives": ["local fixture"],
        "required_event": "input supplied",
      }
    } else {
      {
        "type": "achieved",
        "summary": "native proof and tests completed",
        "evidence": [
          { "criterion": "criterion-1", "evidence_refs": ["proof-native"] },
          { "criterion": "criterion-2", "evidence_refs": ["proof-tests"] },
        ],
      }
    }
    mooncode_service_goal_queue_command(root, session_id, first_count - 1, [
      mooncode_service_goal_queue_write("settlement.txt"),
      {
        "tool": "finish",
        "arguments": { "answer": "settled", "goal_runtime": decision },
      },
    ])
    mooncode_service_goal_queue_command(root, session_id, first_count, [
      mooncode_service_goal_queue_write("sentinel-after-settlement.txt"),
      { "tool": "finish", "arguments": { "answer": "later work" } },
    ])
    let original = mooncode_runtime_quantum_test_daemon(root)
    defer original.httpx.close()
    let clock = MoonCodeServiceGoalWakeClock::{
      binding: original.mooncode_binding_for_session(session_id),
      saw_active: false,
      woke: false,
    }
    let daemon = if wake_on_finish { { ..original, clock, } } else { original }
    let payload : Json = match max_turns {
      Some(limit) => { "live_wait_ms": 0, "max_turns": limit }
      None => { "live_wait_ms": 0 }
    }
    let result = daemon.mooncode_runtime_service_execute(
      session_id, root, payload,
    )
    assert_true(mooncode_json_bool(result, "accepted", default=false))
    assert_eq(
      @fsx.read_file(@pathx.join(root, "settlement.txt")),
      "settlement.txt",
    )
    if !wake_on_finish {
      assert_eq(
        @fsx.read_file(@pathx.join(root, "progress.txt")),
        "progress.txt",
      )
    }
    assert_false(
      @fsx.exists(@pathx.join(root, "sentinel-after-settlement.txt")),
    )
    let claim = daemon.mooncode_runtime_claim_state_payload(session_id, root)
    assert_eq(
      mooncode_json_int(claim, "delivered_command_count", default=0),
      first_count,
    )
    assert_eq(mooncode_json_int(claim, "claimable_command_count", default=0), 1)
    let response = mooncode_goal_runtime_api_get_internal(root, session_id)
    guard response.body is Object(body) && body["status"] is Object(status) else {
      abort("goal runtime status")
    }
    assert_eq(status["terminal"], true)
    assert_eq(
      status["outcome"],
      (if blocked { "blocked" } else { "achieved" }).to_json(),
    )
    let events = daemon.mooncode_runtime_service_events(session_id, root)
    assert_eq(events.length(), 1)
    if wake_on_finish {
      assert_true(clock.woke)
      assert_true(clock.binding.runtime_service_wake_pending)
    }
    if run_later_ordinary {
      mooncode_service_goal_queue_command(root, session_id, first_count + 1, [
        mooncode_service_goal_queue_write("new-ordinary-work.txt"),
        { "tool": "finish", "arguments": { "answer": "new work done" } },
      ])
      ignore(
        daemon.mooncode_runtime_service_execute(session_id, root, {
          "live_wait_ms": 0,
          "service_id": "new-ordinary-run",
        }),
      )
      for path in ["sentinel-after-settlement.txt", "new-ordinary-work.txt"] {
        assert_eq(@fsx.read_file(@pathx.join(root, path)), path)
      }
      let after = daemon.mooncode_runtime_claim_state_payload(session_id, root)
      assert_eq(
        mooncode_json_int(after, "delivered_command_count", default=0),
        first_count + 2,
      )
      assert_false(mooncode_json_bool(after, "claim_ready", default=true))
    }
  })
}

///|
async test "default goal service stops queued outputs at typed achievement" {
  mooncode_service_goal_queue_test(None)
}

///|
async test "explicit goal service quanta still continue then stop at achievement" {
  mooncode_service_goal_queue_test(Some(1))
  mooncode_service_goal_queue_test(Some(2))
}

///|
async test "default goal service stops queued outputs at typed blocked decision" {
  mooncode_service_goal_queue_test(None, blocked=true)
}

///|
async test "goal finalization wake cannot rearm after achievement" {
  mooncode_service_goal_queue_test(None, wake_on_finish=true)
  mooncode_service_goal_queue_test(None, wake_on_finish=true, blocked=true)
}

///|
async test "ordinary finalization wake rearms and writes a later queued output" {
  @fsx.with_temporary_directory("mooncode-service-ordinary-wake-XXXXXX", async fn(
    root,
  ) {
    let session_id = "ordinary-wake"
    mooncode_service_goal_queue_command(root, session_id, 0, [
      mooncode_service_goal_queue_write("before-wake.txt"),
      { "tool": "finish", "arguments": { "answer": "first output" } },
    ])
    let original = mooncode_runtime_quantum_test_daemon(root)
    defer original.httpx.close()
    let clock = MoonCodeServiceGoalWakeClock::{
      binding: original.mooncode_binding_for_session(session_id),
      saw_active: false,
      woke: false,
    }
    let daemon = { ..original, clock, }
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        for _attempt in 0..<1000 {
          if clock.woke {
            break
          }
          @async.sleep(1)
        }
        assert_true(clock.woke)
        mooncode_service_goal_queue_command(root, session_id, 1, [
          mooncode_service_goal_queue_write("after-wake.txt"),
          { "tool": "finish", "arguments": { "answer": "later output" } },
        ])
      })
      let result = daemon.mooncode_runtime_service_execute(session_id, root, {
        "live_wait_ms": 1000,
        "poll_ms": 1,
      })
      assert_true(mooncode_json_bool(result, "accepted", default=false))
    })
    for path in ["before-wake.txt", "after-wake.txt"] {
      assert_eq(@fsx.read_file(@pathx.join(root, path)), path)
    }
    let claim = daemon.mooncode_runtime_claim_state_payload(session_id, root)
    assert_eq(mooncode_json_int(claim, "delivered_command_count", default=0), 2)
    let events = daemon.mooncode_runtime_service_events(session_id, root)
    assert_eq(events.length(), 3)
    assert_eq(
      mooncode_json_string(events[1], "kind", default=""),
      "runtime.service_started",
    )
  })
}

///|
async test "fresh ordinary service after a terminal goal drains later outputs" {
  mooncode_service_goal_queue_test(None, run_later_ordinary=true)
}

///|
async test "service ownership captures a new goal even after immediate settlement" {
  @fsx.with_temporary_directory("mooncode-service-goal-owner-XXXXXX", async fn(
    root,
  ) {
    for terminal_before_refresh in [false, true] {
      let session_id = if terminal_before_refresh {
        "already-settled"
      } else {
        "active"
      }
      goal_gate_write_snapshot(
        root,
        session_id,
        false,
        goal_gate_snapshot(session_id, root),
      )
      let (has_goal, terminal_at_entry) = mooncode_runtime_service_goal_scope(
        root, session_id,
      )
      assert_false(has_goal)
      assert_false(terminal_at_entry)
      assert_false(
        mooncode_runtime_service_refresh_goal_ownership(
          false, terminal_at_entry, root, session_id,
        ),
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
      if terminal_before_refresh {
        ignore(
          mooncode_goal_runtime_append_supervisor_event(
            root,
            session_id,
            Cancelled("settled", "goal settled"),
            2L,
          ),
        )
      }
      let owned = mooncode_runtime_service_refresh_goal_ownership(
        false, terminal_at_entry, root, session_id,
      )
      assert_true(owned)
      if !terminal_before_refresh {
        ignore(
          mooncode_goal_runtime_append_supervisor_event(
            root,
            session_id,
            Cancelled("settled", "goal settled"),
            2L,
          ),
        )
      }
      assert_true(
        mooncode_runtime_service_refresh_goal_ownership(
          owned, terminal_at_entry, root, session_id,
        ),
      )
      let (later_has_goal, later_terminal) = mooncode_runtime_service_goal_scope(
        root, session_id,
      )
      assert_true(later_has_goal)
      assert_true(later_terminal)
      assert_false(
        mooncode_runtime_service_refresh_goal_ownership(
          false, later_terminal, root, session_id,
        ),
      )
    }
  })
}
