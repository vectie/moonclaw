///|
pub struct MaterializedStarterAttachment {
  id : String
  mime_type : String
  source_url : String
  filename : String?
  saved_path : String?
  extracted_text_path : String?
  status : String
  note : String?
  size : Int?
} derive(ToJson, FromJson, Debug)

///|
pub fn MaterializedStarterAttachment::new(
  id~ : String,
  mime_type~ : String,
  source_url~ : String,
  filename? : String? = None,
  saved_path? : String? = None,
  extracted_text_path? : String? = None,
  status? : String = "materialized",
  note? : String? = None,
  size? : Int? = None,
) -> MaterializedStarterAttachment {
  {
    id,
    mime_type,
    source_url,
    filename,
    saved_path,
    extracted_text_path,
    status,
    note,
    size,
  }
}

///|
pub fn starter_attachment_dir(workspace_dir : String) -> String {
  @moonsuite.product_artifact_for_workspace_root(
    workspace_dir, "moonclaw", "starter_attachments",
  )
}

///|
pub fn starter_attachment_manifest_json_path(workspace_dir : String) -> String {
  starter_attachment_dir(workspace_dir) |> @pathx.join("manifest.json")
}

///|
pub fn starter_attachment_manifest_markdown_path(
  workspace_dir : String,
) -> String {
  starter_attachment_dir(workspace_dir) |> @pathx.join("manifest.md")
}

///|
pub fn starter_attachment_digest_path(workspace_dir : String) -> String {
  starter_attachment_dir(workspace_dir) |> @pathx.join("digest.md")
}

///|
fn sanitized_attachment_name(text : String) -> String {
  let builder = StringBuilder::new()
  for char in text {
    if char == '/' || char == '\\' || char == ':' {
      builder.write_char('_')
    } else {
      builder.write_char(char)
    }
  }
  builder.to_string().trim().to_owned()
}

///|
pub fn starter_attachment_file_name(
  attachment_id : String,
  filename : String?,
) -> String {
  let base = match filename {
    Some(filename) if !filename.trim().to_owned().is_blank() =>
      sanitized_attachment_name(filename.trim().to_owned())
    _ => ""
  }
  if base.is_blank() {
    "attachment-\{sanitized_attachment_name(attachment_id)}"
  } else {
    base
  }
}

///|
pub fn starter_attachment_saved_path(
  workspace_dir : String,
  attachment_id : String,
  filename : String?,
) -> String {
  starter_attachment_dir(workspace_dir)
  |> @pathx.join(starter_attachment_file_name(attachment_id, filename))
}

///|
pub fn starter_attachment_extracted_text_path(saved_path : String) -> String {
  "\{saved_path}.extracted.txt"
}

///|
pub fn starter_attachment_summary_file_name(filename : String?) -> String {
  match filename {
    Some(filename) if !filename.trim().to_owned().is_blank() =>
      "\{sanitized_attachment_name(filename.trim().to_owned())}.summary.md"
    None => "starter_attachment.summary.md"
    _ => "starter_attachment.summary.md"
  }
}

///|
pub fn starter_attachment_summary_markdown(
  attachment : MaterializedStarterAttachment,
  extracted_text : String,
) -> String {
  let title = attachment.filename.unwrap_or(attachment.id)
  let trimmed = extracted_text.trim().to_owned()
  let excerpt = if trimmed.length() > 600 {
    trimmed[:600].to_owned() + "..."
  } else {
    trimmed
  }
  let lines = ["# Starter Attachment Summary", ""]
  lines.push("- Filename: \{title}")
  lines.push("- Attachment id: \{attachment.id}")
  lines.push("- MIME type: \{attachment.mime_type}")
  match attachment.saved_path {
    Some(path) => lines.push("- Saved path: \{path}")
    None => ()
  }
  match attachment.extracted_text_path {
    Some(path) => lines.push("- Extracted text path: \{path}")
    None => ()
  }
  lines.push("")
  lines.push("## Extracted Preview")
  lines.push("")
  if excerpt.is_blank() {
    lines.push("No readable text was extracted.")
  } else {
    lines.push(excerpt)
  }
  lines.join("\n").trim_end().to_owned() + "\n"
}

///|
pub fn starter_attachment_digest_markdown(
  attachments : Array[MaterializedStarterAttachment],
  summary_entries : Array[(String, String)],
) -> String {
  let lines = [
    "# Starter Attachment Digest", "", "Use this digest as the compact starter-document overview before reading per-file extracted text in full.",
    "",
  ]
  if attachments.is_empty() {
    lines.push("No starter attachments were materialized.")
    return lines.join("\n").trim_end().to_owned() + "\n"
  }
  for attachment in attachments {
    let title = attachment.filename.unwrap_or(attachment.id)
    lines.push("## \{title}")
    lines.push("")
    lines.push("- Attachment id: \{attachment.id}")
    lines.push("- MIME type: \{attachment.mime_type}")
    lines.push("- Status: \{attachment.status}")
    match attachment.saved_path {
      Some(path) => lines.push("- Saved path: \{path}")
      None => ()
    }
    match attachment.extracted_text_path {
      Some(path) => lines.push("- Extracted text path: \{path}")
      None => ()
    }
    match attachment.note {
      Some(note) if !note.trim().to_owned().is_blank() =>
        lines.push("- Note: \{note.trim().to_owned()}")
      _ => ()
    }
    let mut matched_summary : String? = None
    for entry in summary_entries {
      if entry.0 == attachment.id {
        matched_summary = Some(entry.1)
        break
      }
    }
    match matched_summary {
      Some(summary_markdown) => {
        let excerpt = summary_markdown.trim().to_owned()
        if !excerpt.is_blank() {
          lines.push("")
          lines.push("### Summary")
          lines.push("")
          lines.push(excerpt)
        }
      }
      None => ()
    }
    lines.push("")
  }
  lines.join("\n").trim_end().to_owned() + "\n"
}

///|
pub fn starter_attachment_digest_excerpt(
  digest_markdown : String,
  limit? : Int = 2000,
) -> String {
  let trimmed = digest_markdown.trim().to_owned()
  if trimmed.length() <= limit {
    trimmed
  } else {
    trimmed[:limit].to_owned() + "..."
  }
}

///|
pub fn attachment_is_text_like(
  mime_type : String,
  filename? : String? = None,
) -> Bool {
  if mime_type.has_prefix("text/") ||
    mime_type == "application/json" ||
    mime_type == "application/xml" {
    return true
  }
  let lower = match filename {
    Some(filename) => filename.to_lower()
    None => ""
  }
  lower.has_suffix(".txt") ||
  lower.has_suffix(".md") ||
  lower.has_suffix(".markdown") ||
  lower.has_suffix(".json") ||
  lower.has_suffix(".csv") ||
  lower.has_suffix(".tsv") ||
  lower.has_suffix(".yaml") ||
  lower.has_suffix(".yml") ||
  lower.has_suffix(".xml") ||
  lower.has_suffix(".html")
}

///|
pub fn attachment_is_pdf(
  mime_type : String,
  filename? : String? = None,
) -> Bool {
  if mime_type == "application/pdf" {
    return true
  }
  match filename {
    Some(filename) => filename.to_lower().has_suffix(".pdf")
    None => false
  }
}

///|
pub fn render_materialized_attachment_manifest(
  attachments : Array[MaterializedStarterAttachment],
) -> String {
  let lines = ["# Starter Attachments", ""]
  if attachments.is_empty() {
    lines.push("No starter attachments were materialized.")
    return lines.join("\n")
  }
  for attachment in attachments {
    let title = attachment.filename.unwrap_or(attachment.id)
    lines.push("## \{title}")
    lines.push("- Status: \{attachment.status}")
    lines.push("- Attachment id: \{attachment.id}")
    lines.push("- MIME type: \{attachment.mime_type}")
    lines.push("- Source URL: \{attachment.source_url}")
    match attachment.saved_path {
      Some(path) => lines.push("- Saved path: \{path}")
      None => ()
    }
    match attachment.extracted_text_path {
      Some(path) => lines.push("- Extracted text path: \{path}")
      None => ()
    }
    match attachment.note {
      Some(note) if !note.trim().to_owned().is_blank() =>
        lines.push("- Note: \{note.trim().to_owned()}")
      _ => ()
    }
    lines.push("")
  }
  lines.join("\n").trim_end().to_owned() + "\n"
}
