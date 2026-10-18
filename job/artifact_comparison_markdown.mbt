///|
fn comparison_markdown_text(text : String) -> String {
  let output = StringBuilder()
  for c in text {
    match c {
      '&' => output.write_string("&amp;")
      '<' => output.write_string("&lt;")
      '>' => output.write_string("&gt;")
      '\n' => output.write_string("\\n")
      '\r' => output.write_string("\\r")
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
        output.write_char(c)
      }
      _ => output.write_char(c)
    }
  }
  output.to_string()
}

///|
/// Compact changed-line review. JSON includes the unchanged lines as well.
pub fn ArtifactComparison::to_markdown(self : ArtifactComparison) -> String {
  let lines = [
    "# Retained artifact comparison", "", "Observed saved content only; this does not establish owner acceptance or immutable history.",
    "",
  ]
  for pair in [("Left", self.left), ("Right", self.right)] {
    let (side, artifact) = pair
    let record = artifact.record
    lines.push(
      "- \{side}: \{comparison_markdown_text(record.id)}; run \{comparison_markdown_text(record.run_id)}; version \{record.version}",
    )
    lines.push(
      "- \{side} bytes: \{artifact.content_bytes}; digest: \{artifact.content_sha256}",
    )
  }
  lines.push("")
  lines.push(
    "Added: \{self.diff.added_lines}; removed: \{self.diff.removed_lines}; unchanged: \{self.diff.unchanged_lines}.",
  )
  lines.push("")
  if self.diff.identical {
    lines.push("The retained text is identical.")
  }
  for edit in self.diff.edits {
    if edit.kind == "equal" {
      continue
    }
    let position = if edit.kind == "delete" {
      "Left line \{edit.left_line.unwrap()} removed"
    } else {
      "Right line \{edit.right_line.unwrap()} added"
    }
    let ending = if edit.ending == "\r\n" {
      "CRLF"
    } else if edit.ending == "\n" {
      "LF"
    } else {
      "no final newline"
    }
    lines.push(
      "- \{position} (\{ending}): \{comparison_markdown_text(Json(edit.text).stringify())}",
    )
  }
  lines.join("\n") + "\n"
}
