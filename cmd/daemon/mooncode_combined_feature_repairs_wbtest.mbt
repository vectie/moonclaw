///|
async test "combined worker cancellation survives reload and later child work" {
  @fsx.with_temporary_directory("combined-worker-cancel-XXXXXX", async fn(
    root,
  ) {
    let parent_root = @pathx.join(root, "parent")
    let child_root = @pathx.join(root, "child")
    @fsx.make_directory(parent_root)
    mooncode_worker_results_test_queue(parent_root, child_root, "one", [
      {
        "tool": "write",
        "arguments": {
          "path": "cancelled-output.txt",
          "content": "must not execute",
        },
      },
      { "tool": "finish", "arguments": { "answer": "must not be returned" } },
    ])
    let waiting = mooncode_worker_results_test_wait(parent_root, "all")
    assert_false(mooncode_json_bool(waiting, "ready", default=true))
    let cancel : Json = {
      "protocol": mooncode_protocol_version(),
      "session_id": "child-one",
      "book_root": child_root,
      "command": "cancel",
      "packet": { "command_id": "cancel-linked-child" },
      "payload": { "target_command_id": "child-command-one" },
    }
    mooncode_control_test_queue(
      child_root,
      "child-one",
      cancel,
      now=@clock.Timestamp::from_ms(2L),
    )
    let daemon = mooncode_runtime_quantum_test_daemon(child_root)
    defer daemon.httpx.close()
    ignore(
      daemon.mooncode_submit_cancel_control("child-one", child_root, cancel),
    )
    let cancelled = mooncode_worker_results_test_wait(parent_root, "all")
    assert_true(mooncode_json_bool(cancelled, "ready", default=false))
    let worker = mooncode_json_array_items(cancelled, "workers")[0]
    assert_eq(mooncode_json_string(worker, "status", default=""), "cancelled")
    assert_true(mooncode_json_bool(worker, "terminal", default=false))
    assert_eq(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(worker, "terminal_evidence"),
        "status",
        default="",
      ),
      "runtime-cancelled",
    )
    assert_false(mooncode_json_bool(worker, "successful", default=true))
    let result = mooncode_json_object_field_or_empty(worker, "result")
    assert_eq(mooncode_json_string(result, "answer", default=""), "")
    assert_eq(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(result, "receipt_reference"),
        "command_id",
        default="",
      ),
      "child-command-one",
    )
    assert_eq(
      mooncode_json_array_items(result, "artifact_references").length(),
      0,
    )
    mooncode_control_test_queue(
      child_root,
      "child-one",
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "child-one",
        "book_root": child_root,
        "command": "prompt",
        "model": "fixture/mooncode",
        "packet": { "command_id": "later-unrelated" },
        "runtime_tool_calls": [
          {
            "tool": "write",
            "arguments": { "path": "later-output.txt", "content": "retained" },
          },
          { "tool": "finish", "arguments": { "answer": "unrelated answer" } },
        ],
      },
      now=@clock.Timestamp::from_ms(3L),
    )
    let reloaded = mooncode_runtime_quantum_test_daemon(child_root)
    defer reloaded.httpx.close()
    ignore(
      reloaded.mooncode_submit_cancel_control("child-one", child_root, cancel),
    )
    ignore(
      reloaded.mooncode_runtime_service_execute("child-one", child_root, {
        "live_wait_ms": 0,
      }),
    )
    assert_false(@fsx.exists(@pathx.join(child_root, "cancelled-output.txt")))
    assert_eq(
      @fsx.read_file(@pathx.join(child_root, "later-output.txt")),
      "retained",
    )
    let final_worker = mooncode_json_array_items(
        mooncode_worker_results_test_wait(parent_root, "all"),
        "workers",
      )[0]
    assert_eq(
      mooncode_json_string(final_worker, "status", default=""),
      "cancelled",
    )
    assert_true(mooncode_json_bool(final_worker, "terminal", default=false))
    assert_eq(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(final_worker, "terminal_evidence"),
        "status",
        default="",
      ),
      "runtime-cancelled",
    )
    assert_eq(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(
          mooncode_json_object_field_or_empty(final_worker, "result"),
          "receipt_reference",
        ),
        "command_id",
        default="",
      ),
      "child-command-one",
    )
    assert_false(
      mooncode_json_object_field_or_empty(final_worker, "result")
      .stringify()
      .contains("unrelated answer"),
    )
  })
}

///|
async test "combined review worker returns useful finish without a mutation" {
  @fsx.with_temporary_directory("combined-worker-review-XXXXXX", async fn(
    root,
  ) {
    let parent_root = @pathx.join(root, "parent")
    let child_root = @pathx.join(root, "child")
    @fsx.make_directory(parent_root)
    let command = mooncode_worker_command(
      "parent",
      {
        "id": "review",
        "book_root": child_root,
        "prompt": "Review this code; do not edit or fix any files",
        "task_intent": "read_only",
      },
      "fixture/mooncode",
      "child-review",
      "child-command-review",
    )
    assert_eq(mooncode_runtime_turn_task_intent(command), Some("read_only"))
    assert_false(
      mooncode_runtime_turn_model_needs_coding_tools(
        command,
        mooncode_runtime_turn_prompt_text(command).to_lower().to_string(),
      ),
    )
    assert_false(mooncode_runtime_turn_requires_verification(command))
    @fsx.make_directory(child_root)
    mooncode_worker_test_append(
      parent_root,
      "parent",
      mooncode_journal_event(),
      mooncode_worker_test_record(
        "parent", parent_root, "review", "child-review", child_root,
      ),
    )
    let command = mooncode_json_object_with_field(
      command,
      "runtime_tool_calls",
      Json::array([
        {
          "tool": "finish",
          "arguments": {
            "answer": "Reviewed existing code. The next actionable issue is missing result handback.",
          },
        },
      ]),
    )
    mooncode_control_test_queue(
      child_root,
      "child-review",
      command,
      now=@clock.Timestamp::from_ms(1L),
    )
    let daemon = mooncode_runtime_quantum_test_daemon(child_root)
    defer daemon.httpx.close()
    ignore(
      daemon.mooncode_runtime_service_execute("child-review", child_root, {
        "live_wait_ms": 0,
      }),
    )
    let final_result = mooncode_worker_results_test_wait(parent_root, "all")
    assert_true(mooncode_json_bool(final_result, "ready", default=false))
    let worker = mooncode_json_array_items(final_result, "workers")[0]
    assert_true(mooncode_json_bool(worker, "successful", default=false))
    let result = mooncode_json_object_field_or_empty(worker, "result")
    assert_true(
      mooncode_json_string(result, "answer", default="").contains(
        "next actionable issue",
      ),
    )
    assert_eq(
      mooncode_json_array_items(result, "artifact_references").length(),
      0,
    )
  })
}
