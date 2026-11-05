///|
fn mooncode_watch_response(
  record : Json,
  since : MoonCodeJournalSequence,
) -> Json raise {
  let conversation = mooncode_json_object_field_or_empty(
    record, "mooncode_conversation",
  )
  let revision = mooncode_journal_cursor_from_json(
    mooncode_journal_json_field(conversation, "revision").unwrap_or(
      Json::null(),
    ),
  )
  let changed = revision != since
  let turns = mooncode_json_array_items(conversation, "turns")
  let status = mooncode_json_string(
    turns.last().unwrap_or(Json::null()),
    "status",
    default="",
  )
  @mooncode_core.conversation_watch_response_exact(
    session_id=mooncode_json_string(record, "session_id", default=""),
    revision=revision.text(),
    next_sequence=revision.text(),
    changed~,
    heartbeat=!changed,
    terminal=["done", "failed", "cancelled"].contains(status),
    retry_after_ms=100,
    snapshot=if changed { record } else { Json::null() },
  )
}

///|
async fn mooncode_watch_journal_stamp(path : String) -> (Int64, Int32)? {
  if @fs.exists(path) {
    Some(@fs.mtime(path))
  } else {
    None
  }
}

///|
/// Wait on a cheap filesystem signal, then rebuild from the committed journal.
/// No event transcript, spool or per-client execution state is retained while
/// waiting. The final snapshot is authoritative even if metadata did not change.
async fn Daemon::mooncode_watch_response(
  self : Daemon,
  book_root : String,
  session_id : String,
  since : MoonCodeJournalSequence,
  wait_ms : Int32,
  poll_ms : Int32,
) -> Json {
  let path = mooncode_session_journal_path(book_root, session_id)
  let stamp = mooncode_watch_journal_stamp(path)
  let initial = self.mooncode_watch_snapshot(book_root, session_id, since)
  if mooncode_json_bool(initial, "changed", default=false) || wait_ms == 0 {
    return initial
  }
  let mut remaining = wait_ms
  while remaining > 0 {
    let delay = remaining.min(poll_ms)
    @async.sleep(delay)
    remaining -= delay
    if mooncode_watch_journal_stamp(path) != stamp {
      break
    }
  }
  self.mooncode_watch_snapshot(book_root, session_id, since)
}

///|
async fn Daemon::mooncode_watch_snapshot(
  self : Daemon,
  book_root : String,
  session_id : String,
  since : MoonCodeJournalSequence,
) -> Json {
  guard self.mooncode_session_record(session_id, book_root) is Some(record) else {
    raise json_error(404, "Not Found", {
      "error": { "message": "MoonCode session not found" },
    })
  }
  mooncode_watch_response(record, since)
}

///|
async fn Daemon::mooncode_watch(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let since = mooncode_stream_query_cursor(
    mooncode_request_string(r, "since_revision", default="0"),
  ) catch {
    _ =>
      raise json_error(400, "Bad Request", {
        "error": { "message": "Invalid MoonCode watch revision" },
      })
  }
  let response = self.mooncode_watch_response(
    mooncode_request_book_root(r),
    session_id.to_owned(),
    since,
    mooncode_stream_wait_ms_value(
      mooncode_request_int(r, "wait_ms", default=15000),
    ),
    mooncode_stream_poll_ms_value(
      mooncode_request_int(r, "poll_ms", default=100),
    ),
  )
  w.header().set("Content-Type", "application/json")
  w.header().set("Cache-Control", "no-store")
  w.write_header(200)
  w.write(response.stringify())
}
