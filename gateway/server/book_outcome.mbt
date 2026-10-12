///|
// A read-only snapshot endpoint. The host resolves owned records; a browser
// supplies IDs only, never file paths, completed status or substitute content.
async fn Gateway::handle_book_outcome_source(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  encoded_run_id : String,
) -> Unit {
  guard artifact_route_id(encoded_run_id) is Some(run_id) else {
    raise json_error(400, "BadRequest", {
      "error": { "message": "Choose an exact retained run ID" },
    })
  }
  let request = self.read_json_body(r, "Invalid Book source selection")
  guard request is { "artifact_ids": Array(values), .. } else {
    raise json_error(400, "BadRequest", {
      "error": {
        "message": "Choose retained artifact IDs for the Book handoff",
      },
    })
  }
  let ids : Array[String] = []
  for value in values {
    guard value is String(id) else {
      raise json_error(400, "BadRequest", {
        "error": { "message": "Artifact IDs must be strings" },
      })
    }
    ids.push(id)
  }
  let source = @job.ArtifactStore::new(store=self.job_runtime().store()).freeze_book_outcome_source(
    run_id, ids,
  ) catch {
    error =>
      raise json_error(409, "Conflict", {
        "error": {
          "code": "book_source_unavailable",
          "message": book_outcome_public_error(error.to_string()),
        },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.header().set("Cache-Control", "no-store")
  w.header().set("X-Content-Type-Options", "nosniff")
  w.write_header(200)
  w.write(source.stringify())
}

///|
fn book_outcome_public_error(error : String) -> String {
  for
    message in [
      "Choose between 1 and 32 retained text artifacts", "The selected run is unavailable; refresh and select a completed run",
      "Book handoff requires a completed run with its recorded finish time", "Select each real retained artifact exactly once",
      "Selected artifact does not belong to this exact run and job", "Book v1 accepts UTF-8 text only; use Download for binary output",
      "Retained source is missing; restore it and retry without rerunning work",
      "Selected text exceeds the Book 8 MiB package limit; no bytes were omitted",
      "Selected source is not valid UTF-8; no lossy conversion is allowed", "Selected UTF-8 source cannot be retained byte-for-byte",
      "Source changed while freezing; prior saved handoffs remain available", "Run changed while freezing; refresh before creating another handoff",
      "Frozen text and source context exceed 8 MiB; no bytes were omitted",
    ] {
    if error.contains(message) {
      return message
    }
  }
  "The selected retained source could not be verified. Restore its trusted records and retry; work was not rerun."
}
