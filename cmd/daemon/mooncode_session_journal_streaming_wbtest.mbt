///|
fn streaming_test_sequence(text : String) -> MoonCodeJournalSequence raise {
  if text == "0" {
    MoonCodeJournalSequence::zero()
  } else {
    MoonCodeJournalSequence::parse(text) catch {
      _ => fail("unexpected sequence parse failure")
    }
  }
}

///|
fn streaming_test_v1(sequence : Int) -> String {
  @moonlib_conversation.journal_record(
    session_id="session",
    sequence~,
    record_id="record",
    record_kind="event",
    command_id="",
    client_turn_id="",
    recorded_at="now",
    payload={},
  ).stringify()
}

///|
fn streaming_test_v2(sequence : String) -> String raise {
  mooncode_journal_record_v2(
    session_id="session",
    sequence=streaming_test_sequence(sequence),
    record_id="record",
    record_kind="event",
    command_id="",
    client_turn_id="",
    recorded_at="now",
    payload={},
  ).stringify()
}

///|
fn streaming_test_expect_corrupt(action : () -> Unit raise) -> Unit raise {
  try action() catch {
    InvalidJournal(_) => ()
    MoonCodeGoalRuntimeStoreError::CorruptStore(_) => ()
    MoonCodeGoalRuntimeStoreError::IdentityConflict(_, _, _) =>
      fail("unexpected identity conflict")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected corrupt journal data")
  }
}

///|
fn streaming_test_validate(
  lines : Array[String],
  cursor : String,
) -> Unit raise {
  let mut current = streaming_test_sequence(cursor)
  for line in lines {
    let (_, next) = mooncode_journal_stream_record(line, current)
    current = next
  }
}

///|
fn streaming_test_reject(lines : Array[String], cursor : String) -> Unit raise {
  streaming_test_expect_corrupt(fn() -> Unit raise {
    streaming_test_validate(lines, cursor)
  })
}

///|
test "streaming journal accepts canonical v1 and v2 sequence one" {
  streaming_test_validate([streaming_test_v1(1)], "0")
  streaming_test_validate([streaming_test_v2("1")], "0")
}

///|
test "streaming journal rejects corrupt focused inputs" {
  let canonical = streaming_test_v1(1)
  streaming_test_reject(
    [canonical.replace(old="\"sequence\":1", new="\"sequence\":1.0")],
    "0",
  )
  streaming_test_reject(
    [canonical.replace(old="\"sequence\":1", new="\"sequence\":1e0")],
    "0",
  )
  streaming_test_reject([""], "0")
  streaming_test_reject([streaming_test_v1(2)], "0")
  streaming_test_reject(
    [canonical.replace(old="\"sequence\":1", new="\"sequence\":\"1\"")],
    "0",
  )
  streaming_test_reject(
    [
      streaming_test_v2("1").replace(
        old="\"sequence\":\"1\"",
        new="\"sequence\":1",
      ),
    ],
    "0",
  )
}

///|
test "streaming journal continues beyond signed 64 bit cursor" {
  streaming_test_validate(
    [streaming_test_v2("9223372036854775808")],
    "9223372036854775807",
  )
}

///|
async test "production journal reader returns mixed canonical versions" {
  @fsx.with_temporary_directory("moonclaw-journal-reader-XXXXXX", async fn(
    directory,
  ) {
    let path = @pathx.join(directory, "journal.jsonl")
    @fsx.write_to_file(
      path,
      streaming_test_v1(1) +
      "\n" +
      streaming_test_v2("2") +
      "\n" +
      streaming_test_v1(3) +
      "\n",
    )
    let records = mooncode_read_session_journal_path(path)
    assert_eq(records.length(), 3)
    assert_eq(mooncode_journal_sequence_from_record(records[0]).text(), "1")
    assert_eq(mooncode_journal_sequence_from_record(records[1]).text(), "2")
    assert_eq(mooncode_journal_sequence_from_record(records[2]).text(), "3")
  })
}

///|
async test "streaming journal file scans mixed canonical versions" {
  @fsx.with_temporary_directory("moonclaw-journal-streaming-XXXXXX", async fn(
    directory,
  ) {
    let path = @pathx.join(directory, "journal.jsonl")
    let contents = streaming_test_v1(1) +
      "\n" +
      streaming_test_v2("2") +
      "\n" +
      streaming_test_v1(3) +
      "\n"
    @fsx.write_to_file(path, contents)
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    let cursor = mooncode_journal_stream_file(
      file,
      MoonCodeJournalSequence::zero(),
    )
    inspect(cursor.text(), content="3")
  })
}

///|
test "streaming journal normalizes malformed JSON to journal corruption" {
  let rejected = try {
    ignore(mooncode_journal_stream_record("{", MoonCodeJournalSequence::zero()))
    false
  } catch {
    InvalidJournal(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "journal writer boundary rejects noncanonical numeric repr" {
  let record = mooncode_journal_record_v2(
    session_id="session",
    sequence=streaming_test_sequence("1"),
    record_id="record",
    record_kind="event",
    command_id="",
    client_turn_id="",
    recorded_at="now",
    payload={ "poison": Json::number(1.0, repr="1.0") },
  )
  let rejected = try {
    ignore(mooncode_journal_canonical_line(record))
    false
  } catch {
    InvalidJournal(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "journal writer boundary accepts canonical Unicode payload" {
  let record = mooncode_journal_record_v2(
    session_id="session-你好",
    sequence=streaming_test_sequence("1"),
    record_id="record-🌙",
    record_kind="event",
    command_id="",
    client_turn_id="",
    recorded_at="now",
    payload={ "text": "你好 🌙 quoted and escaped" },
  )
  let line = mooncode_journal_canonical_line(record)
  let (_, cursor) = mooncode_journal_stream_record(
    line,
    MoonCodeJournalSequence::zero(),
  )
  inspect(cursor.text(), content="1")
}
