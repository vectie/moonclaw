///|
async test "mooncode shell marks pipeline status as non-evidence" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "mooncode-pipeline-evidence-XXXXXX"),
  )
  let execution = mooncode_execute_tool_call(
    "session-pipeline",
    book_root,
    {
      "tool": "shell",
      "command_id": "cmd-pipeline",
      "arguments": { "cmd": "false | true" },
    },
    now=@clock.Timestamp::from_ms(1L),
  )
  if !mooncode_execution_sandbox_deployment_configured() {
    mooncode_assert_execution_sandbox_refusal(
      mooncode_json_object_field_or_empty(execution, "result"),
    )
    return
  }
  assert_true(mooncode_json_bool(execution, "accepted", default=false))
  let result = mooncode_json_object_field_or_empty(execution, "result")
  assert_true(
    mooncode_json_bool(
      mooncode_json_object_field_or_empty(result, "metadata"),
      "pipeline_exit_ambiguous",
      default=false,
    ),
  )
  assert_true(
    mooncode_json_string(result, "message", default="").contains(
      "observation-only",
    ),
  )
  let verification = mooncode_execute_tool_call(
    "session-pipeline",
    book_root,
    {
      "tool": "shell",
      "command_id": "cmd-pipeline-verification",
      "arguments": {
        "cmd": "moon test 2>&1 | tail -20",
        "verification_kind": "test",
      },
    },
    now=@clock.Timestamp::from_ms(2L),
  )
  assert_false(mooncode_json_bool(verification, "accepted", default=true))
}
