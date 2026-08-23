///|
fn mooncode_stream_test_expect_corrupt(action : () -> Unit raise) -> Unit raise {
  try action() catch {
    MoonCodeGoalRuntimeStoreError::CorruptStore(_) => ()
    _ => fail("unexpected stream sequence error")
  } noraise {
    _ => fail("expected corrupt stream sequence")
  }
}

///|
test "mooncode stream HTTP cursor boundary is exact and canonical" {
  assert_eq(mooncode_stream_query_cursor("").text(), "0")
  let huge = "922337203685477580812345678901234567890"
  assert_eq(mooncode_stream_query_cursor(huge).text(), huge)
  for bad in ["00", "01", "-1", "+1", "1.0", "1e3", "not-a-cursor"] {
    let rejected = try {
      ignore(mooncode_stream_query_cursor(bad))
      false
    } catch {
      CorruptStore(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "mooncode durable stream records support sparse journal sequence replay" {
  let first : Json = {
    "id": "event-1",
    "kind": "assistant_delta",
    "lane": "transcript",
    "journal_sequence": 2,
  }
  let second : Json = {
    "id": "event-2",
    "kind": "tool_result",
    "lane": "tool",
    "journal_sequence": 5,
  }
  let records = mooncode_stream_records(
    "session-stream",
    "/tmp/book",
    [first, second],
    since=MoonCodeJournalSequence::parse("2"),
    wait_ms=1000,
    poll_ms=100,
    wait_elapsed_ms=300,
    wait_attempt_count=3,
  )
  assert_eq(records.length(), 3)
  assert_eq(mooncode_json_string(records[0], "type", default=""), "meta")
  assert_eq(
    mooncode_json_string(records[0], "contract_id", default=""),
    "mooncode-stream.v2",
  )
  assert_eq(
    mooncode_json_string(records[1], "contract_id", default=""),
    "mooncode-stream.v2",
  )
  assert_eq(
    mooncode_json_string(records[2], "contract_id", default=""),
    "mooncode-stream.v2",
  )
  assert_eq(mooncode_json_int(records[0], "event_count", default=0), 2)
  assert_eq(mooncode_json_int(records[0], "emitted_count", default=0), 1)
  assert_eq(mooncode_json_int(records[0], "wait_ms", default=0), 1000)
  assert_eq(mooncode_json_int(records[0], "poll_ms", default=0), 100)
  assert_eq(mooncode_json_int(records[0], "wait_elapsed_ms", default=0), 300)
  assert_eq(mooncode_json_int(records[0], "wait_attempt_count", default=0), 3)
  assert_eq(mooncode_json_string(records[1], "type", default=""), "event")
  assert_eq(mooncode_json_string(records[1], "sequence", default=""), "5")
  assert_eq(mooncode_json_string(records[1], "since", default=""), "2")
  assert_eq(mooncode_json_string(records[1], "event_id", default=""), "event-2")
  assert_eq(mooncode_json_string(records[2], "type", default=""), "done")
  assert_eq(mooncode_json_string(records[2], "since", default=""), "2")
  assert_eq(mooncode_json_string(records[2], "next_since", default=""), "5")
  assert_eq(mooncode_json_int(records[2], "wait_elapsed_ms", default=0), 300)
}

///|
test "mooncode stream dual-reads exact journal sequences and emits canonical strings" {
  let legacy : Json = {
    "id": "legacy",
    "kind": "assistant_delta",
    "lane": "transcript",
    "journal_sequence": 2,
  }
  let canonical : Json = {
    "id": "canonical",
    "kind": "tool_result",
    "lane": "tool",
    "journal_sequence": "9223372036854775810",
  }
  let records = mooncode_stream_records(
    "session-exact",
    "/tmp/book",
    [legacy, canonical],
    since=MoonCodeJournalSequence::parse("9223372036854775808"),
    wait_ms=0,
    poll_ms=100,
    wait_elapsed_ms=0,
    wait_attempt_count=0,
  )
  assert_eq(records.length(), 3)
  assert_eq(
    mooncode_json_string(records[0], "since", default=""),
    "9223372036854775808",
  )
  assert_eq(
    mooncode_json_string(records[0], "latest_sequence", default=""),
    "9223372036854775810",
  )
  assert_eq(
    mooncode_json_string(records[0], "next_since", default=""),
    "9223372036854775810",
  )
  assert_eq(
    mooncode_json_string(records[1], "sequence", default=""),
    "9223372036854775810",
  )
  assert_eq(
    mooncode_json_string(records[2], "sequence", default=""),
    "9223372036854775810",
  )
  assert_eq(
    mooncode_json_string(records[2], "next_since", default=""),
    "9223372036854775810",
  )
}

///|
test "mooncode stream response cursor stays monotonic for empty events and huge since" {
  let since = MoonCodeJournalSequence::parse(
    "99999999999999999999999999999999999999",
  )
  let records = mooncode_stream_records(
    "session-empty",
    "/tmp/book",
    [],
    since~,
    wait_ms=0,
    poll_ms=100,
    wait_elapsed_ms=0,
    wait_attempt_count=0,
  )
  assert_eq(records.length(), 2)
  assert_eq(
    mooncode_json_string(records[0], "latest_sequence", default=""),
    "0",
  )
  assert_eq(
    mooncode_json_string(records[0], "next_since", default=""),
    since.text(),
  )
  assert_eq(
    mooncode_json_string(records[1], "sequence", default=""),
    since.text(),
  )
  assert_eq(
    mooncode_json_string(records[1], "next_since", default=""),
    since.text(),
  )
}

///|
test "mooncode stream response cursor stays monotonic when latest is below since" {
  let event : Json = { "id": "old", "journal_sequence": "7" }
  let since = MoonCodeJournalSequence::parse("100000000000000000000")
  let records = mooncode_stream_records(
    "session-old",
    "/tmp/book",
    [event],
    since~,
    wait_ms=0,
    poll_ms=100,
    wait_elapsed_ms=0,
    wait_attempt_count=0,
  )
  assert_eq(records.length(), 2)
  assert_eq(
    mooncode_json_string(records[0], "latest_sequence", default=""),
    "7",
  )
  assert_eq(
    mooncode_json_string(records[0], "next_since", default=""),
    since.text(),
  )
  assert_eq(
    mooncode_json_string(records[1], "sequence", default=""),
    since.text(),
  )
  assert_eq(
    mooncode_json_string(records[1], "next_since", default=""),
    since.text(),
  )
}

///|
test "mooncode stream rejects physical zero and malformed present journal sequences" {
  let zero : Json = { "id": "zero", "journal_sequence": 0 }
  let malformed : Json = { "id": "bad", "journal_sequence": "not-a-sequence" }
  mooncode_stream_test_expect_corrupt(fn() -> Unit raise {
    ignore(
      mooncode_stream_records(
        "session-invalid",
        "/tmp/book",
        [zero],
        since=MoonCodeJournalSequence::zero(),
        wait_ms=0,
        poll_ms=100,
        wait_elapsed_ms=0,
        wait_attempt_count=0,
      ),
    )
  })
  mooncode_stream_test_expect_corrupt(fn() -> Unit raise {
    ignore(
      mooncode_stream_records(
        "session-invalid",
        "/tmp/book",
        [malformed],
        since=MoonCodeJournalSequence::zero(),
        wait_ms=0,
        poll_ms=100,
        wait_elapsed_ms=0,
        wait_attempt_count=0,
      ),
    )
  })
}

///|
test "mooncode durable stream serializes jsonl and sse envelopes" {
  let event : Json = { "id": "event-1", "kind": "tool_result", "lane": "tool" }
  let jsonl = mooncode_stream_jsonl_payload(
    "session-stream",
    "/tmp/book",
    [event],
    since=MoonCodeJournalSequence::zero(),
    wait_ms=0,
    poll_ms=100,
    wait_elapsed_ms=0,
    wait_attempt_count=0,
  )
  assert_true(jsonl.contains("\"type\":\"meta\""))
  assert_true(jsonl.contains("\"type\":\"event\""))
  assert_true(jsonl.contains("\"type\":\"done\""))
  assert_true(jsonl.contains("\"contract_id\":\"mooncode-stream.v2\""))
  let sse = mooncode_stream_sse_payload(
    "session-stream",
    "/tmp/book",
    [event],
    since=MoonCodeJournalSequence::zero(),
    wait_ms=0,
    poll_ms=100,
    wait_elapsed_ms=0,
    wait_attempt_count=0,
  )
  assert_true(sse.contains("event: meta\n"))
  assert_true(sse.contains("event: event\n"))
  assert_true(sse.contains("data: {"))
  assert_true(sse.contains("\"contract_id\":\"mooncode-stream.v2\""))
}

///|
test "mooncode stream wait options clamp to bounded live tail values" {
  assert_eq(mooncode_stream_wait_ms_value(-1), 0)
  assert_eq(mooncode_stream_wait_ms_value(0), 0)
  assert_eq(mooncode_stream_wait_ms_value(1000), 1000)
  assert_eq(mooncode_stream_wait_ms_value(90000), 30000)
  assert_eq(mooncode_stream_poll_ms_value(1), 25)
  assert_eq(mooncode_stream_poll_ms_value(100), 100)
  assert_eq(mooncode_stream_poll_ms_value(9000), 2000)
}

///|
async test "mooncode stream uses session journal size as its append fingerprint" {
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "mooncode-stream-fingerprint-XXXXXX"),
  )
  let session_id = "session-stream-fingerprint"
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_event(),
    {
      "id": "event-1",
      "command_id": "command-stream",
      "created_at": "2026-07-15T00:00:00Z",
    },
  )
  let first_size = mooncode_stream_journal_size(book_root, session_id)
  assert_true(first_size > 0L)
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_event(),
    {
      "id": "event-2",
      "command_id": "command-stream",
      "created_at": "2026-07-15T00:00:01Z",
    },
  )
  let second_size = mooncode_stream_journal_size(book_root, session_id)
  assert_true(second_size > first_size)
  let events = mooncode_journal_entries(
    mooncode_read_session_journal(book_root, session_id),
    mooncode_journal_event(),
  )
  assert_eq(events.length(), 2)
  assert_eq(
    mooncode_json_string(events[0], "journal_sequence", default=""),
    "1",
  )
  assert_eq(
    mooncode_json_string(events[1], "journal_sequence", default=""),
    "2",
  )
}
