///|
test "mooncode durable stream records support resumable sequence replay" {
  let first : Json = {
    "id": "event-1",
    "kind": "assistant_delta",
    "lane": "transcript",
  }
  let second : Json = { "id": "event-2", "kind": "tool_result", "lane": "tool" }
  let records = mooncode_stream_records(
    "session-stream",
    "/tmp/book",
    [first, second],
    since=1,
    wait_ms=1000,
    poll_ms=100,
    wait_elapsed_ms=300,
    wait_attempt_count=3,
  )
  assert_eq(records.length(), 3)
  assert_eq(mooncode_json_string(records[0], "type", default=""), "meta")
  assert_eq(mooncode_json_int(records[0], "event_count", default=0), 2)
  assert_eq(mooncode_json_int(records[0], "emitted_count", default=0), 1)
  assert_eq(mooncode_json_int(records[0], "wait_ms", default=0), 1000)
  assert_eq(mooncode_json_int(records[0], "poll_ms", default=0), 100)
  assert_eq(mooncode_json_int(records[0], "wait_elapsed_ms", default=0), 300)
  assert_eq(mooncode_json_int(records[0], "wait_attempt_count", default=0), 3)
  assert_eq(mooncode_json_string(records[1], "type", default=""), "event")
  assert_eq(mooncode_json_int(records[1], "sequence", default=0), 2)
  assert_eq(mooncode_json_string(records[1], "event_id", default=""), "event-2")
  assert_eq(mooncode_json_string(records[2], "type", default=""), "done")
  assert_eq(mooncode_json_int(records[2], "next_since", default=0), 2)
  assert_eq(mooncode_json_int(records[2], "wait_elapsed_ms", default=0), 300)
}

///|
test "mooncode durable stream serializes jsonl and sse envelopes" {
  let event : Json = { "id": "event-1", "kind": "tool_result", "lane": "tool" }
  let jsonl = mooncode_stream_jsonl_payload(
    "session-stream",
    "/tmp/book",
    [event],
    since=0,
    wait_ms=0,
    poll_ms=100,
    wait_elapsed_ms=0,
    wait_attempt_count=0,
  )
  assert_true(jsonl.contains("\"type\":\"meta\""))
  assert_true(jsonl.contains("\"type\":\"event\""))
  assert_true(jsonl.contains("\"type\":\"done\""))
  let sse = mooncode_stream_sse_payload(
    "session-stream",
    "/tmp/book",
    [event],
    since=0,
    wait_ms=0,
    poll_ms=100,
    wait_elapsed_ms=0,
    wait_attempt_count=0,
  )
  assert_true(sse.contains("event: meta\n"))
  assert_true(sse.contains("event: event\n"))
  assert_true(sse.contains("data: {"))
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
async test "mooncode stream uses event log size as its append fingerprint" {
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "mooncode-stream-fingerprint-XXXXXX"),
  )
  let session_id = "session-stream-fingerprint"
  let path = mooncode_events_path(book_root, session_id)
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  @fsx.write_to_file(path, "{\"id\":\"event-1\"}\n")
  let first_size = mooncode_stream_event_log_size(book_root, session_id)
  assert_true(first_size > 0L)
  @fsx.write_to_file(path, "{\"id\":\"event-1\"}\n{\"id\":\"event-2\"}\n")
  let second_size = mooncode_stream_event_log_size(book_root, session_id)
  assert_true(second_size > first_size)
  let events = mooncode_read_jsonl(path)
  assert_eq(events.length(), 2)
}
