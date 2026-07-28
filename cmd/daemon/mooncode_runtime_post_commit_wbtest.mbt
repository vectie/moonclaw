///|
async fn mooncode_post_commit_test_fixture() -> (String, Json) {
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-post-commit-XXXXXX"),
  )
  let setup_args : Array[Array[StringView]] = [
    ["init", "-q"],
    ["config", "user.name", "MoonClaw Test"],
    ["config", "user.email", "moonclaw-test@local"],
  ]
  for args in setup_args {
    assert_true(
      mooncode_json_bool(
        mooncode_runtime_turn_git(
          book_root,
          args,
          timeout_ms=10000,
          max_output_chars=4000,
        ),
        "ok",
        default=false,
      ),
    )
  }
  @fsx.write_to_file(@pathx.join(book_root, "tracked.txt"), "sealed\n")
  let commit = mooncode_execute_tool_call(
    "session-post-commit",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-post-commit",
      "book_root": book_root,
      "tool": "shell",
      "command_id": "command-post-commit",
      "arguments": {
        "cmd": "git add tracked.txt && git commit -m 'sealed change'",
        "timeout_ms": 10000,
      },
    },
    now=@clock.Timestamp::from_ms(1L),
  )
  assert_true(mooncode_json_bool(commit, "accepted", default=false))
  (book_root, commit)
}

///|
fn mooncode_post_commit_test_tool(
  tool : String,
  arguments? : Json = {},
) -> Json {
  { "tool": tool, "arguments": arguments }
}

///|
async test "post-commit seal allows exact read-only verification checkpoint and finish" {
  let (book_root, commit) = mooncode_post_commit_test_fixture()
  let results = [commit]
  let boundary = mooncode_runtime_post_commit_boundary(results)
  let commit_sha = mooncode_json_string(boundary, "commit_sha", default="")
  let commit_tree = mooncode_json_string(boundary, "commit_tree", default="")
  assert_true(commit_sha.length() >= 7)
  assert_true(commit_tree.length() >= 7)
  assert_true(mooncode_json_bool(boundary, "capture_valid", default=false))
  @fsx.make_directory(
    @pathx.join(book_root, ".moonsuite/runtime"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.make_directory(
    @pathx.join(book_root, ".tmp/runtime"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    @pathx.join(book_root, ".moonsuite/runtime/state.json"),
    "{}\n",
  )
  @fsx.write_to_file(@pathx.join(book_root, ".tmp/runtime/log"), "runtime\n")
  for
    tool_call in [
      mooncode_post_commit_test_tool("read", arguments={ "path": "tracked.txt" }),
      mooncode_post_commit_test_tool("shell", arguments={
        "cmd": "git status --short && git diff --check",
      }),
      mooncode_post_commit_test_tool("moon_cmd", arguments={ "command": "test" }),
      mooncode_post_commit_test_tool("checkpoint"),
      mooncode_post_commit_test_tool("finish", arguments={
        "answer": "verified",
      }),
    ] {
    let verdict = mooncode_runtime_post_commit_guard(
      book_root, tool_call, results,
    )
    assert_true(mooncode_json_bool(verdict, "active", default=false))
    assert_true(mooncode_json_bool(verdict, "allowed", default=false))
    assert_eq(
      mooncode_json_string(verdict, "commit_sha", default=""),
      commit_sha,
    )
    assert_eq(
      mooncode_json_string(verdict, "commit_tree", default=""),
      commit_tree,
    )
  }
}

///|
async test "post-commit seal survives planner continuation replay" {
  let (book_root, commit) = mooncode_post_commit_test_fixture()
  let continuation = mooncode_runtime_planner_continuation_event(
    "session-post-commit",
    "command-post-commit",
    {
      "planner_mode": mooncode_planner_mode_model_tool_calls(),
      "tool_calls": [{ "tool": "shell", "arguments": { "cmd": "git status" } }],
    },
    [],
    [commit],
    [],
    next_step_index=1,
    now=@clock.Timestamp::from_ms(2L),
  )
  let replayed = @json.parse(continuation.stringify())
  let retained = mooncode_json_array_items(replayed, "tool_results")
  assert_eq(retained.length(), 1)
  let verdict = mooncode_runtime_post_commit_guard(
    book_root,
    mooncode_post_commit_test_tool("apply_patch", arguments={
      "path": "tracked.txt",
      "diff": "@@",
    }),
    retained,
  )
  assert_true(mooncode_json_bool(verdict, "active", default=false))
  assert_false(mooncode_json_bool(verdict, "allowed", default=true))
}

///|
async test "direct tool endpoint replay rejects mutation after persisted commit event" {
  let (book_root, commit) = mooncode_post_commit_test_fixture()
  let session_id = "session-post-commit"
  let command_id = "command-post-commit"
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_event(),
    mooncode_json_object_field_or_empty(commit, "event"),
  )
  let prior_results = mooncode_tool_prior_command_results(
    book_root, session_id, command_id,
  )
  assert_eq(prior_results.length(), 1)
  assert_true(
    mooncode_json_bool(
      mooncode_runtime_post_commit_boundary(prior_results),
      "capture_valid",
      default=false,
    ),
  )
  let execution = mooncode_execute_guarded_tool_call(
    session_id,
    book_root,
    {
      "tool": "write",
      "command_id": command_id,
      "arguments": { "path": "later.txt", "content": "later\n" },
    },
    prior_results,
    now=@clock.Timestamp::from_ms(3L),
  )
  assert_false(mooncode_json_bool(execution, "accepted", default=true))
  assert_false(@fsx.exists(@pathx.join(book_root, "later.txt")))
}

///|
async test "post-commit seal rejects authored and shell mutations" {
  let (book_root, commit) = mooncode_post_commit_test_fixture()
  let results = [commit]
  for
    tool_call in [
      mooncode_post_commit_test_tool("write", arguments={
        "path": "new.txt",
        "content": "new\n",
      }),
      mooncode_post_commit_test_tool("edit", arguments={
        "path": "tracked.txt",
        "old_string": "sealed",
        "new_string": "changed",
      }),
      mooncode_post_commit_test_tool("apply_patch", arguments={
        "path": "tracked.txt",
        "diff": "@@",
      }),
      mooncode_post_commit_test_tool("revert_patch", arguments={
        "path": "tracked.txt",
        "diff": "@@",
      }),
      mooncode_post_commit_test_tool("shell", arguments={
        "cmd": "git reset --hard HEAD^",
      }),
      mooncode_post_commit_test_tool("moon_cmd", arguments={ "command": "fmt" }),
      mooncode_post_commit_test_tool("moon_cmd", arguments={
        "command": "test",
        "arg": "--update",
      }),
    ] {
    let verdict = mooncode_runtime_post_commit_guard(
      book_root, tool_call, results,
    )
    assert_true(mooncode_json_bool(verdict, "active", default=false))
    assert_false(mooncode_json_bool(verdict, "allowed", default=true))
    assert_true(
      mooncode_json_string(verdict, "reason", default="").contains(
        "post-commit mutation rejected",
      ),
    )
  }
  assert_eq(@fsx.read_file(@pathx.join(book_root, "tracked.txt")), "sealed\n")
}

///|
async test "post-commit verification rejects a changed exact HEAD" {
  let (book_root, commit) = mooncode_post_commit_test_fixture()
  let results = [commit]
  assert_true(
    mooncode_json_bool(
      mooncode_runtime_turn_git(
        book_root,
        ["commit", "--allow-empty", "-m", "unexpected later commit"],
        timeout_ms=10000,
        max_output_chars=4000,
      ),
      "ok",
      default=false,
    ),
  )
  let verdict = mooncode_runtime_post_commit_guard(
    book_root,
    mooncode_post_commit_test_tool("shell", arguments={
      "cmd": "git status --short",
    }),
    results,
  )
  assert_true(mooncode_json_bool(verdict, "active", default=false))
  assert_false(mooncode_json_bool(verdict, "allowed", default=true))
  assert_true(
    mooncode_json_string(verdict, "reason", default="").contains(
      "HEAD/tree or product worktree no longer matches sealed commit",
    ),
  )
}

///|
async test "post-commit verification rejects tracked and untracked product dirt" {
  for untracked in [false, true] {
    let (book_root, commit) = mooncode_post_commit_test_fixture()
    let results = [commit]
    if untracked {
      @fsx.write_to_file(@pathx.join(book_root, "later.txt"), "later\n")
    } else {
      @fsx.write_to_file(@pathx.join(book_root, "tracked.txt"), "regressed\n")
    }
    let verdict = mooncode_runtime_post_commit_guard(
      book_root,
      mooncode_post_commit_test_tool("finish", arguments={
        "answer": "claim exact committed state",
      }),
      results,
    )
    assert_true(mooncode_json_bool(verdict, "active", default=false))
    assert_false(mooncode_json_bool(verdict, "allowed", default=true))
    assert_true(
      mooncode_json_string(verdict, "reason", default="").contains(
        "product worktree no longer matches sealed commit",
      ),
    )
  }
}

///|
async test "shell cannot mutate after commit before the seal is captured" {
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-post-commit-compound-XXXXXX"),
  )
  let setup_args : Array[Array[StringView]] = [
    ["init", "-q"],
    ["config", "user.name", "MoonClaw Test"],
    ["config", "user.email", "moonclaw-test@local"],
  ]
  for args in setup_args {
    ignore(
      mooncode_runtime_turn_git(
        book_root,
        args,
        timeout_ms=10000,
        max_output_chars=4000,
      ),
    )
  }
  @fsx.write_to_file(@pathx.join(book_root, "tracked.txt"), "before\n")
  let execution = mooncode_execute_tool_call(
    "session-compound",
    book_root,
    {
      "tool": "shell",
      "command_id": "command-compound",
      "arguments": {
        "cmd": "git add tracked.txt && git commit -m sealed && touch later.txt",
      },
    },
    now=@clock.Timestamp::from_ms(2L),
  )
  assert_false(mooncode_json_bool(execution, "accepted", default=true))
  assert_false(@fsx.exists(@pathx.join(book_root, "later.txt")))
  let head = mooncode_runtime_turn_git(
    book_root,
    ["rev-parse", "--verify", "HEAD"],
    timeout_ms=10000,
    max_output_chars=4000,
  )
  assert_false(mooncode_json_bool(head, "ok", default=true))
}

///|
async test "wrapped shell cannot hide mutation after commit" {
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-post-commit-wrapped-XXXXXX"),
  )
  let setup_args : Array[Array[StringView]] = [
    ["init", "-q"],
    ["config", "user.name", "MoonClaw Test"],
    ["config", "user.email", "moonclaw-test@local"],
  ]
  for args in setup_args {
    ignore(
      mooncode_runtime_turn_git(
        book_root,
        args,
        timeout_ms=10000,
        max_output_chars=4000,
      ),
    )
  }
  @fsx.write_to_file(@pathx.join(book_root, "tracked.txt"), "before\n")
  let execution = mooncode_execute_tool_call(
    "session-wrapped",
    book_root,
    {
      "tool": "shell",
      "command_id": "command-wrapped",
      "arguments": {
        "cmd": "sh -c 'git add tracked.txt && git commit -m sealed && touch later.txt'",
      },
    },
    now=@clock.Timestamp::from_ms(3L),
  )
  assert_false(mooncode_json_bool(execution, "accepted", default=true))
  assert_false(@fsx.exists(@pathx.join(book_root, "later.txt")))
  let head = mooncode_runtime_turn_git(
    book_root,
    ["rev-parse", "--verify", "HEAD"],
    timeout_ms=10000,
    max_output_chars=4000,
  )
  assert_false(mooncode_json_bool(head, "ok", default=true))
}

///|
async test "post-commit seal is command scoped and a later command starts a new cycle" {
  let (book_root, _) = mooncode_post_commit_test_fixture()
  let verdict = mooncode_runtime_post_commit_guard(
    book_root,
    mooncode_post_commit_test_tool("write", arguments={
      "path": "later.txt",
      "content": "later\n",
    }),
    [],
  )
  assert_false(mooncode_json_bool(verdict, "active", default=true))
  assert_true(mooncode_json_bool(verdict, "allowed", default=false))
}
