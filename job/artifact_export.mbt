///|
/// One portable copy, with paths relative to the export directory. The original
/// record remains provenance; its original absolute path is not an export path.
pub struct ExportedArtifact {
  record : ArtifactRecord
  record_path : String
  record_sha256 : String
  content_path : String
  content_sha256 : String
  content_bytes : Int32
} derive(ToJson, FromJson)

///|
pub struct ArtifactExport {
  schema : String
  artifacts : Array[ExportedArtifact]
  total_content_bytes : Int32
} derive(ToJson, FromJson)

///|
priv struct ArtifactExportSource {
  entry : ExportedArtifact
  record_bytes : Bytes
  content : Bytes
}

///|
fn export_file_name(path : String) -> String {
  let name = StringBuilder()
  let mut length = 0
  for c in @pathx.basename(path) {
    if length >= 96 {
      break
    }
    length += 1
    if c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '.' | '-' | '_') {
      name.write_char(c)
    } else {
      name.write_char('_')
    }
  }
  let result = name.to_string()
  if result.is_empty() || result == "." || result == ".." {
    "content.bin"
  } else {
    result
  }
}

///|
async fn retained_artifact_record(
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
  let directory = @fsx.resolve(store.artifact_dir(id))
  guard directory.has_prefix(store.root + "/artifacts/") else {
    fail("Artifact directory is outside the selected store")
  }
  let path = @fsx.resolve(record.path)
  guard path.has_prefix(directory + "/") else {
    fail("Artifact content is outside its retained artifact directory")
  }
  (record, record_bytes)
}

///|
async fn export_source(
  store : SystemStore,
  id : String,
  index : Int32,
  remaining : Int32,
) -> ArtifactExportSource {
  let (record, record_bytes) = retained_artifact_record(store, id)
  let maximum = if remaining < 16777216 { remaining } else { 16777216 }
  let content = comparison_bytes(record.path, maximum)
  let file_name = export_file_name(record.path)
  {
    entry: {
      record,
      record_path: "records/\{index}.json",
      record_sha256: @capability.sha256_digest_ref_v1(record_bytes).text(),
      content_path: "files/\{index}-\{file_name}",
      content_sha256: @capability.sha256_digest_ref_v1(content).text(),
      content_bytes: content.length(),
    },
    record_bytes,
    content,
  }
}

///|
/// Export selected exact retained revisions into a NEW directory outside the
/// store. Reads durable records directly, including archived and binary output.
/// No index repair, job execution, acceptance, or knowledge promotion occurs.
/// Input validation finishes before creating the output. A filesystem write
/// failure can leave an incomplete directory; manifest.json is written last.
pub async fn export_retained_artifacts(
  root : String,
  artifact_ids : Array[String],
  destination : String,
) -> ArtifactExport {
  guard artifact_ids.length() >= 1 && artifact_ids.length() <= 32 else {
    fail("Select between 1 and 32 exact artifact identifiers")
  }
  let root = @fsx.resolve(root)
  let store = SystemStore::new(root~)
  let seen : Map[String, Bool] = Map([])
  let sources : Array[ArtifactExportSource] = []
  let mut total = 0
  for i, id in artifact_ids {
    guard !seen.contains(id) else { fail("Duplicate artifact identifier") }
    seen[id] = true
    let source = export_source(store, id, i + 1, 67108864 - total)
    total += source.content.length()
    sources.push(source)
  }
  export_prepared_artifacts(store, sources, destination)
}

///|
async fn export_prepared_artifacts(
  store : SystemStore,
  sources : Array[ArtifactExportSource],
  destination : String,
) -> ArtifactExport {
  let root = store.root
  let absolute = @pathx.resolve(destination)
  let parent = @fsx.resolve(@pathx.dirname(absolute))
  let destination = @pathx.join(parent, @pathx.basename(absolute))
  guard destination != root && !destination.has_prefix(root + "/") else {
    fail("Export destination must be outside the source store")
  }
  guard !@fsx.exists(destination) else {
    fail("Export destination already exists; choose a new directory")
  }
  let total = sources.fold(init=0, (sum, source) => {
    sum + source.content.length()
  })
  // Do not export mixed old metadata/new content from an observed update. This
  // is still a bounded snapshot of a saved store, not a live multi-file lock.
  for source in sources {
    let record = source.entry.record
    guard !@fsx.exists(store.artifact_deleted_file(record.id)) &&
      comparison_bytes(store.artifact_record_file(record.id), 262144) ==
      source.record_bytes &&
      comparison_bytes(record.path, 16777216) == source.content else {
      fail("Artifact changed while preparing export")
    }
  }
  let result : ArtifactExport = {
    schema: "moonclaw.artifact-export.v1",
    artifacts: sources.map(s => s.entry),
    total_content_bytes: total,
  }
  let manifest = @encoding/utf8.encode(result.to_json().stringify() + "\n")
  let readme = @encoding/utf8.encode(result.to_readme())
  let checksums = StringBuilder()
  for source in sources {
    checksums.write_string(
      export_checksum_line(source.entry.record_sha256, source.entry.record_path),
    )
    checksums.write_string(
      export_checksum_line(
        source.entry.content_sha256,
        source.entry.content_path,
      ),
    )
  }
  checksums.write_string(
    export_checksum_line(
      @capability.sha256_digest_ref_v1(readme).text(),
      "README.txt",
    ),
  )
  checksums.write_string(
    export_checksum_line(
      @capability.sha256_digest_ref_v1(manifest).text(),
      "manifest.json",
    ),
  )
  // mkdir itself refuses an existing file/directory, including a destination
  // created after the preliminary check. Never merge or overwrite an export.
  @fs.mkdir(destination, permission=0o700)
  @fs.mkdir(@pathx.join(destination, "files"), permission=0o700)
  @fs.mkdir(@pathx.join(destination, "records"), permission=0o700)
  for source in sources {
    export_write(
      @pathx.join(destination, source.entry.content_path),
      source.content,
    )
    export_write(
      @pathx.join(destination, source.entry.record_path),
      source.record_bytes,
    )
  }
  export_write(@pathx.join(destination, "README.txt"), readme)
  export_write(
    @pathx.join(destination, "SHA256SUMS"),
    @encoding/utf8.encode(checksums.to_string()),
  )
  export_write(@pathx.join(destination, "manifest.json"), manifest)
  result
}

///|
/// Host convenience API, also using the exact durable records on disk.
pub async fn ArtifactStore::export_selected(
  self : ArtifactStore,
  artifact_ids : Array[String],
  destination : String,
) -> ArtifactExport {
  export_retained_artifacts(self.store.root, artifact_ids, destination)
}

///|
async fn export_write(path : String, content : Bytes) -> Unit {
  @fs.write_file(path, content, create_mode=CreateNew, permission=0o600)
}

///|
pub extend ExportedArtifact with ToJson::{to_json}

///|
pub extend ExportedArtifact with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend ArtifactExport with ToJson::{to_json}

///|
pub extend ArtifactExport with @moonbitlang/core/json.FromJson::{from_json}
