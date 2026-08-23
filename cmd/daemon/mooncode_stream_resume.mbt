///|
const MOONCODE_STREAM_RESUME_CONTRACT : String = "mooncode-stream-resume.v1"

///|
const MOONCODE_STREAM_RESUME_START : String = "start"

///|
const MOONCODE_STREAM_RESUME_DEFAULT_REPLAY_EVENTS : Int = 128

///|
const MOONCODE_STREAM_RESUME_MAX_REPLAY_EVENTS : Int = 512

///|
const MOONCODE_STREAM_RESUME_CURSOR_PART_HEX_CHARS : Int = 24

///|
const MOONCODE_STREAM_RESUME_CURSOR_MAX_CHARS : Int = 1024

///|
priv struct MoonCodeStreamResumeCursor {
  sequence : MoonCodeJournalSequence
  epoch : String
  token : String
  initial : Bool
}

///|
priv struct MoonCodeStreamResumeSummary {
  scanned_record_count : Int
  durable_event_count : Int
  visible_event_count : Int
  filtered_event_count : Int
  filtered_reasoning_count : Int
  eligible_event_count : Int
  replayed_event_count : Int
  latest_sequence : MoonCodeJournalSequence
  epoch : String
  journal_size : Int64
}

///|
priv struct MoonCodeStreamResumeSpool {
  directory : String
  path : String
  summary : MoonCodeStreamResumeSummary
}

///|
fn mooncode_stream_resume_digest(value : String) -> String {
  mooncode_goal_runtime_sha256_hex(value)[:MOONCODE_STREAM_RESUME_CURSOR_PART_HEX_CHARS].to_owned()
}

///|
fn mooncode_stream_resume_binding(
  session_id : String,
  book_root : String,
) -> String {
  mooncode_stream_resume_digest(
    MOONCODE_STREAM_RESUME_CONTRACT +
    "\nsession\n" +
    session_id +
    "\nbook\n" +
    book_root,
  )
}

///|
fn mooncode_stream_resume_empty_epoch() -> String {
  mooncode_stream_resume_digest(MOONCODE_STREAM_RESUME_CONTRACT + "\nempty")
}

///|
fn mooncode_stream_resume_cursor_checksum(
  binding : String,
  epoch : String,
  sequence : String,
) -> String {
  mooncode_stream_resume_digest(
    MOONCODE_STREAM_RESUME_CONTRACT +
    "\n" +
    binding +
    "\n" +
    epoch +
    "\n" +
    sequence,
  )
}

///|
fn mooncode_stream_resume_cursor_encode(
  session_id : String,
  book_root : String,
  epoch : String,
  sequence : MoonCodeJournalSequence,
) -> String {
  let binding = mooncode_stream_resume_binding(session_id, book_root)
  let sequence_text = sequence.text()
  "mcr1." +
  binding +
  "." +
  epoch +
  "." +
  sequence_text +
  "." +
  mooncode_stream_resume_cursor_checksum(binding, epoch, sequence_text)
}

///|
fn mooncode_stream_resume_hex_part_valid(value : String) -> Bool {
  value.length() == MOONCODE_STREAM_RESUME_CURSOR_PART_HEX_CHARS &&
  value.all(character => {
    character.is_ascii_digit() || (character >= 'a' && character <= 'f')
  })
}

///|
fn mooncode_stream_resume_cursor_parse(
  value : String,
  session_id : String,
  book_root : String,
) -> MoonCodeStreamResumeCursor raise MoonCodeGoalRuntimeStoreError {
  if value == MOONCODE_STREAM_RESUME_START {
    return {
      sequence: MoonCodeJournalSequence::zero(),
      epoch: "",
      token: value,
      initial: true,
    }
  }
  if value == "" || value.length() > MOONCODE_STREAM_RESUME_CURSOR_MAX_CHARS {
    return mooncode_goal_runtime_store_corrupt(
      "resume cursor has invalid length",
    )
  }
  let parts = value.split(".").to_array()
  guard parts.length() == 5 && parts[0] == "mcr1" else {
    return mooncode_goal_runtime_store_corrupt(
      "resume cursor has invalid shape",
    )
  }
  let binding = parts[1].to_owned()
  let epoch = parts[2].to_owned()
  let sequence_text = parts[3].to_owned()
  let checksum = parts[4].to_owned()
  guard mooncode_stream_resume_hex_part_valid(binding) &&
    mooncode_stream_resume_hex_part_valid(epoch) &&
    mooncode_stream_resume_hex_part_valid(checksum) else {
    return mooncode_goal_runtime_store_corrupt(
      "resume cursor has invalid digest",
    )
  }
  guard binding == mooncode_stream_resume_binding(session_id, book_root) else {
    return mooncode_goal_runtime_store_corrupt(
      "resume cursor belongs to another stream",
    )
  }
  let sequence = mooncode_journal_cursor_parse(sequence_text)
  guard checksum ==
    mooncode_stream_resume_cursor_checksum(binding, epoch, sequence.text()) else {
    return mooncode_goal_runtime_store_corrupt(
      "resume cursor checksum mismatch",
    )
  }
  { sequence, epoch, token: value, initial: false }
}

///|
fn mooncode_stream_resume_replay_limit(requested : Int) -> Int {
  if requested <= 0 {
    MOONCODE_STREAM_RESUME_DEFAULT_REPLAY_EVENTS
  } else {
    requested.min(MOONCODE_STREAM_RESUME_MAX_REPLAY_EVENTS)
  }
}

///|
fn mooncode_stream_resume_private_text(text : String) -> Bool {
  let lower = text.to_lower()
  [
    "artifact_path", "spool_path", "journal_jsonl", "working_directory", "file://",
    "/private/tmp/", "/var/folders/", "/tmp/", "/users/", "/home/", "/workspace/",
    "\\users\\", ".moonfort/", ".moonclaw/",
  ].any(marker => lower.contains(marker))
}

///|
fn mooncode_stream_resume_safe_label(text : String) -> String {
  let text = text.trim().to_owned()
  if text == "" || mooncode_stream_resume_private_text(text) {
    ""
  } else if text.length() > 256 {
    mooncode_utf8_prefix_within(text, 256)
  } else {
    text
  }
}

///|
fn mooncode_stream_resume_safe_text(text : String) -> String {
  let text = text.trim().to_owned()
  if text == "" {
    return ""
  }
  if mooncode_stream_resume_private_text(text) {
    return "Private sandbox path omitted from streamed output. Full evidence remains available through the validated workspace artifact contract."
  }
  if text.length() > MOONCODE_DEFAULT_TOOL_OUTPUT_CHARS {
    mooncode_utf8_prefix_within(text, MOONCODE_DEFAULT_TOOL_OUTPUT_CHARS) +
    "\n...[stream output truncated by the named MoonCode output policy]"
  } else {
    text
  }
}

///|
fn mooncode_stream_resume_event_kind(event : Json) -> String {
  let kind = mooncode_json_string(event, "kind", default="")
  if kind != "" {
    kind
  } else {
    mooncode_json_string(event, "event", default="")
  }
}

///|
fn mooncode_stream_resume_project_event(event : Json) -> Json? {
  let kind = mooncode_stream_resume_event_kind(event)
  let event_name = mooncode_json_string(event, "event", default=kind)
  let command_id = mooncode_stream_resume_safe_label(
    mooncode_json_string(event, "command_id", default=""),
  )
  let status = mooncode_json_string(event, "status", default="")
  let created_at = match event {
    Object(fields) => fields.get("created_at").unwrap_or(Json::null())
    _ => Json::null()
  }
  if kind == "reasoning_delta" ||
    kind == "reasoning_message" ||
    event_name == "reasoning_delta" ||
    event_name == "reasoning_message" {
    return None
  }
  if kind == "assistant_delta" || event_name == "assistant_delta" {
    let content = mooncode_stream_resume_safe_text(
      mooncode_conversation_event_content(event),
    )
    if content == "" {
      return None
    }
    return Some({
      "content_kind": "assistant",
      "command_id": command_id,
      "status": if status == "" {
        "running"
      } else {
        status
      },
      "content": content,
      "created_at": created_at,
    })
  }
  if kind == "finish" || event_name == "finish" {
    let content = mooncode_stream_resume_safe_text(
      mooncode_conversation_event_assistant_content(event),
    )
    if content == "" {
      return None
    }
    return Some({
      "content_kind": "assistant",
      "command_id": command_id,
      "status": "done",
      "content": content,
      "created_at": created_at,
    })
  }
  if kind == "runtime.turn_started" ||
    kind == "runtime.planner_started" ||
    kind == "runtime.planner_selected" ||
    kind == "runtime.planner_failed" ||
    kind == "runtime.turn_checkpointed" ||
    kind == "runtime.turn_finished" {
    return Some({
      "content_kind": "planner",
      "command_id": command_id,
      "phase": kind,
      "status": if status == "" {
        "running"
      } else {
        status
      },
      "created_at": created_at,
    })
  }
  let lane = mooncode_json_string(event, "lane", default="")
  if kind == mooncode_event_tool_call() ||
    event_name == mooncode_event_tool_call() ||
    event_name == "tool_result" ||
    kind == "tool_result" ||
    kind == mooncode_event_test_result() ||
    kind == mooncode_event_package_built() ||
    lane == "test" ||
    lane == "diff" ||
    lane == "artifact" {
    let tool_result = mooncode_json_object_field_or_empty(event, "tool_result")
    let output = mooncode_stream_resume_safe_text(
      mooncode_conversation_first_text(
        mooncode_json_string(tool_result, "output", default=""),
        mooncode_conversation_first_text(
          mooncode_json_string(event, "output", default=""),
          mooncode_json_string(event, "detail", default=""),
        ),
      ),
    )
    return Some({
      "content_kind": "tool_output",
      "command_id": command_id,
      "tool_name": mooncode_stream_resume_safe_label(
        mooncode_conversation_first_text(
          mooncode_json_string(event, "tool", default=""),
          mooncode_json_string(event, "tool_name", default=""),
        ),
      ),
      "status": if status == "" {
        "done"
      } else {
        status
      },
      "output": output,
      "truncated": mooncode_json_bool(
        mooncode_json_object_field_or_empty(tool_result, "metadata"),
        "truncated",
        default=mooncode_json_bool(event, "truncated", default=false),
      ),
      "created_at": created_at,
    })
  }
  None
}

///|
fn mooncode_stream_resume_event_record(
  session_id : String,
  book_root : String,
  epoch : String,
  sequence : MoonCodeJournalSequence,
  event_id : String,
  projected : Json,
) -> Json {
  let cursor = mooncode_stream_resume_cursor_encode(
    session_id, book_root, epoch, sequence,
  )
  {
    "type": "event",
    "contract_id": MOONCODE_STREAM_RESUME_CONTRACT,
    "kind": "mooncode-stream-resume-event",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "sequence": sequence.text(),
    "resume_cursor": cursor,
    "event_id": mooncode_stream_resume_safe_label(event_id),
    "content_kind": mooncode_json_string(
      projected,
      "content_kind",
      default="tool_output",
    ),
    "event": projected,
  }
}

///|
async fn mooncode_stream_resume_scan_locked(
  file : @fs.File,
  writer : @fs.File?,
  format : String,
  session_id : String,
  book_root : String,
  requested : MoonCodeStreamResumeCursor,
  replay_limit : Int,
) -> MoonCodeStreamResumeSummary {
  let mut cursor = MoonCodeJournalSequence::zero()
  let mut epoch = mooncode_stream_resume_empty_epoch()
  let mut scanned_record_count = 0
  let mut durable_event_count = 0
  let mut visible_event_count = 0
  let mut filtered_event_count = 0
  let mut filtered_reasoning_count = 0
  let mut eligible_event_count = 0
  let mut replayed_event_count = 0
  mooncode_journal_read_lines(file, async fn(line) {
    let (record, next) = mooncode_journal_stream_record(line, cursor)
    if mooncode_json_string(record, "session_id", default="") != session_id {
      raise InvalidJournal("journal record belongs to a different session")
    }
    if scanned_record_count == 0 {
      epoch = mooncode_stream_resume_digest(
        MOONCODE_STREAM_RESUME_CONTRACT + "\nepoch\n" + line,
      )
    }
    scanned_record_count += 1
    cursor = next
    if mooncode_json_string(record, "record_kind", default="") !=
      mooncode_journal_event() {
      return
    }
    durable_event_count += 1
    let event = mooncode_json_object_with_field(
      mooncode_json_object_field_or_empty(record, "payload"),
      "journal_sequence",
      next.text().to_json(),
    )
    let projected = mooncode_stream_resume_project_event(event)
    if projected is None {
      filtered_event_count += 1
      let kind = mooncode_stream_resume_event_kind(event)
      if kind == "reasoning_delta" || kind == "reasoning_message" {
        filtered_reasoning_count += 1
      }
      return
    }
    visible_event_count += 1
    if next.compare(requested.sequence) <= 0 {
      return
    }
    eligible_event_count += 1
    if eligible_event_count <= replay_limit && writer is Some(output) {
      replayed_event_count += 1
      output.write(
        mooncode_stream_record_frame(
          format,
          mooncode_stream_resume_event_record(
            session_id,
            book_root,
            epoch,
            next,
            mooncode_json_string(event, "id", default=""),
            projected.unwrap(),
          ),
        ),
      )
    }
  })
  {
    scanned_record_count,
    durable_event_count,
    visible_event_count,
    filtered_event_count,
    filtered_reasoning_count,
    eligible_event_count,
    replayed_event_count,
    latest_sequence: cursor,
    epoch,
    journal_size: file.size(),
  }
}

///|
async fn mooncode_stream_resume_scan(
  book_root : String,
  session_id : String,
  requested : MoonCodeStreamResumeCursor,
  replay_limit : Int,
  writer? : @fs.File,
  format? : String = "jsonl",
) -> MoonCodeStreamResumeSummary {
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Shared)
  defer session_lock.unlock()
  let journal_path = mooncode_session_journal_path(book_root, session_id)
  if !(@fsx.exists(journal_path) catch { _ => false }) {
    return {
      scanned_record_count: 0,
      durable_event_count: 0,
      visible_event_count: 0,
      filtered_event_count: 0,
      filtered_reasoning_count: 0,
      eligible_event_count: 0,
      replayed_event_count: 0,
      latest_sequence: MoonCodeJournalSequence::zero(),
      epoch: mooncode_stream_resume_empty_epoch(),
      journal_size: -1L,
    }
  }
  let file = @fs.open(journal_path, mode=ReadWrite, append=false)
  defer file.close()
  file.lock(Exclusive)
  defer file.unlock()
  mooncode_repair_journal_tail(file)
  mooncode_stream_resume_scan_locked(
    file, writer, format, session_id, book_root, requested, replay_limit,
  )
}

///|
fn mooncode_stream_resume_status(
  requested : MoonCodeStreamResumeCursor,
  summary : MoonCodeStreamResumeSummary,
  replay_limit : Int,
) -> String {
  if requested.sequence.compare(summary.latest_sequence) > 0 {
    return "future"
  }
  if !requested.initial &&
    requested.sequence.compare(MoonCodeJournalSequence::zero()) > 0 &&
    requested.epoch != summary.epoch {
    return "expired"
  }
  if summary.eligible_event_count > replay_limit {
    return "gap"
  }
  "ok"
}

///|
fn mooncode_stream_resume_metrics(
  summary : MoonCodeStreamResumeSummary,
  replay_limit : Int,
  status : String,
  wait : MoonCodeStreamWait,
) -> Json {
  {
    "contract_id": "mooncode-stream-resume-metrics.v1",
    "resume_status": status,
    "replay_limit": replay_limit,
    "scanned_record_count": summary.scanned_record_count,
    "durable_event_count": summary.durable_event_count,
    "visible_event_count": summary.visible_event_count,
    "filtered_event_count": summary.filtered_event_count,
    "filtered_reasoning_count": summary.filtered_reasoning_count,
    "eligible_event_count": summary.eligible_event_count,
    "replayed_event_count": summary.replayed_event_count,
    "resume_lag_events": summary.eligible_event_count,
    "gap_detected": status == "gap",
    "cursor_expired": status == "expired",
    "cursor_future": status == "future",
    "wait_elapsed_ms": wait.wait_elapsed_ms,
    "wait_attempt_count": wait.wait_attempt_count,
  }
}

///|
fn mooncode_stream_resume_meta_record(
  session_id : String,
  book_root : String,
  requested : MoonCodeStreamResumeCursor,
  summary : MoonCodeStreamResumeSummary,
  replay_limit : Int,
  wait : MoonCodeStreamWait,
) -> Json {
  {
    "type": "meta",
    "contract_id": MOONCODE_STREAM_RESUME_CONTRACT,
    "kind": "mooncode-stream-resume-meta",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "requested_cursor": requested.token,
    "resume_cursor": mooncode_stream_resume_cursor_encode(
      session_id,
      book_root,
      summary.epoch,
      requested.sequence,
    ),
    "latest_sequence": summary.latest_sequence.text(),
    "emitted_count": summary.replayed_event_count,
    "metrics": mooncode_stream_resume_metrics(summary, replay_limit, "ok", wait),
  }
}

///|
fn mooncode_stream_resume_done_record(
  session_id : String,
  book_root : String,
  requested : MoonCodeStreamResumeCursor,
  summary : MoonCodeStreamResumeSummary,
  replay_limit : Int,
  wait : MoonCodeStreamWait,
) -> Json {
  {
    "type": "done",
    "contract_id": MOONCODE_STREAM_RESUME_CONTRACT,
    "kind": "mooncode-stream-resume-done",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "requested_cursor": requested.token,
    "sequence": summary.latest_sequence.text(),
    "resume_cursor": mooncode_stream_resume_cursor_encode(
      session_id,
      book_root,
      summary.epoch,
      summary.latest_sequence,
    ),
    "emitted_count": summary.replayed_event_count,
    "metrics": mooncode_stream_resume_metrics(summary, replay_limit, "ok", wait),
  }
}

///|
async fn MoonCodeStreamResumeSpool::cleanup(
  self : MoonCodeStreamResumeSpool,
) -> Unit {
  @fs.rmdir(self.directory, recursive=true) catch {
    _ => ()
  }
}

///|
async fn mooncode_stream_resume_create_spool(
  format : String,
  book_root : String,
  session_id : String,
  requested : MoonCodeStreamResumeCursor,
  replay_limit : Int,
) -> MoonCodeStreamResumeSpool {
  let directory = @fs.tmpdir(prefix="mooncode-resume-stream")
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
  let summary = mooncode_stream_resume_scan(
    book_root,
    session_id,
    requested,
    replay_limit,
    writer~,
    format~,
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
async fn mooncode_stream_resume_deliver(
  w : @httpx.ResponseWriter,
  format : String,
  spool : MoonCodeStreamResumeSpool,
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
    w.write(mooncode_stream_record_frame(format, meta))
    w.write_reader(reader)
    w.write(mooncode_stream_record_frame(format, done))
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

///|
async fn Daemon::mooncode_stream_resume(
  self : Daemon,
  session_id : String,
  book_root : String,
  cursor_text : String,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let requested = mooncode_stream_resume_cursor_parse(
    cursor_text, session_id, book_root,
  ) catch {
    _ =>
      raise json_error(400, "Bad Request", {
        "error": {
          "code": -1,
          "message": "MoonCode resume cursor is malformed or belongs to another stream",
          "metadata": {
            "contract_id": MOONCODE_STREAM_RESUME_CONTRACT,
            "resume_status": "rejected",
          },
        },
      })
  }
  let format = mooncode_request_string(r, "format", default="jsonl")
  if format != "jsonl" && format != "sse" {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": "MoonCode resume stream format must be jsonl or sse",
      },
    })
  }
  let replay_limit = mooncode_stream_resume_replay_limit(
    mooncode_request_int(
      r,
      "replay_limit",
      default=MOONCODE_STREAM_RESUME_DEFAULT_REPLAY_EVENTS,
    ),
  )
  let wait_ms = mooncode_stream_wait_ms_value(
    mooncode_request_int(r, "wait_ms", default=0),
  )
  let poll_ms = mooncode_stream_poll_ms_value(
    mooncode_request_int(r, "poll_ms", default=100),
  )
  let mut wait = MoonCodeStreamWait::{
    wait_elapsed_ms: 0,
    wait_attempt_count: 0,
  }
  let mut summary = mooncode_stream_resume_scan(
    book_root, session_id, requested, replay_limit,
  )
  let mut status = mooncode_stream_resume_status(
    requested, summary, replay_limit,
  )
  while status == "ok" &&
        wait_ms > 0 &&
        summary.eligible_event_count == 0 &&
        wait.wait_elapsed_ms < wait_ms {
    if @async.is_being_cancelled() {
      break
    }
    let remaining = wait_ms - wait.wait_elapsed_ms
    let delay = if remaining < poll_ms { remaining } else { poll_ms }
    @async.sleep(delay)
    wait = {
      wait_elapsed_ms: wait.wait_elapsed_ms + delay,
      wait_attempt_count: wait.wait_attempt_count + 1,
    }
    let size = mooncode_stream_journal_size(book_root, session_id)
    if size != summary.journal_size {
      summary = mooncode_stream_resume_scan(
        book_root, session_id, requested, replay_limit,
      )
      status = mooncode_stream_resume_status(requested, summary, replay_limit)
    }
  }
  if status != "ok" {
    let latest_cursor = mooncode_stream_resume_cursor_encode(
      session_id,
      book_root,
      summary.epoch,
      summary.latest_sequence,
    )
    raise json_error(409, "Conflict", {
      "error": {
        "code": -1,
        "message": match status {
          "gap" =>
            "MoonCode resume replay window was exceeded; reload the conversation snapshot"
          "expired" =>
            "MoonCode resume cursor expired after the durable stream epoch changed"
          _ => "MoonCode resume cursor is ahead of the durable stream"
        },
        "metadata": {
          "contract_id": MOONCODE_STREAM_RESUME_CONTRACT,
          "resume_status": status,
          "recovery": "reload_snapshot",
          "latest_cursor": latest_cursor,
          "metrics": mooncode_stream_resume_metrics(
            summary, replay_limit, status, wait,
          ),
        },
      },
    })
  }
  let spool = mooncode_stream_resume_create_spool(
    format, book_root, session_id, requested, replay_limit,
  )
  let final_status = mooncode_stream_resume_status(
    requested,
    spool.summary,
    replay_limit,
  )
  if final_status != "ok" {
    spool.cleanup()
    raise json_error(409, "Conflict", {
      "error": {
        "code": -1,
        "message": "MoonCode resume stream changed while preparing replay; reconnect from the returned cursor",
        "metadata": {
          "contract_id": MOONCODE_STREAM_RESUME_CONTRACT,
          "resume_status": final_status,
          "recovery": "reload_snapshot",
          "latest_cursor": mooncode_stream_resume_cursor_encode(
            session_id,
            book_root,
            spool.summary.epoch,
            spool.summary.latest_sequence,
          ),
          "metrics": mooncode_stream_resume_metrics(
            spool.summary,
            replay_limit,
            final_status,
            wait,
          ),
        },
      },
    })
  }
  let meta = mooncode_stream_resume_meta_record(
    session_id,
    book_root,
    requested,
    spool.summary,
    replay_limit,
    wait,
  )
  let done = mooncode_stream_resume_done_record(
    session_id,
    book_root,
    requested,
    spool.summary,
    replay_limit,
    wait,
  )
  try mooncode_stream_resume_deliver(w, format, spool, meta, done) catch {
    error => {
      spool.cleanup()
      raise error
    }
  } noraise {
    _ => spool.cleanup()
  }
  ignore(self)
}
