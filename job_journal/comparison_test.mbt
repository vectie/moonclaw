///|
fn comparison_event(
  run : String,
  timestamp : Int,
  step? : String,
  status? : Json,
  kind? : String = "step.observed",
  message? : String = "observation",
  job? : String = "job",
) -> String {
  let fields : Map[String, Json] = {
    "run_id": run.to_json(),
    "job_id": job.to_json(),
    "timestamp": timestamp.to_json(),
    "event_type": kind.to_json(),
    "message": message.to_json(),
    "data": { "future": [1, 2] },
  }
  if step is Some(value) {
    fields["step_id"] = value.to_json()
  }
  if status is Some(value) {
    fields["status"] = value
  }
  fields.to_json().stringify()
}

///|
test "compare runs aligns exact steps and preserves original evidence" {
  let input = [
    comparison_event("old", 30, step="work", status="Succeeded"),
    comparison_event(
      "new",
      120,
      step="work",
      status="Unknown",
      message="lost acknowledgement",
    ),
    comparison_event("old", 10, step="work", status="Running"),
    comparison_event("new", 100, step="work", status="Running"),
    comparison_event("old", 1),
    comparison_event("new", 90),
    comparison_event("old", 11, step="removed"),
    comparison_event("new", 110, step="added"),
    comparison_event("other", -1000),
  ].join("\n")
  let entries = @job_journal.parse_journal(input, source="saved.jsonl")
  let result = @job_journal.compare_journal_runs(
    entries,
    baseline_run="old",
    candidate_run="new",
  )
  assert_eq(result.schema, "moonclaw.job-run-comparison.v1")
  assert_eq(result.baseline.events, 4)
  assert_eq(result.candidate.events, 4)
  assert_eq(result.span_delta, 1L)
  assert_eq(result.baseline_run_level_events, 1)
  assert_eq(result.candidate_run_level_events, 1)
  assert_eq(result.steps.map(x => x.step_id), ["added", "removed", "work"])
  assert_eq(result.steps.map(x => x.presence), ["added", "removed", "matched"])
  assert_eq(result.steps[0].event_count_delta, 1)
  assert_eq(result.steps[1].event_count_delta, -1)
  assert_eq(result.steps[0].span_delta, None)
  let work = result.steps[2]
  assert_eq(work.span_delta, Some(0L))
  assert_eq(work.status_changed, Some(true))
  assert_eq(work.event_counts_changed, Some(false))
  assert_eq(work.last_message_changed, Some(true))
  guard work.candidate is Some(candidate) else { fail("Missing candidate") }
  assert_eq(candidate.last_status, Some(Json::string("Unknown")))
  assert_eq(candidate.last.line, 2)
  assert_eq(candidate.last.record, entries[1].record)
  assert_eq(candidate.status_source.map(x => x.line), Some(2))
  assert_true(result.to_markdown().contains("lost acknowledgement"))
}

///|
test "duplicate observations and timestamp ties retain source order" {
  let a = @job_journal.parse_journal(
    "\n" +
    comparison_event("old", 7, step="s", status="first") +
    "\n" +
    comparison_event("old", 7, step="s", status="second") +
    "\n" +
    comparison_event("old", 7, step="s", kind="note"),
    source="a",
  )
  let b = @job_journal.parse_journal(
    comparison_event("new", 7, step="s", status="second") +
    "\n" +
    comparison_event("new", 7, step="s", status="second"),
    source="b",
  )
  a.append(b)
  let result = @job_journal.compare_journal_runs(
    a,
    baseline_run="old",
    candidate_run="new",
  )
  assert_eq(result.baseline.span, 0L)
  assert_eq(result.baseline.last.line, 4)
  assert_eq(result.baseline.status_source.map(x => x.line), Some(3))
  assert_eq(result.candidate.events, 2)
  assert_eq(result.steps[0].event_counts_changed, Some(true))
  assert_eq(result.steps[0].status_changed, Some(false))
  assert_eq(result.steps[0].event_count_delta, -1)
}

///|
test "interval arithmetic is wide and negative deltas remain negative" {
  let text = [
    comparison_event("old", -2147483648, step="s"),
    comparison_event("old", 2147483647, step="s"),
    comparison_event("new", 0, step="s"),
  ].join("\n")
  let result = @job_journal.compare_journal_runs(
    @job_journal.parse_journal(text, source="extreme"),
    baseline_run="old",
    candidate_run="new",
  )
  assert_eq(result.baseline.span, 4294967295L)
  assert_eq(result.span_delta, -4294967295L)
  assert_true(
    result.to_json().stringify().contains("\"span_delta\":\"-4294967295\""),
  )
  assert_eq(result.steps[0].span_delta, Some(-4294967295L))
  assert_eq(result.baseline.last_status, None)
  assert_eq(result.steps[0].status_changed, Some(false))
}

///|
test "run-level observations and cross-job comparison remain explicit" {
  let result = @job_journal.compare_journal_runs(
    @job_journal.parse_journal(
      comparison_event("old", 1, job="job-a") +
      "\n" +
      comparison_event("new", 2, job="job-b"),
      source="runs",
    ),
    baseline_run="old",
    candidate_run="new",
  )
  assert_eq(result.baseline_job, "job-a")
  assert_eq(result.candidate_job, "job-b")
  assert_eq(result.steps.length(), 0)
  assert_eq(result.baseline_run_level_events, 1)
  assert_eq(result.candidate_run_level_events, 1)
  assert_true(result.to_markdown().contains("No step-scoped observations"))
}

///|
test "unusable run selections and ambiguous identities fail" {
  let entries = @job_journal.parse_journal(
    comparison_event("old", 1) + "\n" + comparison_event("new", 2),
    source="valid",
  )
  for pair in [("old", "old"), ("old", "missing"), (" ", "new")] {
    try
      @job_journal.compare_journal_runs(
        entries,
        baseline_run=pair.0,
        candidate_run=pair.1,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("Expected invalid selection")
    }
  }
  entries.append(
    @job_journal.parse_journal(
      comparison_event("old", 3, job="conflicting"),
      source="conflict",
    ),
  )
  try
    @job_journal.compare_journal_runs(
      entries,
      baseline_run="old",
      candidate_run="new",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("Expected ambiguous run failure")
  }
  try
    @job_journal.compare_journal_runs(
      [],
      baseline_run="old",
      candidate_run="new",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("Expected empty input failure")
  }
}

///|
test "Markdown renders identifiers messages and source paths inert" {
  let entries = @job_journal.parse_journal(
    comparison_event(
      "old",
      1,
      step="<img>*step*",
      message="[click](https://example.invalid)\n<script>",
    ) +
    "\n" +
    comparison_event("new", 2, step="<img>*step*", status={ "future": "<svg>" }),
    source="[path]<x>",
  )
  let result = @job_journal.compare_journal_runs(
    entries,
    baseline_run="old",
    candidate_run="new",
  )
  let markdown = result.to_markdown()
  assert_true(markdown.contains("&lt;img&gt;\\*step\\*"))
  assert_true(markdown.contains("\\[path\\]&lt;x&gt;"))
  assert_true(!markdown.contains("<script>"))
  assert_true(!markdown.contains("[click](https://"))
  assert_eq(result.steps[0].status_changed, Some(true))
}
