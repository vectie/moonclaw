///|
async fn Daemon::mooncode_stream(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let session_id = session_id.to_owned()
  let requested_book_root = mooncode_request_book_root(r)
  let book_root = if requested_book_root != "" {
    requested_book_root
  } else {
    match self.mooncode_sessions.get(session_id) {
      Some(binding) => binding.book_root
      None => ""
    }
  }
  if book_root == "" {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": "MoonCode stream requires book_root query or an existing MoonCode session",
        "metadata": { "session_id": session_id },
      },
    })
  }
  let since = mooncode_request_int(r, "since", default=0)
  let format = mooncode_request_string(r, "format", default="jsonl")
  let wait_ms = mooncode_stream_wait_ms_value(
    mooncode_request_int(r, "wait_ms", default=0),
  )
  let poll_ms = mooncode_stream_poll_ms_value(
    mooncode_request_int(r, "poll_ms", default=100),
  )
  let wait = self.mooncode_stream_wait_for_events(
    session_id, book_root, since, wait_ms, poll_ms,
  )
  let events = mooncode_json_array_items(wait, "events")
  if format == "sse" {
    w.header().set("Content-Type", "text/event-stream")
    w.header().set("Cache-Control", "no-cache")
    w.write_header(200)
    w.write(
      mooncode_stream_sse_payload(
        session_id,
        book_root,
        events,
        since~,
        wait_ms~,
        poll_ms~,
        wait_elapsed_ms=mooncode_json_int(wait, "wait_elapsed_ms", default=0),
        wait_attempt_count=mooncode_json_int(
          wait,
          "wait_attempt_count",
          default=0,
        ),
      ),
    )
  } else {
    w.header().set("Content-Type", "application/x-ndjson")
    w.write_header(200)
    w.write(
      mooncode_stream_jsonl_payload(
        session_id,
        book_root,
        events,
        since~,
        wait_ms~,
        poll_ms~,
        wait_elapsed_ms=mooncode_json_int(wait, "wait_elapsed_ms", default=0),
        wait_attempt_count=mooncode_json_int(
          wait,
          "wait_attempt_count",
          default=0,
        ),
      ),
    )
  }
  w.flush()
}

///|
async fn Daemon::mooncode_stream_wait_for_events(
  self : Daemon,
  session_id : String,
  book_root : String,
  since : Int,
  wait_ms : Int,
  poll_ms : Int,
) -> Json {
  let mut elapsed_ms = 0
  let mut attempt_count = 0
  let snapshot = self.mooncode_stream_snapshot(book_root, session_id)
  let mut events = snapshot.0
  let mut journal_size = snapshot.1
  while wait_ms > 0 &&
        mooncode_stream_event_count_after(events, since) == 0 &&
        elapsed_ms < wait_ms {
    if @async.is_being_cancelled() {
      break
    }
    let remaining = wait_ms - elapsed_ms
    let delay = if remaining < poll_ms { remaining } else { poll_ms }
    @async.sleep(delay)
    elapsed_ms += delay
    attempt_count += 1
    let next_journal_size = mooncode_stream_journal_size(book_root, session_id)
    if next_journal_size != journal_size {
      let changed = self.mooncode_stream_snapshot(book_root, session_id)
      events = changed.0
      journal_size = changed.1
    }
  }
  {
    "kind": "mooncode-stream-wait",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "since": since,
    "wait_ms": wait_ms,
    "poll_ms": poll_ms,
    "wait_elapsed_ms": elapsed_ms,
    "wait_attempt_count": attempt_count,
    "ready": mooncode_stream_event_count_after(events, since) > 0,
    "event_count": events.length(),
    "events": Json::array(events),
  }
}

///|
async fn Daemon::mooncode_stream_snapshot(
  self : Daemon,
  book_root : String,
  session_id : String,
) -> (Array[Json], Int64) {
  let mut size_before = mooncode_stream_journal_size(book_root, session_id)
  let mut events = self.mooncode_stream_current_events(book_root, session_id)
  let mut size_after = mooncode_stream_journal_size(book_root, session_id)
  let mut retry_count = 0
  while size_after != size_before && retry_count < 3 {
    size_before = size_after
    events = self.mooncode_stream_current_events(book_root, session_id)
    size_after = mooncode_stream_journal_size(book_root, session_id)
    retry_count += 1
  }
  (events, size_after)
}

///|
async fn mooncode_stream_journal_size(
  book_root : String,
  session_id : String,
) -> Int64 {
  let file = @fs.open(
    mooncode_session_journal_path(book_root, session_id),
    mode=ReadOnly,
  ) catch {
    _ => return -1L
  }
  defer file.close()
  file.size() catch {
    _ => -1L
  }
}

///|
async fn Daemon::mooncode_stream_current_events(
  self : Daemon,
  book_root : String,
  session_id : String,
) -> Array[Json] {
  ignore(self)
  mooncode_journal_entries(
    mooncode_read_session_journal(book_root, session_id),
    mooncode_journal_event(),
  )
}

///|
fn mooncode_stream_jsonl_payload(
  session_id : String,
  book_root : String,
  events : Array[Json],
  since~ : Int,
  wait_ms~ : Int,
  poll_ms~ : Int,
  wait_elapsed_ms~ : Int,
  wait_attempt_count~ : Int,
) -> String {
  let records = mooncode_stream_records(
    session_id,
    book_root,
    events,
    since~,
    wait_ms~,
    poll_ms~,
    wait_elapsed_ms~,
    wait_attempt_count~,
  )
  records.map(record => record.stringify()).join("\n") + "\n"
}

///|
fn mooncode_stream_sse_payload(
  session_id : String,
  book_root : String,
  events : Array[Json],
  since~ : Int,
  wait_ms~ : Int,
  poll_ms~ : Int,
  wait_elapsed_ms~ : Int,
  wait_attempt_count~ : Int,
) -> String {
  let chunks : Array[String] = []
  for
    record in mooncode_stream_records(
      session_id,
      book_root,
      events,
      since~,
      wait_ms~,
      poll_ms~,
      wait_elapsed_ms~,
      wait_attempt_count~,
    ) {
    chunks.push(
      "event: \{mooncode_json_string(record, "type", default="message")}\n" +
      "data: \{record.stringify()}\n",
    )
  }
  chunks.join("\n") + "\n"
}

///|
fn mooncode_stream_records(
  session_id : String,
  book_root : String,
  events : Array[Json],
  since~ : Int,
  wait_ms~ : Int,
  poll_ms~ : Int,
  wait_elapsed_ms~ : Int,
  wait_attempt_count~ : Int,
) -> Array[Json] {
  let latest_sequence = mooncode_stream_latest_sequence(events)
  let clamped_since = if since < 0 { 0 } else { since }
  let emitted_count = mooncode_stream_event_count_after(events, clamped_since)
  let records : Array[Json] = [
    mooncode_stream_meta_record(
      session_id,
      book_root,
      event_count=events.length(),
      since=clamped_since,
      emitted_count~,
      latest_sequence~,
      wait_ms~,
      poll_ms~,
      wait_elapsed_ms~,
      wait_attempt_count~,
    ),
  ]
  for index, event in events {
    let sequence = mooncode_json_int(
      event,
      "journal_sequence",
      default=index + 1,
    )
    if sequence > clamped_since {
      records.push(
        mooncode_stream_event_record(
          session_id,
          book_root,
          event,
          sequence~,
          since=clamped_since,
        ),
      )
    }
  }
  records.push(
    mooncode_stream_done_record(
      session_id,
      book_root,
      latest_sequence~,
      since=clamped_since,
      emitted_count~,
      wait_ms~,
      poll_ms~,
      wait_elapsed_ms~,
      wait_attempt_count~,
    ),
  )
  records
}

///|
fn mooncode_stream_latest_sequence(events : Array[Json]) -> Int {
  let mut latest = 0
  for index, event in events {
    let sequence = mooncode_json_int(
      event,
      "journal_sequence",
      default=index + 1,
    )
    if sequence > latest {
      latest = sequence
    }
  }
  latest
}

///|
fn mooncode_stream_event_count_after(events : Array[Json], since : Int) -> Int {
  let mut count = 0
  for index, event in events {
    if mooncode_json_int(event, "journal_sequence", default=index + 1) > since {
      count += 1
    }
  }
  count
}

///|
fn mooncode_stream_meta_record(
  session_id : String,
  book_root : String,
  event_count~ : Int,
  since~ : Int,
  emitted_count~ : Int,
  latest_sequence~ : Int,
  wait_ms~ : Int,
  poll_ms~ : Int,
  wait_elapsed_ms~ : Int,
  wait_attempt_count~ : Int,
) -> Json {
  {
    "type": "meta",
    "kind": "mooncode-stream-meta",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "event_count": event_count,
    "since": since,
    "emitted_count": emitted_count,
    "latest_sequence": latest_sequence,
    "next_since": latest_sequence,
    "wait_ms": wait_ms,
    "poll_ms": poll_ms,
    "wait_elapsed_ms": wait_elapsed_ms,
    "wait_attempt_count": wait_attempt_count,
    "source": "moonclaw-durable-mooncode-events",
  }
}

///|
fn mooncode_stream_event_record(
  session_id : String,
  book_root : String,
  event : Json,
  sequence~ : Int,
  since~ : Int,
) -> Json {
  {
    "type": "event",
    "kind": "mooncode-stream-event",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "sequence": sequence,
    "since": since,
    "event": event,
    "event_id": mooncode_json_string(event, "id", default=""),
    "event_kind": mooncode_json_string(event, "kind", default=""),
    "event_lane": mooncode_json_string(event, "lane", default="runtime"),
    "source": "moonclaw-durable-mooncode-events",
  }
}

///|
fn mooncode_stream_done_record(
  session_id : String,
  book_root : String,
  latest_sequence~ : Int,
  since~ : Int,
  emitted_count~ : Int,
  wait_ms~ : Int,
  poll_ms~ : Int,
  wait_elapsed_ms~ : Int,
  wait_attempt_count~ : Int,
) -> Json {
  {
    "type": "done",
    "kind": "mooncode-stream-done",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "sequence": latest_sequence,
    "since": since,
    "emitted_count": emitted_count,
    "next_since": latest_sequence,
    "wait_ms": wait_ms,
    "poll_ms": poll_ms,
    "wait_elapsed_ms": wait_elapsed_ms,
    "wait_attempt_count": wait_attempt_count,
    "source": "moonclaw-durable-mooncode-events",
  }
}

///|
fn mooncode_stream_wait_ms_value(requested : Int) -> Int {
  if requested < 0 {
    0
  } else if requested > 30000 {
    30000
  } else {
    requested
  }
}

///|
fn mooncode_stream_poll_ms_value(requested : Int) -> Int {
  if requested < 25 {
    25
  } else if requested > 2000 {
    2000
  } else {
    requested
  }
}
