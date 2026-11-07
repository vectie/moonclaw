///|
async test "mooncode shell marks pipeline status as non-evidence" {
  @fsx.with_temporary_directory("mooncode-pipeline-evidence-XXXXXX", async fn(
    root,
  ) {
    mooncode_with_fixture_moonfort(root, async fn(config) {
      for cmd in ["printf observed | cat", "false | true"] {
        let execution = mooncode_fixture_execute_tool_call(
          config,
          "session-pipeline",
          root,
          {
            "tool": "shell",
            "command_id": cmd,
            "arguments": { "cmd": cmd, "verification_kind": "check" },
          },
          now=@clock.Timestamp::from_ms(1L),
        )
        assert_true(mooncode_json_bool(execution, "accepted", default=false))
        let result = mooncode_tool_result_value(execution)
        assert_true(
          mooncode_json_bool(
            mooncode_json_object_field_or_empty(result, "metadata"),
            "pipeline_exit_ambiguous",
            default=false,
          ),
        )
      }
    })
  })
}
