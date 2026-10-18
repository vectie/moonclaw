///|
/// Plain-text inspection output. Quoting untrusted strings preserves control
/// characters as visible escapes instead of terminal control or fake new rows.
pub fn ArtifactSearch::to_text(self : ArtifactSearch) -> String {
  let out = StringBuilder()
  out.write_string(
    "Retained artifact search: \{self.matching_artifacts} matching, \{self.matches.length()} shown\n",
  )
  out.write_string(
    "Scanned: \{self.scanned_records}; deleted: \{self.deleted_records}; non-text excluded: \{self.excluded_nontext}; issues: \{self.issues.length()}\n",
  )
  if self.truncated {
    out.write_string("Results truncated. Narrow filters before exporting.\n")
  }
  out.write_string(
    "Runtime evidence only; no execution or human acceptance is implied.\n",
  )
  for hit in self.matches {
    out.write_string(
      "\nID \{Json(hit.record.id).stringify()} revision \{hit.record.version} \{hit.record.status.to_json().stringify()}\n",
    )
    out.write_string(
      "  job \{Json(hit.record.job_id).stringify()} run \{Json(hit.record.run_id).stringify()} type \{Json(hit.record.artifact_type).stringify()}\n",
    )
    out.write_string("  \{hit.content_bytes} bytes \{hit.content_sha256}\n")
    for line in hit.lines {
      out.write_string(
        "  line \{line.line}: \{Json(line.excerpt).stringify()}\n",
      )
    }
    if hit.matching_lines > hit.lines.length() {
      out.write_string(
        "  \{hit.matching_lines} matching lines; first \{hit.lines.length()} shown\n",
      )
    }
  }
  for issue in self.issues {
    out.write_string(
      "\nISSUE \{Json(issue.artifact_id).stringify()}: \{issue.reason}\n",
    )
  }
  out.to_string()
}
