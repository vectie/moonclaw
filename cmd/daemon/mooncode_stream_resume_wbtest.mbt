///|
fn mooncode_stream_resume_test_cursor_rejected(
  value : String,
  session_id? : String = "session-resume",
  book_root? : String = "/tmp/book",
) -> Bool {
  try {
    ignore(mooncode_stream_resume_cursor_parse(value, session_id, book_root))
    false
  } catch {
    MoonCodeGoalRuntimeStoreError::CorruptStore(_) => true
    _ => false
  }
}

///|
fn mooncode_stream_resume_test_record(
  session_id : String,
  sequence : String,
  payload : Json,
) -> String raise {
  mooncode_journal_record_v2(
    session_id~,
    sequence=mooncode_journal_cursor_parse(sequence),
    record_id=mooncode_journal_record_id(mooncode_journal_event(), payload),
    record_kind=mooncode_journal_event(),
    command_id=mooncode_json_string(payload, "command_id", default=""),
    client_turn_id="",
    recorded_at="2026-08-23T00:00:00Z",
    payload~,
  ).stringify()
}

///|
fn mooncode_stream_resume_test_jsonl_records(text : String) -> Array[Json] {
  text
  .split("\n")
  .filter_map(line => {
    let line = line.trim()
    if line == "" {
      None
    } else {
      Some(@json.parse(line) catch { _ => Json::null() })
    }
  })
  .collect()
}

///|
test "mooncode typed resume cursor roundtrips and rejects forged stream bindings" {
  assert_eq(
    mooncode_stream_resume_replay_limit(0),
    MOONCODE_STREAM_RESUME_DEFAULT_REPLAY_EVENTS,
  )
  assert_eq(
    mooncode_stream_resume_replay_limit(-1),
    MOONCODE_STREAM_RESUME_DEFAULT_REPLAY_EVENTS,
  )
  assert_eq(mooncode_stream_resume_replay_limit(1), 1)
  assert_eq(
    mooncode_stream_resume_replay_limit(1000000),
    MOONCODE_STREAM_RESUME_MAX_REPLAY_EVENTS,
  )
  let sequence = mooncode_journal_cursor_parse("922337203685477580812345")
  let epoch = mooncode_stream_resume_digest("fixture epoch")
  let encoded = mooncode_stream_resume_cursor_encode(
    "session-resume", "/tmp/book", epoch, sequence,
  )
  let decoded = mooncode_stream_resume_cursor_parse(
    encoded, "session-resume", "/tmp/book",
  )
  assert_eq(decoded.sequence.text(), sequence.text())
  assert_eq(decoded.epoch, epoch)
  assert_false(decoded.initial)
  let initial = mooncode_stream_resume_cursor_parse(
    MOONCODE_STREAM_RESUME_START,
    "session-resume",
    "/tmp/book",
  )
  assert_true(initial.initial)
  assert_eq(initial.sequence.text(), "0")
  assert_true(
    mooncode_stream_resume_test_cursor_rejected(
      encoded,
      session_id="other-session",
    ),
  )
  let forged = encoded[:encoded.length() - 1].to_owned() +
    (if encoded.has_suffix("0") { "1" } else { "0" })
  assert_true(mooncode_stream_resume_test_cursor_rejected(forged))
  assert_true(mooncode_stream_resume_test_cursor_rejected("mcr1.bad"))
  assert_true(
    mooncode_stream_resume_test_cursor_rejected(
      "x".repeat(MOONCODE_STREAM_RESUME_CURSOR_MAX_CHARS + 1),
    ),
  )
}

///|
test "mooncode resume projection hides reasoning raw arguments and sandbox paths" {
  assert_true(
    mooncode_stream_resume_project_event({
      "kind": "reasoning_delta",
      "content": "private chain of thought",
    })
    is None,
  )
  guard mooncode_stream_resume_project_event({
      "id": "planner",
      "kind": "runtime.planner_started",
      "status": "running",
      "detail": "secret planner reasoning",
      "raw_event": { "reasoning": "hidden" },
    })
    is Some(planner) else {
    fail("expected planner projection")
  }
  assert_false(planner.stringify().contains("secret planner reasoning"))
  assert_false(planner.stringify().contains("raw_event"))
  guard mooncode_stream_resume_project_event({
      "id": "tool",
      "kind": "tool_result",
      "event": "tool_result",
      "lane": "artifact",
      "tool": "/private/tmp/moonfort/shell",
      "command_id": "/Users/example/private-command",
      "status": "done",
      "detail": "artifact_path=/private/tmp/moonfort/run-1/output.txt",
      "arguments": {
        "cmd": "secret command",
        "artifact_path": "/private/tmp/moonfort/run-1/output.txt",
      },
      "raw_event": { "spool_path": "/tmp/private.spool" },
      "book_root": "/Users/example/private-book",
    })
    is Some(tool) else {
    fail("expected tool projection")
  }
  let serialized = tool.stringify()
  assert_true(serialized.contains("Private sandbox path omitted"))
  for
    forbidden in [
      "artifact_path", "/private/tmp/", "spool_path", "private.spool", "arguments",
      "secret command", "raw_event", "book_root", "/Users/example/",
    ] {
    assert_false(serialized.contains(forbidden))
  }
  let envelope = mooncode_stream_resume_event_record(
    "session-resume",
    "/tmp/book",
    mooncode_stream_resume_digest("epoch"),
    mooncode_journal_cursor_parse("1"),
    "/private/tmp/moonfort/event-id",
    tool,
  ).stringify()
  for forbidden in ["/private/tmp/", "/Users/", "event-id", "moonfort/shell"] {
    assert_false(envelope.contains(forbidden))
  }
}

///|
async test "mooncode resume scan detects gap expiry and future cursors" {
  @fsx.with_temporary_directory("mooncode-resume-status-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session-resume-status"
    for index in 0..<3 {
      assert_true(
        mooncode_append_session_journal_once(
          root,
          session_id,
          mooncode_journal_event(),
          {
            "id": "assistant-\{index}",
            "kind": "assistant_delta",
            "command_id": "command-resume",
            "content": "visible-\{index}",
            "created_at": "2026-08-23T00:00:0\{index}Z",
          },
        ),
      )
    }
    let initial = mooncode_stream_resume_cursor_parse(
      MOONCODE_STREAM_RESUME_START,
      session_id,
      root,
    )
    let summary = mooncode_stream_resume_scan(root, session_id, initial, 2) catch {
      InvalidJournal(message) => fail("resume scan fixture failed: \{message}")
      error => raise error
    }
    assert_eq(summary.eligible_event_count, 3)
    assert_eq(mooncode_stream_resume_status(initial, summary, 2), "gap")
    let future = MoonCodeStreamResumeCursor::{
      sequence: summary.latest_sequence.next(),
      epoch: summary.epoch,
      token: "fixture-future",
      initial: false,
    }
    assert_eq(mooncode_stream_resume_status(future, summary, 5), "future")
    let stable_cursor_text = mooncode_stream_resume_cursor_encode(
      session_id,
      root,
      summary.epoch,
      mooncode_journal_cursor_parse("1"),
    )
    let stable_cursor = mooncode_stream_resume_cursor_parse(
      stable_cursor_text, session_id, root,
    )
    let path = mooncode_session_journal_path(root, session_id)
    @fsx.write_to_file(
      path,
      mooncode_stream_resume_test_record(session_id, "1", {
        "id": "replacement-first",
        "kind": "assistant_delta",
        "content": "replacement",
        "created_at": "2026-08-23T01:00:00Z",
      }) +
      "\n",
    )
    let replaced = mooncode_stream_resume_scan(
      root, session_id, stable_cursor, 5,
    )
    assert_eq(
      mooncode_stream_resume_status(stable_cursor, replaced, 5),
      "expired",
    )
  })
}

///|
async test "mooncode resume spool is idempotent across disconnect and reconnect" {
  @fsx.with_temporary_directory("mooncode-resume-idempotent-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session-resume-idempotent"
    assert_true(
      mooncode_append_session_journal_once(
        root,
        session_id,
        mooncode_journal_event(),
        {
          "id": "reasoning",
          "kind": "reasoning_delta",
          "content": "must never be streamed",
          "created_at": "2026-08-23T00:00:00Z",
        },
      ) catch {
        InvalidJournal(message) => fail("reasoning append failed: \{message}")
        error => raise error
      },
    )
    assert_true(
      mooncode_append_session_journal_once(
        root,
        session_id,
        mooncode_journal_event(),
        {
          "id": "assistant",
          "kind": "assistant_delta",
          "content": "answer chunk",
          "created_at": "2026-08-23T00:00:01Z",
        },
      ) catch {
        InvalidJournal(message) => fail("assistant append failed: \{message}")
        error => raise error
      },
    )
    assert_true(
      mooncode_append_session_journal_once(
        root,
        session_id,
        mooncode_journal_event(),
        {
          "id": "tool",
          "kind": "tool_result",
          "lane": "tool",
          "tool": "read",
          "detail": "tool output",
          "created_at": "2026-08-23T00:00:02Z",
        },
      ) catch {
        InvalidJournal(message) => fail("tool append failed: \{message}")
        error => raise error
      },
    )
    let initial = mooncode_stream_resume_cursor_parse(
      MOONCODE_STREAM_RESUME_START,
      session_id,
      root,
    )
    let first = mooncode_stream_resume_create_spool(
      "jsonl", root, session_id, initial, 5,
    ) catch {
      InvalidJournal(message) => fail("initial resume spool failed: \{message}")
      error => raise error
    }
    let first_records = mooncode_stream_resume_test_jsonl_records(
      @fsx.read_file(first.path),
    )
    assert_eq(first_records.length(), 2)
    assert_eq(
      mooncode_json_string(first_records[0], "content_kind", default=""),
      "assistant",
    )
    let resume_text = mooncode_json_string(
      first_records[0],
      "resume_cursor",
      default="",
    )
    assert_true(resume_text != "")
    let meta = mooncode_stream_resume_meta_record(
      session_id,
      root,
      initial,
      first.summary,
      5,
      { wait_elapsed_ms: 0, wait_attempt_count: 0 },
    )
    let meta_cursor = mooncode_json_string(meta, "resume_cursor", default="")
    let decoded_meta = mooncode_stream_resume_cursor_parse(
      meta_cursor, session_id, root,
    )
    assert_eq(decoded_meta.sequence.text(), "0")
    first.cleanup()
    let resumed = mooncode_stream_resume_cursor_parse(
      resume_text, session_id, root,
    )
    let second = mooncode_stream_resume_create_spool(
      "jsonl", root, session_id, resumed, 5,
    ) catch {
      InvalidJournal(message) =>
        fail("reconnected resume spool failed: \{message}")
      error => raise error
    }
    let second_bytes = @fsx.read_file(second.path)
    let second_records = mooncode_stream_resume_test_jsonl_records(second_bytes)
    assert_eq(second_records.length(), 1)
    assert_eq(
      mooncode_json_string(second_records[0], "content_kind", default=""),
      "tool_output",
    )
    second.cleanup()
    let repeated = mooncode_stream_resume_create_spool(
      "jsonl", root, session_id, resumed, 5,
    ) catch {
      InvalidJournal(message) =>
        fail("repeated resume spool failed: \{message}")
      error => raise error
    }
    assert_eq(@fsx.read_file(repeated.path), second_bytes)
    repeated.cleanup()
  })
}

///|
async test "mooncode resume HTTP returns deterministic 409 gap and safe reconnect stream" {
  @fsx.with_temporary_directory("mooncode-resume-http-XXXXXX", async fn(root) {
    let session_id = "session-resume-http"
    assert_true(
      mooncode_append_session_journal_once(
        root,
        session_id,
        mooncode_journal_event(),
        {
          "id": "reasoning-http",
          "kind": "reasoning_delta",
          "content": "private reasoning HTTP",
          "created_at": "2026-08-23T00:00:00Z",
        },
      ),
    )
    assert_true(
      mooncode_append_session_journal_once(
        root,
        session_id,
        mooncode_journal_event(),
        {
          "id": "assistant-http",
          "kind": "assistant_delta",
          "content": "public answer HTTP",
          "created_at": "2026-08-23T00:00:01Z",
        },
      ),
    )
    assert_true(
      mooncode_append_session_journal_once(
        root,
        session_id,
        mooncode_journal_event(),
        {
          "id": "tool-http",
          "kind": "tool_result",
          "lane": "artifact",
          "tool": "shell",
          "detail": "artifact_path=/private/tmp/moonfort/output.log",
          "arguments": { "cmd": "secret HTTP command" },
          "created_at": "2026-08-23T00:00:02Z",
        },
      ),
    )
    let daemon = mooncode_stream_http_test_daemon(root)
    defer daemon.httpx.close()
    @async.with_task_group(group => {
      group.spawn_bg(
        () => {
          daemon.httpx.serve((r, w) => {
            daemon.mooncode_stream(session_id~, r, w) catch {
              HttpError(code~, reason~, body~) => {
                w.header().set("Content-Type", "application/json")
                w.write_header(code, reason~)
                w.write(body)
              }
              error => raise error
            }
          })
        },
        no_wait=true,
      )
      @async.pause()
      let base = "http://localhost:\{daemon.httpx.port()}/v1/code/sessions/\{session_id}/stream?book_root=\{root}&format=jsonl&resume_cursor=start"
      let (gap_response, gap_body) = @http.get_stream(base + "&replay_limit=1")
      let gap_text = gap_body.read_all().text()
      gap_body.close()
      assert_eq(gap_response.code, 409)
      assert_true(gap_text.contains("\"resume_status\":\"gap\""))
      assert_true(gap_text.contains("\"recovery\":\"reload_snapshot\""))
      let (response, body) = @http.get_stream(base + "&replay_limit=5")
      let text = body.read_all().text()
      body.close()
      assert_eq(response.code, 200)
      assert_true(text.contains("public answer HTTP"))
      assert_true(text.contains("Private sandbox path omitted"))
      for
        forbidden in [
          "private reasoning HTTP", "artifact_path", "/private/tmp/", "arguments",
          "secret HTTP command", "book_root",
        ] {
        assert_false(text.contains(forbidden))
      }
      let records = mooncode_stream_resume_test_jsonl_records(text)
      let event_records = records.filter(record => {
        mooncode_json_string(record, "type", default="") == "event"
      })
      assert_eq(event_records.length(), 2)
      let reconnect_cursor = mooncode_json_string(
        event_records[0],
        "resume_cursor",
        default="",
      )
      let (reconnect_response, reconnect_body) = @http.get_stream(
        "http://localhost:\{daemon.httpx.port()}/v1/code/sessions/\{session_id}/stream?book_root=\{root}&format=jsonl&resume_cursor=\{reconnect_cursor}&replay_limit=5",
      )
      let reconnect_text = reconnect_body.read_all().text()
      reconnect_body.close()
      assert_eq(reconnect_response.code, 200)
      assert_false(reconnect_text.contains("public answer HTTP"))
      assert_true(reconnect_text.contains("Private sandbox path omitted"))
    })
  })
}
