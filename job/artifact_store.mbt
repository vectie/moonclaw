///|
pub struct ArtifactStore {
  store : SystemStore
}

///|
struct ArtifactBytesWriteRequest {
  run_id : String
  job_id : String
  artifact_type : String
  logical_key : String?
  content_type : String
  file_name : String?
  metadata : Json
  scope : Array[String]
  content : Bytes
  append_only : Bool
}

///|
fn ArtifactBytesWriteRequest::from_text(
  request : ArtifactWriteRequest,
) -> ArtifactBytesWriteRequest {
  ArtifactBytesWriteRequest::{
    run_id: request.run_id,
    job_id: request.job_id,
    artifact_type: request.artifact_type,
    logical_key: request.logical_key,
    content_type: request.content_type,
    file_name: request.file_name,
    metadata: request.metadata,
    scope: request.scope,
    content: @encoding/utf8.encode(request.content),
    append_only: request.append_only,
  }
}

///|
pub fn ArtifactStore::new(store~ : SystemStore) -> ArtifactStore {
  ArtifactStore::{ store, }
}

///|
fn ArtifactStore::default_file_name(content_type : String) -> String {
  if content_type == "application/json" {
    "content.json"
  } else if content_type.has_prefix("text/") {
    "content.txt"
  } else {
    "content.bin"
  }
}

///|
fn ArtifactStore::matches_query(
  artifact : ArtifactRecord,
  query : ArtifactQuery,
) -> Bool {
  let matches_job = match query.job_id {
    Some(job_id) => artifact.job_id == job_id
    None => true
  }
  let matches_run = match query.run_id {
    Some(run_id) => artifact.run_id == run_id
    None => true
  }
  let matches_type = match query.artifact_type {
    Some(artifact_type) => artifact.artifact_type == artifact_type
    None => true
  }
  let matches_key = match query.logical_key {
    Some(logical_key) => artifact.logical_key == Some(logical_key)
    None => true
  }
  let matches_scope = match query.scope {
    Some(scope) => artifact.scope.contains(scope)
    None => true
  }
  let matches_status = match query.status {
    Some(status) => artifact.status == status
    None => true
  }
  matches_job &&
  matches_run &&
  matches_type &&
  matches_key &&
  matches_scope &&
  matches_status
}

///|
fn ArtifactStore::latest_bytes_version(
  self : ArtifactStore,
  request : ArtifactBytesWriteRequest,
) -> Int {
  self.store
  .list_artifacts()
  .filter(fn(artifact) {
    artifact.job_id == request.job_id &&
    artifact.artifact_type == request.artifact_type &&
    artifact.logical_key == request.logical_key
  })
  .fold(init=0, fn(max_version, artifact) {
    if artifact.version > max_version {
      artifact.version
    } else {
      max_version
    }
  })
}

///|
fn ArtifactStore::existing_mutable_bytes_record(
  self : ArtifactStore,
  request : ArtifactBytesWriteRequest,
) -> ArtifactRecord? {
  guard !request.append_only else { return None }
  let artifacts = self.store
    .list_artifacts()
    .filter(fn(artifact) {
      artifact.job_id == request.job_id &&
      artifact.run_id == request.run_id &&
      artifact.artifact_type == request.artifact_type &&
      artifact.logical_key == request.logical_key &&
      artifact.status is Active
    })
  artifacts.sort_by(fn(left, right) {
    right.created_at.compare(left.created_at)
  })
  artifacts.get(0)
}

///|
pub fn ArtifactStore::list(
  self : ArtifactStore,
  query? : ArtifactQuery = ArtifactQuery::new(),
) -> Array[ArtifactRecord] {
  let artifacts = self.store
    .list_artifacts()
    .filter(fn(artifact) { ArtifactStore::matches_query(artifact, query) })
  artifacts.sort_by(fn(left, right) {
    right.created_at.compare(left.created_at)
  })
  artifacts
}

///|
pub fn ArtifactStore::get(
  self : ArtifactStore,
  artifact_id : String,
) -> ArtifactRecord? {
  self.store.get_artifact(artifact_id)
}

///|
pub async fn ArtifactStore::read_text(
  self : ArtifactStore,
  artifact_id : String,
) -> String? {
  match self.store.get_artifact(artifact_id) {
    Some(artifact) if @fsx.exists(artifact.path) =>
      Some(@fsx.read_file(artifact.path))
    _ => None
  }
}

///|
pub async fn ArtifactStore::write(
  self : ArtifactStore,
  request : ArtifactWriteRequest,
  artifact_id : String,
  now_ms : Int,
) -> ArtifactRecord {
  self.write_bytes(
    ArtifactBytesWriteRequest::from_text(request),
    artifact_id,
    now_ms,
  )
}

///|
pub async fn ArtifactStore::write_bytes(
  self : ArtifactStore,
  request : ArtifactBytesWriteRequest,
  artifact_id : String,
  now_ms : Int,
) -> ArtifactRecord {
  let existing = self.existing_mutable_bytes_record(request)
  let id = match existing {
    Some(record) => record.id
    None => artifact_id
  }
  let version = match existing {
    Some(record) => record.version
    None => self.latest_bytes_version(request) + 1
  }
  let file_name = request.file_name.unwrap_or(
    ArtifactStore::default_file_name(request.content_type),
  )
  let path = self.store.artifact_content_file(id, file_name~)
  @fsx.make_directory(
    self.store.artifact_dir(id),
    recursive=true,
    exists_ok=true,
  ) catch {
    _ => ()
  }
  @fsx.write_bytes_to_file(path, request.content)
  let record = ArtifactRecord::{
    id,
    run_id: request.run_id,
    job_id: request.job_id,
    artifact_type: request.artifact_type,
    logical_key: request.logical_key,
    version,
    status: ArtifactStatus::Active,
    path,
    content_type: request.content_type,
    metadata: request.metadata,
    created_at: now_ms,
    archived_at: None,
    scope: request.scope,
  }
  self.store.save_artifact(record)
  record
}

///|
pub async fn ArtifactStore::archive(
  self : ArtifactStore,
  artifact_id : String,
  now_ms : Int,
) -> ArtifactRecord? {
  let artifact = match self.store.get_artifact(artifact_id) {
    Some(artifact) => artifact
    None => return None
  }
  let updated = ArtifactRecord::{
    ..artifact,
    status: ArtifactStatus::Archived,
    archived_at: Some(now_ms),
  }
  self.store.save_artifact(updated)
  Some(updated)
}

///|
fn ArtifactStore::retention_matches(
  artifact : ArtifactRecord,
  policy : ArtifactRetentionPolicy,
) -> Bool {
  let matches_type = match policy.artifact_type {
    Some(artifact_type) => artifact.artifact_type == artifact_type
    None => true
  }
  let matches_scope = match policy.scope {
    Some(scope) => artifact.scope.contains(scope)
    None => true
  }
  matches_type && matches_scope
}

///|
pub async fn ArtifactStore::apply_retention(
  self : ArtifactStore,
  policy : ArtifactRetentionPolicy,
  now_ms : Int,
) -> ArtifactCleanupReport {
  let candidates = self
    .list(query=ArtifactQuery::new(status=Some(ArtifactStatus::Active)))
    .filter(fn(artifact) { ArtifactStore::retention_matches(artifact, policy) })
  let archived_ids : Array[String] = []
  let deleted_ids : Array[String] = []
  let keep_latest = policy.keep_latest.unwrap_or(0)
  for index = 0; index < candidates.length(); index = index + 1 {
    let artifact = candidates[index]
    let older_than_window = index >= keep_latest && keep_latest > 0
    let expired = match policy.max_age_ms {
      Some(max_age_ms) => now_ms - artifact.created_at > max_age_ms
      None => false
    }
    if !older_than_window && !expired {
      continue
    }
    if policy.archive_before_delete {
      ignore(self.archive(artifact.id, now_ms))
      archived_ids.push(artifact.id)
    } else if self.store.delete_artifact(artifact.id) {
      deleted_ids.push(artifact.id)
    }
  }
  ArtifactCleanupReport::{ archived_ids, deleted_ids }
}
