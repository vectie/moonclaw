///|
async test "same-millisecond operations retain distinct recallable results and exact graph links" {
  @fsx.with_temporary_directory("mooncode-recall-XXXXXX", async fn(root) {
    let session = "recall"
    let now = @clock.Timestamp::from_ms(1L)
    let turn = mooncode_conversation_turn_draft(
      turn_id="c",
      client_turn_id="client",
      command_id="c",
      created_at="",
    )
    let refs : Array[String] = []
    for index in 0..<2 {
      let arguments : Json = { "path": "file-\{index}.txt" }
      let call : Json = {
        "tool": "read",
        "arguments": arguments,
        "tool_call_id": "reused-provider-call",
      }
      mooncode_conversation_apply_work_event(
        turn,
        mooncode_runtime_turn_tool_call_event(
          session,
          "c",
          call,
          step=index + 1,
          index=0,
          mode="model",
          model="",
          now~,
        ),
      )
      let result = mooncode_tool_ok_result(
        "read",
        message="read",
        output="original-\{index}\nsecond line",
        metadata=arguments,
      )
      let execution = mooncode_runtime_operation_finished(
        mooncode_runtime_operation_id("c", index, 0),
        call,
        mooncode_tool_execution(
          session,
          root,
          "c",
          "read",
          arguments,
          result,
          now~,
        ),
        step=index,
        index=0,
      )
      let event = mooncode_json_object_field_or_empty(execution, "event")
      refs.push(mooncode_json_string(event, "id", default=""))
      assert_true(
        mooncode_append_session_journal_once(
          root,
          session,
          mooncode_journal_event(),
          event,
        ),
      )
      mooncode_conversation_apply_work_event(turn, event)
    }
    assert_eq(turn.work_steps.length(), 2)
    assert_true(refs[0] != refs[1])
    let daemon = mooncode_control_test_daemon(root)
    defer daemon.httpx.close()
    let calls = refs.map(reference => {
      (
        { "tool": "read_result", "arguments": { "evidence_ref": reference } } :
        Json)
    })
    let recalled = daemon.mooncode_runtime_turn_execute_parallel_reads(
      {
        "command": "prompt",
        "session_id": session,
        "book_root": root,
        "packet": { "command_id": "recall-batch" },
      },
      session,
      root,
      calls,
    )
    assert_eq(recalled.length(), 2)
    for index, execution in recalled {
      assert_true(mooncode_json_bool(execution, "accepted", default=false))
      assert_true(
        mooncode_json_string(
          mooncode_tool_result_value(execution),
          "output",
          default="",
        ).contains("original-\{index}"),
      )
    }
    // Changing the live file must not change the historical observation.
    @fsx.write_to_file(root + "/file-0.txt", "new version")
    let exact = mooncode_tool_read_result(root, session, {
      "evidence_ref": refs[0],
      "details": true,
    })
    assert_true(mooncode_json_bool(exact, "ok", default=false))
    assert_true(
      mooncode_json_string(exact, "output", default="").contains("original-0"),
    )
    let range = mooncode_tool_read_result(root, session, {
      "evidence_ref": refs[0],
      "end_ref": refs[1],
    })
    assert_eq(
      mooncode_json_int(
        mooncode_json_object_field_or_empty(range, "metadata"),
        "result_count",
        default=0,
      ),
      2,
    )
    let page = mooncode_tool_read_result(root, session, {
      "evidence_ref": refs[0],
      "start_line": 1,
      "end_line": 1,
    })
    assert_eq(mooncode_json_string(page, "output", default=""), "original-0")
    let details = mooncode_tool_read_result(root, session, {
      "evidence_ref": refs[0],
      "details": true,
      "start_line": 1,
      "end_line": 1,
    })
    assert_eq(mooncode_json_string(details, "output", default=""), "{")
    let invalid : Array[Json] = [
      { "evidence_ref": "" },
      { "evidence_ref": refs[0], "end_ref": "missing" },
      { "evidence_ref": refs[0], "start_line": 999 },
    ]
    for arguments in invalid {
      assert_false(
        mooncode_json_bool(
          mooncode_tool_read_result(root, session, arguments),
          "ok",
          default=true,
        ),
      )
    }
    assert_false(
      mooncode_json_bool(
        mooncode_tool_read_result(root, "other-session", {
          "evidence_ref": refs[0],
        }),
        "ok",
        default=true,
      ),
    )
    let graph = mooncode_conversation_work_graph("c", turn.work_steps)
    assert_eq(mooncode_json_array_items(graph, "nodes").length(), 6)
    assert_eq(mooncode_json_array_items(graph, "edges").length(), 4)
    let recall : Json = {
      "item_id": "recall-call",
      "tool": "read_result",
      "planner_step": 3,
      "recalls": refs[0],
      "evidence": { "sandbox_evidence": { "artifacts": ["generated.txt"] } },
    }
    turn.work_steps.push(recall)
    let graph = mooncode_conversation_work_graph("c", turn.work_steps)
    assert_true(
      mooncode_json_array_items(graph, "nodes").any(node => {
        mooncode_json_string(node, "path", default="") == "generated.txt"
      }),
    )
    assert_true(
      mooncode_json_array_items(graph, "edges").any(edge => {
        mooncode_json_string(edge, "kind", default="") == "recalls" &&
        mooncode_json_string(edge, "from", default="") ==
        mooncode_json_string(turn.work_steps[0], "item_id", default="")
      }),
    )
    assert_eq(mooncode_read_session_journal(root, session).length(), 2)
    let patch = mooncode_tool_execution(
      session,
      root,
      "patch",
      "apply_patch",
      {},
      mooncode_tool_error_result(
        "apply_patch",
        message="failed patch",
        output="retained diff",
        metadata={ "truncated": true },
      ),
      now~,
    )
    let event = mooncode_json_object_field_or_empty(patch, "event")
    mooncode_append_session_journal(
      root,
      session,
      mooncode_journal_event(),
      event,
    )
    let recalled = mooncode_tool_read_result(root, session, {
      "evidence_ref": mooncode_json_string(event, "id", default=""),
    })
    assert_true(
      mooncode_json_string(recalled, "output", default="").contains(
        "retained diff",
      ),
    )
    assert_true(mooncode_json_bool(recalled, "ok", default=false))
    let source = mooncode_json_object_field_or_empty(
      mooncode_json_object_field_or_empty(recalled, "metadata"),
      "source",
    )
    assert_false(mooncode_json_bool(source, "ok", default=true))
    assert_true(mooncode_json_bool(source, "truncated", default=false))
    assert_eq(
      mooncode_json_string(source, "message", default=""),
      "failed patch",
    )
  })
}
