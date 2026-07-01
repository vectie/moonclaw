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
        ["init", "-q"],
        timeout_ms=10000,
        max_output_chars=4000,
      ),
      "ok",
      default=false,
    ),
  )
  assert_true(
    mooncode_json_bool(
      mooncode_runtime_turn_git(
        book_root,
        ["config", "user.name", "MoonClaw Test"],
        timeout_ms=10000,
        max_output_chars=4000,
      ),
      "ok",
      default=false,
    ),
  )
  assert_true(
    mooncode_json_bool(
      mooncode_runtime_turn_git(
        book_root,
        ["config", "user.email", "moonclaw-test@local"],
        timeout_ms=10000,
        max_output_chars=4000,
      ),
      "ok",
      default=false,
    ),
  )
  @fsx.write_to_file(@pathx.join(book_root, "README.md"), "hello mooncode\n")
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
    "model": "unavailable-model",
  }
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "created_at": @clock.Timestamp::from_ms(5L),
    "command": command,
  })
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @spawn.Manager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
    exec_path: @pathx.join(book_root, "moonclaw"),
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
  assert_eq(
    mooncode_json_string(commit_results[0], "commit_message", default=""),
    "MoonCode test commit",
  )
  let events_log = @fsx.read_file(mooncode_events_path(book_root, session_id))
  assert_true(events_log.contains("\"runtime.commit_created\""))
  assert_true(events_log.contains(commit_sha))
  let git_head = mooncode_runtime_turn_git(
    book_root,
    ["rev-parse", "HEAD"],
    timeout_ms=10000,
    max_output_chars=4000,
  )
  assert_eq(
    mooncode_json_string(git_head, "output", default="").trim().to_owned(),
    commit_sha,
  )
  let git_status = mooncode_runtime_turn_git(
    book_root,
    ["status", "--porcelain"],
    timeout_ms=10000,
    max_output_chars=4000,
  )
  assert_true(
    mooncode_json_string(git_status, "output", default="").contains(
      ".moonsuite/",
    ),
  )
  assert_false(
    mooncode_json_string(git_status, "output", default="").contains("README.md"),
  )
  let after = mooncode_json_object_field_or_empty(result, "claim_state")
  assert_true(after.stringify().contains("\"delivered_command_count\":1"))
}
