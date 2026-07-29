///|
let mooncode_journal_read_chunk_size : Int = 64 * 1024

///|
async fn mooncode_journal_read_lines(
  file : @fs.File,
  consume : async (String) -> Unit,
) -> Unit {
  let buffer : FixedArray[Byte] = FixedArray::make(
    mooncode_journal_read_chunk_size, 0,
  )
  let pending : Array[Bytes] = []
  let mut pending_length = 0
  while true {
    let read = file.read(buffer)
    if read == 0 {
      break
    }
    let mut start = 0
    for index = 0; index < read; index = index + 1 {
      if buffer[index] == b'\n' {
        let piece_length = index - start
        let line_bytes : FixedArray[Byte] = FixedArray::make(
          pending_length + piece_length,
          0,
        )
        let mut offset = 0
        for chunk in pending {
          line_bytes.blit_from_bytes(offset, chunk, 0, chunk.length())
          offset = offset + chunk.length()
        }
        for source = start; source < index; source = source + 1 {
          line_bytes[offset] = buffer[source]
          offset = offset + 1
        }
        pending.clear()
        pending_length = 0
        consume(@encoding/utf8.decode(Bytes::from_array(line_bytes)))
        start = index + 1
      }
    }
    if start < read {
      let chunk = Bytes::makei(read - start, fn(index) { buffer[start + index] })
      pending.push(chunk)
      pending_length = pending_length + chunk.length()
    }
  }
  if pending_length > 0 {
    let line_bytes : FixedArray[Byte] = FixedArray::make(pending_length, 0)
    let mut offset = 0
    for chunk in pending {
      line_bytes.blit_from_bytes(offset, chunk, 0, chunk.length())
      offset = offset + chunk.length()
    }
    consume(@encoding/utf8.decode(Bytes::from_array(line_bytes)))
  }
}

///|
/// Advance the daemon's journal cursor after validating one canonical JSONL record.
///
/// `raw_line` is the operational record unit and must not contain its newline.
/// Keeping the stringify equality here is intentional: in particular, legacy v1
/// numeric sequence spellings such as `1.0` and `1e0` must not be normalized into
/// acceptance by the JSON parser.
fn mooncode_journal_stream_record(
  raw_line : String,
  cursor : MoonCodeJournalSequence,
) -> (Json, MoonCodeJournalSequence) raise {
  if raw_line.is_empty() {
    raise InvalidJournal("blank journal record")
  }
  let parsed = @json.parse(raw_line) catch {
    _ => raise InvalidJournal("invalid journal JSON")
  }
  if parsed.stringify() != raw_line {
    raise InvalidJournal("non-canonical journal record")
  }
  let envelope = mooncode_journal_validate_envelope(parsed) catch {
    MoonCodeGoalRuntimeStoreError::CorruptStore(message) =>
      raise InvalidJournal(message)
    MoonCodeGoalRuntimeStoreError::IdentityConflict(_, _, _) =>
      raise InvalidJournal("unexpected journal identity conflict")
  }
  let next = cursor.next()
  if envelope.sequence.compare(next) != 0 {
    raise InvalidJournal("journal sequence gap")
  }
  (parsed, next)
}

///|
/// Scan a repaired, newline-committed journal from the file's current position.
/// Only the arbitrary-decimal cursor survives each iteration; no aggregate file
/// contents or record collection is retained.
fn mooncode_journal_canonical_line(
  record : Json,
) -> String raise MoonCodeJournalError {
  let line = record.stringify()
  let reparsed = @json.parse(line) catch {
    _ => raise InvalidJournal("journal writer produced invalid JSON")
  }
  if reparsed.stringify() != line {
    raise InvalidJournal("journal writer produced a non-canonical record")
  }
  line
}

///|
priv struct MoonCodeJournalAppendScan {
  cursor : MoonCodeJournalSequence
  duplicate_found : Bool
  inherited_client_turn_id : String
}

///|
async fn mooncode_journal_scan_for_append(
  file : @fs.File,
  expected_session_id : String,
  record_kind : String,
  record_id : String,
  command_id : String,
) -> MoonCodeJournalAppendScan {
  let mut cursor = MoonCodeJournalSequence::zero()
  let mut duplicate_found = false
  let mut inherited_client_turn_id = ""
  mooncode_journal_read_lines(file, async fn(line) {
    let (record, next) = mooncode_journal_stream_record(line, cursor)
    let current_session_id = mooncode_json_string(
      record,
      "session_id",
      default="",
    )
    if current_session_id != expected_session_id {
      raise InvalidJournal("journal record belongs to a different session")
    }
    cursor = next
    let current_record_kind = mooncode_json_string(
      record,
      "record_kind",
      default="",
    )
    let current_record_id = mooncode_json_string(
      record,
      "record_id",
      default="",
    )
    let current_command_id = mooncode_json_string(
      record,
      "command_id",
      default="",
    )
    let current_client_turn_id = mooncode_json_string(
      record,
      "client_turn_id",
      default="",
    )
    if current_record_kind == record_kind && current_record_id == record_id {
      duplicate_found = true
    }
    if command_id != "" &&
      inherited_client_turn_id == "" &&
      current_command_id == command_id &&
      current_client_turn_id != "" {
      inherited_client_turn_id = current_client_turn_id
    }
  })
  { cursor, duplicate_found, inherited_client_turn_id }
}

///|
async fn mooncode_journal_stream_file(
  file : @fs.File,
  cursor : MoonCodeJournalSequence,
) -> MoonCodeJournalSequence {
  let mut current = cursor
  mooncode_journal_read_lines(file, async fn(line) {
    let (_, next) = mooncode_journal_stream_record(line, current)
    current = next
  })
  current
}
