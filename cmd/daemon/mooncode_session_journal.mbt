///|
priv suberror MoonCodeJournalError {
  InvalidJournal(String)
}

///|
fn mooncode_journal_command() -> String {
  "command"
}

///|
fn mooncode_journal_runtime_receipt() -> String {
  "runtime-receipt"
}

///|
fn mooncode_journal_event() -> String {
  "event"
}

///|
fn mooncode_journal_package_result() -> String {
  "package-result"
}

///|
fn mooncode_journal_book_result() -> String {
  "book-result"
}

///|
fn mooncode_journal_goal_event() -> String {
  mooncode_journal_event()
}

///|
fn mooncode_validate_generic_journal_append(
  record_kind : String,
  payload : Json,
) -> Unit raise MoonCodeJournalError {
  if record_kind == mooncode_journal_event() {
    let kind = mooncode_json_string(payload, "kind", default="")
    let id = mooncode_json_string(payload, "id", default="")
    if kind.has_prefix("mooncode.goal.") ||
      kind.has_prefix("mooncode.goal.supervisor.") ||
      id.has_prefix("mooncode.goal.supervisor.") ||
      id == "goal-genesis-v1" {
      raise InvalidJournal(
        "Goal journal events must use the goal-specific atomic API",
      )
    }
  }
}

///|
async fn mooncode_append_session_journal(
  book_root : String,
  session_id : String,
  record_kind : String,
  payload : Json,
) -> Unit {
  ignore(
    mooncode_append_session_journal_once(
      book_root, session_id, record_kind, payload,
    ),
  )
}

///|
/// Finalize the canonical v2 envelope chosen by the production append scan.
/// Keeping exact successor selection here makes the unbounded write boundary
/// directly testable without constructing an impossibly large contiguous file.
fn mooncode_journal_record_for_append(
  session_id : String,
  record_kind : String,
  payload : Json,
  record_id : String,
  command_id : String,
  scan : MoonCodeJournalAppendScan,
) -> Json raise MoonCodeJournalError {
  let direct_client_turn_id = mooncode_journal_payload_client_turn_id(payload)
  let client_turn_id = if direct_client_turn_id != "" {
    direct_client_turn_id
  } else {
    scan.inherited_client_turn_id
  }
  let recorded_at = mooncode_journal_recorded_at(payload)
  if recorded_at is Null {
    raise InvalidJournal(
      "MoonCode journal record `\{record_id}` has no durable timestamp",
    )
  }
  mooncode_journal_record_v2(
    session_id~,
    sequence=scan.cursor.next(),
    record_id~,
    record_kind~,
    command_id~,
    client_turn_id~,
    recorded_at~,
    payload~,
  ) catch {
    MoonCodeGoalRuntimeStoreError::CorruptStore(message) =>
      raise InvalidJournal(
        "MoonCode journal record `\{record_id}` is invalid: \{message}",
      )
    MoonCodeGoalRuntimeStoreError::IdentityConflict(_, _, _) =>
      raise InvalidJournal(
        "MoonCode journal record `\{record_id}` has an unexpected identity conflict",
      )
  }
}

///|
/// Capture every directory from the journal leaf through the filesystem root.
/// Observed existence is not a durability proof: another process may have made
/// a parent visible and crashed before syncing its parent entry. Syncing the
/// complete chain avoids that cross-process first-creation race.
fn mooncode_journal_commit_directories(path : String) -> Array[String] {
  let directories : Array[String] = []
  let mut current = @pathx.dirname(path).to_owned()
  while true {
    directories.push(current)
    let parent = @pathx.dirname(current).to_owned()
    if parent == current {
      break
    }
    current = parent
  }
  directories
}

///|
/// Commit changed directory entries on platforms whose fsync contract supports
/// directory handles. The leaf-to-ancestor order covers recursively created
/// parents as well as the new journal entry.
#cfg(not(platform="windows"))
async fn mooncode_sync_journal_directories(directories : Array[String]) -> Unit {
  for path in directories {
    let directory = @fs.open(path, mode=ReadOnly)
    defer directory.close()
    directory.sync()
  }
}

///|
/// Windows FlushFileBuffers requires a writable file handle and does not offer
/// the POSIX directory-fsync primitive. The journal file flush below is the
/// supported commit boundary; directory sync is intentionally a no-op here.
#cfg(platform="windows")
async fn mooncode_sync_journal_directories(directories : Array[String]) -> Unit {
  ignore(directories)
}

///|
/// Commit file bytes first, then every supported affected directory entry from
/// the leaf through the filesystem anchor.
async fn mooncode_sync_journal_commit(
  file : @fs.File,
  directories : Array[String],
) -> Unit {
  file.sync(only_data=true)
  mooncode_sync_journal_directories(directories)
}

///|
priv enum MoonCodeJournalTransactionDecision[T] {
  NoAppend(T)
  Append(String, Json, T)
}

///|
/// Evaluate and append one record under the same lifecycle, session, and file
/// locks. The callback sees the exact committed prefix used to choose the
/// successor sequence.
async fn[T] mooncode_session_journal_transaction(
  book_root : String,
  session_id : String,
  decide : (Array[Json]) -> MoonCodeJournalTransactionDecision[T] raise,
) -> T {
  let lifecycle_gate = mooncode_open_session_lifecycle_gate(
    book_root, session_id,
  )
  defer lifecycle_gate.close()
  lifecycle_gate.lock(Shared)
  defer lifecycle_gate.unlock()
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Exclusive)
  defer session_lock.unlock()
  mooncode_require_active_session_state_locked(
    book_root,
    session_id,
    allow_create=true,
  )
  let path = mooncode_session_journal_path(book_root, session_id)
  let commit_directories = mooncode_journal_commit_directories(path)
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  let file = @fs.open(
    path,
    mode=ReadWrite,
    append=false,
    create=0o644,
    truncate=false,
  )
  defer file.close()
  file.lock(Exclusive)
  defer file.unlock()
  mooncode_repair_journal_tail(file)
  let records = mooncode_parse_journal_file(file, path, session_id)
  let last_sequence = mooncode_journal_last_sequence_exact(records)
  let identities : Array[(String, String)] = records.map(record => {
    (
      mooncode_json_string(record, "record_kind", default=""),
      mooncode_json_string(record, "record_id", default=""),
    )
  })
  let client_turn_inheritance : Array[(String, String)] = records.filter_map(record => {
    let command_id = mooncode_json_string(record, "command_id", default="")
    let client_turn_id = mooncode_json_string(
      record,
      "client_turn_id",
      default="",
    )
    if command_id != "" && client_turn_id != "" {
      Some((command_id, client_turn_id))
    } else {
      None
    }
  })
  match decide(records) {
    NoAppend(result) => result
    Append(record_kind, payload, result) => {
      let record_id = mooncode_journal_record_id(record_kind, payload)
      for identity in identities {
        let (existing_kind, existing_id) = identity
        if existing_kind == record_kind && existing_id == record_id {
          raise InvalidJournal(
            "MoonCode journal record identity already exists: `\{record_kind}`/`\{record_id}`",
          )
        }
      }
      let command_id = mooncode_journal_command_id(payload)
      let client_turn_id = mooncode_journal_client_turn_id_from_snapshot(
        payload, client_turn_inheritance, command_id,
      )
      let record = mooncode_journal_record_for_append(
        session_id,
        record_kind,
        payload,
        record_id,
        command_id,
        {
          cursor: last_sequence,
          duplicate_found: false,
          inherited_client_turn_id: client_turn_id,
        },
      )
      file.write(mooncode_journal_canonical_line(record) + "\n")
      mooncode_sync_journal_commit(file, commit_directories)
      result
    }
  }
}

///|
/// Append a validated journal record unless its stable identity already exists.
/// Returns true only when this call durably appended the record.
async fn mooncode_append_session_journal_once(
  book_root : String,
  session_id : String,
  record_kind : String,
  payload : Json,
) -> Bool {
  mooncode_validate_generic_journal_append(record_kind, payload)
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Exclusive)
  defer session_lock.unlock()
  mooncode_append_session_journal_once_locked(
    book_root, session_id, record_kind, payload,
  )
}

///|
/// Append while the caller already holds the stable external session lock.
async fn mooncode_append_session_journal_once_locked(
  book_root : String,
  session_id : String,
  record_kind : String,
  payload : Json,
) -> Bool {
  mooncode_require_active_session_state_locked(
    book_root,
    session_id,
    allow_create=true,
  )
  // Stable identity is the only payload validation required before duplicate lookup.
  // Existing records must remain retryable even when later validation rules tighten.
  let record_id = mooncode_journal_record_id(record_kind, payload)
  let path = mooncode_session_journal_path(book_root, session_id)
  let commit_directories = mooncode_journal_commit_directories(path)
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  let file = @fs.open(
    path,
    mode=ReadWrite,
    append=false,
    create=0o644,
    truncate=false,
  )
  defer file.close()
  file.lock(Exclusive)
  defer file.unlock()
  mooncode_repair_journal_tail(file)
  let command_id = mooncode_journal_command_id(payload)
  let scan = mooncode_journal_scan_for_append(
    file, session_id, record_kind, record_id, command_id,
  )
  // Duplicate suppression is deliberately delayed until the streaming scan has
  // validated every committed record through EOF.
  if scan.duplicate_found {
    // A retry may be observing bytes written before an earlier sync failed.
    // Re-establish durability before reporting the validated record as a duplicate.
    mooncode_sync_journal_commit(file, commit_directories)
    return false
  }
  let record = mooncode_journal_record_for_append(
    session_id, record_kind, payload, record_id, command_id, scan,
  )
  file.write(mooncode_journal_canonical_line(record) + "\n")
  mooncode_sync_journal_commit(file, commit_directories)
  true
}

///|
async fn mooncode_read_session_journal(
  book_root : String,
  session_id : String,
) -> Array[Json] {
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Shared)
  defer session_lock.unlock()
  mooncode_read_session_journal_path(
    mooncode_session_journal_path(book_root, session_id),
    session_id,
  )
}

///|
async fn mooncode_read_session_journal_path(
  path : String,
  expected_session_id : String,
) -> Array[Json] {
  if path == "" || !(@fsx.exists(path) catch { _ => false }) {
    return []
  }
  let file = @fs.open(path, mode=ReadWrite, append=false)
  defer file.close()
  file.lock(Exclusive)
  defer file.unlock()
  mooncode_repair_journal_tail(file)
  mooncode_parse_journal_file(file, path, expected_session_id)
}

///|
async fn mooncode_parse_journal_file(
  file : @fs.File,
  path : String,
  expected_session_id : String,
) -> Array[Json] {
  let records : Array[Json] = []
  let mut cursor = MoonCodeJournalSequence::zero()
  mooncode_journal_read_lines(file, async fn(line) {
    let (record, next) = mooncode_journal_stream_record(line, cursor) catch {
      InvalidJournal(message) =>
        raise InvalidJournal(
          "Invalid journal `\{path}` line \{records.length() + 1}: \{message}",
        )
      error => raise error
    }
    if mooncode_json_string(record, "session_id", default="") !=
      expected_session_id {
      raise InvalidJournal(
        "Invalid journal `\{path}` line \{records.length() + 1}: record belongs to a different session",
      )
    }
    records.push(record)
    cursor = next
  })
  records
}

///|
fn mooncode_parse_journal_text(
  text : String,
  path : String,
) -> Array[Json] raise MoonCodeJournalError {
  let records : Array[Json] = []
  // An empty committed prefix contains no records. This must be handled before
  // splitting because split produces one empty line, while blank lines in any
  // nonempty journal remain corruption.
  if text.is_empty() {
    return records
  }
  let lines = text.split("\n").collect()
  let line_count = if text.has_suffix("\n") {
    lines.length() - 1
  } else {
    lines.length()
  }
  let mut cursor = MoonCodeJournalSequence::zero()
  for index = 0; index < line_count; index = index + 1 {
    let line = lines[index]
    if line.is_empty() {
      raise InvalidJournal(
        "Invalid journal `\{path}` line \{index + 1}: blank line",
      )
    }
    try {
      let (record, next) = mooncode_journal_stream_record(
        line.to_owned(),
        cursor,
      )
      records.push(record)
      cursor = next
    } catch {
      error =>
        raise InvalidJournal(
          "Invalid journal `\{path}` line \{index + 1}: \{error}",
        )
    }
  }
  records
}

///|
fn mooncode_journal_sequence_checked(
  record : Json,
  context : String,
) -> MoonCodeJournalSequence raise MoonCodeJournalError {
  mooncode_journal_sequence_from_record(record) catch {
    MoonCodeGoalRuntimeStoreError::CorruptStore(message) =>
      raise InvalidJournal("\{context}: \{message}")
    MoonCodeGoalRuntimeStoreError::IdentityConflict(_, _, _) =>
      raise InvalidJournal("\{context}: unexpected journal identity conflict")
  }
}

///|
fn mooncode_journal_entries(
  records : Array[Json],
  record_kind : String,
) -> Array[Json] raise MoonCodeJournalError {
  let entries : Array[Json] = []
  for index, record in records {
    if mooncode_json_string(record, "record_kind", default="") == record_kind {
      let payload = mooncode_json_object_field_or_empty(record, "payload")
      entries.push(
        mooncode_json_object_with_field(
          payload,
          "journal_sequence",
          mooncode_journal_sequence_checked(
            record,
            "Invalid journal record \{index + 1}",
          )
          .text()
          .to_json(),
        ),
      )
    }
  }
  entries
}

///|
fn mooncode_journal_record_count(
  records : Array[Json],
  record_kind : String,
) -> Int {
  let mut count = 0
  for record in records {
    if mooncode_json_string(record, "record_kind", default="") == record_kind {
      count += 1
    }
  }
  count
}

///|
fn mooncode_journal_last_sequence_exact(
  records : Array[Json],
) -> MoonCodeJournalSequence raise MoonCodeJournalError {
  let mut sequence = MoonCodeJournalSequence::zero()
  for index, record in records {
    sequence = mooncode_journal_sequence_checked(
      record,
      "Invalid journal record \{index + 1}",
    )
  }
  sequence
}

///|
/// Compatibility projection for the legacy goal-supervisor contract, whose
/// basis sequence remains an Int.
fn mooncode_journal_last_sequence(
  records : Array[Json],
) -> Int raise MoonCodeJournalError {
  let text = mooncode_journal_last_sequence_exact(records).text()
  @string.parse_int(text) catch {
    _ =>
      raise InvalidJournal(
        "MoonCode goal supervisor sequence exceeds its legacy Int contract",
      )
  }
}

///|
fn mooncode_journal_sequence(record : Json) -> Int raise MoonCodeJournalError {
  match mooncode_journal_json_field(record, "sequence") {
    Some(Number(value, ..)) => {
      if value != value || value < 1.0 || value > 2147483647.0 {
        raise InvalidJournal("MoonCode journal record has invalid sequence")
      }
      let sequence = value.to_int()
      if sequence.to_double() != value {
        raise InvalidJournal("MoonCode journal record has invalid sequence")
      }
      sequence
    }
    Some(String(text)) => {
      let sequence = @string.parse_int(text) catch {
        _ =>
          raise InvalidJournal(
            "MoonCode goal supervisor sequence exceeds its legacy Int contract",
          )
      }
      if sequence < 1 || sequence.to_string() != text {
        raise InvalidJournal("MoonCode journal record has invalid sequence")
      }
      sequence
    }
    _ => raise InvalidJournal("MoonCode journal record has invalid sequence")
  }
}

///|
fn mooncode_journal_checked_next_sequence(
  last_sequence : Int,
) -> Int raise MoonCodeJournalError {
  if last_sequence == 2147483647 {
    raise InvalidJournal("MoonCode journal sequence is exhausted")
  }
  last_sequence + 1
}

///|
/// Return the byte boundary after the last newline-committed record without
/// materializing the aggregate file. A suffix after this boundary is torn.
async fn mooncode_newline_committed_size(file : @fs.File) -> Int64 {
  let size = file.size()
  if size == 0L {
    return 0L
  }
  if file.read_exactly_at(1, position=size - 1L) == b"\n" {
    return size
  }
  let mut cursor = size
  while cursor > 0L {
    let scan_length = if cursor > 4096L { 4096 } else { cursor.to_int() }
    let start = cursor - scan_length.to_int64()
    let chunk = file.read_exactly_at(scan_length, position=start)
    let mut index = chunk.length()
    while index > 0 {
      index -= 1
      if chunk[index].to_int() == 10 {
        return start + index.to_int64() + 1L
      }
    }
    cursor = start
  }
  0L
}

///|
async fn mooncode_repair_journal_tail(file : @fs.File) -> Unit {
  let size = file.size()
  let committed_size = mooncode_newline_committed_size(file)
  if committed_size == size {
    return
  }
  @moonclaw_fsx.truncate(file, committed_size)
  file.sync(only_data=true)
}

///|
fn mooncode_journal_record_id(
  record_kind : String,
  payload : Json,
) -> String raise MoonCodeJournalError {
  let direct_id = mooncode_json_string(payload, "id", default="")
  let payload_kind = mooncode_json_string(payload, "kind", default="")
  if record_kind == mooncode_journal_goal_event() &&
    payload_kind.has_prefix("mooncode.goal.") {
    let event_id = mooncode_json_string(payload, "event_id", default="")
    if event_id != "" {
      if event_id.trim() != event_id {
        raise InvalidJournal(
          "MoonCode logical goal event has invalid `event_id`",
        )
      }
      return "event:\{event_id}"
    }
    if direct_id == "" {
      raise InvalidJournal("MoonCode logical goal event has invalid `event_id`")
    }
  }
  if direct_id != "" {
    return "\{record_kind}:\{direct_id}"
  }
  let command_id = mooncode_journal_command_id(payload)
  if record_kind == mooncode_journal_command() {
    return "command:\{command_id}"
  }
  if record_kind == mooncode_journal_runtime_receipt() {
    return "runtime-receipt:\{command_id}:\{mooncode_json_string(payload, "status", default="unknown")}:\{mooncode_json_string(payload, "claim_id", default="unclaimed")}"
  }
  let result_id = mooncode_json_string(payload, "result_id", default="")
  if result_id != "" {
    return "\{record_kind}:\{result_id}"
  }
  let timestamp = mooncode_journal_recorded_at(payload).stringify()
  "\{record_kind}:\{command_id}:\{mooncode_json_string(payload, "kind", default="record")}:\{timestamp}"
}

///|
fn mooncode_journal_command_id(payload : Json) -> String {
  let direct = mooncode_json_string(payload, "command_id", default="")
  if direct != "" {
    return direct
  }
  let command = mooncode_json_object_field_or_empty(payload, "command")
  let nested = mooncode_command_id(command)
  if nested != "" {
    return nested
  }
  let command_entry = mooncode_json_object_field_or_empty(
    payload, "command_entry",
  )
  mooncode_runtime_command_entry_id(command_entry)
}

///|
fn mooncode_journal_client_turn_id_from_snapshot(
  payload : Json,
  inheritance : Array[(String, String)],
  command_id : String,
) -> String {
  let direct = mooncode_journal_payload_client_turn_id(payload)
  if direct != "" {
    return direct
  }
  if command_id == "" {
    return ""
  }
  for entry in inheritance {
    let (existing_command_id, client_turn_id) = entry
    if existing_command_id == command_id {
      return client_turn_id
    }
  }
  ""
}

///|
fn mooncode_journal_payload_client_turn_id(payload : Json) -> String {
  let direct = mooncode_json_string(payload, "client_turn_id", default="")
  if direct != "" {
    return direct
  }
  let command = mooncode_json_object_field_or_empty(payload, "command")
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let packet_id = mooncode_json_string(packet, "client_turn_id", default="")
  if packet_id != "" {
    return packet_id
  }
  let command_entry = mooncode_json_object_field_or_empty(
    payload, "command_entry",
  )
  let nested_command = mooncode_json_object_field_or_empty(
    command_entry, "command",
  )
  mooncode_json_string(
    mooncode_json_object_field_or_empty(nested_command, "packet"),
    "client_turn_id",
    default="",
  )
}

///|
fn mooncode_journal_recorded_at(payload : Json) -> Json {
  for key in ["created_at", "completed_at", "claimed_at", "recorded_at"] {
    match mooncode_journal_json_field(payload, key) {
      Some(Null) | None => ()
      Some(value) => return value
    }
  }
  Json::null()
}

///|
fn mooncode_journal_json_field(json : Json, key : String) -> Json? {
  match json {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
async fn mooncode_read_locked_file(path : String) -> String {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  file.lock(Shared)
  defer file.unlock()
  let size = file.size()
  if size == 0L {
    return ""
  }
  if size > 0x7fffffffL {
    raise InvalidJournal("MoonCode durable file is too large to read: \{path}")
  }
  @encoding/utf8.decode(file.read_exactly_at(size.to_int(), position=0L))
}

///|
async fn mooncode_write_locked_file(path : String, content : String) -> Unit {
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  let file = @fs.open(
    path,
    mode=ReadWrite,
    append=false,
    create=0o644,
    truncate=false,
  )
  defer file.close()
  file.lock(Exclusive)
  defer file.unlock()
  @moonclaw_fsx.truncate(file, 0L)
  file.write(content)
  file.sync()
}

///|
fn mooncode_session_journal_path(
  book_root : String,
  session_id : String,
) -> String {
  mooncode_session_dir(book_root, session_id) |> @pathx.join("journal.jsonl")
}

///|
fn mooncode_session_journal_path_by_safe_id(
  book_root : String,
  safe_session_id : String,
  archived? : Bool = false,
) -> String {
  mooncode_session_dir_by_safe_id(book_root, safe_session_id, archived~)
  |> @pathx.join("journal.jsonl")
}
