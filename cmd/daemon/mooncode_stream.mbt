///|
let mooncode_stream_contract_id : String = "mooncode-stream.v2"

///|
/// Scalar result used by production stream scans so waiting never retains
/// journal payloads in memory.
priv struct MoonCodeStreamSummary {
  event_count : Int
  eligible_event_count : Int
  latest_event_sequence : MoonCodeJournalSequence
  journal_size : Int64
}

///|
/// Scalar wait receipt. The scan summary stays local to the wait loop; the
/// post-wait spool is the authoritative response snapshot.
priv struct MoonCodeStreamWait {
  wait_elapsed_ms : Int
  wait_attempt_count : Int
}

///|
/// Temporary on-disk projection. The writer must be closed before this value
/// escapes the locked scan so response I/O never holds journal/session locks.
priv struct MoonCodeStreamSpool {
  directory : String
  path : String
  summary : MoonCodeStreamSummary
}

///|
/// Scan one already-repaired journal while its caller owns the session and
/// journal locks. Keeping this scalar avoids retaining payloads while waiting.
async fn mooncode_stream_scan_locked(
  file : @fs.File,
  expected_session_id : String,
  since : MoonCodeJournalSequence,
) -> MoonCodeStreamSummary {
  let mut cursor = MoonCodeJournalSequence::zero()
  let mut event_count = 0
  let mut eligible_event_count = 0
  let mut latest_event_sequence = MoonCodeJournalSequence::zero()
  mooncode_journal_read_lines(file, async fn(line) {
    let (record, next) = mooncode_journal_stream_record(line, cursor)
    if mooncode_json_string(record, "session_id", default="") !=
      expected_session_id {
      raise InvalidJournal("journal record belongs to a different session")
    }
    cursor = next
    if mooncode_json_string(record, "record_kind", default="") ==
      mooncode_journal_event() {
      event_count = event_count + 1
      latest_event_sequence = next
      if next.compare(since) > 0 {
        eligible_event_count = eligible_event_count + 1
      }
    }
  })
  {
    event_count,
    eligible_event_count,
    latest_event_sequence,
    journal_size: file.size(),
  }
}

///|
/// Read a scalar journal summary while holding the stable session lock. A
/// missing journal is an empty stream and uses -1 as its append fingerprint.
async fn mooncode_stream_summary(
  book_root : String,
  session_id : String,
  since : MoonCodeJournalSequence,
) -> MoonCodeStreamSummary {
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Shared)
  defer session_lock.unlock()
  let journal_path = mooncode_session_journal_path(book_root, session_id)
  if !(@fsx.exists(journal_path) catch { _ => false }) {
    return {
      event_count: 0,
      eligible_event_count: 0,
      latest_event_sequence: MoonCodeJournalSequence::zero(),
      journal_size: -1L,
    }
  }
  let file = @fs.open(journal_path, mode=ReadWrite, append=false)
  defer file.close()
  file.lock(Exclusive)
  defer file.unlock()
  mooncode_repair_journal_tail(file)
  mooncode_stream_scan_locked(file, session_id, since)
}

///|
/// Parse the HTTP `since` boundary without converting its magnitude through a
/// machine integer. An absent value means the initial zero cursor.
fn mooncode_stream_query_cursor(
  since_text : String,
) -> MoonCodeJournalSequence raise MoonCodeGoalRuntimeStoreError {
  if since_text == "" {
    MoonCodeJournalSequence::zero()
  } else {
    mooncode_journal_cursor_parse(since_text)
  }
}

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
  let since_text = mooncode_request_string(r, "since", default="")
  let since = mooncode_stream_query_cursor(since_text) catch {
    _ =>
      raise json_error(400, "Bad Request", {
        "error": {
          "code": -1,
          "message": "MoonCode stream since must be a canonical nonnegative journal cursor",
          "metadata": { "since": since_text },
        },
      })
  }
  let format = mooncode_request_string(r, "format", default="jsonl")
  let wait_ms = mooncode_stream_wait_ms_value(
    mooncode_request_int(r, "wait_ms", default=0),
  )
  let poll_ms = mooncode_stream_poll_ms_value(
    mooncode_request_int(r, "poll_ms", default=100),
  )
  let wait = self.mooncode_stream_wait_for_summary(
    session_id, book_root, since, wait_ms, poll_ms,
  )
  let spool = mooncode_stream_create_spool(format, book_root, session_id, since)
  let summary = spool.summary
  let meta = mooncode_stream_meta_record(
    session_id,
    book_root,
    event_count=summary.event_count,
    since~,
    emitted_count=summary.eligible_event_count,
    latest_sequence=summary.latest_event_sequence,
    wait_ms~,
    poll_ms~,
    wait_elapsed_ms=wait.wait_elapsed_ms,
    wait_attempt_count=wait.wait_attempt_count,
  )
  let done = mooncode_stream_done_record(
    session_id,
    book_root,
    latest_sequence=summary.latest_event_sequence,
    since~,
    emitted_count=summary.eligible_event_count,
    wait_ms~,
    poll_ms~,
    wait_elapsed_ms=wait.wait_elapsed_ms,
    wait_attempt_count=wait.wait_attempt_count,
  )
  try mooncode_stream_deliver_spool(w, format, spool, meta, done) catch {
    error => {
      spool.cleanup()
      raise error
    }
  } noraise {
    _ => spool.cleanup()
  }
}

///|
async fn Daemon::mooncode_stream_wait_for_summary(
  self : Daemon,
  session_id : String,
  book_root : String,
  since : MoonCodeJournalSequence,
  wait_ms : Int,
  poll_ms : Int,
) -> MoonCodeStreamWait {
  ignore(self)
  let mut elapsed_ms = 0
  let mut attempt_count = 0
  let mut summary = mooncode_stream_summary(book_root, session_id, since)
  while wait_ms > 0 && summary.eligible_event_count == 0 && elapsed_ms < wait_ms {
    if @async.is_being_cancelled() {
      break
    }
    let remaining = wait_ms - elapsed_ms
    let delay = if remaining < poll_ms { remaining } else { poll_ms }
    @async.sleep(delay)
    elapsed_ms += delay
    attempt_count += 1
    let next_journal_size = mooncode_stream_journal_size(book_root, session_id)
    if next_journal_size != summary.journal_size {
      summary = mooncode_stream_summary(book_root, session_id, since)
    }
  }
  { wait_elapsed_ms: elapsed_ms, wait_attempt_count: attempt_count }
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
fn mooncode_stream_jsonl_payload(
  session_id : String,
  book_root : String,
  events : Array[Json],
  since~ : MoonCodeJournalSequence,
  wait_ms~ : Int,
  poll_ms~ : Int,
  wait_elapsed_ms~ : Int,
  wait_attempt_count~ : Int,
) -> String raise MoonCodeGoalRuntimeStoreError {
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
  since~ : MoonCodeJournalSequence,
  wait_ms~ : Int,
  poll_ms~ : Int,
  wait_elapsed_ms~ : Int,
  wait_attempt_count~ : Int,
) -> String raise MoonCodeGoalRuntimeStoreError {
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
  since~ : MoonCodeJournalSequence,
  wait_ms~ : Int,
  poll_ms~ : Int,
  wait_elapsed_ms~ : Int,
  wait_attempt_count~ : Int,
) -> Array[Json] raise MoonCodeGoalRuntimeStoreError {
  let latest_sequence = mooncode_stream_latest_sequence(events)
  let next_since = if since.compare(latest_sequence) >= 0 {
    since
  } else {
    latest_sequence
  }
  let emitted_count = mooncode_stream_event_count_after(events, since)
  let records : Array[Json] = [
    mooncode_stream_meta_record(
      session_id,
      book_root,
      event_count=events.length(),
      since~,
      emitted_count~,
      latest_sequence~,
      wait_ms~,
      poll_ms~,
      wait_elapsed_ms~,
      wait_attempt_count~,
    ),
  ]
  for index, event in events {
    let sequence = mooncode_stream_event_sequence(event, index)
    if sequence.compare(since) > 0 {
      records.push(
        mooncode_stream_event_record(
          session_id,
          book_root,
          event,
          sequence~,
          since~,
        ),
      )
    }
  }
  records.push(
    mooncode_stream_done_record(
      session_id,
      book_root,
      latest_sequence=next_since,
      since~,
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
fn mooncode_stream_event_sequence(
  event : Json,
  index : Int,
) -> MoonCodeJournalSequence raise MoonCodeGoalRuntimeStoreError {
  let value = match event {
    Object(fields) => fields.get("journal_sequence")
    _ => None
  }
  match value {
    Some(Number(_, repr=Some(raw))) => MoonCodeJournalSequence::parse(raw)
    Some(Number(_, repr=None) as number) =>
      MoonCodeJournalSequence::parse(number.stringify())
    Some(String(raw)) => MoonCodeJournalSequence::parse(raw)
    Some(_) =>
      mooncode_goal_runtime_store_corrupt(
        "stream event journal_sequence is not a number or string",
      )
    None => MoonCodeJournalSequence::parse("\{index + 1}")
  }
}

///|
fn mooncode_stream_latest_sequence(
  events : Array[Json],
) -> MoonCodeJournalSequence raise MoonCodeGoalRuntimeStoreError {
  let mut latest = MoonCodeJournalSequence::zero()
  for index, event in events {
    let sequence = mooncode_stream_event_sequence(event, index)
    if sequence.compare(latest) > 0 {
      latest = sequence
    }
  }
  latest
}

///|
fn mooncode_stream_event_count_after(
  events : Array[Json],
  since : MoonCodeJournalSequence,
) -> Int raise MoonCodeGoalRuntimeStoreError {
  let mut count = 0
  for index, event in events {
    if mooncode_stream_event_sequence(event, index).compare(since) > 0 {
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
  since~ : MoonCodeJournalSequence,
  emitted_count~ : Int,
  latest_sequence~ : MoonCodeJournalSequence,
  wait_ms~ : Int,
  poll_ms~ : Int,
  wait_elapsed_ms~ : Int,
  wait_attempt_count~ : Int,
) -> Json {
  let next_sequence = if latest_sequence.compare(since) >= 0 {
    latest_sequence
  } else {
    since
  }
  {
    "type": "meta",
    "contract_id": mooncode_stream_contract_id,
    "kind": "mooncode-stream-meta",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "event_count": event_count,
    "since": since.text(),
    "emitted_count": emitted_count,
    "latest_sequence": latest_sequence.text(),
    "next_since": next_sequence.text(),
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
  sequence~ : MoonCodeJournalSequence,
  since~ : MoonCodeJournalSequence,
) -> Json {
  {
    "type": "event",
    "contract_id": mooncode_stream_contract_id,
    "kind": "mooncode-stream-event",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "sequence": sequence.text(),
    "since": since.text(),
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
  latest_sequence~ : MoonCodeJournalSequence,
  since~ : MoonCodeJournalSequence,
  emitted_count~ : Int,
  wait_ms~ : Int,
  poll_ms~ : Int,
  wait_elapsed_ms~ : Int,
  wait_attempt_count~ : Int,
) -> Json {
  let next_sequence = if latest_sequence.compare(since) >= 0 {
    latest_sequence
  } else {
    since
  }
  {
    "type": "done",
    "contract_id": mooncode_stream_contract_id,
    "kind": "mooncode-stream-done",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "sequence": next_sequence.text(),
    "since": since.text(),
    "emitted_count": emitted_count,
    "next_since": next_sequence.text(),
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
