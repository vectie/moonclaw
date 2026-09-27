///|
async test "mooncode submit turn durably queues and starts runtime" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-submit-turn-XXXXXX"),
  )
  let session_id = "session-submit-turn"
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: mooncode_test_model_loader(book_root),
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
  @async.with_task_group(group => {
    let command : Json = {
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command": "prompt",
      "model": "fixture/mooncode",
      "text": "Reply once",
      "packet": { "command_id": "cmd-submit-turn" },
      "runtime_tool_calls": [
        { "tool": "finish", "arguments": { "answer": "done" } },
      ],
    }
    let response = daemon.mooncode_submit_turn_response(
      group~,
      session_id,
      command,
    )
    assert_true(mooncode_json_bool(response, "accepted", default=false))
    assert_eq(
      mooncode_json_string(response, "command_id", default=""),
      "cmd-submit-turn",
    )
    assert_true(
      mooncode_json_bool(
        mooncode_json_object_field_or_empty(response, "queue"),
        "queued",
        default=false,
      ),
    )
    assert_eq(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(response, "service"),
        "status",
        default="",
      ),
      "started",
    )
    assert_eq(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(response, "session"),
        "session_id",
        default="",
      ),
      session_id,
    )
    let retry = daemon.mooncode_submit_turn_response(
      group~,
      session_id,
      command,
    )
    assert_true(
      mooncode_json_bool(
        mooncode_json_object_field_or_empty(retry, "queue"),
        "duplicate",
        default=false,
      ),
    )
    assert_false(
      mooncode_json_bool(
        mooncode_json_object_field_or_empty(retry, "service"),
        "started",
        default=false,
      ),
    )
    group.return_immediately(())
  })
  let journal = @fsx.read_file(
    mooncode_session_journal_path(book_root, session_id),
  )
  assert_true(journal.contains("cmd-submit-turn"))
  assert_true(journal.contains("command.queued_for_runtime_turn"))
  assert_true(journal.contains("runtime.service_started"))
  assert_eq(
    mooncode_journal_record_count(
      mooncode_read_session_journal(book_root, session_id),
      mooncode_journal_command(),
    ),
    1,
  )
}
