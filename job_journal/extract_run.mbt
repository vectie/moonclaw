///|
/// Extract a complete exact job/run pair as a reusable saved JSONL journal.
/// Every supplied event is validated, including unrelated events. Records are
/// serialized without changing their JSON values; duplicate observations and
/// equal-timestamp input order survive. Original whitespace/source lines do not.
/// The result can be parsed again by parse_journal (4 Mi UTF-16 code units).
pub fn extract_run_journal(
  entries : Array[JournalEntry],
  job_id~ : String,
  run_id~ : String,
) -> String raise {
  // Validate and sort all records before selecting the exact pair.
  let ordered = select_journal_entries(entries)
  let lines : Array[String] = []
  let mut units = 0
  for entry in ordered {
    let event = event_fields(entry)
    if event.job_id != job_id || event.run_id != run_id {
      continue
    }
    let line = entry.record.stringify()
    guard line.length() < 4194304 - units else {
      fail("Extracted journal exceeds 4 Mi code units")
    }
    units += line.length() + 1
    lines.push(line)
  }
  guard !lines.is_empty() else {
    fail("No observations for the exact job/run pair")
  }
  lines.join("\n") + "\n"
}
