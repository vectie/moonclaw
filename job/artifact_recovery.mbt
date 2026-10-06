///|
// Artifact records are durable checkpoints; the shared index is a recoverable
// cache. Keep legacy index-only entries readable, but never let a stale cache
// replace a newer per-artifact record or resurrect an explicitly deleted one.
async fn SystemStore::reload_artifacts_unlocked(self : SystemStore) -> Unit {
  let recovered : Map[String, ArtifactRecord] = Map([])
  let issues : Array[String] = []
  let index_path = self.artifacts_index_file()
  if @fsx.exists(index_path) {
    let file : ArtifactsIndexFile? = try_load_json_file(index_path)
    match file {
      Some(file) =>
        for artifact in file.artifacts {
          recovered.set(artifact.id, artifact)
        }
      None =>
        issues.push(
          "Artifact index checkpoint is unreadable; recovered durable records",
        )
    }
  }
  let root = self.root |> @pathx.join("artifacts")
  if @fsx.exists(root) {
    for entry in @fsx.list_directory(root) {
      guard entry.kind is Directory else { continue }
      if @fsx.exists(self.artifact_deleted_file(entry.name)) {
        recovered.remove(entry.name) |> ignore()
        continue
      }
      let record_path = entry.path |> @pathx.join("record.json")
      if !@fsx.exists(record_path) {
        issues.push(
          "Incomplete artifact checkpoint: \{entry.name}; no durable record",
        )
        continue
      }
      let record : ArtifactRecord? = try_load_json_file(record_path)
      match record {
        Some(record) if record.id == entry.name =>
          recovered.set(record.id, record)
        _ =>
          issues.push(
            "Unreadable artifact checkpoint: \{entry.name}; retained any prior index entry",
          )
      }
    }
  }
  clear_map(self.artifacts)
  for artifact in recovered.values() {
    // Legacy index-only entries may have no artifact directory to scan.
    if @fsx.exists(self.artifact_deleted_file(artifact.id)) {
      continue
    }
    self.artifacts.set(artifact.id, artifact)
    if !@fsx.exists(artifact.path) {
      issues.push("Artifact content is unavailable: \{artifact.id}")
    }
  }
  self.artifact_recovery_issues.clear()
  self.artifact_recovery_issues.append(issues)
}

///|
/// Diagnostics from the most recent artifact recovery. Readable artifacts remain
/// available even when another checkpoint is incomplete or unreadable.
pub fn SystemStore::list_artifact_recovery_issues(
  self : SystemStore,
) -> Array[String] {
  self.artifact_recovery_issues.copy()
}

///|
fn SystemStore::artifact_deleted_file(
  self : SystemStore,
  artifact_id : String,
) -> String {
  self.root
  |> @pathx.join("index")
  |> @pathx.join("deleted-artifacts")
  |> @pathx.join("\{artifact_id}.json")
}

///|
// Call only while holding the existing store lock. A process interruption can
// leave the temporary file, but cannot truncate the last confirmed checkpoint.
async fn write_artifact_checkpoint(path : String, content : Bytes) -> Unit {
  let temporary = "\{path}.pending"
  @fsx.write_bytes_to_file(temporary, content)
  @fsx.atomic_rename(temporary, path)
}

///|
async fn SystemStore::save_artifact_unlocked(
  self : SystemStore,
  artifact : ArtifactRecord,
) -> Unit {
  if @fsx.exists(self.artifact_deleted_file(artifact.id)) {
    fail("Artifact \{artifact.id} was deleted; use a new artifact identity")
  }
  @fsx.make_directory(
    self.artifact_dir(artifact.id),
    recursive=true,
    exists_ok=true,
  )
  write_artifact_checkpoint(
    self.artifact_record_file(artifact.id),
    @encoding/utf8.encode(artifact.to_json().stringify()),
  )
  // Publish to memory only after the durable record has committed. An index
  // failure remains an explicit error and is recoverable without rerunning work.
  self.artifacts.set(artifact.id, artifact)
  self.save_artifacts_index_unlocked()
}
