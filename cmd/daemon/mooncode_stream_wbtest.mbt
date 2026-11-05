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
