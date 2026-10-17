///|
fn directory_fixture() -> Array[@job_journal.JournalEntry] raise {
  @job_journal.parse_journal(
    (
      #|{"run_id":"run-a","job_id":"job","event_type":"run.started","timestamp":1,"status":"Running","message":"Initial objective","data":{}}
      #|{"run_id":"run-b","job_id":"job","event_type":"run.started","timestamp":-10,"message":"other","data":{}}
      #|{"run_id":"run-a","job_id":"job","event_type":"step.done","timestamp":30,"step_id":"s","status":"Succeeded","message":"<script>later</script>","data":{}}
      #|{"run_id":"run-b","job_id":"job","event_type":"run.unknown","timestamp":25,"status":{"future":"unknown"},"message":"receipt lost","data":{}}
      #|{"run_id":"run-a","job_id":"other-job","event_type":"run.done","timestamp":30,"status":null,"message":"collision","data":{}}
    ),
    source="saved.jsonl",
  )
}

///|
test "run directory discovers exact pairs without promoting step success" {
  let entries = directory_fixture()
  let result = @job_journal.journal_run_directory(entries)
  assert_eq(result.total_runs, 3)
  assert_eq(result.total_events, 5)
  assert_eq(result.runs[0].run_id, "run-a")
  assert_eq(result.runs[0].job_id, "job")
  assert_eq(result.runs[0].events, 2)
  assert_eq(result.runs[0].steps, 1)
  assert_eq(result.runs[0].last_run_status, Some(Json::string("Running")))
  assert_eq(result.runs[0].status_source.unwrap().line, 1)
  assert_true(result.runs[0].ambiguous_run_id)
  assert_eq(result.runs[1].last_run_status, Some(Json::null()))
  assert_eq(result.runs[1].status_source.unwrap().line, 5)
  assert_eq(result.runs[2].first_timestamp, -10)
  assert_eq(result.runs[2].last_run_status, Some({ "future": "unknown" }))
  assert_true(result.to_markdown().contains("&lt;script&gt;"))
  assert_true(result.to_markdown().contains("Ambiguous run ID"))
}

///|
test "run filters retain complete histories and pagination is deterministic" {
  let entries = directory_fixture()
  let one = @job_journal.journal_run_directory(
    entries,
    query="INITIAL",
    job_id="job",
    limit=1,
  )
  assert_eq(one.matched_runs, 1)
  assert_eq(one.runs[0].events, 2)
  assert_true(one.runs[0].ambiguous_run_id)
  let first = @job_journal.journal_run_directory(entries, limit=1)
  assert_eq(first.next_offset, Some(1))
  let rest = @job_journal.journal_run_directory(entries, offset=1, limit=2)
  assert_eq(rest.runs.length(), 2)
  assert_eq(rest.next_offset, None)
  assert_eq(
    @job_journal.journal_run_directory(entries, offset=2147483647).runs.length(),
    0,
  )
  assert_eq(
    @job_journal.journal_run_directory(entries, query="no match").matched_runs,
    0,
  )
  assert_eq(@job_journal.journal_run_directory([]).total_runs, 0)
}

///|
test "run directory stable timestamp ties, duplicate observations and missing status" {
  let entries = @job_journal.parse_journal(
    (
      #|{"run_id":"r","job_id":"j","event_type":"step","timestamp":4,"step_id":"","status":"Succeeded","message":"first","data":{}}
      #|{"run_id":"r","job_id":"j","event_type":"step","timestamp":4,"step_id":"","status":"Succeeded","message":"second","data":{}}
    ),
    source="one",
  )
  entries.append(
    @job_journal.parse_journal(
      (
        #|{"run_id":"r","job_id":"j","event_type":"step","timestamp":4,"step_id":"","status":"Succeeded","message":"second","data":{}}
      ),
      source="two",
    ),
  )
  let card = @job_journal.journal_run_directory(entries).runs[0]
  assert_eq(card.events, 3)
  assert_eq(card.steps, 1)
  assert_eq(card.sources, ["one", "two"])
  assert_eq(card.last_event.source, "two")
  assert_eq(card.last_run_status, None)
  assert_true(card.status_source is None)
}

///|
test "run directory rejects invalid bounds and oversized input" {
  let entries = directory_fixture()
  assert_true(
    (Ok(@job_journal.journal_run_directory(entries, limit=0)) catch {
      error => Err(error)
    })
    is Err(_),
  )
  assert_true(
    (Ok(@job_journal.journal_run_directory(entries, limit=101)) catch {
      error => Err(error)
    })
    is Err(_),
  )
  assert_true(
    (Ok(@job_journal.journal_run_directory(entries, offset=-1)) catch {
      error => Err(error)
    })
    is Err(_),
  )
  assert_true(
    (Ok(@job_journal.journal_run_directory(Array::make(10001, entries[0]))) catch {
      error => Err(error)
    })
    is Err(_),
  )
}
