///|
fn mooncode_worker_test_record(
  parent : String,
  parent_root : String,
  worker_id : String,
  child_session_id : String,
  child_root : String,
) -> Json {
  mooncode_worker_record(
    parent,
    parent_root,
    { "id": worker_id, "book_root": child_root },
    child_session_id,
    "child-command-\{worker_id}",
    "worker-\{child_session_id}",
    "parent-command",
    @clock.Timestamp::from_ms(1L),
  )
}

///|
fn mooncode_worker_test_service_event(
  child_session_id : String,
  child_root : String,
  service_id : String,
  kind : String,
  status : String,
  created_at : Int64,
) -> Json {
  mooncode_runtime_service_attach(
    mooncode_event(
      session_id=child_session_id,
      command_id=service_id,
      lane="runtime",
      kind~,
      title="Worker runtime service",
      status~,
      detail="worker runtime test event",
      now=@clock.Timestamp::from_ms(created_at),
    ),
    child_root,
    { "service_id": service_id },
  )
}

///|
async fn mooncode_worker_test_append(
  book_root : String,
  session_id : String,
  record_kind : String,
  payload : Json,
) -> Unit {
  mooncode_append_session_journal(book_root, session_id, record_kind, payload) catch {
    InvalidJournal(message) => fail(message)
    error => raise error
  }
}

///|
async test "spawn worker validation rejects the whole batch before effects" {
  @fsx.with_temporary_directory("mooncode-workers-validate-XXXXXX", async fn(
    root,
  ) {
    let child_root = @pathx.join(root, "child")
    @fsx.make_directory(child_root)
    let report = mooncode_validate_spawn_workers(root, [], {
      "workers": [
        { "id": "one", "book_root": child_root, "prompt": "valid" },
        {
          "id": "two",
          "book_root": @pathx.join(root, "missing"),
          "prompt": "invalid",
        },
      ],
    })
    assert_false(mooncode_json_bool(report, "ok", default=true))
    assert_true(
      mooncode_json_array_items(report, "errors").any(error => {
        error.stringify().contains("isolated from the parent")
      }),
    )
    assert_eq(mooncode_worker_records(root, "parent").length(), 0)
    assert_false(@fsx.exists(mooncode_sessions_root(child_root)))
  })
}

///|
test "worker child command is an ordinary linked prompt" {
  let command = mooncode_worker_command(
    "parent",
    {
      "id": "docs",
      "book_root": "/tmp/docs",
      "prompt": "Inspect docs",
      "task_intent": "read_only",
    },
    "provider/model",
    "parent-worker-docs",
    "worker-prompt-docs",
  )
  assert_eq(
    mooncode_json_string(command, "session_id", default=""),
    "parent-worker-docs",
  )
  assert_eq(mooncode_json_string(command, "command", default=""), "prompt")
  assert_eq(
    mooncode_json_string(command, "model", default=""),
    "provider/model",
  )
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  assert_eq(
    mooncode_json_string(payload, "parent_session_id", default=""),
    "parent",
  )
  assert_eq(
    mooncode_json_string(payload, "task_intent", default=""),
    "read_only",
  )
}

///|
async test "wait workers uses durable any and all terminal evidence" {
  @fsx.with_temporary_directory("mooncode-workers-wait-XXXXXX", async fn(root) {
    let child_one_root = @pathx.join(root, "child-one")
    let child_two_root = @pathx.join(root, "child-two")
    @fsx.make_directory(child_one_root)
    @fsx.make_directory(child_two_root)
    let parent = "parent"
    let child_one = "child-one"
    let child_two = "child-two"
    let service_one = "worker-\{child_one}"
    let service_two = "worker-\{child_two}"
    mooncode_worker_test_append(
      root,
      parent,
      mooncode_journal_event(),
      mooncode_worker_test_record(
        parent, root, "one", child_one, child_one_root,
      ),
    )
    mooncode_worker_test_append(
      root,
      parent,
      mooncode_journal_event(),
      mooncode_worker_test_record(
        parent, root, "two", child_two, child_two_root,
      ),
    )
    mooncode_worker_test_append(
      child_one_root,
      child_one,
      mooncode_journal_event(),
      mooncode_worker_test_service_event(
        child_one, child_one_root, service_one, "runtime.service_started", "running",
        2L,
      ),
    )
    mooncode_worker_test_append(
      child_one_root,
      child_one,
      mooncode_journal_event(),
      mooncode_worker_test_service_event(
        child_one, child_one_root, service_one, "runtime.service_finished", "done",
        3L,
      ),
    )
    mooncode_worker_test_append(
      child_two_root,
      child_two,
      mooncode_journal_event(),
      mooncode_worker_test_service_event(
        child_two, child_two_root, service_two, "runtime.service_started", "running",
        4L,
      ),
    )
    mooncode_worker_test_append(
      child_one_root,
      child_one,
      mooncode_journal_runtime_receipt(),
      mooncode_runtime_turn_receipt(
        child_one,
        child_one_root,
        {
          "command_id": "child-command-one",
          "receipt": { "claim_id": "claim-one" },
        },
        { "accepted": true },
        consumer_id="worker-test",
        now=@clock.Timestamp::from_ms(3L),
      ),
    )
    let any = mooncode_wait_workers_projection(parent, root, { "mode": "any" })
    let all_running = mooncode_wait_workers_projection(parent, root, {
      "mode": "all",
    })
    assert_true(
      mooncode_json_bool(
        mooncode_json_object_field_or_empty(any, "metadata"),
        "ready",
        default=false,
      ),
    )
    assert_false(
      mooncode_json_bool(
        mooncode_json_object_field_or_empty(all_running, "metadata"),
        "ready",
        default=true,
      ),
    )
    mooncode_worker_test_append(
      child_two_root,
      child_two,
      mooncode_journal_event(),
      mooncode_worker_test_service_event(
        child_two, child_two_root, service_two, "runtime.service_finished", "done",
        5L,
      ),
    )
    mooncode_worker_test_append(
      child_two_root,
      child_two,
      mooncode_journal_runtime_receipt(),
      mooncode_runtime_turn_receipt(
        child_two,
        child_two_root,
        {
          "command_id": "child-command-two",
          "receipt": { "claim_id": "claim-two" },
        },
        { "accepted": true },
        consumer_id="worker-test",
        now=@clock.Timestamp::from_ms(5L),
      ),
    )
    let all_done = mooncode_wait_workers_projection(parent, root, {
      "mode": "all",
    })
    let metadata = mooncode_json_object_field_or_empty(all_done, "metadata")
    assert_true(mooncode_json_bool(metadata, "ready", default=false))
    let workers = mooncode_json_array_items(metadata, "workers")
    assert_eq(workers.length(), 2)
    assert_eq(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(workers[0], "terminal_evidence"),
        "kind",
        default="",
      ),
      mooncode_kind_runtime_receipt(),
    )
  })
}

///|
async test "worker spawning is unavailable without native runtime context" {
  @fsx.with_temporary_directory("mooncode-workers-context-XXXXXX", async fn(
    root,
  ) {
    let execution = mooncode_execute_tool_call_in_runtime(
      None,
      "parent",
      root,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "parent",
        "book_root": root,
        "command_id": "cmd-workers",
        "tool": "spawn_workers",
        "arguments": {
          "workers": [
            { "id": "one", "book_root": root, "prompt": "Must be isolated" },
          ],
        },
      },
      now=@clock.Timestamp::from_ms(1L),
    )
    assert_false(mooncode_json_bool(execution, "accepted", default=true))
    assert_true(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(execution, "result"),
        "message",
        default="",
      ).contains("requires the native"),
    )
  })
}

///|
test "worker tools are projected by native capability" {
  assert_true(mooncode_native_capability_tools().contains("spawn_workers"))
  assert_true(mooncode_native_capability_tools().contains("wait_workers"))
  assert_true(mooncode_tool_supported("spawn_workers"))
  assert_true(mooncode_tool_supported("wait_workers"))
}

///|
async test "wait workers scopes default wait to active command and guides progression" {
  @fsx.with_temporary_directory("mooncode-workers-scoped-XXXXXX", async fn(
    root,
  ) {
    let old_root = @pathx.join(root, "old-worker")
    let cur_root = @pathx.join(root, "cur-worker")
    @fsx.make_directory(old_root)
    @fsx.make_directory(cur_root)
    let parent = "parent"
    // Unfinished worker from an earlier command must not poison a new command's default wait.
    mooncode_worker_test_append(
      root,
      parent,
      mooncode_journal_event(),
      mooncode_worker_record(
        parent,
        root,
        { "id": "stale", "book_root": old_root },
        "child-stale",
        "child-cmd-stale",
        "worker-child-stale",
        "earlier-command",
        @clock.Timestamp::from_ms(1L),
      ),
    )
    mooncode_worker_test_append(
      root,
      parent,
      mooncode_journal_event(),
      mooncode_worker_record(
        parent,
        root,
        { "id": "fresh", "book_root": cur_root },
        "child-fresh",
        "child-cmd-fresh",
        "worker-child-fresh",
        "active-command",
        @clock.Timestamp::from_ms(2L),
      ),
    )
    mooncode_worker_test_append(
      cur_root,
      "child-fresh",
      mooncode_journal_runtime_receipt(),
      mooncode_runtime_turn_receipt(
        "child-fresh",
        cur_root,
        {
          "command_id": "child-cmd-fresh",
          "receipt": { "claim_id": "claim-fresh" },
        },
        { "accepted": true },
        consumer_id="worker-test",
        now=@clock.Timestamp::from_ms(3L),
      ),
    )
    let scoped = mooncode_wait_workers_projection(
      parent,
      root,
      { "mode": "all" },
      command_id="active-command",
    )
    let meta = mooncode_json_object_field_or_empty(scoped, "metadata")
    assert_true(mooncode_json_bool(meta, "ready", default=false))
    assert_eq(mooncode_json_array_items(meta, "workers").length(), 1)
    assert_true(
      mooncode_json_string(meta, "next_action", default="").contains(
        "Do not call wait_workers again",
      ),
    )
    assert_true(
      mooncode_json_string(scoped, "output", default="").contains("ready=true"),
    )
    // Explicit worker_ids still inspects historical workers if requested.
    let explicit_stale = mooncode_wait_workers_projection(
      parent,
      root,
      { "mode": "all", "worker_ids": ["stale"] },
      command_id="active-command",
    )
    assert_false(
      mooncode_json_bool(
        mooncode_json_object_field_or_empty(explicit_stale, "metadata"),
        "ready",
        default=true,
      ),
    )
  })
}

///|
test "followup planner emits escalating guidance after ready wait_workers" {
  let ready_exec : Json = {
    "tool": "wait_workers",
    "accepted": true,
    "result": { "ok": true, "metadata": { "ready": true } },
  }
  let first = mooncode_runtime_turn_worker_wait_guidance([ready_exec], [
    ready_exec,
  ])
  assert_true(first.contains("ready=true"))
  let repeated = mooncode_runtime_turn_worker_wait_guidance([ready_exec], [
    ready_exec, ready_exec,
  ])
  assert_true(repeated.contains("STOP calling wait_workers"))
}
