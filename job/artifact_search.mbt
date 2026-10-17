///|
/// A one-based line number and bounded Unicode-safe excerpt. Excerpts are
/// evidence for inspection, never rendered as commands or markup.
pub struct ArtifactSearchLine {
  line : Int32
  excerpt : String
} derive(ToJson)

///|
pub struct ArtifactSearchMatch {
  record : ArtifactRecord
  record_sha256 : String
  content_sha256 : String
  content_bytes : Int32
  matching_lines : Int32
  lines : Array[ArtifactSearchLine]
} derive(ToJson)

///|
pub struct ArtifactSearchIssue {
  artifact_id : String
  reason : String
} derive(ToJson)

///|
pub struct ArtifactSearch {
  schema : String
  store_root : String
  query : ArtifactQuery
  text : String?
  scanned_records : Int32
  excluded_nontext : Int32
  deleted_records : Int32
  matching_artifacts : Int32
  truncated : Bool
  matches : Array[ArtifactSearchMatch]
  issues : Array[ArtifactSearchIssue]
} derive(ToJson)

///|
fn search_lines(
  content : String,
  needle : String,
) -> (Int32, Array[ArtifactSearchLine]) {
  let lines : Array[ArtifactSearchLine] = []
  let mut count = 0
  let mut line_number = 0
  for line in content.split("\n") {
    line_number += 1
    if line.find(needle) is Some(position) {
      count += 1
      if lines.length() < 3 {
        let chars = line.iter().to_array()
        let before = line[:position].iter().count()
        let start = if before > 48 { before - 48 } else { 0 }
        let end = if start + 240 < chars.length() {
          start + 240
        } else {
          chars.length()
        }
        let excerpt = StringBuilder()
        if start > 0 {
          excerpt.write_string("…")
        }
        for i in start..<end {
          excerpt.write_char(chars[i])
        }
        if end < chars.length() {
          excerpt.write_string("…")
        }
        lines.push({ line: line_number, excerpt: excerpt.to_string(), })
      }
    }
  }
  (count, lines)
}

///|
/// Find durable output revisions without loading or repairing the runtime index.
/// Filters are exact AND matches. Text is a case-sensitive, single-line literal;
/// omitting it catalogs any MIME type. Both active and archived records are
/// searched unless status is filtered. Results are ordered by artifact ID.
pub async fn search_retained_artifacts(
  root : String,
  query~ : ArtifactQuery = ArtifactQuery::new(),
  text~ : String? = None,
  limit~ : Int32 = 32,
) -> ArtifactSearch {
  guard limit >= 1 && limit <= 32 else {
    fail("Search limit must be between 1 and 32")
  }
  if text is Some(needle) {
    guard !needle.is_empty() &&
      needle.length() <= 128 &&
      !needle.contains("\n") &&
      !needle.contains("\r") else {
      fail(
        "Search text must be a nonempty single-line literal of at most 128 UTF-16 units",
      )
    }
  }
  let root = @fsx.resolve(root)
  guard @fsx.kind(root) is Directory else {
    fail("Expected an existing saved store directory")
  }
  let store = SystemStore::new(root~)
  let directory = @pathx.join(root, "artifacts")
  let entries = if @fsx.exists(directory) {
    @fsx.list_directory(directory)
  } else {
    []
  }
  guard entries.length() <= 2048 else {
    fail("Search supports at most 2048 artifact directory entries")
  }
  entries.sort_by((left, right) => left.name.lexical_compare(right.name))
  let matches : Array[ArtifactSearchMatch] = []
  let issues : Array[ArtifactSearchIssue] = []
  let mut scanned = 0
  let mut excluded = 0
  let mut deleted = 0
  let mut matching = 0
  let mut read_bytes = 0
  for entry in entries {
    if !(entry.kind is Directory) {
      issues.push({
        artifact_id: entry.name,
        reason: "Not a regular artifact directory",
      })
      continue
    }
    if @fsx.exists(store.artifact_deleted_file(entry.name)) {
      deleted += 1
      continue
    }
    scanned += 1
    let observed = try? retained_artifact_record(store, entry.name)
    guard observed is Ok((record, record_bytes)) else {
      if observed is Err(error) && @async.is_being_cancelled() {
        raise error
      }
      issues.push({
        artifact_id: entry.name,
        reason: "Unreadable or invalid durable record or content path",
      })
      continue
    }
    if !ArtifactStore::matches_query(record, query) {
      continue
    }
    let mime = record.content_type.split(";").to_array()[0]
      .trim()
      .to_owned()
      .to_lower()
    if text is Some(_) &&
      !(mime.has_prefix("text/") ||
      mime == "application/json" ||
      mime.has_suffix("+json")) {
      excluded += 1
      continue
    }
    let observed = try? comparison_bytes(record.path, 16777216)
    guard observed is Ok(bytes) else {
      if observed is Err(error) && @async.is_being_cancelled() {
        raise error
      }
      issues.push({
        artifact_id: entry.name,
        reason: "Content unavailable, changed or exceeds 16 MiB",
      })
      continue
    }
    read_bytes += bytes.length()
    guard read_bytes <= 67108864 else {
      fail("Search content scan exceeds 64 MiB; narrow metadata filters")
    }
    let (matching_lines, lines) = if text is Some(needle) {
      let decoded = try? @encoding/utf8.decode(bytes)
      guard decoded is Ok(content) && @encoding/utf8.encode(content) == bytes else {
        issues.push({
          artifact_id: entry.name,
          reason: "Text content is not lossless UTF-8",
        })
        continue
      }
      search_lines(content, needle)
    } else {
      (0, [])
    }
    if text is Some(_) && matching_lines == 0 {
      continue
    }
    let unchanged = try? comparison_bytes(
      store.artifact_record_file(record.id),
      262144,
    )
    guard unchanged is Ok(current_record) &&
      current_record == record_bytes &&
      !@fsx.exists(store.artifact_deleted_file(record.id)) else {
      if unchanged is Err(error) && @async.is_being_cancelled() {
        raise error
      }
      issues.push({
        artifact_id: entry.name,
        reason: "Record changed while searching",
      })
      continue
    }
    matching += 1
    if matches.length() < limit {
      matches.push({
        record,
        record_sha256: @capability.sha256_digest_ref_v1(record_bytes).text(),
        content_sha256: @capability.sha256_digest_ref_v1(bytes).text(),
        content_bytes: bytes.length(),
        matching_lines,
        lines,
      })
    }
  }
  {
    schema: "moonclaw.artifact-search.v1",
    store_root: root,
    query,
    text,
    scanned_records: scanned,
    excluded_nontext: excluded,
    deleted_records: deleted,
    matching_artifacts: matching,
    truncated: matching > matches.length(),
    matches,
    issues,
  }
}

///|
/// Export a complete nonempty search selection. Re-read and match the observed
/// record/content digests before creating the destination, preserving the exact
/// revisions found by search. An incomplete search requires a narrower query
/// or explicit exact-ID selection through the existing export API.
pub async fn ArtifactSearch::export_selected(
  self : ArtifactSearch,
  destination : String,
) -> ArtifactExport {
  guard !self.truncated &&
    self.issues.is_empty() &&
    self.matches.length() >= 1 &&
    self.matches.length() <= 32 &&
    self.matches.length() == self.matching_artifacts else {
    fail(
      "Export requires a complete nonempty search of at most 32 artifacts without issues; narrow the query or select exact IDs",
    )
  }
  let store = SystemStore::new(root=self.store_root)
  let sources : Array[ArtifactExportSource] = []
  let seen : Map[String, Bool] = {}
  let mut total = 0
  for index, observed in self.matches {
    guard !seen.contains(observed.record.id) else {
      fail("Duplicate search artifact identifier")
    }
    seen[observed.record.id] = true
    let source = export_source(
      store,
      observed.record.id,
      index + 1,
      67108864 - total,
    )
    guard source.entry.record_sha256 == observed.record_sha256 &&
      source.entry.content_sha256 == observed.content_sha256 &&
      source.entry.content_bytes == observed.content_bytes else {
      fail("Artifact changed since search; search again before exporting")
    }
    total += source.content.length()
    sources.push(source)
  }
  export_prepared_artifacts(store, sources, destination)
}
