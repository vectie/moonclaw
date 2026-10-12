///|
fn book_outcome_digest(bytes : Bytes) -> String {
  @capability.sha256_digest_ref_v1(bytes).text()
}

///|
/// Freeze selected completed text outputs with their exact host-owned run and
/// artifact records. The returned value contains all bytes needed by the
/// portable handoff; it is evidence only and does not submit or accept in Book.
/// Binary output stays available through the independent byte download API.
pub async fn ArtifactStore::freeze_book_outcome_source(
  self : ArtifactStore,
  run_id : String,
  artifact_ids : Array[String],
) -> Json {
  if artifact_ids.is_empty() || artifact_ids.length() > 32 {
    fail("Choose between 1 and 32 retained text artifacts")
  }
  guard self.store.get_run(run_id) is Some(run) else {
    fail("The selected run is unavailable; refresh and select a completed run")
  }
  guard (
      run.status is Succeeded || run.status is Failed || run.status is Cancelled
    ) &&
    run.finished_at is Some(_) else {
    fail("Book handoff requires a completed run with its recorded finish time")
  }
  let run_json = run.to_json()
  let records : Array[Json] = []
  let artifacts : Array[Json] = []
  let retained : Array[(ArtifactRecord, Bytes)] = []
  let seen : Map[String, Bool] = Map([])
  let mut total = 0
  for id in artifact_ids {
    if seen.contains(id) || id.has_prefix("synthetic:") {
      fail("Select each real retained artifact exactly once")
    }
    seen[id] = true
    guard self.get(id) is Some(record) &&
      record.run_id == run_id &&
      record.job_id == run.job_id else {
      fail("Selected artifact does not belong to this exact run and job")
    }
    if !(record.content_type.has_prefix("text/") ||
      record.content_type == "application/json") {
      fail("Book v1 accepts UTF-8 text only; use Download for binary output")
    }
    guard self.read_bytes(run_id, id) is Some(bytes) else {
      fail(
        "Retained source is missing; restore it and retry without rerunning work",
      )
    }
    total += bytes.length()
    if total > 8388608 {
      fail(
        "Selected text exceeds the Book 8 MiB package limit; no bytes were omitted",
      )
    }
    let text = @encoding/utf8.decode(bytes) catch {
      _ =>
        fail(
          "Selected source is not valid UTF-8; no lossy conversion is allowed",
        )
    }
    // The browser must be able to recover precisely the native bytes, including
    // BOMs, non-ASCII and NUL; never normalize or trim retained output.
    if @encoding/utf8.encode(text) != bytes {
      fail("Selected UTF-8 source cannot be retained byte-for-byte")
    }
    records.push({
      "record": record.to_json(),
      "digest": book_outcome_digest(bytes),
      "byte_length": bytes.length(),
    })
    artifacts.push({ "id": id, "text": text })
    retained.push((record, bytes))
  }
  // A completed run is not sufficient evidence of immutable workspace files.
  // Re-read every owned record and byte sequence before freezing this snapshot.
  for (record, bytes) in retained {
    guard self.get(record.id) is Some(current) &&
      current.to_json() == record.to_json() &&
      self.read_bytes(run_id, record.id) == Some(bytes) else {
      fail(
        "Source changed while freezing; prior saved handoffs remain available",
      )
    }
  }
  guard self.store.get_run(run_id) is Some(current) &&
    current.to_json() == run_json else {
    fail("Run changed while freezing; refresh before creating another handoff")
  }
  let context : Json = {
    "contract_version": "moonclaw.completed-text-source.v1",
    "run": run_json,
    "artifacts": records,
  }
  let source_json = context.stringify()
  let result : Json = {
    "contract_version": "moonclaw.book-outcome-source.v1",
    "source_digest": book_outcome_digest(@encoding/utf8.encode(source_json)),
    "source_json": source_json,
    "artifacts": artifacts,
  }
  if @encoding/utf8.encode(result.stringify()).length() > 8388608 {
    fail("Frozen text and source context exceed 8 MiB; no bytes were omitted")
  }
  result
}
