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
async fn mooncode_stream_create_spool(
  format : String,
  book_root : String,
  session_id : String,
  since : MoonCodeJournalSequence,
) -> MoonCodeStreamSpool {
  let directory = @fs.tmpdir(prefix="mooncode-stream")
  errdefer (@fs.rmdir(directory, recursive=true) catch { _ => () })
  let path = @pathx.join(directory, "events.spool")
  let writer = @fs.open(
    path,
    mode=WriteOnly,
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  defer writer.close()
  let summary = mooncode_stream_scan(book_root, session_id, since, emit=async fn(
    sequence,
    event,
  ) {
    writer.write(
      mooncode_stream_record_frame(
        format,
        mooncode_stream_event_record(
          session_id,
          book_root,
          event,
          sequence~,
          since~,
        ),
      ),
    )
  })
  { directory, path, summary, }
}

///|
async fn MoonCodeStreamSpool::cleanup(self : MoonCodeStreamSpool) -> Unit {
  @fs.rmdir(self.directory, recursive=true) catch {
    _ => ()
  }
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
  defer reader.close()
  if format == "sse" {
    w.header().set("Content-Type", "text/event-stream")
    w.header().set("Cache-Control", "no-cache")
  } else {
    w.header().set("Content-Type", "application/x-ndjson")
  }
  w.write_header(200)
  w.write(mooncode_stream_record_frame(format, meta))
  w.write_reader(reader)
  w.write(mooncode_stream_record_frame(format, done))
  w.flush()
}
