///|
async test "mooncode shell refuses workspace authoring by redirection" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "mooncode-shell-redirection-XXXXXX"),
  )
  let execution = mooncode_execute_tool_call(
    "session-redirection",
    book_root,
    {
      "tool": "shell",
      "command_id": "cmd-redirection",
      "arguments": { "cmd": "printf changed > tracked.txt" },
    },
    now=@clock.Timestamp::from_ms(1L),
  )
  assert_false(mooncode_json_bool(execution, "accepted", default=true))
  assert_false(@fsx.exists(@pathx.join(book_root, "tracked.txt")))
  assert_true(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(execution, "result"),
      "message",
      default="",
    ).contains("use write, edit, or apply_patch"),
  )
}

///|
async test "mooncode shell refuses in-place authoring inside a loop" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "mooncode-shell-in-place-XXXXXX"),
  )
  let target = @pathx.join(book_root, "tracked.txt")
  @fsx.write_to_file(target, "old\n")
  let execution = mooncode_execute_tool_call(
    "session-in-place",
    book_root,
    {
      "tool": "shell",
      "command_id": "cmd-in-place",
      "arguments": {
        "cmd": "for file in tracked.txt; do sed -i.bak s/old/new/ \"$file\"; done",
      },
    },
    now=@clock.Timestamp::from_ms(1L),
  )
  assert_false(mooncode_json_bool(execution, "accepted", default=true))
  assert_eq(@fsx.read_file(target), "old\n")
  assert_false(@fsx.exists(target + ".bak"))
  assert_true(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(execution, "result"),
      "message",
      default="",
    ).contains("use write, edit, or apply_patch"),
  )
}

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
