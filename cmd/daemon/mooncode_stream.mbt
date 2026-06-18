///|
async fn Daemon::mooncode_stream(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let session_id = session_id.to_owned()
  let binding = self.mooncode_sessions.get(session_id)
  let requested_book_root = mooncode_request_book_root(r)
  let book_root = if requested_book_root != "" {
    requested_book_root
  } else {
    match binding {
      Some(binding) => binding.book_root
      None => ""
    }
  }
  if book_root == "" {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": "MoonCode stream requires book_root query or an existing live binding",
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
    binding, session_id, book_root, since, wait_ms, poll_ms,
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
  binding : MoonCodeSessionBinding?,
  session_id : String,
  book_root : String,
  since : Int,
  wait_ms : Int,
  poll_ms : Int,
) -> Json {
  let mut elapsed_ms = 0
  let mut attempt_count = 0
  let mut events = self.mooncode_stream_current_events(
    binding, book_root, session_id,
  )
  while wait_ms > 0 && events.length() <= since && elapsed_ms < wait_ms {
    if @async.is_being_cancelled() {
      break
    }
    let remaining = wait_ms - elapsed_ms
    let delay = if remaining < poll_ms { remaining } else { poll_ms }
    @async.sleep(delay)
    elapsed_ms += delay
    attempt_count += 1
    events = self.mooncode_stream_current_events(binding, book_root, session_id)
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
    "ready": events.length() > since,
    "event_count": events.length(),
    "events": Json::array(events),
  }
}

///|
async fn Daemon::mooncode_stream_current_events(
  self : Daemon,
  binding : MoonCodeSessionBinding?,
  book_root : String,
  session_id : String,
) -> Array[Json] {
  match binding {
    Some(binding) => self.mooncode_sync_live_task_events(binding)
    None => ()
  }
  mooncode_read_jsonl(mooncode_events_path(book_root, session_id))
}

///|
async fn Daemon::mooncode_sync_live_task_events(
  self : Daemon,
  binding : MoonCodeSessionBinding,
) -> Unit {
  match self.by_id.get(binding.task_id) {
    Some(Running(task)) => {
      let mut persisted_task_event_count = binding.persisted_task_event_count
      for index, event in task.broadcast.values() {
        let mooncode_event = mooncode_event_from_task_stream(
          session_id=binding.session_id,
          command_id=binding.last_command_id,
          task_id=task.id.to_string(),
          event,
          index~,
        )
        if index >= binding.persisted_task_event_count {
          self.mooncode_persist_event(binding, mooncode_event)
          persisted_task_event_count = index + 1
        }
      }
      if persisted_task_event_count != binding.persisted_task_event_count {
        binding.persisted_task_event_count = persisted_task_event_count
        binding.last_updated = self.clock.now()
        self.mooncode_persist_session(binding)
      }
    }
    _ => ()
  }
}

///|
fn mooncode_stream_jsonl_payload(
  session_id : String,
  book_root : String,
  events : Array[Json],
  since? : Int = 0,
  wait_ms? : Int = 0,
  poll_ms? : Int = 100,
  wait_elapsed_ms? : Int = 0,
  wait_attempt_count? : Int = 0,
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
  since? : Int = 0,
  wait_ms? : Int = 0,
  poll_ms? : Int = 100,
  wait_elapsed_ms? : Int = 0,
  wait_attempt_count? : Int = 0,
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
  since? : Int = 0,
  wait_ms? : Int = 0,
  poll_ms? : Int = 100,
  wait_elapsed_ms? : Int = 0,
  wait_attempt_count? : Int = 0,
) -> Array[Json] {
  let latest_sequence = events.length()
  let clamped_since = if since < 0 {
    0
  } else if since > latest_sequence {
    latest_sequence
  } else {
    since
  }
  let emitted_count = latest_sequence - clamped_since
  let records : Array[Json] = [
    mooncode_stream_meta_record(
      session_id,
      book_root,
      event_count=latest_sequence,
      since=clamped_since,
      emitted_count~,
      latest_sequence~,
      wait_ms~,
      poll_ms~,
      wait_elapsed_ms~,
      wait_attempt_count~,
    ),
  ]
  for index in clamped_since..<events.length() {
    records.push(
      mooncode_stream_event_record(
        session_id,
        book_root,
        events[index],
        sequence=index + 1,
        since=clamped_since,
      ),
    )
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

///|
fn mooncode_event_from_task_stream(
  session_id~ : String,
  command_id~ : String,
  task_id~ : String,
  event : @server.ServerStreamEvent,
  index~ : Int,
) -> Json {
  match event {
    @server.Moonclaw({ id, created, desc }) => {
      let desc_json = desc.to_json()
      let msg = mooncode_json_string(desc_json, "msg", default="")
      {
        "id": "moonclaw-\{session_id}-\{task_id}-task-event-\{index}",
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "command_id": command_id,
        "task_id": task_id,
        "lane": mooncode_task_event_lane(msg),
        "kind": mooncode_task_event_kind(msg),
        "title": mooncode_task_event_title(msg),
        "status": mooncode_task_event_status(msg),
        "detail": mooncode_task_event_detail(desc_json),
        "rendered_text": mooncode_task_event_rendered_text(desc_json),
        "structured_result": mooncode_task_event_structured_result(desc_json),
        "created_at": created,
        "source": "moonclaw-task-stream",
        "moonclaw_event_id": id,
        "moonclaw_event": desc_json,
      }
    }
    @server.MoonclawQueuedMessagesSynchronized(messages) =>
      {
        "id": "moonclaw-\{session_id}-\{task_id}-queued-\{index}",
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "command_id": command_id,
        "task_id": task_id,
        "lane": "runtime",
        "kind": "runtime.queue_synchronized",
        "title": "MoonClaw queued messages synchronized",
        "status": "running",
        "detail": "MoonClaw task has \{messages.length()} queued message(s)",
        "created_at": @clock.epoch.now(),
        "source": "moonclaw-task-stream",
        "queued_messages": messages,
      }
  }
}
