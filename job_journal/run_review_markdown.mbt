///|
/// Render a review to save next to the selected export's manifest.json.
/// Only validated portable member paths become links; original paths stay inert.
pub fn RunReview::to_markdown(self : RunReview) -> String raise {
  let lines : Array[String] = [
    "# Saved run review",
    "",
    "- Run: \{markdown_text(self.run_id)}",
    "- Job: \{markdown_text(self.job_id)}",
    "- Manifest: \{markdown_text(self.manifest_source)}",
    "- Included: \{self.events.length()} events, \{self.artifacts.length()} artifacts, \{self.selected_content_bytes} declared content bytes",
    "- Other runs excluded: \{self.excluded_events} events, \{self.excluded_artifacts} artifacts",
    "",
  ]
  for note in self.notes {
    lines.push(markdown_text(note))
    lines.push("")
  }
  lines.push("## Exported output revisions")
  lines.push("")
  lines.push(
    "Save this document beside manifest.json so the relative file links resolve. Verify the export's SHA256SUMS separately before trusting copied bytes.",
  )
  lines.push("")
  for artifact in self.artifacts {
    let fields = review_artifact_fields(artifact)
    guard fields.record_path == "records/\{artifact.index}.json" &&
      review_member_path(fields.content_path, artifact.index) else {
      fail("Artifact member paths are not safe portable links")
    }
    let record = fields.record
    lines.push("### \{markdown_text(record.id)} · revision \{record.version}")
    lines.push("")
    if record.logical_key is Some(key) {
      lines.push("- Logical output: \{markdown_text(key)}")
    }
    lines.push(
      "- Type: \{markdown_text(record.artifact_type)}; content type: \{markdown_text(record.content_type)}",
    )
    lines.push(
      "- Recorded artifact status: \{markdown_text(record.status.stringify())}",
    )
    lines.push("- Scope: \{markdown_text(record.scope.to_json().stringify())}")
    lines.push("- Metadata: \{markdown_text(record.metadata.stringify())}")
    lines.push("- Created timestamp: \{record.created_at}")
    if record.archived_at is Some(time) {
      lines.push("- Archived timestamp: \{time}")
    }
    lines.push(
      "- [Open exported content](\{fields.content_path}) · [Original record](\{fields.record_path})",
    )
    lines.push(
      "- Declared content: \{fields.content_bytes} bytes; \{markdown_text(fields.content_sha256)}",
    )
    lines.push(
      "- Declared original record digest: \{markdown_text(fields.record_sha256)}",
    )
    lines.push(
      "- Original path (provenance only): \{markdown_text(record.path)}",
    )
    lines.push("- Manifest entry: \{artifact.index}")
    lines.push("")
  }
  lines.push("## Recorded journal")
  lines.push("")
  lines.push(
    "Stored timestamps retain the producer's scale. Equal timestamps retain input order. Full structured event data and export-entry metadata remain in the JSON review.",
  )
  lines.push("")
  for entry in self.events {
    let event = event_fields(entry)
    lines.push("### \{event.timestamp} · \{markdown_text(event.event_type)}")
    lines.push("")
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
  lines.join("\n") + "\n"
}
