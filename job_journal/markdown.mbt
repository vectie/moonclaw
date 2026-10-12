///|
fn markdown_text(text : String) -> String {
  let output = StringBuilder::new()
  for character in text {
    match character {
      '&' => output.write_string("&amp;")
      '<' => output.write_string("&lt;")
      '>' => output.write_string("&gt;")
      '\n' => output.write_string(" ")
      '\r' => ()
      '\\'
      | '`'
      | '*'
      | '_'
      | '{'
      | '}'
      | '['
      | ']'
      | '('
      | ')'
      | '#'
      | '+'
      | '-'
      | '.'
      | '!'
      | '|' => {
        output.write_char('\\')
        output.write_char(character)
      }
      _ => output.write_char(character)
    }
  }
  output.to_string()
}

///|
/// Human-readable saved-journal digest. Full event data stays in JSON export;
/// messages are escaped as inert Markdown text, with no generated file links.
pub fn JournalPage::to_markdown(self : JournalPage) -> String raise {
  let lines : Array[String] = [
    "# Saved job journal",
    "",
    "Recorded observations only. This view does not establish current runtime status or owner acceptance.",
    "",
    "Source records: \{self.total_events}; matching records: \{self.matched_events}; shown: \{self.returned_events}; offset: \{self.offset}.",
    "",
  ]
  if self.entries.is_empty() {
    lines.push("No events on this page.")
  }
  for entry in self.entries {
    let event = event_fields(entry)
    lines.push("## \{event.timestamp} · \{markdown_text(event.event_type)}")
    lines.push("")
    lines.push("- Run: \{markdown_text(event.run_id)}")
    lines.push("- Job: \{markdown_text(event.job_id)}")
    if event.step_id is Some(step) {
      lines.push("- Step: \{markdown_text(step)}")
    }
    if event.status is Some(status) {
      lines.push("- Recorded status: \{markdown_text(status.stringify())}")
    }
    lines.push("- Source: \{markdown_text(entry.source)}; line \{entry.line}")
    lines.push("")
    lines.push(markdown_text(event.message))
    lines.push("")
  }
  if self.next_offset is Some(offset) {
    lines.push("Next offset: \{offset}.")
  }
  lines.join("\n") + "\n"
}
