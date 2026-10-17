///|
/// A selected run's saved observations and exported output revisions together.
/// This joins supplied metadata, without deriving live state or verifying bytes.
pub struct RunReview {
  schema : String
  run_id : String
  job_id : String
  manifest_source : String
  total_events : Int32
  excluded_events : Int32
  total_artifacts : Int32
  excluded_artifacts : Int32
  selected_content_bytes : Int32
  content_verification : String
  notes : Array[String]
  events : Array[JournalEntry]
  artifacts : Array[ReviewArtifact]
} derive(ToJson)

///|
fn review_job(current : String?, incoming : String) -> String raise {
  guard !incoming.is_blank() else { fail("Blank selected run job identity") }
  if current is Some(id) && id != incoming {
    fail("Selected run has conflicting job identities")
  }
  incoming
}

///|
/// Join by exact run ID, requiring one consistent job ID across both inputs.
/// Events retain chronological/input order and artifacts retain manifest order.
/// Unknown fields survive in the original event and export-entry JSON.
pub fn review_run(
  entries : Array[JournalEntry],
  manifest_text : String,
  manifest_source~ : String,
  run_id~ : String,
) -> RunReview raise {
  guard !run_id.is_blank() else { fail("A run ID is required") }
  guard entries.length() <= 10000 else {
    fail("Combined journals exceed 10000 events")
  }
  let all_artifacts = parse_review_artifacts(manifest_text, manifest_source)
  let selected : Array[(JournalEntry, Int32, Int32)] = []
  let mut job : String? = None
  for index, entry in entries {
    let event = event_fields(entry)
    if event.run_id == run_id {
      job = Some(review_job(job, event.job_id))
      selected.push((entry, event.timestamp, index))
    }
  }
  selected.sort_by(fn(left, right) {
    let order = left.1.compare(right.1)
    if order == 0 {
      left.2.compare(right.2)
    } else {
      order
    }
  })
  let artifacts : Array[ReviewArtifact] = []
  let mut selected_content_bytes = 0
  for artifact in all_artifacts {
    let fields = review_artifact_fields(artifact)
    if fields.record.run_id == run_id {
      job = Some(review_job(job, fields.record.job_id))
      artifacts.push(artifact)
      selected_content_bytes += fields.content_bytes
    }
  }
  guard job is Some(job_id) else { fail("Run ID not found in supplied inputs") }
  let notes = [
    "Only the supplied journals and artifact selection are included; this is not a complete run archive.",
    "Artifact paths and SHA-256 values are manifest claims; content and record files were not read or verified.",
    "Recorded statuses are observations, not current run state or owner acceptance. No redaction was applied.",
  ]
  if selected.is_empty() {
    notes.push("No journal events for this run were supplied.")
  }
  if artifacts.is_empty() {
    notes.push(
      "No artifacts for this run occur in the supplied export selection.",
    )
  }
  {
    schema: "moonclaw.run-review.v1",
    run_id,
    job_id,
    manifest_source,
    total_events: entries.length(),
    excluded_events: entries.length() - selected.length(),
    total_artifacts: all_artifacts.length(),
    excluded_artifacts: all_artifacts.length() - artifacts.length(),
    selected_content_bytes,
    content_verification: "not_checked",
    notes,
    events: selected.map(item => item.0),
    artifacts,
  }
}
