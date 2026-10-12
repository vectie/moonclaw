///|
fn observation_markdown(
  label : String,
  observation : JournalObservation,
) -> String raise {
  let first = event_fields(observation.first)
  let last = event_fields(observation.last)
  let status = observation.last_status
    .map(value => value.stringify())
    .unwrap_or("not recorded")
  let lines : Array[String] = [
    "- \{label}: \{observation.events} events; observed span \{observation.span}; timestamps \{first.timestamp} → \{last.timestamp}",
    "  - Last recorded status: \{markdown_text(status)}",
    "  - First: \{markdown_text(observation.first.source)} line \{observation.first.line}",
    "  - Last: \{markdown_text(observation.last.source)} line \{observation.last.line}",
    "  - Last message: \{markdown_text(last.message)}",
  ]
  if observation.status_source is Some(source) {
    lines.push(
      "  - Status source: \{markdown_text(source.source)} line \{source.line}",
    )
  }
  for count in observation.event_counts {
    lines.push("  - \{markdown_text(count.event_type)}: \{count.count}")
  }
  lines.join("\n")
}

///|
pub fn JournalRunComparison::to_markdown(
  self : JournalRunComparison,
) -> String raise {
  let lines : Array[String] = [
    "# Compare saved job runs",
    "",
    "Recorded observations only, not live status or owner acceptance. Spans use the producer's stored timestamp units, not measured execution duration. Deltas are candidate minus baseline.",
    "",
    "Baseline run: \{markdown_text(self.baseline_run)}; job: \{markdown_text(self.baseline_job)}.",
    "Candidate run: \{markdown_text(self.candidate_run)}; job: \{markdown_text(self.candidate_job)}.",
    "",
    observation_markdown("Baseline", self.baseline),
    observation_markdown("Candidate", self.candidate),
    "",
    "Run span delta: \{self.span_delta}.",
    "Run-level events without a step: baseline \{self.baseline_run_level_events}; candidate \{self.candidate_run_level_events}.",
    "",
    "Steps are aligned by exact ID only. Repeated attempts within a step are aggregated; added/removed means absent from the supplied observations.",
    "",
  ]
  if self.steps.is_empty() {
    lines.push("No step-scoped observations.")
  }
  for step in self.steps {
    lines.push("## \{markdown_text(step.step_id)} · \{step.presence}")
    lines.push("")
    if step.baseline is Some(value) {
      lines.push(observation_markdown("Baseline", value))
    }
    if step.candidate is Some(value) {
      lines.push(observation_markdown("Candidate", value))
    }
    lines.push("- Event count delta: \{step.event_count_delta}")
    if step.span_delta is Some(delta) {
      lines.push("- Observed span delta: \{delta}")
    }
    if step.status_changed is Some(value) {
      lines.push("- Recorded status changed: \{value}")
    }
    if step.event_counts_changed is Some(value) {
      lines.push("- Event type/count distribution changed: \{value}")
    }
    if step.last_message_changed is Some(value) {
      lines.push("- Last message changed: \{value}")
    }
    lines.push("")
  }
  lines.join("\n") + "\n"
}
