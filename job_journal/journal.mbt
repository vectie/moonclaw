///|
// Shared selection for paged inspection and full CSV export. Validation always
// includes unselected records; ties retain their original input positions.
fn select_journal_entries(
  entries : Array[JournalEntry],
  run_id? : String,
  step_id? : String,
  event_type? : String,
  query? : String,
  since? : Int,
  until? : Int,
) -> Array[JournalEntry] raise {
  guard entries.length() <= 10000 else {
    fail("Combined journals exceed 10000 events")
  }
  match (since, until) {
    (Some(start), Some(end)) if start > end =>
      fail("Since must not exceed until")
    _ => ()
  }
  let needle = query.map(text => text.to_lower())
  let matched : Array[(JournalEntry, Int, Int)] = []
  for position, entry in entries {
    let event = event_fields(entry)
    if run_id is Some(id) && event.run_id != id {
      continue
    }
    if step_id is Some(id) && event.step_id != Some(id) {
      continue
    }
    if event_type is Some(kind) && event.event_type != kind {
      continue
    }
    if since is Some(start) && event.timestamp < start {
      continue
    }
    if until is Some(end) && event.timestamp > end {
      continue
    }
    if needle is Some(text) && !event.message.to_lower().contains(text) {
      continue
    }
    matched.push((entry, event.timestamp, position))
  }
  matched.sort_by(fn(left, right) {
    let time_order = left.1.compare(right.1)
    if time_order == 0 {
      left.2.compare(right.2)
    } else {
      time_order
    }
  })
  matched.map(item => item.0)
}

///|
/// One original job event, with its physical position in an explicit input.
/// The record includes unknown fields unchanged and is never executed.
pub struct JournalEntry {
  source : String
  line : Int
  record : Json
} derive(ToJson)

///|
/// An offline view of saved observations, not a live runtime status projection.
pub struct JournalPage {
  schema : String
  total_events : Int
  matched_events : Int
  returned_events : Int
  offset : Int
  next_offset : Int?
  entries : Array[JournalEntry]
} derive(ToJson)

///|
// This projection follows JobRunEvent's durable JSON shape. Keep the original
// JSON alongside it so additional producer fields and status values survive.
priv struct EventFields {
  run_id : String
  job_id : String
  event_type : String
  timestamp : Int
  step_id : String?
  status : Json?
  message : String
  data : Json
} derive(FromJson)

///|
fn event_fields(entry : JournalEntry) -> EventFields raise {
  // The derived optional-string decoder accepts absence but rejects JSON null.
  // Project a null step as run-level without changing the retained raw record.
  let projection = if entry.record is { "step_id": Null, .. } {
    let fields : Map[String, Json] = Map([])
    if entry.record is Object(original) {
      for key, value in original {
        if key != "step_id" {
          fields[key] = value
        }
      }
    }
    fields.to_json()
  } else {
    entry.record
  }
  let fields : EventFields = @json.from_json(projection) catch {
    _ =>
      fail(
        "Invalid job event at source \{entry.source.to_json().stringify()} line \{entry.line}",
      )
  }
  guard entry.record is { "timestamp": Number(number, ..), .. } &&
    number == fields.timestamp.to_double() else {
    fail(
      "Invalid job timestamp at source \{entry.source.to_json().stringify()} line \{entry.line}",
    )
  }
  fields
}

///|
/// Read actual SystemStore events.jsonl bytes decoded as text. Blank lines are
/// skipped but physical source line numbers remain intact. Parsing is all-or-
/// nothing, including records outside a later filter or requested page.
pub fn parse_journal(
  text : String,
  source~ : String,
) -> Array[JournalEntry] raise {
  guard !source.is_blank() else { fail("A journal source name is required") }
  guard text.length() <= 4194304 else {
    fail("Journal exceeds 4 Mi code units")
  }
  let entries : Array[JournalEntry] = []
  for index, raw in text.split("\n").to_array() {
    let line = raw.trim()
    if line.is_empty() {
      continue
    }
    guard entries.length() < 10000 else { fail("Journal exceeds 10000 events") }
    let record = @json.parse(line.to_owned()) catch {
      _ =>
        fail(
          "Invalid JSON at source \{source.to_json().stringify()} line \{index + 1}",
        )
    }
    let entry = JournalEntry::{ source, line: index + 1, record, }
    ignore(event_fields(entry))
    entries.push(entry)
  }
  entries
}

///|
/// Merge explicit journal records, then filter and page in chronological order.
/// Equal timestamps retain input-array order. No event is deduplicated: even
/// identical records can be distinct persisted observations.
pub fn explore_journal(
  entries : Array[JournalEntry],
  run_id? : String,
  step_id? : String,
  event_type? : String,
  query? : String,
  since? : Int,
  until? : Int,
  offset? : Int = 0,
  limit? : Int = 100,
) -> JournalPage raise {
  guard offset >= 0 else { fail("Offset must be nonnegative") }
  guard limit >= 1 && limit <= 1000 else {
    fail("Limit must be between 1 and 1000")
  }
  let matched = select_journal_entries(
    entries,
    run_id?,
    step_id?,
    event_type?,
    query?,
    since?,
    until?,
  )
  let selected : Array[JournalEntry] = []
  // Subtraction avoids overflowing for a large valid offset.
  for position, item in matched {
    if position >= offset && position - offset < limit {
      selected.push(item)
    }
  }
  let next_offset = if selected.length() < matched.length() &&
    offset < matched.length() - selected.length() {
    Some(offset + selected.length())
  } else {
    None
  }
  {
    schema: "moonclaw.job-journal-page.v1",
    total_events: entries.length(),
    matched_events: matched.length(),
    returned_events: selected.length(),
    offset,
    next_offset,
    entries: selected,
  }
}
