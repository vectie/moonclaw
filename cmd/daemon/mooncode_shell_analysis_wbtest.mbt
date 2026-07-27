///|
test "mooncode shell detects semantic git commit commands" {
  assert_true(mooncode_shell_has_git_commit("git commit -m 'validated'"))
  assert_true(mooncode_shell_has_git_commit("git -C . commit -m validated"))
  assert_true(
    mooncode_shell_has_git_commit("git\t-C\t. \\\n commit -m validated"),
  )
  assert_true(
    mooncode_shell_has_git_commit("env GIT_AUTHOR_NAME=test git commit -m ok"),
  )
  assert_false(mooncode_shell_has_git_commit("git commit-tree HEAD^{tree}"))
  assert_false(mooncode_shell_has_git_commit("echo 'git commit -m nope'"))
  assert_false(mooncode_shell_has_git_commit("git status --short"))
}

///|
test "mooncode shell identifies ambiguous pipelines by syntax" {
  assert_true(mooncode_shell_pipeline_exit_ambiguous("check|tail -20"))
  assert_true(mooncode_shell_pipeline_exit_ambiguous("check\t|\ttail -20"))
  assert_true(mooncode_shell_pipeline_exit_ambiguous("check\n|\ntail -20"))
  assert_true(mooncode_shell_pipeline_exit_ambiguous("check |& tail -20"))
  assert_false(mooncode_shell_pipeline_exit_ambiguous("check || recover"))
  assert_false(
    mooncode_shell_pipeline_exit_ambiguous("rg 'left|right' source.mbt"),
  )
  assert_false(
    mooncode_shell_pipeline_exit_ambiguous(
      "set -o pipefail; check 2>&1 | tail -20",
    ),
  )
  assert_false(
    mooncode_shell_pipeline_exit_ambiguous(
      "set -euo pipefail; check 2>&1|tail -20",
    ),
  )
  assert_true(
    mooncode_shell_pipeline_exit_ambiguous(
      "echo pipefail; check 2>&1 | tail -20",
    ),
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
  assert_false(mooncode_json_bool(execution, "accepted", default=true))
  let result = mooncode_json_object_field_or_empty(execution, "result")
  assert_true(
    mooncode_json_bool(
      mooncode_json_object_field_or_empty(result, "metadata"),
      "pipeline_exit_ambiguous",
      default=false,
    ),
  )
  assert_true(
    mooncode_json_string(result, "message", default="").contains("pipefail"),
  )
}
