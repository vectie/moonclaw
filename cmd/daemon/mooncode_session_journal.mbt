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
priv enum MoonCodeJournalTransactionDecision[T] {
  NoAppend(T)
  Append(String, Json, T)
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
async fn[T] mooncode_session_journal_transaction(
  book_root : String,
  session_id : String,
  decide : (Array[Json]) -> MoonCodeJournalTransactionDecision[T] raise,
) -> T {
  let path = mooncode_session_journal_path(book_root, session_id)
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  let file = @fs.open(
    path,
    mode=ReadWrite,
    append=true,
    create=0o644,
    truncate=false,
  )
  defer file.close()
  file.lock(Exclusive)
  defer file.unlock()
  mooncode_repair_journal_tail(file)
  let records = mooncode_parse_journal_file(file, path)
  // Snapshot this before the callback: Json arrays are mutable, and durability must
  // reflect whether the committed journal had any records when the lock was acquired.
  let was_empty = records.is_empty()
  let last_sequence = mooncode_journal_last_sequence(records)
  let identities : Array[(String, String)] = records.map(fn(record) {
    (
      mooncode_json_string(record, "record_kind", default=""),
      mooncode_json_string(record, "record_id", default=""),
    )
  })
  let client_turn_inheritance : Array[(String, String)] = records.filter_map(fn(
    record,
  ) {
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
      let sequence = mooncode_journal_checked_next_sequence(last_sequence)
      let command_id = mooncode_journal_command_id(payload)
      let client_turn_id = mooncode_journal_client_turn_id_from_snapshot(
        payload, client_turn_inheritance, command_id,
      )
      let recorded_at = mooncode_journal_recorded_at(payload)
      if recorded_at is Null {
        raise InvalidJournal(
          "MoonCode journal record `\{record_id}` has no durable timestamp",
        )
      }
      let record = @moonlib_conversation.journal_record(
        session_id~,
        sequence~,
        record_id~,
        record_kind~,
        command_id~,
        client_turn_id~,
        recorded_at~,
        payload~,
      )
      let issues = @moonlib_conversation.journal_record_issues(record)
      if !issues.is_empty() {
        raise InvalidJournal(
          "MoonCode journal rejected `\{record_id}`: \{issues.join("; ")}",
        )
      }
      file.write(record.stringify() + "\n")
      // Full sync is the strongest portable file guarantee for the first record;
      // existing-file appends need only synchronize data. No public portable API
      // is available here to fsync the parent directory namespace entry.
      file.sync(only_data=!was_empty)
      result
    }
  }
}

///|
/// Append a validated journal record unless its stable identity already exists.
/// Returns true only when this call has appended and synchronized the record: a full
/// file sync for its first record, and a data-only sync for an existing journal.
/// Parent-directory namespace durability is not promised because no public portable
/// directory-fsync API is available.
async fn mooncode_append_session_journal_once(
  book_root : String,
  session_id : String,
  record_kind : String,
  payload : Json,
) -> Bool {
  mooncode_session_journal_transaction(book_root, session_id, fn(
    records,
  ) raise {
    // Json objects are mutable. Derive identity only after the transaction lock is held,
    // so duplicate lookup and the eventual record construction observe one no-yield state.
    let record_id = mooncode_journal_record_id(record_kind, payload)
    for record in records {
      if mooncode_json_string(record, "record_kind", default="") == record_kind &&
        mooncode_json_string(record, "record_id", default="") == record_id {
        return NoAppend(false)
      }
    }
    Append(record_kind, payload, true)
  })
}

///|
async fn mooncode_read_session_journal(
  book_root : String,
  session_id : String,
) -> Array[Json] {
  mooncode_read_session_journal_path(
    mooncode_session_journal_path(book_root, session_id),
  )
}

///|
async fn mooncode_read_session_journal_path(path : String) -> Array[Json] {
  if path == "" || !(@fsx.exists(path) catch { _ => false }) {
    return []
  }
  let file = @fs.open(path, mode=ReadWrite, append=false)
  defer file.close()
  file.lock(Exclusive)
  defer file.unlock()
  mooncode_repair_journal_tail(file)
  mooncode_parse_journal_file(file, path)
}

///|
async fn mooncode_parse_journal_file(
  file : @fs.File,
  path : String,
) -> Array[Json] {
  let size = file.size()
  if size == 0L {
    return []
  }
  if size > 0x7fffffffL {
    raise InvalidJournal("MoonCode journal is too large to replay: \{path}")
  }
  let bytes = file.read_exactly_at(size.to_int(), position=0L)
  let text = @encoding/utf8.decode(bytes)
  mooncode_parse_journal_text(text, path)
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
    _ => raise InvalidJournal("MoonCode journal record has invalid sequence")
  }
}

///|
fn mooncode_parse_journal_text(
  text : String,
  path : String,
) -> Array[Json] raise MoonCodeJournalError {
  let records : Array[Json] = []
  let mut expected_sequence = 1
  for index, raw_line in text.split("\n") {
    let line = raw_line.trim()
    if line.is_empty() {
      continue
    }
    let record = @json.parse(line.to_owned()) catch {
      _ =>
        raise InvalidJournal(
          "MoonCode journal contains invalid JSON at line \{index + 1}: \{path}",
        )
    }
    let issues = @moonlib_conversation.journal_record_issues(record)
    if !issues.is_empty() {
      raise InvalidJournal(
        "MoonCode journal record at line \{index + 1} is invalid: \{issues.join("; ")}",
      )
    }
    let sequence = mooncode_journal_sequence(record)
    if sequence != expected_sequence {
      raise InvalidJournal(
        "MoonCode journal sequence gap at line \{index + 1}: expected \{expected_sequence}, found \{sequence}",
      )
    }
    records.push(record)
    expected_sequence += 1
  }
  records
}

///|
fn mooncode_journal_entries(
  records : Array[Json],
  record_kind : String,
) -> Array[Json] {
  let entries : Array[Json] = []
  for record in records {
    if mooncode_json_string(record, "record_kind", default="") == record_kind {
      let payload = mooncode_json_object_field_or_empty(record, "payload")
      entries.push(
        mooncode_json_object_with_field(
          payload,
          "journal_sequence",
          mooncode_json_int(record, "sequence", default=0).to_json(),
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
fn mooncode_journal_last_sequence(
  records : Array[Json],
) -> Int raise MoonCodeJournalError {
  match records.last() {
    Some(record) => mooncode_journal_sequence(record)
    None => 0
  }
}

///|
async fn mooncode_repair_journal_tail(file : @fs.File) -> Unit {
  let size = file.size()
  if size == 0L {
    return
  }
  if file.read_exactly_at(1, position=size - 1L) == b"\n" {
    return
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
        @moonclaw_fsx.truncate(file, start + index.to_int64() + 1L)
        file.sync(only_data=true)
        return
      }
    }
    cursor = start
  }
  @moonclaw_fsx.truncate(file, 0L)
  file.sync(only_data=true)
}

///|
fn mooncode_journal_record_id(
  record_kind : String,
  payload : Json,
) -> String raise MoonCodeJournalError {
  let direct_id = mooncode_json_string(payload, "id", default="")
  if direct_id != "" {
    return "\{record_kind}:\{direct_id}"
  }
  let payload_kind = mooncode_json_string(payload, "kind", default="")
  if record_kind == mooncode_journal_goal_event() &&
    payload_kind.has_prefix("mooncode.goal.") {
    let event_id = mooncode_json_string(payload, "event_id", default="")
    if event_id == "" || event_id.trim() != event_id {
      raise InvalidJournal("MoonCode logical goal event has invalid `event_id`")
    }
    return "event:\{event_id}"
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
