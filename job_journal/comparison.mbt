///|
pub struct JournalEventCount {
  event_type : String
  count : Int32
} derive(ToJson, Eq)

///|
/// An observed interval, not execution duration. First/last and last status keep
/// their complete original source records so callers can inspect the evidence.
pub struct JournalObservation {
  events : Int32
  first : JournalEntry
  last : JournalEntry
  span : Int64
  event_counts : Array[JournalEventCount]
  last_status : Json?
  status_source : JournalEntry?
} derive(ToJson)

///|
pub struct JournalStepComparison {
  step_id : String
  presence : String
  baseline : JournalObservation?
  candidate : JournalObservation?
  span_delta : Int64?
  event_count_delta : Int32
  status_changed : Bool?
  event_counts_changed : Bool?
  last_message_changed : Bool?
} derive(ToJson)

///|
pub struct JournalRunComparison {
  schema : String
  baseline_run : String
  candidate_run : String
  baseline_job : String
  candidate_job : String
  baseline : JournalObservation
  candidate : JournalObservation
  span_delta : Int64
  steps : Array[JournalStepComparison]
  baseline_run_level_events : Int32
  candidate_run_level_events : Int32
} derive(ToJson)

///|
fn observe_journal(entries : Array[JournalEntry]) -> JournalObservation raise {
  guard !entries.is_empty() else { fail("Cannot observe an empty selection") }
  let counts : Map[String, Int32] = {}
  let mut status : Json? = None
  let mut status_source : JournalEntry? = None
  for entry in entries {
    let fields = event_fields(entry)
    counts[fields.event_type] = counts.get(fields.event_type).unwrap_or(0) + 1
    if fields.status is Some(value) {
      status = Some(value)
      status_source = Some(entry)
    }
  }
  let event_counts : Array[JournalEventCount] = []
  for event_type, count in counts {
    event_counts.push({ event_type, count, })
  }
  event_counts.sort_by((a, b) => a.event_type.lexical_compare(b.event_type))
  let first = entries[0]
  let last = entries[entries.length() - 1]
  {
    events: entries.length(),
    first,
    last,
    span: event_fields(last).timestamp.to_int64() -
    event_fields(first).timestamp.to_int64(),
    event_counts,
    last_status: status,
    status_source,
  }
}

///|
fn journal_run_parts(
  entries : Array[JournalEntry],
  run_id : String,
) -> (String, JournalObservation, Map[String, Array[JournalEntry]], Int32) raise {
  let selected : Array[(JournalEntry, Int32, Int32)] = []
  let mut job_id : String? = None
  for index, entry in entries {
    let event = event_fields(entry)
    if event.run_id != run_id {
      continue
    }
    if job_id is Some(job) && job != event.job_id {
      fail("Selected run ID occurs under multiple job IDs")
    }
    job_id = Some(event.job_id)
    selected.push((entry, event.timestamp, index))
  }
  guard job_id is Some(job) else { fail("Selected run has no journal events") }
  selected.sort_by((a, b) => {
    let time = a.1.compare(b.1)
    if time == 0 {
      a.2.compare(b.2)
    } else {
      time
    }
  })
  let sorted = selected.map(item => item.0)
  let steps : Map[String, Array[JournalEntry]] = {}
  let mut run_level = 0
  for entry in sorted {
    match event_fields(entry).step_id {
      Some(step) => {
        let group = steps
          .get(step)
          .unwrap_or_else(() => {
            let group : Array[JournalEntry] = []
            steps[step] = group
            group
          })
        group.push(entry)
      }
      None => run_level += 1
    }
  }
  (job, observe_journal(sorted), steps, run_level)
}

///|
/// Compare explicit saved runs by exact step ID. Events are never paired into
/// attempts, deduplicated, or treated as live state. All supplied records are
/// validated, including those outside the two selected runs.
pub fn compare_journal_runs(
  entries : Array[JournalEntry],
  baseline_run~ : String,
  candidate_run~ : String,
) -> JournalRunComparison raise {
  guard entries.length() <= 10000 else {
    fail("Combined journals exceed 10000 events")
  }
  guard !baseline_run.is_blank() && !candidate_run.is_blank() else {
    fail("Both run IDs must be nonblank")
  }
  guard baseline_run != candidate_run else {
    fail("Select two distinct run IDs")
  }
  let (baseline_job, baseline, left, baseline_run_level_events) = journal_run_parts(
    entries, baseline_run,
  )
  let (candidate_job, candidate, right, candidate_run_level_events) = journal_run_parts(
    entries, candidate_run,
  )
  let ids : Array[String] = []
  for id, _ in left {
    ids.push(id)
  }
  for id, _ in right {
    if !left.contains(id) {
      ids.push(id)
    }
  }
  ids.sort_by((a, b) => a.lexical_compare(b))
  let steps : Array[JournalStepComparison] = []
  for step_id in ids {
    let a = left.get(step_id).map(group => observe_journal(group))
    let b = right.get(step_id).map(group => observe_journal(group))
    let presence = match (a, b) {
      (None, Some(_)) => "added"
      (Some(_), None) => "removed"
      _ => "matched"
    }
    let (span_delta, status_changed, event_counts_changed, last_message_changed) = match
      (a, b) {
      (Some(a), Some(b)) =>
        (
          Some(b.span - a.span),
          Some(a.last_status != b.last_status),
          Some(a.event_counts != b.event_counts),
          Some(event_fields(a.last).message != event_fields(b.last).message),
        )
      _ => (None, None, None, None)
    }
    steps.push({
      step_id,
      presence,
      baseline: a,
      candidate: b,
      span_delta,
      event_count_delta: b.map(x => x.events).unwrap_or(0) -
      a.map(x => x.events).unwrap_or(0),
      status_changed,
      event_counts_changed,
      last_message_changed,
    })
  }
  {
    schema: "moonclaw.job-run-comparison.v1",
    baseline_run,
    candidate_run,
    baseline_job,
    candidate_job,
    span_delta: candidate.span - baseline.span,
    baseline,
    candidate,
    steps,
    baseline_run_level_events,
    candidate_run_level_events,
  }
}
