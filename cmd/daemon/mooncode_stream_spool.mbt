///|
fn mooncode_stream_record_frame(format : String, record : Json) -> String {
  if format == "sse" {
    "event: " +
    mooncode_json_string(record, "type", default="message") +
    "\ndata: " +
    record.stringify() +
    "\n\n"
  } else {
    record.stringify() + "\n"
  }
}

///|
async fn mooncode_stream_spool_scan_locked(
  file : @fs.File,
  writer : @fs.File,
  format : String,
  book_root : String,
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
      event_count += 1
      latest_event_sequence = next
      if next.compare(since) > 0 {
        eligible_event_count += 1
        let event = mooncode_json_object_with_field(
          mooncode_json_object_field_or_empty(record, "payload"),
          "journal_sequence",
          next.text().to_json(),
        )
        let stream_record = mooncode_stream_event_record(
          expected_session_id,
          book_root,
          event,
          sequence=next,
          since~,
        )
        writer.write(mooncode_stream_record_frame(format, stream_record))
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
async fn mooncode_stream_spool_summary(
  writer : @fs.File,
  format : String,
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
  mooncode_stream_spool_scan_locked(
    file, writer, format, book_root, session_id, since,
  )
}

///|
async fn mooncode_stream_create_spool(
  format : String,
  book_root : String,
  session_id : String,
  since : MoonCodeJournalSequence,
) -> MoonCodeStreamSpool {
  let directory = @fs.tmpdir(prefix="mooncode-stream")
  let path = @pathx.join(directory, "events.spool")
  let writer = @fs.open(
    path,
    mode=WriteOnly,
    create_mode=CreateOrTruncate,
    permission=0o600,
  ) catch {
    error => {
      @fs.rmdir(directory, recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  let summary = mooncode_stream_spool_summary(
    writer, format, book_root, session_id, since,
  ) catch {
    error => {
      writer.close()
      @fs.rmdir(directory, recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  writer.close()
  { directory, path, summary }
}

///|
async fn MoonCodeStreamSpool::cleanup(self : MoonCodeStreamSpool) -> Unit {
  @fs.rmdir(self.directory, recursive=true) catch {
    _ => ()
  }
}

///|
async fn mooncode_stream_write_record(
  w : @httpx.ResponseWriter,
  format : String,
  record : Json,
) -> Unit {
  w.write(mooncode_stream_record_frame(format, record))
}

///|
async fn mooncode_stream_deliver_spool(
  w : @httpx.ResponseWriter,
  format : String,
  spool : MoonCodeStreamSpool,
  meta : Json,
  done : Json,
) -> Unit {
  let reader = @fs.open(spool.path, mode=ReadOnly)
  try {
    if format == "sse" {
      w.header().set("Content-Type", "text/event-stream")
      w.header().set("Cache-Control", "no-cache")
    } else {
      w.header().set("Content-Type", "application/x-ndjson")
    }
    w.write_header(200)
    mooncode_stream_write_record(w, format, meta)
    w.write_reader(reader)
    mooncode_stream_write_record(w, format, done)
    w.flush()
  } catch {
    error => {
      reader.close()
      raise error
    }
  } noraise {
    _ => reader.close()
  }
}
