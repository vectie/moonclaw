///|
async fn mooncode_worker_results_test_queue(
  parent_root : String,
  child_root : String,
  worker_id : String,
  calls : Array[Json],
) -> Unit {
  @fsx.make_directory(child_root)
  let child = "child-\{worker_id}"
  mooncode_worker_test_append(
    parent_root,
    "parent",
    mooncode_journal_event(),
    mooncode_worker_test_record(
      "parent", parent_root, worker_id, child, child_root,
    ),
  )
  let command = mooncode_worker_command(
    "parent",
    {
      "id": worker_id,
      "book_root": child_root,
      "prompt": "Research and report findings",
      "task_intent": "read_only",
    },
    "fixture/mooncode",
    child,
    "child-command-\{worker_id}",
  )
  let command = mooncode_json_object_with_field(
    command,
    "runtime_tool_calls",
    Json::array(calls),
  )
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let command = mooncode_json_object_with_field(
    command,
    "payload",
    mooncode_json_object_with_field(payload, "approval_wait_ms", 0),
  )
  mooncode_control_test_queue(
    child_root,
    child,
    command,
    now=@clock.Timestamp::from_ms(1L),
  )
}

///|
async fn mooncode_worker_results_test_wait(
  parent_root : String,
  mode : String,
) -> Json {
  mooncode_json_object_field_or_empty(
    mooncode_wait_workers_projection("parent", parent_root, { "mode": mode }),
    "metadata",
  )
}

///|
async test "worker handback returns exact native child answers and canonical artifacts repeatedly" {
  @fsx.with_temporary_directory("worker-results-native-XXXXXX", async fn(root) {
    let parent_root = @pathx.join(root, "parent")
    @fsx.make_directory(parent_root)
    for id in ["one", "two"] {
      let child_root = @pathx.join(root, id)
      mooncode_worker_results_test_queue(parent_root, child_root, id, [
        {
          "tool": "write",
          "arguments": {
            "path": "finding.txt",
            "content": "ordinary-artifact-\{id}",
          },
        },
        {
          "tool": "write",
          "arguments": {
            "path": "portable/app-tool/finding.txt",
            "content": "artifact-\{id}",
          },
        },
        { "tool": "finish", "arguments": { "answer": "REAL_RESEARCH_\{id}" } },
      ])
      let daemon = mooncode_runtime_quantum_test_daemon(child_root)
      defer daemon.httpx.close()
      let ran = daemon.mooncode_runtime_service_execute(
        "child-\{id}",
        child_root,
        { "service_id": "worker-child-\{id}", "live_wait_ms": 0 },
      )
      assert_true(ran.stringify().contains("REAL_RESEARCH_\{id}"))
      assert_eq(
        @fsx.read_file(@pathx.join(child_root, "portable/app-tool/finding.txt")),
        "artifact-\{id}",
      )
      // A later ordinary message can even reuse the same service id. Its answer
      // must never replace the exact command captured by the spawn link.
      mooncode_control_test_queue(
        child_root,
        "child-\{id}",
        {
          "protocol": mooncode_protocol_version(),
          "session_id": "child-\{id}",
          "book_root": child_root,
          "command": "prompt",
          "model": "fixture/mooncode",
          "packet": { "command_id": "unrelated-\{id}" },
          "runtime_tool_calls": [
            {
              "tool": "write",
              "arguments": { "path": "WRONG_LATER.txt", "content": "unrelated" },
            },
            { "tool": "finish", "arguments": { "answer": "WRONG_LATER_\{id}" } },
          ],
        },
        now=@clock.Timestamp::from_ms(2L),
      )
      ignore(
        daemon.mooncode_runtime_service_execute("child-\{id}", child_root, {
          "service_id": "worker-child-\{id}",
          "live_wait_ms": 0,
        }),
      )
    }
    let first = mooncode_worker_results_test_wait(parent_root, "all")
    assert_true(mooncode_json_bool(first, "ready", default=false))
    let workers = mooncode_json_array_items(first, "workers")
    assert_eq(workers.length(), 2)
    for index, id in ["one", "two"] {
      let worker = workers[index]
      let early_result = mooncode_json_object_field_or_empty(worker, "result")
      assert_eq(
        mooncode_json_string(early_result, "answer", default=""),
        "REAL_RESEARCH_\{id}",
      )
      assert_eq(
        mooncode_json_string(worker, "child_command_id", default=""),
        "child-command-\{id}",
      )
      assert_eq(mooncode_json_string(worker, "status", default=""), "done")
      assert_true(mooncode_json_bool(worker, "successful", default=false))
      let result = mooncode_json_object_field_or_empty(worker, "result")
      assert_eq(
        mooncode_json_string(result, "answer", default=""),
        "REAL_RESEARCH_\{id}",
      )
      let receipt = mooncode_json_object_field_or_empty(
        result, "receipt_reference",
      )
      assert_eq(
        mooncode_json_string(receipt, "command_id", default=""),
        "child-command-\{id}",
      )
      assert_eq(
        mooncode_json_string(receipt, "record_kind", default=""),
        mooncode_journal_runtime_receipt(),
      )
      assert_true(mooncode_json_string(receipt, "record_id", default="") != "")
      assert_true(mooncode_json_string(receipt, "sequence", default="") != "")
      let artifacts = mooncode_json_array_items(result, "artifact_references")
      assert_true(
        artifacts.any(item => {
          mooncode_json_string(item, "path", default="") ==
          "portable/app-tool/finding.txt"
        }),
      )
      assert_true(
        artifacts.any(item => {
          mooncode_json_string(item, "path", default="") == "finding.txt"
        }),
      )
      for artifact in artifacts {
        assert_eq(
          mooncode_json_string(artifact, "child_command_id", default=""),
          "child-command-\{id}",
        )
        let source = mooncode_json_object_field_or_empty(artifact, "source")
        assert_true(mooncode_json_string(source, "record_id", default="") != "")
        assert_true(mooncode_json_string(source, "sequence", default="") != "")
        assert_eq(
          mooncode_json_string(artifact, "access", default=""),
          "reference-only",
        )
      }
      assert_true(
        mooncode_json_array_items(result, "result_references").length() > 0,
      )
      assert_false(result.stringify().contains("WRONG_LATER"))
      let escaped = mooncode_tool_read(parent_root, {
        "path": mooncode_session_journal_path(
          @pathx.join(root, id),
          "child-\{id}",
        ),
      })
      assert_true(mooncode_json_bool(escaped, "is_error", default=false))
    }
    assert_eq(first, mooncode_worker_results_test_wait(parent_root, "all"))
  })
}

///|
async test "worker approval wait is nonterminal until native approval and resume complete" {
  @fsx.with_temporary_directory("worker-results-approval-XXXXXX", async fn(
    root,
  ) {
    let parent_root = @pathx.join(root, "parent")
    let child_root = @pathx.join(root, "child")
    @fsx.make_directory(parent_root)
    mooncode_worker_results_test_queue(parent_root, child_root, "one", [
      {
        "tool": "write",
        "requires_approval": true,
        "arguments": { "path": "approved.txt", "content": "approved" },
      },
      { "tool": "finish", "arguments": { "answer": "APPROVED_RESEARCH" } },
    ])
    let daemon = mooncode_control_test_daemon(child_root)
    defer daemon.httpx.close()
    ignore(
      daemon.mooncode_runtime_service_execute("child-one", child_root, {
        "service_id": "worker-child-one",
        "live_wait_ms": 0,
      }),
    )
    for mode in ["any", "all"] {
      let waiting = mooncode_worker_results_test_wait(parent_root, mode)
      assert_false(mooncode_json_bool(waiting, "ready", default=true))
      let worker = mooncode_json_array_items(waiting, "workers")[0]
      assert_eq(mooncode_json_string(worker, "status", default=""), "waiting")
      assert_false(mooncode_json_bool(worker, "terminal", default=true))
      let pending = mooncode_json_object_field_or_empty(worker, "pending")
      assert_eq(
        mooncode_json_string(pending, "state", default=""),
        "awaiting-approval",
      )
      assert_true(
        mooncode_json_string(pending, "approval_id", default="") != "",
      )
      assert_eq(
        mooncode_json_string(pending, "target_command_id", default=""),
        "child-command-one",
      )
    }
    let request = mooncode_control_test_approval_request(
      mooncode_journal_entries(
        mooncode_read_session_journal(child_root, "child-one"),
        mooncode_journal_event(),
      ),
    )
    @async.with_task_group(group => {
      ignore(
        daemon.mooncode_submit_turn_response(group~, "child-one", {
          "protocol": mooncode_protocol_version(),
          "session_id": "child-one",
          "book_root": child_root,
          "command": "approve_tool",
          "model": "fixture/mooncode",
          "text": "Approve fixture write",
          "packet": { "command_id": "approve-one" },
          "payload": {
            "approval_id": mooncode_json_string(
              request,
              "approval_id",
              default="",
            ),
            "target_command_id": "child-command-one",
            "tool_call_id": mooncode_json_string(
              request,
              "tool_call_id",
              default="",
            ),
          },
        }),
      )
      let binding = daemon.mooncode_binding_for_session("child-one")
      let mut attempts = 0
      while binding.runtime_service_running && attempts < 200 {
        @async.sleep(10)
        attempts += 1
      }
      assert_false(binding.runtime_service_running)
      group.return_immediately(())
    })
    let completed = mooncode_worker_results_test_wait(parent_root, "all")
    assert_true(mooncode_json_bool(completed, "ready", default=false))
    let worker = mooncode_json_array_items(completed, "workers")[0]
    assert_eq(mooncode_json_string(worker, "status", default=""), "done")
    assert_eq(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(worker, "result"),
        "answer",
        default="",
      ),
      "APPROVED_RESEARCH",
    )
    assert_eq(
      mooncode_json_object_field_or_empty(worker, "pending"),
      Json::object({}),
    )
  })
}

///|
async test "worker native failure and cancellation are terminal distinct unsuccessful outcomes" {
  @fsx.with_temporary_directory("worker-results-fail-cancel-XXXXXX", async fn(
    root,
  ) {
    let parent_root = @pathx.join(root, "parent")
    @fsx.make_directory(parent_root)
    for id in ["failed", "cancelled"] {
      let child_root = @pathx.join(root, id)
      let calls : Array[Json] = if id == "failed" {
        [{ "tool": "read", "arguments": { "path": "missing.txt" } }]
      } else {
        [
          {
            "tool": "write",
            "requires_approval": true,
            "arguments": { "path": "never.txt", "content": "never" },
          },
        ]
      }
      mooncode_worker_results_test_queue(parent_root, child_root, id, calls)
      let daemon = mooncode_control_test_daemon(child_root)
      defer daemon.httpx.close()
      ignore(
        daemon.mooncode_runtime_service_execute("child-\{id}", child_root, {
          "service_id": "worker-child-\{id}",
          "live_wait_ms": 0,
        }),
      )
      if id == "cancelled" {
        ignore(
          daemon.mooncode_submit_cancel_control("child-\{id}", child_root, {
            "command": "cancel",
            "packet": { "command_id": "cancel-child" },
            "payload": { "target_command_id": "child-command-\{id}" },
          }),
        )
      }
    }
    let result = mooncode_worker_results_test_wait(parent_root, "all")
    assert_true(mooncode_json_bool(result, "ready", default=false))
    for index, id in ["failed", "cancelled"] {
      let worker = mooncode_json_array_items(result, "workers")[index]
      assert_eq(mooncode_json_string(worker, "status", default=""), id)
      assert_true(mooncode_json_bool(worker, "terminal", default=false))
      assert_false(mooncode_json_bool(worker, "successful", default=true))
      let evidence = mooncode_json_object_field_or_empty(
        worker, "terminal_evidence",
      )
      let reason = mooncode_json_string(evidence, "reason", default="")
      assert_true(
        reason.contains(
          if id == "failed" {
            "missing.txt"
          } else {
            "cancelled"
          },
        ),
      )
      let reason_reference = mooncode_json_object_field_or_empty(
        evidence, "reason_reference",
      )
      assert_eq(
        mooncode_json_string(reason_reference, "command_id", default=""),
        "child-command-\{id}",
      )
      assert_true(
        mooncode_json_string(reason_reference, "record_id", default="") != "",
      )
      assert_eq(
        mooncode_json_string(
          mooncode_json_object_field_or_empty(worker, "result"),
          "answer",
          default="",
        ),
        "",
      )
    }
  })
}

///|
async test "worker lifecycle stops and unrelated receipts never prove command completion" {
  @fsx.with_temporary_directory("worker-results-lifecycle-XXXXXX", async fn(
    root,
  ) {
    let child_root = @pathx.join(root, "child")
    @fsx.make_directory(child_root)
    mooncode_worker_test_append(
      root,
      "parent",
      mooncode_journal_event(),
      mooncode_worker_test_record("parent", root, "one", "child", child_root),
    )
    for status in ["waiting", "done", "failed", "cancelled"] {
      mooncode_worker_test_append(
        child_root,
        "child",
        mooncode_journal_event(),
        mooncode_worker_test_service_event(
          "child",
          child_root,
          "worker-child",
          "runtime.service_finished",
          status,
          (status.length() + 2).to_int64(),
        ),
      )
      for mode in ["all", "any"] {
        let result = mooncode_worker_results_test_wait(root, mode)
        assert_false(mooncode_json_bool(result, "ready", default=true))
        assert_false(
          mooncode_json_bool(
            mooncode_json_array_items(result, "workers")[0],
            "terminal",
            default=true,
          ),
        )
      }
    }
  })
}

///|
async test "worker paused checkpoint remains unfinished and command scoped" {
  @fsx.with_temporary_directory("worker-results-paused-XXXXXX", async fn(root) {
    let child_root = @pathx.join(root, "child")
    @fsx.make_directory(child_root)
    mooncode_worker_test_append(
      root,
      "parent",
      mooncode_journal_event(),
      mooncode_worker_test_record("parent", root, "one", "child", child_root),
    )
    mooncode_worker_test_append(
      child_root,
      "child",
      mooncode_journal_event(),
      mooncode_runtime_planner_continuation_event(
        "child",
        "child-command-one",
        {},
        [],
        [],
        [],
        next_step_index=3,
        now=@clock.Timestamp::from_ms(2L),
      ),
    )
    mooncode_worker_test_append(
      child_root,
      "child",
      mooncode_journal_event(),
      mooncode_worker_test_service_event(
        "child", child_root, "worker-child", "runtime.service_finished", "done",
        3L,
      ),
    )
    mooncode_worker_test_append(
      child_root,
      "child",
      mooncode_journal_runtime_receipt(),
      mooncode_runtime_turn_receipt(
        "child",
        child_root,
        {
          "command_id": "other-command",
          "receipt": { "claim_id": "other-claim" },
        },
        {
          "accepted": true,
          "tool_results": [
            {
              "tool": "finish",
              "accepted": true,
              "result": { "output": "UNRELATED_SUCCESS" },
            },
          ],
        },
        consumer_id="test",
        now=@clock.Timestamp::from_ms(4L),
      ),
    )
    for mode in ["any", "all"] {
      let result = mooncode_worker_results_test_wait(root, mode)
      assert_false(mooncode_json_bool(result, "ready", default=true))
      let worker = mooncode_json_array_items(result, "workers")[0]
      assert_eq(mooncode_json_string(worker, "status", default=""), "paused")
      let pending = mooncode_json_object_field_or_empty(worker, "pending")
      assert_eq(
        mooncode_json_string(pending, "state", default=""),
        "planner-quantum-paused",
      )
      assert_eq(
        mooncode_json_string(pending, "reason", default=""),
        "planner-step-quantum",
      )
      assert_false(worker.stringify().contains("UNRELATED_SUCCESS"))
    }
  })
}

///|
async test "worker handback bounds answers and canonical references without dereferencing artifacts" {
  @fsx.with_temporary_directory("worker-results-bounds-XXXXXX", async fn(root) {
    let child_root = @pathx.join(root, "child")
    @fsx.make_directory(child_root)
    mooncode_worker_test_append(
      root,
      "parent",
      mooncode_journal_event(),
      mooncode_worker_test_record("parent", root, "one", "child", child_root),
    )
    let answer = "research finding ".repeat(2000)
    mooncode_worker_test_append(
      child_root,
      "child",
      mooncode_journal_runtime_receipt(),
      mooncode_runtime_turn_receipt(
        "child",
        child_root,
        {
          "command_id": "child-command-one",
          "receipt": { "claim_id": "bounded-claim" },
        },
        {
          "accepted": true,
          "tool_results": [
            {
              "tool": "finish",
              "accepted": true,
              "result": { "metadata": { "answer": answer } },
            },
            {
              "tool": "finish",
              "accepted": false,
              "result": { "output": "REJECTED_FINISH" },
            },
          ],
        },
        consumer_id="test",
        now=@clock.Timestamp::from_ms(2L),
      ),
    )
    mooncode_worker_test_append(
      child_root,
      "child",
      mooncode_journal_event(),
      mooncode_tool_result_event(
        "child",
        child_root,
        "child-command-one",
        "apply_patch",
        mooncode_tool_ok_result("apply_patch", message="patched", output="", metadata={
          "changed_paths": ["patched.txt"],
        }),
        now=@clock.Timestamp::from_ms(2L),
      ),
    )
    mooncode_worker_test_append(
      child_root,
      "child",
      mooncode_journal_event(),
      mooncode_tool_result_event(
        "child",
        child_root,
        "child-command-one",
        "write",
        mooncode_tool_error_result("write", message="failed", metadata={
          "path": "FAILED_ARTIFACT.txt",
        }),
        now=@clock.Timestamp::from_ms(2L),
      ),
    )
    let artifacts : Array[Json] = [
      "../outside.txt", "/tmp/outside.txt", "nested/../../escape.txt",
    ]
    for i = 0; i < 80; i = i + 1 {
      artifacts.push("findings/\{i}.txt".to_json())
    }
    for i = 0; i < 40; i = i + 1 {
      mooncode_worker_test_append(
        child_root,
        "child",
        mooncode_journal_book_result(),
        {
          "kind": "mooncode-book-result",
          "session_id": "child",
          "book_root": child_root,
          "command_id": "child-command-one",
          "result_id": "result-\{i}",
          "result_path": "results/\{i}.json",
          "created_at": @clock.Timestamp::from_ms((i + 3).to_int64()),
          "book_result": { "artifacts": Json::array(artifacts) },
        },
      )
    }
    let metadata = mooncode_worker_results_test_wait(root, "all")
    let result = mooncode_json_object_field_or_empty(
      mooncode_json_array_items(metadata, "workers")[0],
      "result",
    )
    let actual = mooncode_json_string(result, "answer", default="")
    assert_true(answer.has_prefix(actual))
    assert_true(actual.length() <= 16000 && actual.length() > 0)
    assert_true(mooncode_json_bool(result, "answer_truncated", default=false))
    assert_eq(
      mooncode_json_array_items(result, "result_references").length(),
      32,
    )
    assert_eq(
      mooncode_json_array_items(result, "artifact_references").length(),
      64,
    )
    assert_true(
      mooncode_json_bool(result, "result_references_truncated", default=false),
    )
    assert_true(
      mooncode_json_bool(result, "artifact_references_truncated", default=false),
    )
    assert_false(result.stringify().contains("outside.txt"))
    assert_false(result.stringify().contains("escape.txt"))
    assert_false(result.stringify().contains("REJECTED_FINISH"))
    assert_false(result.stringify().contains("FAILED_ARTIFACT"))
    assert_true(
      mooncode_json_array_items(result, "artifact_references").any(item => {
        mooncode_json_string(item, "path", default="") == "patched.txt"
      }),
    )
    assert_eq(
      mooncode_json_string(result, "artifact_access", default=""),
      "reference-only",
    )
  })
}

///|
async test "worker successful native artifact without finish keeps empty answer and real references" {
  @fsx.with_temporary_directory("worker-results-no-answer-XXXXXX", async fn(
    root,
  ) {
    let parent_root = @pathx.join(root, "parent")
    let child_root = @pathx.join(root, "child")
    @fsx.make_directory(parent_root)
    mooncode_worker_results_test_queue(parent_root, child_root, "one", [
      {
        "tool": "write",
        "arguments": {
          "path": "portable/app-tool/result.txt",
          "content": "artifact-only",
        },
      },
    ])
    let daemon = mooncode_runtime_quantum_test_daemon(child_root)
    defer daemon.httpx.close()
    ignore(
      daemon.mooncode_runtime_service_execute("child-one", child_root, {
        "service_id": "worker-child-one",
        "live_wait_ms": 0,
      }),
    )
    assert_eq(
      @fsx.read_file(@pathx.join(child_root, "portable/app-tool/result.txt")),
      "artifact-only",
    )
    let metadata = mooncode_worker_results_test_wait(parent_root, "all")
    assert_true(mooncode_json_bool(metadata, "ready", default=false))
    let worker = mooncode_json_array_items(metadata, "workers")[0]
    assert_true(mooncode_json_bool(worker, "terminal", default=false))
    assert_true(mooncode_json_bool(worker, "successful", default=false))
    let result = mooncode_json_object_field_or_empty(worker, "result")
    assert_eq(mooncode_json_string(result, "answer", default="missing"), "")
    assert_true(
      mooncode_json_array_items(result, "artifact_references").any(item => {
        mooncode_json_string(item, "path", default="") ==
        "portable/app-tool/result.txt"
      }),
    )
    assert_true(
      mooncode_json_array_items(result, "result_references").length() > 0,
    )
  })
}
