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
} derive(ToJson, FromJson, Show)

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
  workspace_dir
  |> @pathx.join(".moonclaw")
  |> @pathx.join("starter_attachments")
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
fn sanitized_attachment_name(text : String) -> String {
  let builder = StringBuilder::new()
  for char in text {
    if char == '/' || char == '\\' || char == ':' {
      builder.write_char('_')
    } else {
      builder.write_char(char)
    }
  }
  builder.to_string().trim().to_string()
}

///|
pub fn starter_attachment_file_name(
  attachment_id : String,
  filename : String?,
) -> String {
  let base = match filename {
    Some(filename) if !filename.trim().to_string().is_blank() =>
      sanitized_attachment_name(filename.trim().to_string())
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
      Some(note) if !note.trim().to_string().is_blank() =>
        lines.push("- Note: \{note.trim().to_string()}")
      _ => ()
    }
    lines.push("")
  }
  lines.join("\n").trim_end().to_string() + "\n"
}
