///|
/// An original export entry and its one-based position in the supplied manifest.
/// Paths and checksums describe the export; no referenced file is read here.
pub struct ReviewArtifact {
  source : String
  index : Int
  entry : Json
} derive(ToJson)

///|
priv struct ReviewArtifactFields {
  record : ReviewRecordFields
  record_path : String
  record_sha256 : String
  content_path : String
  content_sha256 : String
  content_bytes : Int
} derive(FromJson)

///|
priv struct ReviewRecordFields {
  id : String
  run_id : String
  job_id : String
  artifact_type : String
  logical_key : String?
  version : Int
  status : Json
  path : String
  content_type : String
  metadata : Json
  created_at : Int
  archived_at : Int?
  scope : Array[String]
} derive(FromJson)

///|
fn review_integer(json : Json, name : String, value : Int) -> Unit raise {
  guard json.as_object() is Some(fields) &&
    fields.get(name) is Some(Number(number, ..)) &&
    number == value.to_double() else {
    fail("Expected exact artifact integer: \{name}")
  }
}

///|
fn review_digest(text : String) -> Bool {
  if !text.has_prefix("sha256:") || text.length() != 71 {
    return false
  }
  for c in text[7:] {
    if !(c is ('0'..='9' | 'a'..='f')) {
      return false
    }
  }
  true
}

///|
fn review_member_path(path : String, index : Int) -> Bool {
  let prefix = "files/\{index}-"
  if !path.has_prefix(prefix) ||
    path.length() <= prefix.length() ||
    path.length() > prefix.length() + 96 {
    return false
  }
  for c in path[prefix.length():] {
    if !(c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '.' | '-' | '_')) {
      return false
    }
  }
  true
}

///|
fn review_artifact_fields(
  artifact : ReviewArtifact,
) -> ReviewArtifactFields raise {
  @json.from_json(artifact.entry) catch {
    _ => fail("Invalid artifact entry \{artifact.index}")
  }
}

///|
fn parse_review_artifacts(
  text : String,
  source : String,
) -> Array[ReviewArtifact] raise {
  guard !source.is_blank() else {
    fail("An artifact manifest source is required")
  }
  guard text.length() <= 4194304 else {
    fail("Artifact manifest exceeds 4 Mi code units")
  }
  let manifest = @json.parse(text) catch {
    _ => fail("Invalid artifact manifest JSON")
  }
  guard manifest
    is {
      "schema": String("moonclaw.artifact-export.v1"),
      "artifacts": Array(entries),
      "total_content_bytes": Number(total, ..),
      ..
    } else {
    fail("Expected moonclaw.artifact-export.v1 manifest")
  }
  guard entries.length() >= 1 && entries.length() <= 32 else {
    fail("Export manifest must contain between 1 and 32 artifacts")
  }
  let result : Array[ReviewArtifact] = []
  let seen : Map[String, Bool] = {}
  let mut bytes = 0
  for index, entry in entries {
    let artifact = ReviewArtifact::{ source, index: index + 1, entry, }
    let fields = review_artifact_fields(artifact)
    let record = fields.record
    guard !record.id.is_blank() &&
      !record.run_id.is_blank() &&
      !record.job_id.is_blank() else {
      fail("Blank artifact identity")
    }
    guard !seen.contains(record.id) else {
      fail("Duplicate export artifact ID")
    }
    seen[record.id] = true
    guard entry is { "record": raw_record, .. } else {
      fail("Missing artifact record")
    }
    review_integer(raw_record, "version", record.version)
    review_integer(raw_record, "created_at", record.created_at)
    if record.archived_at is Some(value) {
      review_integer(raw_record, "archived_at", value)
    }
    review_integer(entry, "content_bytes", fields.content_bytes)
    guard record.version >= 1 else {
      fail("Artifact revision must be positive")
    }
    guard fields.content_bytes >= 0 && fields.content_bytes <= 16777216 else {
      fail("Artifact content byte count is outside export limits")
    }
    guard fields.record_path == "records/\{index + 1}.json" &&
      review_member_path(fields.content_path, index + 1) else {
      fail("Artifact member paths do not match the portable export layout")
    }
    guard review_digest(fields.record_sha256) &&
      review_digest(fields.content_sha256) else {
      fail("Invalid artifact SHA-256 reference")
    }
    bytes += fields.content_bytes
    guard bytes <= 67108864 else { fail("Export exceeds 64 MiB total content") }
    result.push(artifact)
  }
  guard total == bytes.to_double() else {
    fail("Export content total disagrees with entries")
  }
  result
}
