///|
test "HTML report exact pair preserves observation text, scope, and provenance" {
  let first : Json = {
    "run_id": "r<&",
    "job_id": "j",
    "timestamp": 1,
    "event_type": "<custom>",
    "message": "</pre><script>雪 & \"quote\"</script>",
    "data": { "future": [true, null] },
    "status": { "Unknown": [] },
  }
  let step : Json = {
    "run_id": "r<&",
    "job_id": "j",
    "timestamp": 2,
    "event_type": "step",
    "message": "step <done>",
    "data": null,
    "step_id": "",
    "status": "Completed",
  }
  let clear : Json = {
    "run_id": "r<&",
    "job_id": "j",
    "timestamp": 3,
    "event_type": "observation",
    "message": "no guess",
    "data": null,
    "status": null,
  }
  let other : Json = {
    "run_id": "r<&",
    "job_id": "other",
    "timestamp": 0,
    "event_type": "run",
    "message": "excluded-message",
    "data": null,
  }
  let entries = @job_journal.parse_journal(
    "\n" + [clear, step, other, first, step].map(x => x.stringify()).join("\n"),
    source="saved<&.jsonl",
  )
  let html = @job_journal.journal_run_html(entries, job_id="j", run_id="r<&")
  assert_true(html.has_prefix("<!doctype html>"))
  assert_true(
    html.contains("Selected observations: 4; excluded: 1; distinct steps: 1"),
  )
  assert_true(
    html.contains(
      "&lt;/pre&gt;&lt;script&gt;雪 &amp; &quot;quote&quot;&lt;/script&gt;",
    ),
  )
  assert_true(!html.contains("<script>"))
  assert_true(!html.contains("excluded-message"))
  assert_true(html.contains("saved&lt;&amp;.jsonl"))
  assert_true(html.contains("physical line 5"))
  assert_true(
    html.contains("<td><code>null</code></td><td><a href=\"#event-4\">"),
  )
  assert_true(html.contains("Step &quot;&quot;"))
  assert_eq(html.split("<details id=").to_array().length(), 5)
  assert_eq(
    html,
    @job_journal.journal_run_html(entries, job_id="j", run_id="r<&"),
  )
}

///|
test "HTML report validates unrelated records and rejects missing exact pair" {
  let entries = @job_journal.parse_journal(
    fixture("r", 1, "x").stringify(),
    source="input",
  )
  assert_true(
    (Ok(@job_journal.journal_run_html(entries, job_id="wrong", run_id="r")) catch {
      error => Err(error)
    })
    is Err(_),
  )
  assert_true(
    (Ok(@job_journal.journal_run_html([], job_id="job-1", run_id="r")) catch {
      error => Err(error)
    })
    is Err(_),
  )
  if entries[0].record is Object(fields) {
    fields.remove("status")
  }
  let html = @job_journal.journal_run_html(entries, job_id="job-1", run_id="r")
  assert_true(html.contains("<td><code>not recorded</code>"))
  let unrelated = @job_journal.parse_journal(
    fixture("other", 2, "bad").stringify(),
    source="bad",
  )
  if unrelated[0].record is Object(fields) {
    fields["timestamp"] = null
  }
  entries.append(unrelated)
  assert_true(
    (Ok(@job_journal.journal_run_html(entries, job_id="job-1", run_id="r")) catch {
      error => Err(error)
    })
    is Err(_),
  )
}

///|
test "null step remains run-level and its original record survives report and extraction" {
  let record : Json = {
    "job_id": "job-1",
    "run_id": "r",
    "event_type": "observed",
    "timestamp": 7,
    "step_id": null,
    "status": "ReviewPending",
    "message": "run-level with explicit null step",
    "data": null,
  }
  let entries = @job_journal.parse_journal(
    "\n" + record.stringify(),
    source="null-step",
  )
  assert_eq(entries[0].record, record)
  assert_eq(entries[0].line, 2)
  let html = @job_journal.journal_run_html(entries, job_id="job-1", run_id="r")
  assert_true(html.contains("distinct steps: 0"))
  assert_true(html.contains(">Run-level</a></th>"))
  assert_true(html.contains("&quot;step_id&quot;:null"))
  assert_true(html.contains("<td><code>&quot;ReviewPending&quot;</code>"))
  assert_eq(@job_journal.journal_run_directory(entries).runs[0].steps, 0)
  assert_eq(
    @job_journal.parse_journal(
      @job_journal.extract_run_journal(entries, job_id="job-1", run_id="r"),
      source="reopened",
    )[0].record,
    record,
  )
  // Null support must not silently accept other non-string step identifiers.
  if record is Object(fields) {
    fields["step_id"] = 4
  }
  try
    @job_journal.parse_journal(record.stringify(), source="invalid-step")
  catch {
    _ => ()
  } noraise {
    _ => fail("Expected non-string, non-null step ID to fail")
  }
}

///|
test "HTML report covers every event beyond explorer page and bounds expanded text" {
  let entry = @job_journal.parse_journal(
    fixture("r", 1, "x").stringify(),
    source="many",
  )
  let many : Array[@job_journal.JournalEntry] = []
  for _ in 0..<1001 {
    many.append(entry)
  }
  let html = @job_journal.journal_run_html(many, job_id="job-1", run_id="r")
  assert_true(html.contains("id=\"event-1001\""))
  let big = @job_journal.parse_journal(
    fixture("r", 1, "<".repeat(1100000)).stringify(),
    source="expanded",
  )
  try @job_journal.journal_run_html(big, job_id="job-1", run_id="r") catch {
    error =>
      assert_true(
        error.to_string().contains("HTML report exceeds 8 Mi code units"),
      )
  } noraise {
    _ => fail("Expected expanded output limit")
  }
}
