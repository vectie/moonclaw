///|
async fn mooncode_moon_fmt_test_git(
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
async fn mooncode_moon_fmt_test_commit_baseline(book_root : String) -> Unit {
  mooncode_moon_fmt_test_git(book_root, Init)
  mooncode_moon_fmt_test_git(book_root, AddAll)
  mooncode_moon_fmt_test_git(book_root, Commit("baseline"))
}

///|
async test "mooncode contained scoped fmt permits verified terminal completion without planner restart" (
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
  let requested_test_path = @pathx.join(source_root, "requested_wbtest.mbt")
  let tracked_dirty_path = @pathx.join(source_root, "tracked_dirty.mbt")
  let clean_unrequested_path = @pathx.join(source_root, "clean_unrequested.mbt")
  let untracked_dirty_path = @pathx.join(source_root, "untracked_dirty.mbt")
  @fsx.write_to_file(requested_path, "///|\npub fn requested()->Int{1}\n")
  @fsx.write_to_file(
    requested_test_path, "///|\ntest \"requested value\" {\n  assert_eq(requested(), 2)\n}\n",
  )
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
  let source_change = mooncode_execute_tool_call(
    "session-fmt-scope",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-fmt-scope",
      "book_root": book_root,
      "tool": "edit",
      "command_id": "cmd-fmt-scope",
      "arguments": {
        "path": "tools/demo/src/requested.mbt",
        "old_string": "pub fn requested()->Int{1}",
        "new_string": "pub fn requested()->Int{2}",
      },
    },
    now=@clock.Timestamp::from_ms(77L),
  )
  assert_true(mooncode_json_bool(source_change, "accepted", default=false))
  mooncode_with_fixture_moonfort(book_root, async fn(config) {
    let focused_test = mooncode_execute_tool_call(
      "session-fmt-scope",
      book_root,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-fmt-scope",
        "book_root": book_root,
        "tool": "moon_cmd",
        "command_id": "cmd-fmt-scope",
        "arguments": {
          "command": "test",
          "target": "native",
          "path": "tools/demo/src",
        },
      },
      now=@clock.Timestamp::from_ms(78L),
    )
    assert_true(mooncode_json_bool(focused_test, "accepted", default=false))
    let all_target_check = mooncode_execute_tool_call(
      "session-fmt-scope",
      book_root,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-fmt-scope",
        "book_root": book_root,
        "tool": "moon_cmd",
        "command_id": "cmd-fmt-scope",
        "arguments": {
          "command": "check",
          "target": "all",
          "path": "tools/demo/src",
        },
      },
      now=@clock.Timestamp::from_ms(79L),
    )
    assert_true(mooncode_json_bool(all_target_check, "accepted", default=false))
    let execution = mooncode_execute_tool_call(
      "session-fmt-scope",
      book_root,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-fmt-scope",
        "book_root": book_root,
        "tool": "moon_cmd",
        "command_id": "cmd-fmt-scope",
        "arguments": {
          "command": "fmt",
          "path": "tools/demo/src/requested.mbt",
        },
      },
      now=@clock.Timestamp::from_ms(80L),
    )
    let result = mooncode_json_object_field_or_empty(execution, "result")
    assert_true(mooncode_json_bool(result, "ok", default=false))
    let message = mooncode_json_string(result, "message", default="")
    assert_true(
      message.contains(
        "moon fmt formatted the requested paths: tools/demo/src/requested.mbt",
      ),
    )
    assert_true(
      message.contains(
        "Out-of-scope formatter changes were restored and verified",
      ),
    )
    assert_true(message.contains("Continue with the task"))
    assert_true(
      message.contains(
        "do not widen formatter scope unless a restored path is independently task-owned",
      ),
    )
    assert_false(message.contains("Reissue moon fmt"))
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
        "pub fn requested() -> Int {\n  2\n}",
      ),
    )
    let commit = mooncode_fixture_execute_tool_call(
      config,
      "session-fmt-scope",
      book_root,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-fmt-scope",
        "book_root": book_root,
        "tool": "shell",
        "command_id": "cmd-fmt-scope",
        "arguments": {
          "cmd": "git add -- tools/demo/src/requested.mbt tools/demo/src/tracked_dirty.mbt tools/demo/src/untracked_dirty.mbt && git -c user.name='MoonClaw Test' -c user.email=moonclaw-test@local commit -m 'terminal evidence'",
          "timeout_ms": 10000,
        },
      },
      now=@clock.Timestamp::from_ms(81L),
    )
    assert_true(mooncode_json_bool(commit, "accepted", default=false))
    let commit_metadata = mooncode_json_object_field_or_empty(
      mooncode_json_object_field_or_empty(commit, "result"),
      "metadata",
    )
    assert_true(
      mooncode_json_bool(
        commit_metadata,
        "post_commit_capture_valid",
        default=false,
      ),
    )
    let commit_sha = mooncode_json_string(
      commit_metadata,
      "commit_sha",
      default="",
    )
    assert_true(commit_sha != "")
    let clean_status = mooncode_fixture_execute_tool_call(
      config,
      "session-fmt-scope",
      book_root,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-fmt-scope",
        "book_root": book_root,
        "tool": "shell",
        "command_id": "cmd-fmt-scope",
        "arguments": {
          "cmd": "git status --porcelain=v1 && git rev-parse HEAD",
          "timeout_ms": 10000,
        },
      },
      now=@clock.Timestamp::from_ms(82L),
    )
    assert_true(mooncode_json_bool(clean_status, "accepted", default=false))
    assert_eq(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(clean_status, "result"),
        "output",
        default="",
      )
      .trim()
      .to_owned(),
      commit_sha,
    )
    let milestones : Array[Json] = [
      {
        "id": "implementation",
        "title": "Implement and verify the requested repair",
        "evidence_kind": "path_changed",
        "path": "tools/demo/src",
        "context_paths": ["tools/demo/src/requested.mbt"],
      },
    ]
    let command : Json = {
      "command": "prompt",
      "text": "Implement the requested MoonBit repair and run focused tests.",
      "payload": {
        "horizon_id": "contained-formatter-terminal",
        "task_contract": {
          "horizon_id": "contained-formatter-terminal",
          "objective": "Implement and verify the requested repair",
          "milestones": Json::array(milestones),
        },
      },
    }
    let done_milestones : Array[Json] = [
      {
        "id": "implementation",
        "title": "Implement and verify the requested repair",
        "status": "done",
        "evidence_kind": "path_changed",
        "path": "tools/demo/src",
        "context_paths": ["tools/demo/src/requested.mbt"],
      },
    ]
    let results : Array[Json] = [
      source_change, focused_test, all_target_check, execution, commit, clean_status,
    ]
    let checkpoint = mooncode_runtime_horizon_checkpoint_execution(
      command,
      "session-fmt-scope",
      book_root,
      "cmd-fmt-scope",
      {
        "tool": "checkpoint",
        "arguments": {
          "horizon_id": "contained-formatter-terminal",
          "milestones": Json::array(done_milestones),
          "next_action": "Finish.",
        },
      },
      results,
      now=@clock.Timestamp::from_ms(83L),
    )
    assert_true(mooncode_json_bool(checkpoint, "accepted", default=false))
    results.push(checkpoint)
    let finish = mooncode_execute_tool_call(
      "session-fmt-scope",
      book_root,
      {
        "protocol": mooncode_protocol_version(),
        "session_id": "session-fmt-scope",
        "book_root": book_root,
        "tool": "finish",
        "command_id": "cmd-fmt-scope",
        "arguments": { "answer": "Implemented, verified, and committed." },
      },
      now=@clock.Timestamp::from_ms(84L),
    )
    assert_true(mooncode_json_bool(finish, "accepted", default=false))
    results.push(finish)
    let verdict = mooncode_runtime_turn_completion_verdict(
      command,
      results,
      require_horizon=true,
    )
    assert_true(verdict.accepted)
    assert_eq(
      verdict.reason,
      "coding completion has accepted mutation and subsequent successful typed test evidence",
    )
    let plan : Json = { "planner_mode": "model-tool-calls" }
    let finish_calls : Array[Json] = [
      { "tool": "finish", "arguments": { "answer": "done" } },
    ]
    assert_false(
      mooncode_runtime_turn_recoverable_horizon_finish(
        command, plan, finish_calls, results,
      ),
    )
    assert_eq(
      mooncode_runtime_turn_horizon_finish_rejection_message(
        command, finish_calls, results,
      ),
      "",
    )
    assert_true(mooncode_runtime_turn_stops_tool_batch(plan, finish))
  })
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
