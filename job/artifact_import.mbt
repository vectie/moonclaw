///|
/// A relocated inspection record plus the exact original-record provenance.
/// The artifact ID, producing job/run, revision, state and content are unchanged.
pub struct ImportedArtifact {
  record : ArtifactRecord
  record_sha256 : String
  original_record_path : String
  original_record_sha256 : String
  content_sha256 : String
  content_bytes : Int32
} derive(ToJson)

///|
pub struct ArtifactImport {
  schema : String
  source_manifest_sha256 : String
  artifacts : Array[ImportedArtifact]
  total_content_bytes : Int32
} derive(ToJson)

///|
priv struct ArtifactImportSource {
  entry : ImportedArtifact
  original_bytes : Bytes
  relocated_bytes : Bytes
  content : Bytes
}

///|
async fn import_packet_bytes(
  root : String,
  relative : String,
  maximum : Int32,
) -> Bytes {
  let path = @fsx.resolve(@pathx.join(root, relative))
  guard path.has_prefix(root + "/") else {
    fail("Export member is outside the selected packet")
  }
  comparison_bytes(path, maximum)
}

///|
fn import_integer(json : Json, key : String, expected : Int32) -> Unit raise {
  guard json is Object(fields) &&
    fields.get(key) is Some(Number(number, ..)) &&
    number == expected.to_double() else {
    fail("Expected an exact integer for \{key}")
  }
}

///|
/// Reopen a portable artifact export as a NEW artifact-only inspection store.
/// Original record bytes and the manifest remain under provenance/. Only the
/// local content path is changed in each inspectable record. No job, authority,
/// execution state, index repair or output acceptance is imported.
/// All inputs are validated before writing. import.json is written last; a
/// write interruption can leave an incomplete directory, which is not reused.
pub async fn import_artifact_export(
  packet : String,
  destination : String,
) -> ArtifactImport {
  let packet = @fsx.resolve(packet)
  guard @fsx.kind(packet) is Directory else {
    fail("Expected a portable artifact export directory")
  }
  let absolute = @pathx.resolve(destination)
  let parent = @fsx.resolve(@pathx.dirname(absolute))
  let destination = @pathx.join(parent, @pathx.basename(absolute))
  guard destination != packet && !destination.has_prefix(packet + "/") else {
    fail("Import destination must be outside the export packet")
  }
  guard !@fsx.exists(destination) else {
    fail("Import destination already exists; choose a new directory")
  }
  let manifest_bytes = import_packet_bytes(packet, "manifest.json", 16777216)
  let manifest_json = @json.parse(@encoding/utf8.decode(manifest_bytes))
  let manifest : ArtifactExport = @json.from_json(manifest_json)
  guard manifest.schema == "moonclaw.artifact-export.v1" else {
    fail("Unsupported artifact export schema")
  }
  guard manifest.artifacts.length() >= 1 && manifest.artifacts.length() <= 32 else {
    fail("Import requires between 1 and 32 artifact entries")
  }
  import_integer(
    manifest_json,
    "total_content_bytes",
    manifest.total_content_bytes,
  )
  guard manifest.total_content_bytes >= 0 &&
    manifest.total_content_bytes <= 67108864 else {
    fail("Import content exceeds the 64 MiB total limit")
  }
  guard manifest_json is { "artifacts": Array(raw_entries), .. } else {
    fail("Expected export artifact entries")
  }
  let seen : Map[String, Bool] = Map([])
  let sources : Array[ArtifactImportSource] = []
  let mut total = 0
  for i, source in manifest.artifacts {
    let original = source.record
    comparison_id(original.id)
    guard !seen.contains(original.id) else {
      fail("Duplicate artifact identifier in export")
    }
    seen[original.id] = true
    guard original.version >= 1 else { fail("Invalid artifact revision") }
    guard raw_entries[i] is { "record": raw_record, .. } else {
      fail("Expected original artifact record")
    }
    import_integer(raw_record, "version", original.version)
    import_integer(raw_entries[i], "content_bytes", source.content_bytes)
    guard source.content_bytes >= 0 && source.content_bytes <= 16777216 else {
      fail("Import content exceeds the 16 MiB per-file limit")
    }
    let name = export_file_name(original.path)
    guard source.record_path == "records/\{i + 1}.json" &&
      source.content_path == "files/\{i + 1}-\{name}" else {
      fail("Export member paths do not match the v1 portable layout")
    }
    let original_bytes = import_packet_bytes(packet, source.record_path, 262144)
    guard @capability.sha256_digest_ref_v1(original_bytes).text() ==
      source.record_sha256 else {
      fail("Original artifact record checksum mismatch")
    }
    let original_json = @json.parse(@encoding/utf8.decode(original_bytes))
    let retained : ArtifactRecord = @json.from_json(original_json)
    import_integer(original_json, "version", retained.version)
    guard retained.to_json() == original.to_json() else {
      fail("Manifest and original artifact record disagree")
    }
    total += source.content_bytes
    guard total <= 67108864 else {
      fail("Import content exceeds the 64 MiB total limit")
    }
    let content = import_packet_bytes(
      packet,
      source.content_path,
      source.content_bytes,
    )
    guard content.length() == source.content_bytes &&
      @capability.sha256_digest_ref_v1(content).text() == source.content_sha256 else {
      fail("Artifact content length or checksum mismatch")
    }
    // Preserve unknown record fields too; only this inspection path is remapped.
    let path = destination
      |> @pathx.join("artifacts")
      |> @pathx.join(original.id)
      |> @pathx.join("content.bin")
    guard original_json is Object(fields) else {
      fail("Expected original record object")
    }
    fields["path"] = Json(path)
    let relocated_bytes = @encoding/utf8.encode(Json(fields).stringify() + "\n")
    guard relocated_bytes.length() <= 262144 else {
      fail("Relocated artifact record exceeds the 256 KiB inspection limit")
    }
    sources.push({
      entry: {
        record: { ..original, path, },
        record_sha256: @capability.sha256_digest_ref_v1(relocated_bytes).text(),
        original_record_path: "provenance/" + source.record_path,
        original_record_sha256: source.record_sha256,
        content_sha256: source.content_sha256,
        content_bytes: source.content_bytes,
      },
      original_bytes,
      relocated_bytes,
      content,
    })
  }
  guard total == manifest.total_content_bytes else {
    fail("Export total content length disagrees with its entries")
  }
  let result : ArtifactImport = {
    schema: "moonclaw.artifact-import.v1",
    source_manifest_sha256: @capability.sha256_digest_ref_v1(manifest_bytes).text(),
    artifacts: sources.map(source => source.entry),
    total_content_bytes: total,
  }
  @fs.mkdir(destination, permission=0o700)
  @fs.mkdir(@pathx.join(destination, "artifacts"), permission=0o700)
  @fs.mkdir(@pathx.join(destination, "provenance"), permission=0o700)
  @fs.mkdir(@pathx.join(destination, "provenance/records"), permission=0o700)
  export_write(
    @pathx.join(destination, "provenance/manifest.json"),
    manifest_bytes,
  )
  for source in sources {
    let directory = destination
      |> @pathx.join("artifacts")
      |> @pathx.join(source.entry.record.id)
    @fs.mkdir(directory, permission=0o700)
    export_write(source.entry.record.path, source.content)
    export_write(@pathx.join(directory, "record.json"), source.relocated_bytes)
    export_write(
      @pathx.join(destination, source.entry.original_record_path),
      source.original_bytes,
    )
  }
  export_write(
    @pathx.join(destination, "README.txt"),
    @encoding/utf8.encode(
      "MoonClaw artifact-only inspection store\n\nRuntime evidence only. No output acceptance is implied.\nUse search_artifacts, compare_artifacts and export_artifacts with this directory.\nOriginal records and manifest are retained under provenance/. Only local content paths were relocated.\nNo jobs, plans, authority, journal, memory or runtime execution state were restored.\nChecksums establish byte consistency, not source authenticity. No redaction was applied.\nimport.json records the completed import; keep incomplete directories and retry to a new path.\n",
    ),
  )
  export_write(
    @pathx.join(destination, "import.json"),
    @encoding/utf8.encode(result.to_json().stringify() + "\n"),
  )
  result
}

///|
pub extend ImportedArtifact with ToJson::{to_json}

///|
pub extend ArtifactImport with ToJson::{to_json}
