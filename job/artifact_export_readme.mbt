///|
fn export_checksum_line(digest : String, path : String) -> String {
  digest.replace(old="sha256:", new="") + "  " + path + "\n"
}

///|
fn export_label(value : String) -> String {
  let out = StringBuilder()
  for c in value {
    if c.to_int() < 32 || c.to_int() == 127 {
      out.write_string("?")
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// Plain text index. Content is not rendered or executed in this index.
pub fn ArtifactExport::to_readme(self : ArtifactExport) -> String {
  let out = StringBuilder()
  out.write_string("MoonClaw retained artifact export\n\n")
  out.write_string("Runtime evidence only. No output acceptance is implied.\n")
  out.write_string(
    "Open files/ using an appropriate trusted viewer. Original metadata is in records/.\n",
  )
  out.write_string(
    "Paths in original records are provenance, not paths to follow on this computer.\n",
  )
  out.write_string(
    "Verify the complete copy from this directory with: sha256sum -c SHA256SUMS\n",
  )
  out.write_string(
    "Checksums detect changed bytes; this is not a signed authenticity claim.\n",
  )
  out.write_string(
    "Review all content and metadata before sharing; no secret redaction was applied.\n",
  )
  out.write_string(
    "This is a review copy, not a runtime store backup or restore format.\n\n",
  )
  out.write_string(
    "Artifacts: \{self.artifacts.length()}, content bytes: \{self.total_content_bytes}\n",
  )
  for i, entry in self.artifacts {
    let record = entry.record
    let id = export_label(record.id)
    let job = export_label(record.job_id)
    let run = export_label(record.run_id)
    let kind = export_label(record.artifact_type)
    let key = export_label(record.logical_key.unwrap_or("(none)"))
    let mime = export_label(record.content_type)
    let status = match record.status {
      Active => "Active"
      Archived => "Archived"
    }
    out.write_string(
      "\n\{i + 1}. Artifact \{id}, revision \{record.version} (\{status})\n",
    )
    out.write_string("   Job: \{job}; run: \{run}\n")
    out.write_string("   Type: \{kind}; logical key: \{key}\n")
    out.write_string(
      "   Content: \{entry.content_path} (\{entry.content_bytes} bytes, \{mime})\n",
    )
    out.write_string("   SHA-256: \{entry.content_sha256}\n")
    out.write_string("   Original record: \{entry.record_path}\n")
  }
  out.to_string()
}
