///|
test "mooncode retains a payload contract that declares only task scope" {
  let command : Json = {
    "payload": { "task_contract": { "scope": ["cmd/daemon"] } },
  }
  let contract = mooncode_runtime_horizon_task_contract(command)
  assert_eq(mooncode_json_array_string_items(contract, "scope"), ["cmd/daemon"])
}

///|
async fn mooncode_task_scope_test_git(
  book_root : String,
  operation : @trusted_host_process.GitOperation,
) -> Unit {
  let result = mooncode_moon_fmt_git(book_root, operation)
  if !mooncode_json_bool(result, "ok", default=false) {
    fail(
      "trusted git operation failed: \{mooncode_json_string(result, "message", default="")}",
    )
  }
}

///|
async fn mooncode_task_scope_test_commit_baseline(book_root : String) -> Unit {
  mooncode_task_scope_test_git(book_root, @trusted_host_process.Init)
  mooncode_task_scope_test_git(book_root, @trusted_host_process.AddAll)
  mooncode_task_scope_test_git(
    book_root,
    @trusted_host_process.Commit("baseline"),
  )
}

///|
async test "mooncode rejects direct mutations outside task scope" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-task-scope-direct-XXXXXX"),
  )
  @fsx.make_directory(
    @pathx.join(book_root, "cmd/daemon"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.make_directory(
    @pathx.join(book_root, "third_party"),
    recursive=true,
    exists_ok=true,
  )
  let outside = @pathx.join(book_root, "third_party/runtime.mbt")
  @fsx.write_to_file(outside, "before\n")
  let execution = mooncode_execute_tool_call(
    "session-task-scope",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-task-scope",
      "book_root": book_root,
      "tool": "write",
      "command_id": "cmd-task-scope",
      "task_contract": { "scope": ["cmd/daemon"] },
      "arguments": { "path": "third_party/runtime.mbt", "content": "after\n" },
    },
    now=@clock.Timestamp::from_ms(1L),
  )
  assert_false(mooncode_json_bool(execution, "accepted", default=true))
  assert_eq(@fsx.read_file(outside), "before\n")
  assert_true(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(execution, "result"),
      "message",
      default="",
    ).contains("task scope rejects mutation"),
  )
}

///|
async test "mooncode rejects an entire multi-file patch when one target is outside scope" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-task-scope-patch-XXXXXX"),
  )
  @fsx.make_directory(
    @pathx.join(book_root, "cmd/daemon"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.make_directory(
    @pathx.join(book_root, "third_party"),
    recursive=true,
    exists_ok=true,
  )
  let allowed = @pathx.join(book_root, "cmd/daemon/runtime.mbt")
  let outside = @pathx.join(book_root, "third_party/runtime.mbt")
  @fsx.write_to_file(allowed, "before\n")
  @fsx.write_to_file(outside, "before\n")
  let diff =
    #|--- a/cmd/daemon/runtime.mbt
    #|+++ b/cmd/daemon/runtime.mbt
    #|@@ -1 +1 @@
    #|-before
    #|+after
    #|--- a/third_party/runtime.mbt
    #|+++ b/third_party/runtime.mbt
    #|@@ -1 +1 @@
    #|-before
    #|+after
    #|
  let execution = mooncode_execute_tool_call(
    "session-task-scope",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-task-scope",
      "book_root": book_root,
      "tool": "apply_patch",
      "command_id": "cmd-task-scope",
      "task_contract": { "scope": ["cmd/daemon"] },
      "arguments": { "diff": diff },
    },
    now=@clock.Timestamp::from_ms(2L),
  )
  assert_false(mooncode_json_bool(execution, "accepted", default=true))
  assert_eq(@fsx.read_file(allowed), "before\n")
  assert_eq(@fsx.read_file(outside), "before\n")
}

///|
async test "mooncode restores indirect shell-tool changes outside task scope" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-task-scope-indirect-XXXXXX"),
  )
  let allowed_root = @pathx.join(book_root, "allowed")
  let outside_root = @pathx.join(book_root, "outside")
  @fsx.make_directory(allowed_root, recursive=true, exists_ok=true)
  @fsx.make_directory(outside_root, recursive=true, exists_ok=true)
  @fsx.write_to_file(
    @pathx.join(book_root, "moon.mod"),
    "name = \"example/task_scope\"\n",
  )
  @fsx.write_to_file(@pathx.join(book_root, ".gitignore"), "/_build/\n")
  @fsx.write_to_file(@pathx.join(allowed_root, "moon.pkg"), "")
  @fsx.write_to_file(@pathx.join(outside_root, "moon.pkg"), "")
  let allowed = @pathx.join(allowed_root, "allowed.mbt")
  let outside = @pathx.join(outside_root, "outside.mbt")
  let allowed_before = "///|\npub fn allowed()->Int{1}\n"
  let outside_before = "///|\npub fn outside()->Int{2}\n"
  @fsx.write_to_file(allowed, allowed_before)
  @fsx.write_to_file(outside, outside_before)
  mooncode_task_scope_test_commit_baseline(book_root)
  let execution = mooncode_with_fixture_moonfort(book_root, async fn(_) {
    mooncode_execute_tool_call(
      "session-task-scope",
      book_root,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-task-scope",
        "book_root": book_root,
        "tool": "moon_cmd",
        "command_id": "cmd-task-scope",
        "task_contract": { "scope": ["allowed"] },
        "arguments": { "command": "fmt" },
      },
      now=@clock.Timestamp::from_ms(3L),
    )
  })
  assert_false(mooncode_json_bool(execution, "accepted", default=true))
  assert_true(@fsx.read_file(allowed) != allowed_before)
  let metadata = mooncode_json_object_field_or_empty(
    mooncode_json_object_field_or_empty(execution, "result"),
    "metadata",
  )
  let scope = mooncode_json_object_field_or_empty(metadata, "task_scope")
  if @fsx.read_file(outside) != outside_before {
    fail("outside scope was retained: \{scope.stringify()}")
  }
  assert_true(
    mooncode_json_array_string_items(scope, "restored_paths").contains(
      "outside/outside.mbt",
    ),
  )
}

///|
test "mooncode task scope fails closed for invalid declarations" {
  let error = mooncode_task_scope_preflight_error(
    { "task_contract": { "scope": ["../outside"] } },
    "write",
    { "path": "cmd/daemon/runtime.mbt" },
  )
  assert_true(error is Some(_))
}

///|
test "mooncode scope uses the explicit patch path when diff parsing has no files" {
  assert_eq(
    mooncode_task_scope_direct_mutation_paths("apply_patch", {
      "path": "third_party/runtime.mbt",
      "diff": "*** Begin Patch\n*** Update File: third_party/runtime.mbt",
    }),
    ["third_party/runtime.mbt"],
  )
}

///|
test "mooncode narrowly scoped shell rejects Git workspace mutations" {
  let error = mooncode_task_scope_preflight_error(
    { "task_contract": { "scope": ["cmd/daemon"] } },
    "shell",
    { "cmd": "git add cmd/daemon && git commit -m scoped" },
  )
  assert_true(error is Some(_))
  assert_eq(
    mooncode_task_scope_preflight_error(
      { "task_contract": { "scope": ["cmd/daemon"] } },
      "shell",
      { "cmd": "moon test cmd/daemon --target native" },
    ),
    None,
  )
}
