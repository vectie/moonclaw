///|
fn journal_sequence_test_record(sequence : Json, id : String) -> Json {
  let base = @moonlib_conversation.journal_record(
    session_id="sequence-test",
    sequence=1,
    record_id=id,
    record_kind="event",
    command_id="",
    client_turn_id="",
    recorded_at={ "seconds": 1, "nanoseconds": 0 },
    payload={},
  )
  match base {
    Json::Object(fields) => {
      let copied = fields.copy()
      copied["sequence"] = sequence
      Json::object(copied)
    }
    _ => abort("journal record unexpectedly is not an object")
  }
}

///|
fn journal_sequence_test_line(sequence : Json, id : String) -> String {
  journal_sequence_test_record(sequence, id).stringify()
}

///|
fn assert_invalid_journal_sequence(text : String) -> Unit raise {
  let rejected = try {
    ignore(mooncode_parse_journal_text(text, "sequence-test.jsonl"))
    false
  } catch {
    InvalidJournal(_) => true
  }
  assert_true(rejected)
}

///|
test "journal exact contiguous sequences 1 then 2 pass" {
  let text = journal_sequence_test_line(1, "one") +
    "\n" +
    journal_sequence_test_line(2, "two") +
    "\n"
  let records = mooncode_parse_journal_text(text, "sequence-test.jsonl")
  assert_eq(records.length(), 2)
  assert_eq(mooncode_journal_last_sequence(records), 2)
}

///|
test "journal rejects fractional sequence" {
  assert_invalid_journal_sequence(journal_sequence_test_line(1.5, "fraction"))
}

///|
test "journal rejects zero sequence" {
  assert_invalid_journal_sequence(journal_sequence_test_line(0, "zero"))
}

///|
test "journal rejects negative sequence" {
  assert_invalid_journal_sequence(journal_sequence_test_line(-1, "negative"))
}

///|
test "journal rejects huge sequence" {
  assert_invalid_journal_sequence(journal_sequence_test_line(1.0e100, "huge"))
}

///|
test "journal rejects wrong sequence type" {
  assert_invalid_journal_sequence(journal_sequence_test_line("1", "type"))
}

///|
test "journal rejects sequence gap" {
  let text = journal_sequence_test_line(1, "one") +
    "\n" +
    journal_sequence_test_line(3, "three")
  assert_invalid_journal_sequence(text)
}
