///|
async fn mooncode_native_eval_harness_report(
  session_id : String,
  now~ : @clock.Timestamp,
) -> Json {
  let fixture_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-eval-XXXXXX"),
  )
  mooncode_prepare_eval_fixture(fixture_root)
  let write_case = mooncode_eval_tool_case(
    session_id,
    fixture_root,
    "write",
    "eval-write",
    { "path": "tools/eval.txt", "content": "hello mooncode\n" },
    now~,
    expected_path="tools/eval.txt",
    expected_detail="writes a MoonBook-owned file and emits diff evidence",
  )
  let read_case = mooncode_eval_tool_case(
    session_id,
    fixture_root,
    "read",
    "eval-read",
    { "path": "tools/eval.txt" },
    now~,
    expected_output="hello mooncode",
    expected_detail="reads the file previously written by the native tool harness",
  )
  let edit_case = mooncode_eval_tool_case(
    session_id,
    fixture_root,
    "edit",
    "eval-edit",
    {
      "path": "tools/eval.txt",
      "old_string": "mooncode",
      "new_string": "MoonCode",
    },
    now~,
    expected_path="tools/eval.txt",
    expected_diff="+hello MoonCode",
    expected_detail="edits a file and emits source-bounded diff evidence",
  )
  let apply_patch_case = mooncode_eval_tool_case(
    session_id,
    fixture_root,
    "apply_patch",
    "eval-apply-patch",
    {
      "path": "tools/eval.txt",
      "old_string": "hello MoonCode",
      "new_string": "hello MoonCode patched",
      "verification_command": "grep 'hello MoonCode patched' tools/eval.txt",
    },
    now~,
    expected_path="tools/eval.txt",
    expected_diff="+hello MoonCode patched",
    expected_kind="runtime.patch_applied",
    expected_detail="applies a reviewed text patch, verifies it, and emits runtime patch proof",
  )
  let revert_patch_case = mooncode_eval_tool_case(
    session_id,
    fixture_root,
    "revert_patch",
    "eval-revert-patch",
    {
      "path": "tools/eval.txt",
      "old_string": "hello MoonCode",
      "new_string": "hello MoonCode patched",
    },
    now~,
    expected_path="tools/eval.txt",
    expected_diff="+hello MoonCode",
    expected_kind="runtime.patch_reverted",
    expected_detail="reverts a reviewed text patch and emits runtime patch proof",
  )
  @fsx.write_to_file(
    @pathx.join(fixture_root, "tools/eval-diff.txt"),
    "one\ntwo\nthree\n",
  )
  let unified_diff = "--- a/tools/eval-diff.txt\n+++ b/tools/eval-diff.txt\n@@\n one\n-two\n+Two\n three\n"
  let apply_unified_case = mooncode_eval_tool_case(
    session_id,
    fixture_root,
    "apply_patch",
    "eval-apply-unified-patch",
    { "diff": unified_diff },
    now~,
    expected_path="tools/eval-diff.txt",
    expected_diff="+Two",
    expected_kind="runtime.patch_applied",
    expected_detail="applies a reviewed unified diff and emits runtime patch proof",
  )
  let revert_unified_case = mooncode_eval_tool_case(
    session_id,
    fixture_root,
    "revert_patch",
    "eval-revert-unified-patch",
    { "diff": unified_diff },
    now~,
    expected_path="tools/eval-diff.txt",
    expected_diff="+two",
    expected_kind="runtime.patch_reverted",
    expected_detail="reverts a reviewed unified diff and emits runtime patch proof",
  )
  @fsx.write_to_file(
    @pathx.join(fixture_root, "tools/eval-patchset-a.txt"),
    "a\nold\n",
  )
  @fsx.write_to_file(
    @pathx.join(fixture_root, "tools/eval-patchset-b.txt"),
    "b\nold\n",
  )
  let patchset_diff = "--- a/tools/eval-patchset-a.txt\n+++ b/tools/eval-patchset-a.txt\n@@\n a\n-old\n+new\n--- a/tools/eval-patchset-b.txt\n+++ b/tools/eval-patchset-b.txt\n@@\n b\n-old\n+new\n"
  let apply_patchset_case = mooncode_eval_tool_case(
    session_id,
    fixture_root,
    "apply_patch",
    "eval-apply-patchset",
    { "diff": patchset_diff },
    now~,
    expected_path="patchset",
    expected_diff="+new",
    expected_kind="runtime.patch_applied",
    expected_detail="applies a reviewed multi-file unified diff patchset and emits runtime patch proof",
  )
  let revert_patchset_case = mooncode_eval_tool_case(
    session_id,
    fixture_root,
    "revert_patch",
    "eval-revert-patchset",
    { "diff": patchset_diff },
    now~,
    expected_path="patchset",
    expected_diff="+old",
    expected_kind="runtime.patch_reverted",
    expected_detail="reverts a reviewed multi-file unified diff patchset and emits runtime patch proof",
  )
  let shell_case = mooncode_eval_tool_case(
    session_id,
    fixture_root,
    "shell",
    "eval-shell",
    { "cmd": "pwd", "timeout_ms": 5000 },
    now~,
    expected_output=fixture_root,
    expected_detail="runs shell commands inside the selected book root",
  )
  let moon_ide_case = mooncode_eval_tool_case(
    session_id,
    fixture_root,
    "moon_ide",
    "eval-moon-ide",
    {
      "action": "outline",
      "path": ".",
      "target": "native",
      "timeout_ms": 30000,
    },
    now~,
    expected_output="answer",
    expected_kind="moon_ide.finished",
    expected_detail="runs read-only MoonBit semantic navigation from the selected book root",
  )
  let moon_cmd_case = mooncode_eval_tool_case(
    session_id,
    fixture_root,
    "moon_cmd",
    "eval-moon-cmd",
    { "command": "check", "target": "native", "timeout_ms": 30000 },
    now~,
    expected_kind="moon_cmd.finished",
    expected_detail="runs structured MoonBit commands from the selected book root",
  )
  let moon_check_case = mooncode_eval_tool_case(
    session_id,
    fixture_root,
    "moon_check",
    "eval-moon-check",
    { "timeout_ms": 30000 },
    now~,
    expected_detail="runs MoonBit checks from the selected book root",
  )
  let finish_case = mooncode_eval_tool_case(
    session_id,
    fixture_root,
    "finish",
    "eval-finish",
    { "answer": "eval complete" },
    now~,
    expected_output="eval complete",
    expected_detail="records terminal finish output",
  )
  let tool_cases = [
    write_case, read_case, shell_case, moon_ide_case, moon_cmd_case, moon_check_case,
    finish_case,
  ]
  let file_edit_cases = [
    edit_case, apply_patch_case, revert_patch_case, apply_unified_case, revert_unified_case,
    apply_patchset_case, revert_patchset_case,
  ]
  let tool_harness = mooncode_eval_harness(
    "tool_harness", "Native tool harness", tool_cases,
  )
  let file_edit_harness = mooncode_eval_harness(
    "file_edit", "Native file-edit harness", file_edit_cases,
  )
  let harnesses = [tool_harness, file_edit_harness]
  let passed = mooncode_eval_passed_harness_count(harnesses)
  {
    "kind": "mooncode-native-eval-harness-report",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "source": "moonclaw-native-eval-harness",
    "session_id": session_id,
    "generated_at": now,
    "fixture_root": fixture_root,
    "status": if passed == harnesses.length() {
      "passed"
    } else {
      "failed"
    },
    "passed_harness_count": passed,
    "harness_count": harnesses.length(),
    "harnesses": Json::array(harnesses),
  }
}

///|
async fn mooncode_prepare_eval_fixture(root : String) -> Unit {
  @fsx.make_directory(root, recursive=true, exists_ok=true)
  @fsx.write_to_file(
    @pathx.join(root, "moon.mod.json"),
    "{\n  \"name\": \"mooncode/eval_fixture\",\n  \"version\": \"0.0.1\",\n  \"deps\": {},\n  \"preferred-target\": \"native\"\n}\n",
  )
  @fsx.write_to_file(@pathx.join(root, "moon.pkg"), "")
  @fsx.write_to_file(
    @pathx.join(root, "eval.mbt"),
    "///|\npub fn answer() -> Int {\n  42\n}\n",
  )
}

///|
async fn mooncode_eval_tool_case(
  session_id : String,
  fixture_root : String,
  tool : String,
  command_id : String,
  arguments : Json,
  now~ : @clock.Timestamp,
  expected_output? : String = "",
  expected_path? : String = "",
  expected_diff? : String = "",
  expected_kind? : String = "",
  expected_detail~ : String,
) -> Json {
  let execution = mooncode_execute_tool_call(
    session_id,
    fixture_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": fixture_root,
      "tool": tool,
      "command_id": command_id,
      "arguments": arguments,
    },
    now~,
  )
  let accepted = mooncode_json_bool(execution, "accepted", default=false)
  let result = mooncode_json_object_field_or_empty(execution, "result")
  let event = mooncode_json_object_field_or_empty(execution, "event")
  let output = mooncode_json_string(result, "output", default="")
  let path = mooncode_json_string(event, "path", default="")
  let diff = mooncode_json_string(event, "diff", default="")
  let kind = mooncode_json_string(event, "kind", default="")
  let output_ok = expected_output == "" || output.contains(expected_output)
  let path_ok = expected_path == "" || path == expected_path
  let diff_ok = expected_diff == "" || diff.contains(expected_diff)
  let kind_ok = expected_kind == "" || kind == expected_kind
  let passed = accepted && output_ok && path_ok && diff_ok && kind_ok
  {
    "id": tool,
    "tool": tool,
    "status": if passed {
      "passed"
    } else {
      "failed"
    },
    "accepted": accepted,
    "detail": expected_detail,
    "message": mooncode_json_string(result, "message", default=""),
    "output_ok": output_ok,
    "path_ok": path_ok,
    "diff_ok": diff_ok,
    "kind_ok": kind_ok,
    "event": event,
  }
}

///|
fn mooncode_eval_harness(
  id : String,
  title : String,
  cases : Array[Json],
) -> Json {
  let passed = mooncode_eval_passed_case_count(cases)
  {
    "id": id,
    "title": title,
    "status": if passed == cases.length() {
      "passed"
    } else {
      "failed"
    },
    "passed_case_count": passed,
    "case_count": cases.length(),
    "cases": Json::array(cases),
    "evidence": "\{passed}/\{cases.length()} case(s) passed.",
  }
}

///|
fn mooncode_eval_passed_case_count(cases : Array[Json]) -> Int {
  let mut passed = 0
  for case in cases {
    if mooncode_json_string(case, "status", default="") == "passed" {
      passed += 1
    }
  }
  passed
}

///|
fn mooncode_eval_passed_harness_count(harnesses : Array[Json]) -> Int {
  let mut passed = 0
  for harness in harnesses {
    if mooncode_json_string(harness, "status", default="") == "passed" {
      passed += 1
    }
  }
  passed
}

///|
fn mooncode_eval_harnesses_or_empty(native_eval : Json?) -> Array[Json] {
  match native_eval {
    Some(report) => mooncode_json_array_items(report, "harnesses")
    None => []
  }
}

///|
fn mooncode_eval_harness_status(native_eval : Json?) -> String {
  match native_eval {
    Some(report) => mooncode_json_string(report, "status", default="missing")
    None => "missing"
  }
}

///|
async test "mooncode native eval harness proves tools and file edits" (
  t : @test.Test,
) {
  ignore(t)
  let report = mooncode_native_eval_harness_report(
    "session-eval",
    now=@clock.Timestamp::from_ms(99L),
  )
  assert_eq(mooncode_json_string(report, "status", default=""), "passed")
  let harnesses = mooncode_json_array_items(report, "harnesses")
  assert_eq(harnesses.length(), 2)
  assert_eq(
    mooncode_json_string(harnesses[0], "id", default=""),
    "tool_harness",
  )
  assert_eq(mooncode_json_string(harnesses[1], "id", default=""), "file_edit")
  assert_true(report.stringify().contains("moon_ide"))
  assert_true(report.stringify().contains("moon_cmd"))
  assert_true(report.stringify().contains("moon_check"))
  assert_true(report.stringify().contains("+hello MoonCode"))
}
