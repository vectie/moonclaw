///|
fn human_revision_public_error(error : String) -> String {
  for
    message in [
      "Human revision parent does not belong to this retained run and job", "Human revisions require retained UTF-8 text or JSON",
      "Human revision source is missing; restore it without rerunning work", "Human revision text exceeds the 8 MiB limit",
      "Invalid human revision save ID or parent digest", "Save ID already records different human revision content",
      "Parent content changed; keep your draft and reopen the source before saving",
    ] {
    if error.contains(message) {
      return message
    }
  }
  "Save confirmation is unavailable. Keep your draft and retry the same save ID to recover any committed copy."
}

///|
async fn Gateway::handle_save_human_revision(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  raw_run : String,
  raw_parent : String,
) -> Unit {
  // Unlike legacy read access, this new mutation is never anonymous.
  guard self.auth.token is Some(token) && !token.is_blank() else {
    raise json_error(401, "Unauthorized", {
      "error": {
        "message": "Saving human revisions requires a configured gateway bearer token.",
      },
    })
  }
  guard artifact_route_id(raw_run) is Some(run_id) &&
    artifact_route_id(raw_parent) is Some(parent_id) else {
    raise json_error(400, "BadRequest", {
      "error": { "message": "Choose exact retained run and artifact IDs." },
    })
  }
  let body = self.read_json_body(r, "Invalid human revision request")
  guard body is Object(fields) &&
    fields.length() == 3 &&
    body
    is {
      "save_id": String(save_id),
      "expected_parent_digest": String(expected),
      "content": String(content),
    } else {
    raise json_error(400, "BadRequest", {
      "error": {
        "message": "Send only save_id, expected_parent_digest and content.",
      },
    })
  }
  let artifacts = @job.ArtifactStore::new(store=self.job_runtime().store())
  let record = artifacts.save_human_revision(
    run_id,
    parent_id,
    save_id,
    expected,
    content,
    current_time_ms(),
  ) catch {
    error =>
      raise json_error(409, "Conflict", {
        "error": { "message": human_revision_public_error(error.to_string()) },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.header().set("Cache-Control", "no-store")
  w.header().set("X-Content-Type-Options", "nosniff")
  w.write_header(200)
  let result : Json = { "artifact": record.to_json(), "save_id": save_id }
  w.write(result.stringify())
}
