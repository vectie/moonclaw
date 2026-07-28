///|
async fn mooncode_moon_fmt_test_git(
  book_root : String,
  args : Array[String],
) -> Unit {
  let result = mooncode_moon_fmt_git(book_root, args)
  if !mooncode_json_bool(result, "ok", default=false) {
    fail(
      "git \{args.join(" ")} failed: \{mooncode_json_string(result, "message", default="")}",
    )
  }
}

///|
async fn mooncode_moon_fmt_test_commit_baseline(book_root : String) -> Unit {
  mooncode_moon_fmt_test_git(book_root, ["init", "-q"])
  mooncode_moon_fmt_test_git(book_root, ["add", "."])
  mooncode_moon_fmt_test_git(book_root, [
    "-c", "user.name=MoonClaw Test", "-c", "user.email=moonclaw-test@local", "commit",
    "-qm", "baseline",
  ])
}

///|
async test "mooncode scoped fmt restores unrelated nested-module changes without erasing dirty files" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-fmt-scope-XXXXXX"),
  )
  let nested_module = @pathx.join(book_root, "tools/demo")
  let source_root = @pathx.join(nested_module, "src")
  @fsx.make_directory(source_root, recursive=true, exists_ok=true)
  @fsx.write_to_file(
    @pathx.join(nested_module, "moon.mod"),
    "name = \"example/fmt_scope\"\n",
  )
  @fsx.write_to_file(@pathx.join(nested_module, ".gitignore"), "/_build/\n")
  @fsx.write_to_file(@pathx.join(source_root, "moon.pkg"), "")
  let requested_path = @pathx.join(source_root, "requested.mbt")
  let tracked_dirty_path = @pathx.join(source_root, "tracked_dirty.mbt")
  let clean_unrequested_path = @pathx.join(source_root, "clean_unrequested.mbt")
  let untracked_dirty_path = @pathx.join(source_root, "untracked_dirty.mbt")
  @fsx.write_to_file(requested_path, "///|\npub fn requested()->Int{1}\n")
  @fsx.write_to_file(
    tracked_dirty_path, "///|\npub fn tracked_dirty() -> Int {\n  20\n}\n",
  )
  let clean_unrequested_before = "///|\npub fn clean_unrequested()->Int{4}\n"
  @fsx.write_to_file(clean_unrequested_path, clean_unrequested_before)
  mooncode_moon_fmt_test_commit_baseline(book_root)
  let tracked_dirty_before = "///|\npub fn tracked_dirty()->Int{2}\n"
  let untracked_dirty_before = "///|\npub fn untracked_dirty()->Int{3}\n"
  @fsx.write_to_file(tracked_dirty_path, tracked_dirty_before)
  @fsx.write_to_file(untracked_dirty_path, untracked_dirty_before)
  let execution = mooncode_execute_tool_call(
    "session-fmt-scope",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-fmt-scope",
      "book_root": book_root,
      "tool": "moon_cmd",
      "command_id": "cmd-fmt-scope",
      "arguments": { "command": "fmt", "path": "tools/demo/src/requested.mbt" },
    },
    now=@clock.Timestamp::from_ms(80L),
  )
  let result = mooncode_json_object_field_or_empty(execution, "result")
  assert_false(mooncode_json_bool(result, "ok", default=true))
  assert_true(
    mooncode_json_string(result, "message", default="").contains(
      "moon fmt changed paths outside its explicit scope",
    ),
  )
  let metadata = mooncode_json_object_field_or_empty(result, "metadata")
  assert_eq(mooncode_json_int(metadata, "status", default=-1), 0)
  assert_eq(
    mooncode_json_string(metadata, "command", default=""),
    "moon fmt src/requested.mbt",
  )
  let scope = mooncode_json_object_field_or_empty(metadata, "formatter_scope")
  let out_of_scope = mooncode_json_array_string_items(
    scope, "out_of_scope_paths",
  )
  let restored = mooncode_json_array_string_items(scope, "restored_paths")
  let expected_out_of_scope = [
    "tools/demo/src/clean_unrequested.mbt", "tools/demo/src/moon.pkg", "tools/demo/src/tracked_dirty.mbt",
    "tools/demo/src/untracked_dirty.mbt",
  ]
  assert_eq(out_of_scope.length(), expected_out_of_scope.length())
  assert_eq(restored.length(), expected_out_of_scope.length())
  for path in expected_out_of_scope {
    assert_true(out_of_scope.contains(path))
    assert_true(restored.contains(path))
  }
  assert_true(
    mooncode_json_array_string_items(scope, "retained_paths").is_empty(),
  )
  assert_true(mooncode_json_bool(scope, "restore_verified", default=false))
  assert_eq(@fsx.read_file(tracked_dirty_path), tracked_dirty_before)
  assert_eq(@fsx.read_file(untracked_dirty_path), untracked_dirty_before)
  assert_eq(@fsx.read_file(clean_unrequested_path), clean_unrequested_before)
  assert_true(
    @fsx.read_file(requested_path).contains(
      "pub fn requested() -> Int {\n  1\n}",
    ),
  )
}

///|
async test "mooncode scoped fmt fails before execution when state cannot be snapshotted" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-fmt-no-git-XXXXXX"),
  )
  @fsx.write_to_file(
    @pathx.join(book_root, "moon.mod"),
    "name = \"example/no_git\"\n",
  )
  @fsx.write_to_file(@pathx.join(book_root, "moon.pkg"), "")
  let source = @pathx.join(book_root, "main.mbt")
  let before = "///|\npub fn answer()->Int{42}\n"
  @fsx.write_to_file(source, before)
  let execution = mooncode_execute_tool_call(
    "session-fmt-no-git",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-fmt-no-git",
      "book_root": book_root,
      "tool": "moon_cmd",
      "command_id": "cmd-fmt-no-git",
      "arguments": { "command": "fmt", "path": "main.mbt" },
    },
    now=@clock.Timestamp::from_ms(81L),
  )
  let result = mooncode_json_object_field_or_empty(execution, "result")
  assert_false(mooncode_json_bool(result, "ok", default=true))
  assert_true(
    mooncode_json_string(result, "message", default="").contains(
      "requires a verified Git worktree snapshot before execution",
    ),
  )
  assert_eq(@fsx.read_file(source), before)
}
