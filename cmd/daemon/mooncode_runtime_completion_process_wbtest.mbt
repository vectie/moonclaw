///|
/// Exercises the existing AllowDegraded fixture executor with an actual native
/// MoonBit test command. No daemon, sockets, model, credentials or Git is used.
async test "already-satisfied task uses ordinary finish after an actual required test through existing degraded executor" {
  @fsx.with_temporary_directory("mooncode-completion-process-XXXXXX", async fn(
    root,
  ) {
    let source = "///|\ntest \"already satisfied\" { assert_eq(2 + 2, 4) }\n"
    @fsx.write_to_file(root + "/moon.mod", "name = \"fixture/completion\"\n")
    @fsx.write_to_file(root + "/moon.pkg", "")
    @fsx.write_to_file(root + "/already_test.mbt", source)
    let process_command = "moon test --target native --frozen --strip -j1 --no-render"
    let contract = mooncode_json_object_with_field(
      completion_test_contract(),
      "required_checks",
      [
        {
          "id": "actual-tests",
          "tool": "shell",
          "command": process_command,
          "cwd": ".",
          "exit_code": 0,
        },
      ],
    )
    let command = mooncode_json_object_with_field(
      completion_test_command(contract~),
      "book_root",
      Json(root),
    )
    mooncode_with_fixture_moonfort(root, async fn(config) {
      let evidence : Array[Json] = []
      for
        index, call in (
          [
            { "tool": "read", "arguments": { "path": "already_test.mbt" } },
            {
              "tool": "shell",
              "arguments": {
                "cmd": process_command,
                "cwd": ".",
                "verification_kind": "test",
                "timeout_ms": 60000,
              },
            },
          ] : Array[Json]) {
        let body = mooncode_json_object_with_field(
          mooncode_json_object_with_field(
            mooncode_json_object_with_field(call, "protocol", "mooncode.v1"),
            "session_id",
            "completion-session",
          ),
          "command_id",
          "completion-command",
        )
        let execution = mooncode_fixture_execute_tool_call(
          config,
          "completion-session",
          root,
          body,
          now=@clock.Timestamp::from_ms(10L + index.to_int64()),
        )
        assert_true(
          mooncode_json_bool(execution, "accepted", default=false),
          msg=execution.stringify(),
        )
        evidence.push(execution)
      }
      let metadata = mooncode_json_object_field_or_empty(
        mooncode_tool_result_value(evidence[1]),
        "metadata",
      )
      assert_eq(mooncode_task_field(metadata, "exit_code"), Json(0))
      assert_true(
        mooncode_json_string(
          mooncode_tool_result_value(evidence[1]),
          "output",
          default="",
        ).contains("Total tests: 1, passed: 1, failed: 0"),
      )
      let sandbox = mooncode_json_object_field_or_empty(
        metadata, "sandbox_evidence",
      )
      assert_true(sandbox.stringify().contains("Degraded"))
      let finish_arguments : Json = {
        "answer": "The existing implementation satisfies the request; its tests passed.",
      }
      let finish = mooncode_execute_tool_call(
        "completion-session",
        root,
        {
          "protocol": "mooncode.v1",
          "session_id": "completion-session",
          "command_id": "completion-command",
          "tool": "finish",
          "arguments": finish_arguments,
        },
        now=@clock.Timestamp::from_ms(13L),
      )
      let completed = evidence + [finish]
      let verdict = mooncode_runtime_turn_completion_verdict(command, completed)
      assert_true(verdict.accepted, msg=verdict.reason)
      assert_eq(@fsx.read_file(root + "/already_test.mbt"), source)
      assert_eq(
        @fsx.read_file(root + "/moon.mod"),
        "name = \"fixture/completion\"\n",
      )
      assert_eq(
        mooncode_runtime_required_check_evidence(command, completed).length(),
        1,
      )
    })
  })
}
