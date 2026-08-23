///|
test "mooncode historical commit status paths retain renamed and quoted targets" {
  let paths = mooncode_runtime_commit_status_paths(
    "R  \"docs/old name.md\" -> \"docs/new name.md\"\n?? \"src/new file.mbt\"\n",
  )
  assert_eq(paths, ["docs/new name.md", "src/new file.mbt"])
}

///|
async test "mooncode native runtime turn creates commit proof" (t : @test.Test) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-commit-XXXXXX"),
  )
  assert_true(
    mooncode_json_bool(
      mooncode_runtime_turn_git(
        book_root,
        @trusted_host_process.Init,
        timeout_ms=10000,
        max_output_chars=4000,
      ),
      "ok",
      default=false,
    ),
  )
  @fsx.write_to_file(@pathx.join(book_root, "README.md"), "hello mooncode\n")
  @fsx.make_directory(
    @pathx.join(book_root, "code"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    @pathx.join(book_root, "code/runtime.txt"),
    "accepted mooncode runtime output\n",
  )
  @fsx.make_directory(
    @pathx.join(book_root, ".tmp/products/moonclaw"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    @pathx.join(book_root, ".tmp/products/moonclaw/scratch.txt"),
    "suite temp scratch\n",
  )
  let session_id = "session-runtime-commit"
  let command_id = "cmd-runtime-commit"
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "commit",
    "text": "Commit accepted MoonCode changes",
    "payload": { "commit_message": "MoonCode test commit" },
    "packet": {
      "command_id": command_id,
      "payload": { "commit_message": "MoonCode test commit" },
    },
    "model": "codex/gpt-5.6-sol",
  }
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": command_id,
      "created_at": @clock.Timestamp::from_ms(5L),
      "command": command,
    },
  )
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @trusted_host_process.DaemonChildManager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
    httpx: @httpx.Server::new("[::1]", 0, reuse_addr=true),
    port: 0,
    events: @broadcast.Broadcast::new(),
    serve: book_root,
    conversations: @conversation.Manager::new(
      home=book_root,
      uuid=@uuid.generator(@rand.chacha8()),
    ),
    home: book_root,
    pending_codex_auth: {},
    mooncode_sessions: {},
  }
  let result = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
    "consumer_id": "test-runtime",
  })
  assert_true(mooncode_json_bool(result, "accepted", default=false))
  let execution = mooncode_json_object_field_or_empty(result, "execution")
  assert_eq(mooncode_json_string(execution, "control", default=""), "commit")
  assert_eq(
    mooncode_json_string(execution, "planner_mode", default=""),
    "deterministic-fallback",
  )
  let commit_results = mooncode_json_array_items(execution, "commit_results")
  assert_eq(commit_results.length(), 1)
  assert_eq(
    mooncode_json_string(commit_results[0], "event", default=""),
    "commit_created",
  )
  let commit_sha = mooncode_json_string(
    commit_results[0],
    "commit_sha",
    default="",
  )
  assert_true(commit_sha.length() >= 7)
  let commit_tree = mooncode_json_string(
    commit_results[0],
    "commit_tree",
    default="",
  )
  assert_true(commit_tree.length() >= 7)
  assert_eq(
    mooncode_json_string(commit_results[0], "commit_message", default=""),
    "MoonCode test commit",
  )
  let changed_paths = mooncode_json_array_string_items(
    commit_results[0],
    "changed_paths",
  )
  assert_true(changed_paths.contains("README.md"))
  assert_true(changed_paths.contains("code/runtime.txt"))
  let events_log = @fsx.read_file(
    mooncode_session_journal_path(book_root, session_id),
  )
  assert_true(events_log.contains("\"runtime.commit_created\""))
  assert_true(events_log.contains(commit_sha))
  let git_head = mooncode_runtime_turn_git(
    book_root,
    @trusted_host_process.Head,
    timeout_ms=10000,
    max_output_chars=4000,
  )
  assert_eq(
    mooncode_json_string(git_head, "output", default="").trim().to_owned(),
    commit_sha,
  )
  let git_status = mooncode_runtime_turn_git(
    book_root,
    @trusted_host_process.StatusPorcelain,
    timeout_ms=10000,
    max_output_chars=4000,
  )
  assert_true(
    mooncode_json_string(git_status, "output", default="").contains(
      ".moonsuite/",
    ),
  )
  assert_true(
    mooncode_json_string(git_status, "output", default="").contains(".tmp/"),
  )
  assert_false(
    mooncode_json_string(git_status, "output", default="").contains("README.md"),
  )
  assert_false(
    mooncode_json_string(git_status, "output", default="").contains(
      "code/runtime.txt",
    ),
  )
  let committed_files = mooncode_runtime_turn_git(
    book_root,
    @trusted_host_process.ListHeadTree,
    timeout_ms=10000,
    max_output_chars=4000,
  )
  let committed_output = mooncode_json_string(
    committed_files,
    "output",
    default="",
  )
  assert_true(committed_output.contains("README.md"))
  assert_true(committed_output.contains("code/runtime.txt"))
  assert_false(committed_output.contains(".tmp/products/moonclaw/scratch.txt"))
  assert_false(committed_output.contains(".moonsuite/"))
  let after = mooncode_json_object_field_or_empty(result, "claim_state")
  assert_true(after.stringify().contains("\"delivered_command_count\":1"))
}

///|
test "commit event reports durable creation when exact sealing fails" {
  let command : Json = {
    "book_root": ".",
    "packet": { "command_id": "commit-unsealed" },
  }
  let result = mooncode_runtime_turn_commit_result(
    "session-unsealed",
    ".",
    command,
    accepted=false,
    created=true,
    message="commit",
    status_before="M tracked.txt\n",
    commit_sha="0123456789abcdef",
    commit_tree="fedcba9876543210",
    status_after="?? later.txt\n",
    detail="commit created but exact seal failed",
    output="",
    now=@clock.Timestamp::from_ms(9L),
  )
  assert_eq(mooncode_json_string(result, "event", default=""), "commit_created")
  assert_true(mooncode_json_bool(result, "commit_created", default=false))
  assert_false(mooncode_json_bool(result, "accepted", default=true))
  let event = mooncode_runtime_turn_commit_event(
    "session-unsealed",
    "commit-unsealed",
    command,
    result,
    now=@clock.Timestamp::from_ms(10L),
  )
  assert_eq(
    mooncode_json_string(event, "kind", default=""),
    "runtime.commit_created",
  )
  assert_eq(mooncode_json_string(event, "status", default=""), "failed")
}

///|
async test "trusted commit does not execute repository post-commit hooks" {
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-commit-unsealed-XXXXXX"),
  )
  assert_true(
    mooncode_json_bool(
      mooncode_runtime_turn_git(
        book_root,
        @trusted_host_process.Init,
        timeout_ms=10000,
        max_output_chars=4000,
      ),
      "ok",
      default=false,
    ),
  )
  @fsx.write_to_file(@pathx.join(book_root, "tracked.txt"), "commit me\n")
  let hook = @pathx.join(book_root, ".git/hooks/post-commit")
  @fsx.write_to_file(hook, "#!/bin/sh\nprintf 'later\\n' > later.txt\n")
  @fs.chmod(hook, 0o700)
  let command : Json = {
    "book_root": book_root,
    "packet": {
      "command_id": "commit-hook-unsealed",
      "payload": { "commit_message": "commit with dirty hook" },
    },
    "payload": { "commit_message": "commit with dirty hook" },
  }
  let results = mooncode_runtime_turn_commit_results(
    "session-hook-unsealed",
    book_root,
    command,
    now=@clock.Timestamp::from_ms(11L),
  )
  assert_eq(results.length(), 1)
  assert_true(mooncode_json_bool(results[0], "commit_created", default=false))
  assert_eq(
    mooncode_json_string(results[0], "event", default=""),
    "commit_created",
  )
  assert_true(mooncode_json_bool(results[0], "accepted", default=false))
  assert_false(@fsx.exists(@pathx.join(book_root, "later.txt")))
  let event = mooncode_runtime_turn_commit_event(
    "session-hook-unsealed",
    "commit-hook-unsealed",
    command,
    results[0],
    now=@clock.Timestamp::from_ms(12L),
  )
  assert_eq(
    mooncode_json_string(event, "kind", default=""),
    "runtime.commit_created",
  )
}
