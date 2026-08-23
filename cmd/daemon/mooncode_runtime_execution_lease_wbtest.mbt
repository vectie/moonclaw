///|
async fn mooncode_execution_lease_test_daemon(book_root : String) -> Daemon {
  Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @trusted_host_process.DaemonChildManager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
    httpx: @httpx.Server::new("[::1]", 0, reuse_addr=true),
    port: 0,
    events: @broadcast.Broadcast::new(),
    serve: book_root,
    conversations: @conversation.Manager::new(
      home=book_root,
      uuid=@uuid.generator(@rand.chacha8()),
    ),
    home: book_root,
    pending_codex_auth: {},
    mooncode_sessions: {},
  }
}

///|
async test "runtime execution lease is stable nonblocking and externally rooted" {
  @fsx.with_temporary_directory("mooncode-execution-lease-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session-execution-lease"
    let path = mooncode_session_execution_lease_path(root, session_id)
    assert_true(path.contains("mooncode/session-locks/"))
    assert_true(path.has_suffix("session-execution-lease.execution-lease"))
    assert_false(path.contains("mooncode/sessions/session-execution-lease/"))
    assert_false(path.contains("mooncode/archived/sessions/"))
    let first = mooncode_open_session_execution_lease(root, session_id)
    let second = mooncode_open_session_execution_lease(root, session_id)
    assert_true(first.try_lock(Exclusive))
    assert_false(second.try_lock(Exclusive))
    first.unlock()
    first.close()
    assert_true(second.try_lock(Exclusive))
    second.unlock()
    second.close()
  })
}

///|
async test "runtime turn returns busy without claiming while execution lease is held" {
  @fsx.with_temporary_directory("mooncode-turn-lease-XXXXXX", async fn(root) {
    let session_id = "session-turn-lease"
    let lease = mooncode_open_session_execution_lease(root, session_id)
    assert_true(lease.try_lock(Exclusive))
    let daemon = mooncode_execution_lease_test_daemon(root)
    let busy = daemon.mooncode_runtime_turn_execute(session_id, root, {
      "consumer_id": "lease-test",
    })
    assert_false(mooncode_json_bool(busy, "accepted", default=true))
    assert_false(mooncode_json_bool(busy, "ran", default=true))
    assert_eq(mooncode_json_string(busy, "status", default=""), "busy")
    assert_eq(
      mooncode_json_string(busy, "error_code", default=""),
      "runtime-execution-busy",
    )
    assert_false(@fsx.exists(mooncode_session_journal_path(root, session_id)))
    lease.unlock()
    lease.close()
    let idle = daemon.mooncode_runtime_turn_execute(session_id, root, {
      "consumer_id": "lease-test",
    })
    assert_eq(mooncode_json_string(idle, "status", default=""), "")
    assert_false(mooncode_json_bool(idle, "ran", default=true))
  })
}

///|
async test "runtime service execution lease is single-flight across daemon instances and released" {
  @fsx.with_temporary_directory("mooncode-service-lease-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session-service-lease"
    let first_daemon = mooncode_execution_lease_test_daemon(root)
    let second_daemon = mooncode_execution_lease_test_daemon(root)
    @async.with_task_group(group => {
      let first = first_daemon.mooncode_start_runtime_service(
        group~,
        session_id,
        root,
        {
          "service_id": "service-first",
          "max_turns": 1,
          "live_wait_ms": 5000,
          "poll_ms": 25,
        },
      )
      assert_true(mooncode_json_bool(first, "started", default=false))
      let second = second_daemon.mooncode_start_runtime_service(
        group~,
        session_id,
        root,
        {
          "service_id": "service-second",
          "max_turns": 1,
          "live_wait_ms": 5000,
          "poll_ms": 25,
        },
      )
      assert_false(mooncode_json_bool(second, "started", default=true))
      assert_eq(mooncode_json_string(second, "status", default=""), "running")
      assert_eq(
        mooncode_json_string(second, "busy_reason", default=""),
        "execution-lease-held",
      )
      let first_events = first_daemon.mooncode_runtime_service_events(
        session_id, root,
      )
      assert_eq(first_events.length(), 1)
      assert_eq(
        mooncode_json_string(first_events[0], "kind", default=""),
        "runtime.service_started",
      )
      let first_binding = first_daemon.mooncode_binding_for_session(session_id)
      match first_binding.runtime_service_task {
        Some(task) => {
          task.cancel()
          let _ = task.wait() catch { _ => () }
        }
        None => abort("first runtime service task missing")
      }
      assert_false(first_binding.runtime_service_running)
      let third = second_daemon.mooncode_start_runtime_service(
        group~,
        session_id,
        root,
        {
          "service_id": "service-third",
          "max_turns": 1,
          "live_wait_ms": 5000,
          "poll_ms": 25,
        },
      )
      assert_true(mooncode_json_bool(third, "started", default=false))
      let second_binding = second_daemon.mooncode_binding_for_session(
        session_id,
      )
      match second_binding.runtime_service_task {
        Some(task) => {
          task.cancel()
          let _ = task.wait() catch { _ => () }
        }
        None => abort("second runtime service task missing")
      }
      assert_false(second_binding.runtime_service_running)
      let events = second_daemon.mooncode_runtime_service_events(
        session_id, root,
      )
      let mut started_count = 0
      for event in events {
        if mooncode_json_string(event, "kind", default="") ==
          "runtime.service_started" {
          started_count += 1
        }
      }
      assert_eq(started_count, 2)
    })
  })
}

///|
async test "runtime loop owns execution lease across the whole loop" {
  @fsx.with_temporary_directory("mooncode-loop-lease-XXXXXX", async fn(root) {
    let session_id = "session-loop-lease"
    let lease = mooncode_open_session_execution_lease(root, session_id)
    assert_true(lease.try_lock(Exclusive))
    let daemon = mooncode_execution_lease_test_daemon(root)
    let busy = daemon.mooncode_runtime_loop_execute(session_id, root, {
      "consumer_id": "lease-loop-test",
      "max_turns": 2,
      "live_wait_ms": 0,
    })
    assert_false(mooncode_json_bool(busy, "accepted", default=true))
    assert_eq(mooncode_json_string(busy, "stopped_by", default=""), "busy")
    assert_eq(mooncode_json_int(busy, "turn_count", default=-1), 0)
    assert_false(@fsx.exists(mooncode_session_journal_path(root, session_id)))
    lease.unlock()
    lease.close()
    let idle = daemon.mooncode_runtime_loop_execute(session_id, root, {
      "consumer_id": "lease-loop-test",
      "max_turns": 2,
      "live_wait_ms": 0,
    })
    assert_eq(mooncode_json_string(idle, "stopped_by", default=""), "idle")
  })
}

///|
async test "runtime service distinguishes a busy operation from a running service" {
  @fsx.with_temporary_directory("mooncode-service-busy-XXXXXX", async fn(root) {
    let session_id = "session-service-busy"
    let lease = mooncode_open_session_execution_lease(root, session_id)
    assert_true(lease.try_lock(Exclusive))
    let daemon = mooncode_execution_lease_test_daemon(root)
    @async.with_task_group(group => {
      let busy = daemon.mooncode_start_runtime_service(
        group~,
        session_id,
        root,
        { "service_id": "not-the-owner", "live_wait_ms": 0 },
      )
      assert_false(mooncode_json_bool(busy, "accepted", default=true))
      assert_false(mooncode_json_bool(busy, "started", default=true))
      assert_eq(mooncode_json_string(busy, "status", default=""), "busy")
      assert_eq(mooncode_json_string(busy, "service_id", default="x"), "")
      assert_eq(
        mooncode_json_string(busy, "busy_reason", default=""),
        "execution-lease-held",
      )
      assert_eq(
        daemon.mooncode_runtime_service_events(session_id, root).length(),
        0,
      )
    })
    lease.unlock()
    lease.close()
  })
}

///|
async test "runtime entry points do not resurrect an archived session" {
  @fsx.with_temporary_directory("mooncode-runtime-archive-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session-runtime-archive"
    let daemon = mooncode_execution_lease_test_daemon(root)
    ignore(
      mooncode_append_session_journal(
        root,
        session_id,
        mooncode_journal_command(),
        {
          "kind": "mooncode-command",
          "protocol": mooncode_protocol_version(),
          "session_id": session_id,
          "command_id": "cmd-archived",
          "created_at": @clock.Timestamp::from_ms(1L),
          "command": {
            "protocol": mooncode_protocol_version(),
            "session_id": session_id,
            "book_root": root,
            "command": "prompt",
            "runtime_tool_calls": [
              { "tool": "finish", "arguments": { "answer": "done" } },
            ],
          },
        },
      ),
    )
    let archived = daemon.mooncode_manage_session_response(session_id, {
      "action": "archive",
      "book_root": root,
    })
    assert_true(mooncode_json_bool(archived, "archived", default=false))
    assert_false(@fsx.exists(mooncode_session_dir(root, session_id)))
    let turn_rejected = try {
      ignore(daemon.mooncode_runtime_turn_execute(session_id, root, {}))
      false
    } catch {
      InvalidJournal(_) => true
      _ => false
    }
    assert_true(turn_rejected)
    let loop_rejected = try {
      ignore(
        daemon.mooncode_runtime_loop_execute(session_id, root, {
          "max_turns": 1,
          "live_wait_ms": 0,
        }),
      )
      false
    } catch {
      InvalidJournal(_) => true
      _ => false
    }
    assert_true(loop_rejected)
    let service_rejected = try {
      ignore(
        daemon.mooncode_runtime_service_execute(session_id, root, {
          "max_turns": 1,
          "live_wait_ms": 0,
        }),
      )
      false
    } catch {
      InvalidJournal(_) => true
      _ => false
    }
    assert_true(service_rejected)
    assert_false(@fsx.exists(mooncode_session_dir(root, session_id)))
    assert_true(
      @fsx.exists(
        mooncode_session_dir_by_safe_id(
          root,
          mooncode_safe_session_id(session_id),
          archived=true,
        ),
      ),
    )
  })
}
