///|
test "extract exact pair preserves records and stable chronological duplicates" {
  let one : Json = {
    "run_id": "shared",
    "job_id": "one",
    "timestamp": 20,
    "event_type": "future",
    "message": "雪\nquoted \"text\"",
    "data": { "opaque": [null, true] },
    "status": null,
    "step_id": "",
    "unknown": { "keep": 17 },
  }
  let other : Json = {
    "run_id": "shared",
    "job_id": "two",
    "timestamp": 1,
    "event_type": "run",
    "message": "other job",
    "data": null,
  }
  let earlier : Json = {
    "run_id": "shared",
    "job_id": "one",
    "timestamp": -1,
    "event_type": "run",
    "message": "earlier",
    "data": null,
    "status": { "FutureStatus": [1] },
  }
  let entries = @job_journal.parse_journal(
    [one, other, earlier, one].map(j => j.stringify()).join("\n"),
    source="original",
  )
  let exported = @job_journal.extract_run_journal(
    entries,
    job_id="one",
    run_id="shared",
  )
  let reopened = @job_journal.parse_journal(exported, source="extracted")
  assert_eq(reopened.length(), 3)
  assert_eq(reopened[0].record, earlier)
  assert_eq(reopened[1].record, one)
  assert_eq(reopened[2].record, one)
  assert_eq(
    @job_journal.extract_run_journal(reopened, job_id="one", run_id="shared"),
    exported,
  )
  assert_eq(entries[0].source, "original")
  assert_eq(entries[0].line, 1)
}

///|
test "extract fails on absent pair and includes all events beyond a page" {
  let entries = @job_journal.parse_journal(
    Array::make(1001, fixture("run", 1, "x").stringify()).join("\n"),
    source="many",
  )
  let output = @job_journal.extract_run_journal(
    entries,
    job_id="job-1",
    run_id="run",
  )
  assert_eq(@job_journal.parse_journal(output, source="again").length(), 1001)
  assert_true(
    (Ok(@job_journal.extract_run_journal(entries, job_id="other", run_id="run")) catch {
      error => Err(error)
    })
    is Err(_),
  )
  assert_true(
    (Ok(@job_journal.extract_run_journal([], job_id="job-1", run_id="run")) catch {
      error => Err(error)
    })
    is Err(_),
  )
}

///|
test "extract output stays within the journal reimport text budget" {
  let entry = @job_journal.parse_journal(
    fixture("run", 1, "x".repeat(1000000)).stringify(),
    source="large",
  )
  let entries : Array[@job_journal.JournalEntry] = []
  for _ in 0..<5 {
    entries.append(entry)
  }
  try
    @job_journal.extract_run_journal(entries, job_id="job-1", run_id="run")
  catch {
    error =>
      assert_true(
        error.to_string().contains("Extracted journal exceeds 4 Mi code units"),
      )
  } noraise {
    _ => fail("Expected reimport budget failure")
  }
}
