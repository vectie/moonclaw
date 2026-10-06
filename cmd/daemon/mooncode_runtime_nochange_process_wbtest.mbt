///|
/// Exercises the existing AllowDegraded fixture executor with an actual native
/// MoonBit test command. No daemon, sockets, model, credentials or Git is used.
async test "nochange actual required test through existing degraded executor" {
  @fsx.with_temporary_directory("mooncode-nochange-process-XXXXXX", async fn(
    root,
  ) {
    let source = "///|\ntest \"already satisfied\" { assert_eq(2 + 2, 4) }\n"
    @fsx.write_to_file(root + "/moon.mod", "name = \"fixture/nochange\"\n")
    @fsx.write_to_file(root + "/moon.pkg", "")
    @fsx.write_to_file(root + "/already_test.mbt", source)
    let process_command = "moon test --target native --frozen --strip -j1 --no-render"
    let policy = mooncode_json_object_with_field(
      nochange_test_policy(),
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
      nochange_test_command(policy~),
      "book_root",
      root.to_json(),
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
            "nochange-session",
          ),
          "command_id",
          "nochange-command",
        )
        let execution = mooncode_fixture_execute_tool_call(
          config,
          "nochange-session",
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
        mooncode_runtime_turn_result_payload(evidence[1]),
        "metadata",
      )
      assert_eq(mooncode_nochange_field(metadata, "exit_code"), (0).to_json())
      assert_true(
        mooncode_json_string(
          mooncode_runtime_turn_result_payload(evidence[1]),
          "output",
          default="",
        ).contains("Total tests: 1, passed: 1, failed: 0"),
      )
      let sandbox = mooncode_json_object_field_or_empty(
        metadata, "sandbox_evidence",
      )
      assert_true(sandbox.stringify().contains("Degraded"))
      let proposal = mooncode_json_object_with_field(
        nochange_test_proposal(),
        "evidence_refs",
        Json::array(
          evidence.map(result => {
            mooncode_nochange_result_event_id(command, result).to_json()
          }),
        ),
      )
      let arguments = mooncode_json_object_with_field(
        nochange_test_checkpoint_arguments(),
        "no_change",
        proposal,
      )
      let checkpoint = mooncode_runtime_horizon_checkpoint_execution(
        command,
        "nochange-session",
        root,
        "nochange-command",
        { "tool": "checkpoint", "arguments": arguments },
        evidence,
        now=@clock.Timestamp::from_ms(12L),
      )
      assert_true(
        mooncode_json_bool(checkpoint, "accepted", default=false),
        msg=checkpoint.stringify(),
      )
      let finish_arguments : Json = {
        "answer": "No net source change; required checks passed.",
        "completion_outcome": "no_change",
        "no_change": proposal,
      }
      let finish = mooncode_execute_tool_call(
        "nochange-session",
        root,
        {
          "protocol": "mooncode.v1",
          "session_id": "nochange-session",
          "command_id": "nochange-command",
          "tool": "finish",
          "arguments": finish_arguments,
        },
        now=@clock.Timestamp::from_ms(13L),
      )
      let completed = evidence + [checkpoint, finish]
      let verdict = mooncode_runtime_turn_completion_verdict(
        command,
        completed,
        require_horizon=true,
      )
      assert_true(verdict.accepted, msg=verdict.reason)
      assert_eq(@fsx.read_file(root + "/already_test.mbt"), source)
      assert_eq(
        @fsx.read_file(root + "/moon.mod"),
        "name = \"fixture/nochange\"\n",
      )
      let projection = mooncode_nochange_verdict_projection(
        verdict, command, completed,
      )
      assert_eq(
        mooncode_json_string(projection, "original_task_acceptance", default=""),
        "unevaluated",
      )
      assert_eq(
        mooncode_json_array_items(projection, "required_check_evidence").length(),
        1,
      )
    })
  })
}
