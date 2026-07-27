///|
fn mooncode_stream_test_v2_record(
  session_id : String,
  sequence : String,
  record_kind : String,
  record_id : String,
  payload : Json,
) -> Json raise {
  mooncode_journal_record_v2(
    session_id~,
    sequence=MoonCodeJournalSequence::parse(sequence),
    record_id~,
    record_kind~,
    command_id="command-stream",
    client_turn_id="",
    recorded_at="2026-07-26T00:00:00Z",
    payload~,
  )
}

///|
async test "stream summary repairs torn mixed-v1/v2 journal and ignores non-events" {
  @fsx.with_temporary_directory("mooncode-stream-summary-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session-stream-summary"
    let path = mooncode_session_journal_path(root, session_id)
    @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
    let legacy = @moonlib_conversation.journal_record(
      session_id~,
      sequence=1,
      record_id="command:legacy",
      record_kind=mooncode_journal_command(),
      command_id="command-stream",
      client_turn_id="",
      recorded_at="2026-07-26T00:00:00Z",
      payload={ "command_id": "command-stream" },
    )
    let current = mooncode_stream_test_v2_record(
      session_id,
      "2",
      mooncode_journal_event(),
      "event:current",
      {
        "id": "current",
        "kind": "tool_result",
        "lane": "tool",
        "command_id": "command-stream",
      },
    )
    @fsx.write_to_file(
      path,
      legacy.stringify() + "\n" + current.stringify() + "\n{\"kind\":",
    )
    let before_size = @fsx.read_file(path).length()
    let summary = mooncode_stream_summary(
      root,
      session_id,
      MoonCodeJournalSequence::zero(),
    )
    assert_eq(summary.event_count, 1)
    assert_eq(summary.eligible_event_count, 1)
    assert_eq(summary.latest_event_sequence.text(), "2")
    assert_true(summary.journal_size.to_int() < before_size)
    assert_true(@fsx.read_file(path).has_suffix("\n"))
    let huge = MoonCodeJournalSequence::parse(
      "922337203685477580812345678901234567890",
    )
    let past = mooncode_stream_summary(root, session_id, huge)
    assert_eq(past.event_count, 1)
    assert_eq(past.eligible_event_count, 0)
    let size_before_command = past.journal_size
    assert_true(
      mooncode_append_session_journal_once(
        root,
        session_id,
        mooncode_journal_command(),
        { "command_id": "command-later", "created_at": "2026-07-26T00:00:01Z" },
      ),
    )
    let after_command = mooncode_stream_summary(
      root,
      session_id,
      MoonCodeJournalSequence::parse("2"),
    )
    assert_true(after_command.journal_size > size_before_command)
    assert_eq(after_command.eligible_event_count, 0)
    assert_eq(after_command.latest_event_sequence.text(), "2")
  })
}

///|
async test "stream summary rejects a foreign-session committed record" {
  @fsx.with_temporary_directory("mooncode-stream-foreign-XXXXXX", async fn(
    root,
  ) {
    let expected = "session-stream-expected"
    let path = mooncode_session_journal_path(root, expected)
    @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
    let foreign = mooncode_stream_test_v2_record(
      "session-stream-foreign",
      "1",
      mooncode_journal_event(),
      "event:foreign",
      { "id": "foreign", "kind": "tool_result", "lane": "tool" },
    )
    @fsx.write_to_file(path, foreign.stringify() + "\n")
    let rejected = try {
      ignore(
        mooncode_stream_summary(root, expected, MoonCodeJournalSequence::zero()),
      )
      false
    } catch {
      InvalidJournal(_) => true
      _ => false
    }
    assert_true(rejected)
  })
}

///|
async test "stream spool JSONL and SSE bytes match compatibility payloads" {
  @fsx.with_temporary_directory("mooncode-stream-spool-XXXXXX", async fn(root) {
    let session_id = "session-stream-spool"
    assert_true(
      mooncode_append_session_journal_once(
        root,
        session_id,
        mooncode_journal_command(),
        { "command_id": "command-stream", "created_at": "2026-07-26T00:00:00Z" },
      ),
    )
    assert_true(
      mooncode_append_session_journal_once(
        root,
        session_id,
        mooncode_journal_event(),
        {
          "id": "event-stream",
          "kind": "tool_result",
          "lane": "tool",
          "command_id": "command-stream",
          "created_at": "2026-07-26T00:00:01Z",
        },
      ),
    )
    let since = MoonCodeJournalSequence::zero()
    let events = mooncode_journal_entries(
      mooncode_read_session_journal(root, session_id),
      mooncode_journal_event(),
    )
    let jsonl = mooncode_stream_create_spool("jsonl", root, session_id, since)
    let jsonl_meta = mooncode_stream_meta_record(
      session_id,
      root,
      event_count=jsonl.summary.event_count,
      since~,
      emitted_count=jsonl.summary.eligible_event_count,
      latest_sequence=jsonl.summary.latest_event_sequence,
      wait_ms=0,
      poll_ms=100,
      wait_elapsed_ms=0,
      wait_attempt_count=0,
    )
    let jsonl_done = mooncode_stream_done_record(
      session_id,
      root,
      latest_sequence=jsonl.summary.latest_event_sequence,
      since~,
      emitted_count=jsonl.summary.eligible_event_count,
      wait_ms=0,
      poll_ms=100,
      wait_elapsed_ms=0,
      wait_attempt_count=0,
    )
    let jsonl_actual = mooncode_stream_record_frame("jsonl", jsonl_meta) +
      @fsx.read_file(jsonl.path) +
      mooncode_stream_record_frame("jsonl", jsonl_done)
    let jsonl_expected = mooncode_stream_jsonl_payload(
      session_id,
      root,
      events,
      since~,
      wait_ms=0,
      poll_ms=100,
      wait_elapsed_ms=0,
      wait_attempt_count=0,
    )
    assert_eq(jsonl_actual, jsonl_expected)
    jsonl.cleanup()
    let sse = mooncode_stream_create_spool("sse", root, session_id, since)
    let sse_meta = mooncode_stream_meta_record(
      session_id,
      root,
      event_count=sse.summary.event_count,
      since~,
      emitted_count=sse.summary.eligible_event_count,
      latest_sequence=sse.summary.latest_event_sequence,
      wait_ms=0,
      poll_ms=100,
      wait_elapsed_ms=0,
      wait_attempt_count=0,
    )
    let sse_done = mooncode_stream_done_record(
      session_id,
      root,
      latest_sequence=sse.summary.latest_event_sequence,
      since~,
      emitted_count=sse.summary.eligible_event_count,
      wait_ms=0,
      poll_ms=100,
      wait_elapsed_ms=0,
      wait_attempt_count=0,
    )
    let sse_actual = mooncode_stream_record_frame("sse", sse_meta) +
      @fsx.read_file(sse.path) +
      mooncode_stream_record_frame("sse", sse_done)
    let sse_expected = mooncode_stream_sse_payload(
      session_id,
      root,
      events,
      since~,
      wait_ms=0,
      poll_ms=100,
      wait_elapsed_ms=0,
      wait_attempt_count=0,
    )
    assert_eq(sse_actual, sse_expected)
    sse.cleanup()
  })
}

///|
async test "stream scalar scan handles thousands of records without collection" {
  @fsx.with_temporary_directory("mooncode-stream-large-XXXXXX", async fn(root) {
    let session_id = "session-stream-large"
    let path = mooncode_session_journal_path(root, session_id)
    @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
    let writer = @fs.open(path, mode=WriteOnly, create=0o600, truncate=true)
    for index = 0; index < 5000; index = index + 1 {
      let sequence = (index + 1).to_string()
      let record = mooncode_stream_test_v2_record(
        session_id,
        sequence,
        mooncode_journal_event(),
        "event:" + sequence,
        { "id": "event-" + sequence, "kind": "progress", "lane": "runtime" },
      )
      writer.write(record.stringify() + "\n")
    }
    writer.close()
    let summary = mooncode_stream_summary(
      root,
      session_id,
      MoonCodeJournalSequence::parse("4999"),
    )
    assert_eq(summary.event_count, 5000)
    assert_eq(summary.eligible_event_count, 1)
    assert_eq(summary.latest_event_sequence.text(), "5000")
  })
}

///|
async fn mooncode_stream_http_test_daemon(book_root : String) -> Daemon {
  let httpx = @httpx.Server::new("[::1]", 0, reuse_addr=true)
  let uuid = @uuid.generator(@rand.chacha8())
  Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=book_root, cwd=book_root),
    uuid,
    process: @spawn.Manager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
    exec_path: @pathx.join(book_root, "unused"),
    httpx,
    port: httpx.port(),
    events: @broadcast.Broadcast::new(),
    serve: book_root,
    conversations: @conversation.Manager::new(home=book_root, uuid~),
    home: book_root,
    pending_codex_auth: {},
    mooncode_sessions: {},
  }
}

///|
async test "stream HTTP serves exact chunked JSONL and SSE and validates before 200" {
  @fsx.with_temporary_directory("mooncode-stream-http-XXXXXX", async fn(root) {
    let session_id = "session-stream-http"
    assert_true(
      mooncode_append_session_journal_once(
        root,
        session_id,
        mooncode_journal_event(),
        {
          "id": "event-http",
          "kind": "progress",
          "lane": "runtime",
          "created_at": "2026-07-26T00:00:00Z",
        },
      ),
    )
    let events = mooncode_journal_entries(
      mooncode_read_session_journal(root, session_id),
      mooncode_journal_event(),
    )
    let since = MoonCodeJournalSequence::zero()
    let daemon = mooncode_stream_http_test_daemon(root)
    defer daemon.httpx.close()
    @async.with_task_group(group => {
      group.spawn_bg(
        () => {
          daemon.httpx.serve((r, w) => daemon.mooncode_stream(session_id~, r, w))
        },
        no_wait=true,
      )
      @async.pause()
      let base = "http://localhost:\{daemon.httpx.port()}/v1/code/sessions/\{session_id}/stream?book_root=\{root}"
      let (jsonl_response, jsonl_body) = @http.get_stream(
        base + "&format=jsonl",
      )
      assert_eq(jsonl_response.code, 200)
      assert_eq(jsonl_response.headers["content-type"], "application/x-ndjson")
      assert_eq(jsonl_response.headers["transfer-encoding"], "chunked")
      let jsonl_text = jsonl_body.read_all().text()
      jsonl_body.close()
      assert_eq(
        jsonl_text,
        mooncode_stream_jsonl_payload(
          session_id,
          root,
          events,
          since~,
          wait_ms=0,
          poll_ms=100,
          wait_elapsed_ms=0,
          wait_attempt_count=0,
        ),
      )
      let (sse_response, sse_body) = @http.get_stream(base + "&format=sse")
      assert_eq(sse_response.code, 200)
      assert_eq(sse_response.headers["content-type"], "text/event-stream")
      assert_eq(sse_response.headers["transfer-encoding"], "chunked")
      let sse_text = sse_body.read_all().text()
      sse_body.close()
      assert_eq(
        sse_text,
        mooncode_stream_sse_payload(
          session_id,
          root,
          events,
          since~,
          wait_ms=0,
          poll_ms=100,
          wait_elapsed_ms=0,
          wait_attempt_count=0,
        ),
      )
      let foreign = mooncode_stream_test_v2_record(
        "foreign-session",
        "1",
        mooncode_journal_event(),
        "event:foreign",
        { "id": "foreign", "kind": "progress", "lane": "runtime" },
      )
      @fsx.write_to_file(
        mooncode_session_journal_path(root, session_id),
        foreign.stringify() + "\n",
      )
      let rejected_before_200 = try {
        let (response, body) = @http.get_stream(base + "&format=jsonl")
        body.close()
        response.code != 200
      } catch {
        _ => true
      }
      assert_true(rejected_before_200)
    })
  })
}
