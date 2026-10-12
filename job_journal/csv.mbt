///|
// Quoting protects CSV structure. The separate leading-apostrophe convention
// reduces spreadsheet formula interpretation and is recorded for exact undo.
fn csv_quote(value : String) -> String {
  "\"" + value.replace_all(old="\"", new="\"\"") + "\""
}

///|
fn csv_needs_prefix(value : String) -> Bool {
  for character in value {
    match character {
      '\t' | '\r' | '\n' | '\u{FEFF}' => return true
      ' ' => continue
      '=' | '+' | '-' | '@' | '\'' => return true
      _ => return false
    }
  }
  false
}

///|
/// Export every matching saved observation as UTF-8-compatible RFC 4180 CSV.
/// This is a bounded offline selection, not a live state or an importable store.
/// Strings that could be interpreted as formulas get a leading apostrophe;
/// text_prefixed_columns records exactly which fields received it. The parsed
/// original record, including unknown fields, is retained as record_json.
pub fn journal_csv(
  entries : Array[JournalEntry],
  run_id? : String,
  step_id? : String,
  event_type? : String,
  query? : String,
  since? : Int,
  until? : Int,
) -> String raise {
  let selected = select_journal_entries(
    entries,
    run_id?,
    step_id?,
    event_type?,
    query?,
    since?,
    until?,
  )
  let columns = [
    "source", "source_line", "timestamp", "run_id", "job_id", "step_id", "event_type",
    "status_json", "message", "data_json", "record_json", "text_prefixed_columns",
  ]
  let rows = [columns.join(",")]
  let mut units = rows[0].length() + 2
  for entry in selected {
    let event = event_fields(entry)
    let values = [
      entry.source,
      entry.line.to_string(),
      event.timestamp.to_string(),
      event.run_id,
      event.job_id,
      event.step_id.unwrap_or(""),
      event.event_type,
      event.status.map(status => status.stringify()).unwrap_or(""),
      event.message,
      event.data.stringify(),
      entry.record.stringify(),
    ]
    let prefixed : Array[String] = []
    for index, value in values {
      // Physical lines and producer timestamps are validated integer values.
      if index != 1 && index != 2 && csv_needs_prefix(value) {
        values[index] = "'" + value
        prefixed.push(columns[index])
      }
    }
    values.push(prefixed.join(";"))
    let row = values.map(csv_quote).join(",")
    guard row.length() <= 16777216 - units - 2 else {
      fail("CSV export exceeds 16 Mi code units; narrow the selection")
    }
    units += row.length() + 2
    rows.push(row)
  }
  rows.join("\r\n") + "\r\n"
}
