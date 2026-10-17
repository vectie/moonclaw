///|
/// Metadata comes from the exact retained record, and the digest from the bytes
/// read for this comparison. Neither is a claim of historical immutability.
pub struct ComparedArtifact {
  record : ArtifactRecord
  content_sha256 : String
  content_bytes : Int32
} derive(ToJson)

///|
pub struct ArtifactComparison {
  schema : String
  left : ComparedArtifact
  right : ComparedArtifact
  diff : @artifact_diff.TextDiff
} derive(ToJson)

///|
fn comparison_id(id : String) -> Unit raise {
  guard !id.is_empty() && id != "." && id != ".." else {
    fail("Expected an exact artifact identifier")
  }
  for c in id {
    guard c != '/' && c != '\\' && c.to_int() >= 32 && c.to_int() != 127 else {
      fail("Invalid artifact identifier")
    }
  }
}

///|
async fn comparison_bytes(path : String, maximum : Int32) -> Bytes {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  guard file.kind() is Regular else { fail("Expected a retained regular file") }
  let size = file.size()
  guard size <= maximum.to_int64() else {
    fail("Retained file exceeds byte limit \{maximum}")
  }
  let bytes = file.read_exactly_at(size.to_int(), position=0L)
  guard file.size() == size else { fail("Retained file changed while reading") }
  bytes
}

///|
async fn comparison_record(
  store : SystemStore,
  id : String,
) -> (ArtifactRecord, Bytes) {
  comparison_id(id)
  guard !@fsx.exists(store.artifact_deleted_file(id)) else {
    fail("Artifact has a retained deletion marker")
  }
  let record_bytes = comparison_bytes(store.artifact_record_file(id), 262144)
  let json = @json.parse(@encoding/utf8.decode(record_bytes))
  let record : ArtifactRecord = @json.from_json(json)
  guard record.id == id else { fail("Retained artifact identity mismatch") }
  guard json is { "version": Number(version, ..), .. } &&
    version == record.version.to_double() &&
    record.version >= 1 else {
    fail("Invalid retained artifact version")
  }
  let mime = record.content_type.split(";").to_array()[0]
    .trim()
    .to_owned()
    .to_lower()
  guard mime.has_prefix("text/") ||
    mime == "application/json" ||
    mime.has_suffix("+json") else {
    fail("Only retained text or JSON artifacts can be compared")
  }
  let directory = @fsx.resolve(store.artifact_dir(id))
  let path = @fsx.resolve(record.path)
  guard path.has_prefix(directory + "/") else {
    fail("Artifact content is outside its retained artifact directory")
  }
  (record, record_bytes)
}

///|
/// Compare two exact durable checkpoints without loading/reconciling a store.
/// Both must represent the same job, artifact type and logical key; versions
/// may come from different runs and either comparison direction is supported.
pub async fn compare_retained_artifacts(
  root : String,
  left_id : String,
  right_id : String,
) -> ArtifactComparison {
  let store = SystemStore::new(root~)
  let (left, left_record_bytes) = comparison_record(store, left_id)
  let (right, right_record_bytes) = comparison_record(store, right_id)
  guard left.job_id == right.job_id &&
    left.artifact_type == right.artifact_type &&
    left.logical_key == right.logical_key else {
    fail("Artifacts belong to different logical outputs")
  }
  let before = comparison_bytes(left.path, 1048576)
  let after = comparison_bytes(right.path, 1048576)
  let diff = @artifact_diff.compare_text(
    @encoding/utf8.decode(before),
    @encoding/utf8.decode(after),
  )
  // Detect changed metadata/deletion while loading the pair. The runtime has no
  // immutable content contract; these digests name observed bytes, not a lock.
  guard !@fsx.exists(store.artifact_deleted_file(left_id)) &&
    !@fsx.exists(store.artifact_deleted_file(right_id)) &&
    comparison_bytes(store.artifact_record_file(left_id), 262144) ==
    left_record_bytes &&
    comparison_bytes(store.artifact_record_file(right_id), 262144) ==
    right_record_bytes else {
    fail("Artifact checkpoint changed while comparing")
  }
  {
    schema: "moonclaw.artifact-comparison.v1",
    left: {
      record: left,
      content_sha256: @capability.sha256_digest_ref_v1(before).text(),
      content_bytes: before.length(),
    },
    right: {
      record: right,
      content_sha256: @capability.sha256_digest_ref_v1(after).text(),
      content_bytes: after.length(),
    },
    diff,
  }
}

///|
/// Host convenience API, still reading exact durable checkpoints rather than
/// potentially stale in-memory artifact metadata.
pub async fn ArtifactStore::compare_text(
  self : ArtifactStore,
  left_id : String,
  right_id : String,
) -> ArtifactComparison {
  compare_retained_artifacts(self.store.root, left_id, right_id)
}
