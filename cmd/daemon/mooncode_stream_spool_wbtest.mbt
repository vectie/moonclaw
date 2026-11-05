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
    let summary = mooncode_stream_scan(
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
    let past = mooncode_stream_scan(root, session_id, huge)
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
    let after_command = mooncode_stream_scan(
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
        mooncode_stream_scan(root, expected, MoonCodeJournalSequence::zero()),
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
async test "stream spool projects physical journal positions in JSONL and SSE" {
  @fsx.with_temporary_directory("mooncode-stream-spool-XXXXXX", async fn(root) {
    let session_id = "session-stream-spool"
    for index in 0..<5 {
      let event = index == 1 || index == 4
      mooncode_append_session_journal(
        root,
        session_id,
        if event {
          mooncode_journal_event()
        } else {
          mooncode_journal_command()
        },
        {
          "id": "entry-" + index.to_string(),
          "command_id": "command-" + index.to_string(),
          "kind": "progress",
          "lane": "runtime",
          "created_at": "2026-07-26T00:00:00Z",
          "journal_sequence": "payload-cannot-set-the-cursor",
        },
      )
    }
    for
      (cursor, expected) in (
        [
          ("0", ["2", "5"]),
          ("2", ["5"]),
          ("999999999999999999999999999999", []),
        ] : Array[(String, Array[String])]) {
      for format in ["jsonl", "sse"] {
        let spool = mooncode_stream_create_spool(
          format,
          root,
          session_id,
          mooncode_journal_cursor_parse(cursor),
        )
        defer spool.cleanup()
        let body = @fsx.read_file(spool.path)
        let records = body
          .split("\n")
          .filter(line => {
            line != "" && (format == "jsonl" || line.has_prefix("data: "))
          })
          .collect()
          .map(line => {
            @json.parse(
              if format == "sse" {
                line[6:].to_owned()
              } else {
                line.to_owned()
              },
            )
          })
        assert_eq(
          records.map(record => {
            mooncode_json_string(record, "sequence", default="")
          }),
          expected,
        )
        assert_eq(spool.summary.event_count, 2)
        assert_eq(spool.summary.eligible_event_count, expected.length())
        assert_eq(spool.summary.latest_event_sequence.text(), "5")
        for record in records {
          assert_eq(
            mooncode_json_string(record, "contract_id", default=""),
            "mooncode-stream.v2",
          )
          assert_eq(mooncode_json_string(record, "since", default=""), cursor)
          assert_eq(
            mooncode_json_string(record, "sequence", default=""),
            mooncode_json_string(
              mooncode_json_object_field_or_empty(record, "event"),
              "journal_sequence",
              default="",
            ),
          )
        }
      }
    }
  })
}

///|
async test "stream scalar scan handles thousands of records without collection" {
  @fsx.with_temporary_directory("mooncode-stream-large-XXXXXX", async fn(root) {
    let session_id = "session-stream-large"
    let path = mooncode_session_journal_path(root, session_id)
    @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
    let writer = @fs.open(
      path,
      mode=WriteOnly,
      create_mode=CreateOrTruncate,
      permission=0o600,
    )
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
    let summary = mooncode_stream_scan(
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
async test "stream HTTP serves exact chunked JSONL and SSE and validates before 200" {
  @fsx.with_temporary_directory("mooncode-stream-http-XXXXXX", async fn(root) {
    let session_id = "session-stream-http"
    mooncode_append_session_journal(
      root,
      session_id,
      mooncode_journal_event(),
      {
        "id": "event-http",
        "kind": "progress",
        "lane": "runtime",
        "created_at": "2026-07-26T00:00:00Z",
      },
    )
    let daemon = integration_fixture_daemon(root)
    defer daemon.httpx.close()
    @async.with_task_group(group => {
      group.spawn_bg(
        () => {
          daemon.httpx.serve((r, w) => daemon.mooncode_stream(session_id~, r, w))
        },
        no_wait=true,
      )
      @async.pause()
      let base = "http://127.0.0.1:\{daemon.httpx.port()}/v1/code/sessions/\{session_id}/stream?book_root=\{root}"
      let (response, body) = @http.get_stream(base + "&format=jsonl")
      assert_eq(response.code, 200)
      assert_eq(response.headers["content-type"], "application/x-ndjson")
      assert_eq(response.headers["transfer-encoding"], "chunked")
      let text = body.read_all().text()
      body.close()
      let lines = text.split("\n").filter(line => line != "").collect()
      let records = lines.map(line => @json.parse(line.to_owned()))
      assert_eq(
        records.map(record => mooncode_json_string(record, "type", default="")),
        ["meta", "event", "done"],
      )
      assert_eq(mooncode_json_int(records[0], "event_count", default=0), 1)
      assert_eq(mooncode_json_string(records[1], "sequence", default=""), "1")
      assert_eq(
        mooncode_json_string(records[1], "event_id", default=""),
        "event-http",
      )
      assert_eq(mooncode_json_string(records[2], "next_since", default=""), "1")
      let (response, body) = @http.get_stream(base + "&format=sse")
      assert_eq(response.code, 200)
      assert_eq(response.headers["content-type"], "text/event-stream")
      assert_eq(response.headers["transfer-encoding"], "chunked")
      let text = body.read_all().text()
      body.close()
      assert_eq(
        text,
        "event: meta\ndata: " +
        lines[0].to_owned() +
        "\n\nevent: event\ndata: " +
        lines[1].to_owned() +
        "\n\nevent: done\ndata: " +
        lines[2].to_owned() +
        "\n\n",
      )
      // Reconnect at/beyond the tail: no duplicate event and no cursor regression.
      for cursor in ["1", "999999999999999999999999999999999"] {
        let (response, body) = @http.get_stream(base + "&since=" + cursor)
        assert_eq(response.code, 200)
        let records = body
          .read_all()
          .text()
          .split("\n")
          .filter(line => line != "")
          .collect()
          .map(line => @json.parse(line.to_owned()))
        body.close()
        assert_eq(records.length(), 2)
        assert_eq(mooncode_json_int(records[0], "emitted_count", default=-1), 0)
        assert_eq(
          mooncode_json_string(records[1], "next_since", default=""),
          cursor,
        )
      }
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
