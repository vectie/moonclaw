///|
fn streaming_test_sequence(text : String) -> MoonCodeJournalSequence raise {
  mooncode_journal_cursor_parse(text) catch {
    _ => fail("unexpected sequence parse failure")
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
fn streaming_test_append_record(
  sequence : String,
  record_id : String,
  command_id : String,
  client_turn_id : String,
) -> String raise {
  mooncode_journal_record_v2(
    session_id="session",
    sequence=streaming_test_sequence(sequence),
    record_id~,
    record_kind="event",
    command_id~,
    client_turn_id~,
    recorded_at="now",
    payload={},
  ).stringify()
}

///|
async fn streaming_test_scan_file(
  contents : String,
  record_id : String,
  command_id : String,
) -> MoonCodeJournalAppendScan {
  @fsx.with_temporary_directory("moonclaw-journal-append-scan-XXXXXX", async fn(
    directory,
  ) {
    let path = @pathx.join(directory, "journal.jsonl")
    @fsx.write_to_file(path, contents)
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    mooncode_journal_scan_for_append(
      file, "session", "event", record_id, command_id,
    )
  })
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
async test "append scan reads mixed cursor and inherits first matching client id" {
  let contents = streaming_test_v1(1) +
    "\n" +
    streaming_test_append_record("2", "other", "command", "client-first") +
    "\n" +
    streaming_test_append_record("3", "other-2", "command", "client-later") +
    "\n"
  let scan = streaming_test_scan_file(contents, "missing", "command")
  assert_eq(scan.cursor.text(), "3")
  assert_false(scan.duplicate_found)
  assert_eq(scan.inherited_client_turn_id, "client-first")
}

///|
async test "append scan finds duplicate through EOF" {
  let contents = streaming_test_append_record("1", "duplicate", "", "") +
    "\n" +
    streaming_test_append_record("2", "other", "", "") +
    "\n"
  let scan = streaming_test_scan_file(contents, "duplicate", "")
  assert_eq(scan.cursor.text(), "2")
  assert_true(scan.duplicate_found)
}

///|
async test "append scan rejects corruption after duplicate" {
  let contents = streaming_test_append_record("1", "duplicate", "", "") +
    "\n" +
    "malformed\n"
  try streaming_test_scan_file(contents, "duplicate", "") catch {
    InvalidJournal(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected malformed journal corruption")
  }
}

///|
async test "append scan does not inherit client id from command mismatch" {
  let contents = streaming_test_append_record(
      "1", "other", "wrong-command", "client",
    ) +
    "\n"
  let scan = streaming_test_scan_file(contents, "missing", "command")
  assert_eq(scan.inherited_client_turn_id, "")
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
    let records = mooncode_read_session_journal_path(path, "session")
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

///|
test "stream rejects physical sequence zero" {
  streaming_test_expect_corrupt(fn() -> Unit raise {
    ignore(
      mooncode_journal_validate_envelope(mooncode_sequence_v1_envelope("0")),
    )
  })
}

///|
test "journal text replay accepts empty and mixed v1 v2 committed records" {
  assert_eq(mooncode_parse_journal_text("", "fixture").length(), 0)
  let text = streaming_test_v1(1) + "\n" + streaming_test_v2("2") + "\n"
  let records = mooncode_parse_journal_text(text, "fixture") catch {
    InvalidJournal(message) => fail(message)
  }
  assert_eq(records.length(), 2)
  assert_eq(mooncode_journal_last_sequence_exact(records).text(), "2")
}

///|
test "journal text replay rejects internal blank records" {
  streaming_test_expect_corrupt(fn() -> Unit raise {
    ignore(
      mooncode_parse_journal_text(streaming_test_v1(1) + "\n\n", "fixture"),
    )
  })
}

///|
test "stream and exact last sequence preserve values beyond Int64" {
  let previous = streaming_test_sequence("9223372036854775807")
  let (record, next) = mooncode_journal_stream_record(
    streaming_test_v2("9223372036854775808"),
    previous,
  )
  assert_eq(next.text(), "9223372036854775808")
  assert_eq(
    mooncode_journal_last_sequence_exact([record]).text(),
    "9223372036854775808",
  )
}

///|
test "journal entries project mixed exact sequences and shadow payload sequence" {
  let v1 = @moonlib_conversation.journal_record(
    session_id="session",
    sequence=1,
    record_id="v1",
    record_kind="event",
    command_id="",
    client_turn_id="",
    recorded_at="now",
    payload={ "journal_sequence": "shadow-v1", "value": "one" },
  )
  let v2 = mooncode_journal_record_v2(
    session_id="session",
    sequence=streaming_test_sequence("9223372036854775808"),
    record_id="v2",
    record_kind="event",
    command_id="",
    client_turn_id="",
    recorded_at="now",
    payload={ "journal_sequence": 7, "value": "two" },
  )
  let entries = mooncode_journal_entries([v1, v2], "event")
  assert_eq(entries.length(), 2)
  assert_eq(
    mooncode_json_string(entries[0], "journal_sequence", default=""),
    "1",
  )
  assert_eq(
    mooncode_json_string(entries[1], "journal_sequence", default=""),
    "9223372036854775808",
  )
}

///|
test "journal entries reject zero and malformed present physical sequences" {
  streaming_test_expect_corrupt(fn() -> Unit raise {
    ignore(
      mooncode_journal_entries([mooncode_sequence_v1_envelope("0")], "event"),
    )
  })
  let malformed = streaming_test_v2("1").replace(
    old="\"sequence\":\"1\"",
    new="\"sequence\":\"malformed\"",
  )
  streaming_test_expect_corrupt(fn() -> Unit raise {
    let record = @json.parse(malformed) catch {
      _ => fail("fixture parse failed")
    }
    ignore(mooncode_journal_entries([record], "event"))
  })
}

///|
test "journal durability chain reaches the filesystem anchor" {
  let directories = mooncode_journal_commit_directories(
    "/book/.moonsuite/products/moonclaw/mooncode/sessions/s/journal.jsonl",
  )
  assert_eq(
    directories[0],
    "/book/.moonsuite/products/moonclaw/mooncode/sessions/s",
  )
  assert_true(directories.contains("/book"))
  assert_eq(directories[directories.length() - 1], "/")
}

///|
async test "production append writes canonical v2 strings and repairs torn suffix" {
  @fsx.with_temporary_directory("moonclaw-journal-v2-append-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session-production-v2"
    assert_true(
      mooncode_append_session_journal_once(root, session_id, "event", {
        "id": "first",
        "command_id": "command",
        "created_at": "time-1",
      }),
    )
    assert_true(
      mooncode_append_session_journal_once(root, session_id, "event", {
        "id": "second",
        "command_id": "command",
        "created_at": "time-2",
      }),
    )
    let path = mooncode_session_journal_path(root, session_id)
    let committed = @fsx.read_file(path)
    let lines = committed.split("\n").collect()
    assert_eq(lines.length(), 3)
    for index in 0..<2 {
      let line = lines[index].to_owned()
      let record = @json.parse(line) catch {
        _ => fail("production append emitted invalid JSON")
      }
      assert_eq(record.stringify(), line)
      assert_eq(
        mooncode_json_string(record, "contract_id", default=""),
        mooncode_journal_contract_id_v2(),
      )
      assert_eq(
        mooncode_json_string(record, "sequence", default=""),
        (index + 1).to_string(),
      )
    }
    @fsx.write_to_file(path, committed + "{\"kind\":")
    assert_true(
      mooncode_append_session_journal_once(root, session_id, "event", {
        "id": "third",
        "command_id": "command",
        "created_at": "time-3",
      }),
    )
    let repaired = @fsx.read_file(path)
    assert_false(repaired.contains("{\"kind\":{\"kind\":"))
    let records = mooncode_read_session_journal(root, session_id)
    assert_eq(records.length(), 3)
    assert_eq(mooncode_journal_sequence_from_record(records[2]).text(), "3")
  })
}

///|
async test "production append duplicate retry is byte stable" {
  @fsx.with_temporary_directory("moonclaw-journal-v2-dedup-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session-production-dedup"
    assert_true(
      mooncode_append_session_journal_once(root, session_id, "event", {
        "id": "stable",
        "command_id": "command",
        "created_at": "time-1",
        "detail": "first",
      }),
    )
    let path = mooncode_session_journal_path(root, session_id)
    let before = @fsx.read_file(path)
    assert_false(
      mooncode_append_session_journal_once(root, session_id, "event", {
        "id": "stable",
        "command_id": "command",
        "detail": "retry without timestamp",
      }),
    )
    assert_eq(@fsx.read_file(path), before)
  })
}

///|
async test "production append direct client id wins then command inheritance applies" {
  @fsx.with_temporary_directory("moonclaw-journal-client-id-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session-client-id"
    assert_true(
      mooncode_append_session_journal_once(root, session_id, "event", {
        "id": "first",
        "command_id": "command",
        "client_turn_id": "client-first",
        "created_at": "time-1",
      }),
    )
    assert_true(
      mooncode_append_session_journal_once(root, session_id, "event", {
        "id": "second",
        "command_id": "command",
        "created_at": "time-2",
      }),
    )
    assert_true(
      mooncode_append_session_journal_once(root, session_id, "event", {
        "id": "third",
        "command_id": "command",
        "client_turn_id": "client-direct",
        "created_at": "time-3",
      }),
    )
    let records = mooncode_read_session_journal(root, session_id)
    assert_eq(
      mooncode_json_string(records[0], "client_turn_id", default=""),
      "client-first",
    )
    assert_eq(
      mooncode_json_string(records[1], "client_turn_id", default=""),
      "client-first",
    )
    assert_eq(
      mooncode_json_string(records[2], "client_turn_id", default=""),
      "client-direct",
    )
  })
}

///|
async test "production append continues a legacy v1 prefix with v2" {
  @fsx.with_temporary_directory("moonclaw-journal-v1-v2-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session-v1-v2"
    let path = mooncode_session_journal_path(root, session_id)
    @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
    let legacy = @moonlib_conversation.journal_record(
      session_id~,
      sequence=1,
      record_id="event:legacy",
      record_kind="event",
      command_id="command",
      client_turn_id="",
      recorded_at="time-1",
      payload={
        "id": "legacy",
        "command_id": "command",
        "created_at": "time-1",
      },
    )
    @fsx.write_to_file(path, legacy.stringify() + "\n")
    assert_true(
      mooncode_append_session_journal_once(root, session_id, "event", {
        "id": "current",
        "command_id": "command",
        "created_at": "time-2",
      }),
    )
    let lines = @fsx.read_file(path).split("\n").collect()
    let current = @json.parse(lines[1].to_owned()) catch {
      _ => fail("current record is invalid JSON")
    }
    assert_eq(
      mooncode_json_string(current, "contract_id", default=""),
      mooncode_journal_contract_id_v2(),
    )
    assert_eq(mooncode_json_string(current, "sequence", default=""), "2")
  })
}

///|
async test "append scan rejects committed records from another session" {
  let foreign = mooncode_journal_record_v2(
      session_id="foreign",
      sequence=streaming_test_sequence("1"),
      record_id="event:foreign",
      record_kind="event",
      command_id="command",
      client_turn_id="",
      recorded_at="time",
      payload={},
    ).stringify() +
    "\n"
  let rejected = try {
    ignore(streaming_test_scan_file(foreign, "missing", "command"))
    false
  } catch {
    InvalidJournal(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
async test "production append normalizes missing timestamp to InvalidJournal" {
  @fsx.with_temporary_directory("moonclaw-journal-invalid-append-XXXXXX", async fn(
    root,
  ) {
    let rejected = try {
      ignore(
        mooncode_append_session_journal_once(root, "session-invalid", "event", {
          "id": "missing-time",
          "command_id": "command",
        }),
      )
      false
    } catch {
      InvalidJournal(_) => true
      _ => false
    }
    assert_true(rejected)
  })
}

///|
async test "production read rejects a journal from another session" {
  @fsx.with_temporary_directory("moonclaw-journal-read-session-XXXXXX", async fn(
    root,
  ) {
    let path = @pathx.join(root, "journal.jsonl")
    let foreign = mooncode_journal_record_v2(
      session_id="foreign",
      sequence=streaming_test_sequence("1"),
      record_id="event:foreign",
      record_kind="event",
      command_id="command",
      client_turn_id="",
      recorded_at="time",
      payload={},
    )
    @fsx.write_to_file(path, foreign.stringify() + "\n")
    let rejected = try {
      ignore(mooncode_read_session_journal_path(path, "expected"))
      false
    } catch {
      InvalidJournal(_) => true
      _ => false
    }
    assert_true(rejected)
  })
}

///|
async test "production append rejects noncanonical payload without bytes" {
  @fsx.with_temporary_directory("moonclaw-journal-invalid-number-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session-invalid-number"
    let rejected = try {
      ignore(
        mooncode_append_session_journal_once(root, session_id, "event", {
          "id": "invalid-number",
          "command_id": "command",
          "created_at": "time",
          "value": Json::number(1.0, repr="1.0"),
        }),
      )
      false
    } catch {
      InvalidJournal(_) => true
      _ => false
    }
    assert_true(rejected)
    assert_eq(
      @fsx.read_file(mooncode_session_journal_path(root, session_id)),
      "",
    )
  })
}

///|
test "production append finalizer advances beyond signed 64 bit" {
  let scan = MoonCodeJournalAppendScan::{
    cursor: streaming_test_sequence("9223372036854775808"),
    duplicate_found: false,
    inherited_client_turn_id: "client-inherited",
  }
  let record = mooncode_journal_record_for_append(
    "session",
    "event",
    { "id": "huge", "command_id": "command", "created_at": "time" },
    "event:huge",
    "command",
    scan,
  )
  assert_eq(
    mooncode_json_string(record, "sequence", default=""),
    "9223372036854775809",
  )
  assert_eq(
    mooncode_json_string(record, "client_turn_id", default=""),
    "client-inherited",
  )
}
