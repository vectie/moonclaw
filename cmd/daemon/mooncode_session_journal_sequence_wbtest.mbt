///|
async test "append wrapper concurrent same identity appends exactly once" {
  @fsx.with_temporary_directory("mooncode-wrapper-same-XXXXXX", async fn(root) {
    let session_id = "wrapper-same"
    let payload : Json = {
      "id": "same",
      "recorded_at": { "seconds": 1, "nanoseconds": 0 },
    }
    let mut appended = 0
    @async.with_task_group(async fn(group) {
      let tasks = Array::new(capacity=16)
      for _ in 0..<16 {
        tasks.push(
          group.spawn(async fn() {
            mooncode_append_session_journal_once(
              root,
              session_id,
              mooncode_journal_event(),
              payload,
            )
          }),
        )
      }
      for task in tasks {
        if task.wait() {
          appended += 1
        }
      }
    })
    assert_eq(appended, 1)
    let records = mooncode_read_session_journal(root, session_id)
    assert_eq(records.length(), 1)
    assert_eq(mooncode_json_int(records[0], "sequence", default=0), 1)
  })
}

///|
async test "append wrapper concurrent distinct identities appends all" {
  @fsx.with_temporary_directory("mooncode-wrapper-distinct-XXXXXX", async fn(
    root,
  ) {
    let session_id = "wrapper-distinct"
    let mut appended = 0
    @async.with_task_group(async fn(group) {
      let tasks = Array::new(capacity=16)
      for i in 0..<16 {
        let payload : Json = {
          "id": "event-\{i}",
          "recorded_at": { "seconds": i + 1, "nanoseconds": 0 },
        }
        tasks.push(
          group.spawn(async fn() {
            mooncode_append_session_journal_once(
              root,
              session_id,
              mooncode_journal_event(),
              payload,
            )
          }),
        )
      }
      for task in tasks {
        if task.wait() {
          appended += 1
        }
      }
    })
    assert_eq(appended, 16)
    let records = mooncode_read_session_journal(root, session_id)
    assert_eq(records.length(), 16)
    for i in 0..<16 {
      assert_eq(mooncode_json_int(records[i], "sequence", default=0), i + 1)
      let expected_payload : Json = {
        "id": "event-\{i}",
        "recorded_at": { "seconds": i + 1, "nanoseconds": 0 },
      }
      let expected_id = mooncode_journal_record_id(
        mooncode_journal_event(),
        expected_payload,
      )
      let mut occurrences = 0
      for record in records {
        if mooncode_json_string(record, "record_id", default="") == expected_id {
          occurrences += 1
        }
      }
      assert_eq(occurrences, 1)
    }
  })
}

///|
async test "append wrapper reads mutable payload identity after waiting for lock" {
  @fsx.with_temporary_directory("mooncode-wrapper-mutable-XXXXXX", async fn(
    root,
  ) {
    let session_id = "wrapper-mutable"
    let path = mooncode_session_journal_path(root, session_id)
    @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
    let file = @fs.open(path, mode=ReadWrite, create=0o644)
    file.lock(Exclusive)
    let payload : Json = {
      "id": "A",
      "recorded_at": { "seconds": 1, "nanoseconds": 0 },
    }
    @async.with_task_group(async fn(group) {
      let task = group.spawn(async fn() {
        mooncode_append_session_journal_once(
          root,
          session_id,
          mooncode_journal_event(),
          payload,
        )
      })
      @async.pause()
      @async.pause()
      @async.pause()
      match payload {
        Object(fields) => fields["id"] = ("B" : Json)
        _ => abort("expected mutable payload object")
      }
      file.unlock()
      assert_true(task.wait())
    })
    file.close()
    let records = mooncode_read_session_journal(root, session_id)
    assert_eq(records.length(), 1)
    match records[0] {
      Object(record_fields) =>
        match record_fields.get("payload") {
          Some(stored_payload) =>
            assert_eq(
              mooncode_json_string(stored_payload, "id", default=""),
              "B",
            )
          None => abort("missing journal envelope payload")
        }
      _ => abort("journal envelope is not an object")
    }
    let before = @fsx.read_file(path)
    assert_false(
      mooncode_append_session_journal_once(
        root,
        session_id,
        mooncode_journal_event(),
        payload,
      ),
    )
    assert_eq(@fsx.read_file(path), before)
    assert_eq(mooncode_read_session_journal(root, session_id).length(), 1)
  })
}

///|
async test "journal transaction preserves inherited client turn after callback clears records" {
  @fsx.with_temporary_directory("mooncode-journal-inherited-turn-XXXXXX", async fn(
    root,
  ) {
    let session_id = "inherited-turn"
    let seed : Json = {
      "id": "seed",
      "command_id": "command-1",
      "client_turn_id": "turn-1",
      "recorded_at": { "seconds": 1, "nanoseconds": 0 },
    }
    let _ = mooncode_append_session_journal_once(
      root,
      session_id,
      mooncode_journal_event(),
      seed,
    )
    let next : Json = {
      "id": "next",
      "command_id": "command-1",
      "recorded_at": { "seconds": 2, "nanoseconds": 0 },
    }
    ignore(
      mooncode_session_journal_transaction(root, session_id, fn(records) {
        records.clear()
        Append(mooncode_journal_event(), next, true)
      }),
    )
    let records = mooncode_read_session_journal(root, session_id)
    assert_eq(records.length(), 2)
    assert_eq(
      mooncode_json_string(records[1], "client_turn_id", default=""),
      "turn-1",
    )
    assert_eq(mooncode_json_int(records[1], "sequence", default=0), 2)
  })
}

///|
async test "journal transaction callback failure unlocks without mutation" {
  @fsx.with_temporary_directory("mooncode-journal-callback-failure-XXXXXX", async fn(
    root,
  ) {
    let session_id = "callback-failure"
    let seed : Json = {
      "id": "seed",
      "recorded_at": { "seconds": 1, "nanoseconds": 0 },
    }
    let _ = mooncode_append_session_journal_once(
      root,
      session_id,
      mooncode_journal_event(),
      seed,
    )
    let path = mooncode_session_journal_path(root, session_id)
    let before = @fsx.read_file(path)
    let caught = try {
      let _result : Unit = mooncode_session_journal_transaction(
        root,
        session_id,
        fn(_) raise { raise InvalidJournal("intentional callback failure") },
      )
      false
    } catch {
      InvalidJournal("intentional callback failure") => true
      _ => false
    }
    assert_true(caught)
    assert_eq(@fsx.read_file(path), before)
    let next : Json = {
      "id": "next",
      "recorded_at": { "seconds": 2, "nanoseconds": 0 },
    }
    let _ = mooncode_append_session_journal_once(
      root,
      session_id,
      mooncode_journal_event(),
      next,
    )
    let records = mooncode_read_session_journal(root, session_id)
    assert_eq(records.length(), 2)
    assert_eq(mooncode_json_int(records[0], "sequence", default=0), 1)
    assert_eq(mooncode_json_int(records[1], "sequence", default=0), 2)
  })
}

///|
async test "journal transaction same identity concurrent calls linearize once" {
  @fsx.with_temporary_directory("mooncode-journal-concurrent-XXXXXX", async fn(
    root,
  ) {
    let session_id = "concurrent-identity"
    let payload : Json = {
      "id": "concurrent",
      "recorded_at": { "seconds": 1, "nanoseconds": 0 },
    }
    let record_id = mooncode_journal_record_id(
      mooncode_journal_event(),
      payload,
    )
    let mut appended = 0
    @async.with_task_group(async fn(group) {
      let tasks = Array::new(capacity=16)
      for _ in 0..<16 {
        tasks.push(
          group.spawn(async fn() {
            mooncode_session_journal_transaction(root, session_id, fn(records) {
              let present = records.any(fn(record) {
                mooncode_json_string(record, "record_id", default="") ==
                record_id
              })
              if present {
                NoAppend(false)
              } else {
                Append(mooncode_journal_event(), payload, true)
              }
            })
          }),
        )
      }
      for task in tasks {
        if task.wait() {
          appended += 1
        }
      }
    })
    assert_eq(appended, 1)
    let records = mooncode_read_session_journal(root, session_id)
    assert_eq(records.length(), 1)
    assert_eq(mooncode_json_int(records[0], "sequence", default=0), 1)
    assert_true(
      @fsx.read_file(mooncode_session_journal_path(root, session_id)).has_suffix(
        "\n",
      ),
    )
  })
}

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
test "journal checked next sequence starts at one" {
  assert_eq(mooncode_journal_checked_next_sequence(0), 1)
}

///|
test "journal checked next sequence rejects maximum" {
  let rejected = try {
    ignore(mooncode_journal_checked_next_sequence(2147483647))
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

///|
/// Structured-edit recovery coverage for transaction callback effects.
async test "journal transaction appends one record and returns typed result" {
  @fsx.with_temporary_directory("mooncode-journal-transaction-XXXXXX", async fn(
    root,
  ) {
    let session_id = "transaction-success"
    let payload : Json = {
      "id": "stable-event",
      "kind": "runtime.started.v1",
      "recorded_at": { "seconds": 123, "nanoseconds": 0 },
    }
    let result : String = mooncode_session_journal_transaction(
      root,
      session_id,
      fn(records) raise {
        if !records.is_empty() {
          raise InvalidJournal("expected empty transaction journal")
        }
        Append(mooncode_journal_event(), payload, "appended")
      },
    )
    assert_eq(result, "appended")
    let records = mooncode_read_session_journal(root, session_id)
    assert_eq(records.length(), 1)
    assert_eq(mooncode_json_int(records[0], "sequence", default=0), 1)
    assert_eq(
      mooncode_json_string(records[0], "record_id", default=""),
      mooncode_journal_record_id(mooncode_journal_event(), payload),
    )
  })
}

///|
async test "journal transaction collision uses immutable pre-callback snapshot" {
  @fsx.with_temporary_directory("mooncode-journal-collision-XXXXXX", async fn(
    root,
  ) {
    let session_id = "transaction-collision"
    let payload : Json = {
      "id": "stable-event",
      "kind": "runtime.started.v1",
      "recorded_at": { "seconds": 123, "nanoseconds": 0 },
    }
    assert_true(
      mooncode_append_session_journal_once(
        root,
        session_id,
        mooncode_journal_event(),
        payload,
      ),
    )
    let path = mooncode_session_journal_path(root, session_id)
    let before = @fsx.read_file(path)
    let rejected = try {
      ignore(
        mooncode_session_journal_transaction(root, session_id, fn(
          records,
        ) raise {
          records.clear()
          Append(mooncode_journal_event(), payload, ())
        }),
      )
      false
    } catch {
      InvalidJournal(_) => true
      _ => false
    }
    assert_true(rejected)
    let after = @fsx.read_file(path)
    assert_eq(after, before)
    assert_eq(mooncode_read_session_journal(root, session_id).length(), 1)
  })
}
