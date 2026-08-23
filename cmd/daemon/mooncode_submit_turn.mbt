///|
async fn Daemon::mooncode_submit_turn(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
  let body : Json = reader.read() catch {
    _ =>
      raise json_error(400, "Bad Request", {
        "error": {
          "code": -1,
          "message": "Invalid JSON body for MoonCode turn",
        },
      })
  }
  let session_id = session_id.to_owned()
  let response = self.mooncode_submit_turn_response(group~, session_id, body)
  w.header().set("Content-Type", "application/json")
  w.write_header(202, reason="Accepted")
  w.write(response.stringify(indent=2))
}

///|
async fn Daemon::mooncode_submit_turn_response(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  session_id : String,
  body : Json,
) -> Json {
  let report = mooncode_validate_command_body(session_id, body)
  if !mooncode_json_bool(report, "ok", default=false) {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": mooncode_json_string(
          report,
          "message",
          default="Invalid MoonCode turn",
        ),
        "metadata": report,
      },
    })
  }
  let book_root = mooncode_book_root(body)
  let action = mooncode_json_string(body, "command", default="prompt")
  if action == "approve_tool" || action == "reject_tool" {
    ignore(
      mooncode_runtime_tool_approval_control_request(
        session_id, book_root, body,
      ),
    )
  }
  let queue = self.mooncode_queue_command_response(
    session_id~,
    body,
    queue_source="moonclaw-submit-turn",
  )
  let service = if action == "cancel" {
    self.mooncode_submit_cancel_control(session_id, book_root, body)
  } else if action == "approve_tool" || action == "reject_tool" {
    self.mooncode_submit_tool_approval_control(
      group~,
      session_id,
      book_root,
      body,
    )
  } else {
    self.mooncode_start_runtime_service(group~, session_id, book_root, body)
  }
  let session = self
    .mooncode_session_record(session_id, book_root)
    .unwrap_or(Json::object({}))
  {
    "kind": "mooncode-turn-accepted",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "accepted": true,
    "session_id": session_id,
    "command_id": mooncode_command_id(body),
    "book_root": book_root,
    "queue": queue,
    "service": service,
    "session": session,
  }
}

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
  @async.with_task_group(group => {
    let response = daemon.mooncode_submit_turn_response(group~, session_id, {
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command": "prompt",
      "model": "codex/gpt-5.6-sol",
      "text": "Reply once",
      "packet": { "command_id": "cmd-submit-turn" },
      "runtime_tool_calls": [
        { "tool": "finish", "arguments": { "answer": "done" } },
      ],
    })
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
    group.return_immediately(())
  })
  let journal = @fsx.read_file(
    mooncode_session_journal_path(book_root, session_id),
  )
  assert_true(journal.contains("cmd-submit-turn"))
  assert_true(journal.contains("command.queued_for_runtime_turn"))
  assert_true(journal.contains("runtime.service_started"))
}
