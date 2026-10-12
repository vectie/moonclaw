///|
/// One exact (job, run) pair discovered in saved journals. A status belongs only
/// to the last status-bearing run-level event; step status never becomes run status.
pub struct JournalRunCard {
  job_id : String
  run_id : String
  ambiguous_run_id : Bool
  events : Int
  steps : Int
  sources : Array[String]
  first_timestamp : Int
  last_timestamp : Int
  last_event : JournalEntry
  last_run_status : Json?
  status_source : JournalEntry?
} derive(ToJson)

///|
pub struct JournalRunDirectory {
  schema : String
  total_events : Int
  total_runs : Int
  matched_runs : Int
  offset : Int
  next_offset : Int?
  runs : Array[JournalRunCard]
} derive(ToJson)

///|
/// Discover runs before choosing an existing journal inspection command. Filters
/// select whole run cards, never partial event histories. Every input is validated.
/// Ordering is latest timestamp descending, then job ID and run ID lexically.
pub fn journal_run_directory(
  entries : Array[JournalEntry],
  job_id? : String,
  query? : String,
  offset? : Int = 0,
  limit? : Int = 50,
) -> JournalRunDirectory raise {
  guard offset >= 0 else { fail("Offset must be nonnegative") }
  guard limit >= 1 && limit <= 100 else {
    fail("Limit must be between 1 and 100")
  }
  let sorted = select_journal_entries(entries)
  let groups : Map[String, Array[JournalEntry]] = {}
  let run_jobs : Map[String, Map[String, Bool]] = {}
  for entry in sorted {
    let event = event_fields(entry)
    let key = [event.job_id, event.run_id].to_json().stringify()
    let group = groups
      .get(key)
      .unwrap_or_else(() => {
        let group : Array[JournalEntry] = []
        groups[key] = group
        group
      })
    group.push(entry)
    let jobs = run_jobs
      .get(event.run_id)
      .unwrap_or_else(() => {
        let jobs : Map[String, Bool] = {}
        run_jobs[event.run_id] = jobs
        jobs
      })
    jobs[event.job_id] = true
  }
  let needle = query.map(text => text.to_lower())
  let cards : Array[JournalRunCard] = []
  for _, group in groups {
    let first = event_fields(group[0])
    if job_id is Some(job) && first.job_id != job {
      continue
    }
    let steps : Map[String, Bool] = {}
    let sources : Array[String] = []
    let mut status : Json? = None
    let mut status_source : JournalEntry? = None
    let mut matches = match needle {
      None => true
      Some(text) =>
        first.run_id.to_lower().contains(text) ||
        first.job_id.to_lower().contains(text)
    }
    for entry in group {
      let event = event_fields(entry)
      if needle is Some(text) && event.message.to_lower().contains(text) {
        matches = true
      }
      if !sources.contains(entry.source) {
        sources.push(entry.source)
      }
      match event.step_id {
        Some(step) => steps[step] = true
        None =>
          if event.status is Some(value) {
            status = Some(value)
            status_source = Some(entry)
          }
      }
    }
    if !matches {
      continue
    }
    let last_event = group[group.length() - 1]
    cards.push({
      job_id: first.job_id,
      run_id: first.run_id,
      ambiguous_run_id: run_jobs[first.run_id].length() > 1,
      events: group.length(),
      steps: steps.length(),
      sources,
      first_timestamp: first.timestamp,
      last_timestamp: event_fields(last_event).timestamp,
      last_event,
      last_run_status: status,
      status_source,
    })
  }
  cards.sort_by((a, b) => {
    let time = b.last_timestamp.compare(a.last_timestamp)
    let job = a.job_id.lexical_compare(b.job_id)
    if time != 0 {
      time
    } else if job != 0 {
      job
    } else {
      a.run_id.lexical_compare(b.run_id)
    }
  })
  let selected : Array[JournalRunCard] = []
  for index, card in cards {
    if index >= offset && index - offset < limit {
      selected.push(card)
    }
  }
  {
    schema: "moonclaw.saved-run-directory.v1",
    total_events: entries.length(),
    total_runs: groups.length(),
    matched_runs: cards.length(),
    offset,
    next_offset: if offset < cards.length() - selected.length() {
      Some(offset + selected.length())
    } else {
      None
    },
    runs: selected,
  }
}

///|
/// Inert readable directory. Original status and last observation are retained
/// in the JSON form. No links, controls, acceptance or current state are inferred.
pub fn JournalRunDirectory::to_markdown(
  self : JournalRunDirectory,
) -> String raise {
  let lines = [
    "# Saved run directory",
    "",
    "Historical observations only. Latest recorded run status is not current runtime status, safe retry permission, or owner acceptance.",
    "",
    "Runs: \{self.total_runs}; matching: \{self.matched_runs}; shown: \{self.runs.length()}; offset: \{self.offset}.",
    "",
  ]
  for card in self.runs {
    lines.push("## " + markdown_text(card.run_id))
    lines.push("- Job: " + markdown_text(card.job_id))
    lines.push(
      "- Observed interval: \{card.first_timestamp} to \{card.last_timestamp}; events: \{card.events}; distinct steps: \{card.steps}",
    )
    lines.push(
      "- Latest recorded run-level status: " +
      markdown_text(
        card.last_run_status
        .map(value => value.stringify())
        .unwrap_or("not recorded"),
      ),
    )
    if card.status_source is Some(entry) {
      lines.push(
        "- Status source: " +
        markdown_text(entry.source) +
        "; line \{entry.line}",
      )
    }
    if card.ambiguous_run_id {
      lines.push(
        "- Ambiguous run ID: also recorded under another job. Keep job identity when inspecting; run-only selection is unsafe.",
      )
    }
    lines.push(
      "- Last observation source: " +
      markdown_text(card.last_event.source) +
      "; line \{card.last_event.line}",
    )
    lines.push(markdown_text(event_fields(card.last_event).message))
    lines.push("")
  }
  if self.runs.is_empty() {
    lines.push("No runs on this page.")
  }
  if self.next_offset is Some(offset) {
    lines.push("Next offset: \{offset}.")
  }
  lines.join("\n") + "\n"
}
