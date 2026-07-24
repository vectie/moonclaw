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
async fn mooncode_journal_stream_file(
  file : @fs.File,
  cursor : MoonCodeJournalSequence,
) -> MoonCodeJournalSequence {
  let mut current = cursor
  while true {
    match file.read_until("\n") {
      Some(line) => {
        let (_, next) = mooncode_journal_stream_record(line, current)
        current = next
      }
      None => break
    }
  }
  current
}
