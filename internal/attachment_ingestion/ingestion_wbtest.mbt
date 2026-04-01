///|
test "starter_attachment_file_name sanitizes separators" {
  inspect(
    starter_attachment_file_name("file:1", Some("../parcel/brief.pdf")),
    content=".._parcel_brief.pdf",
  )
}

///|
test "attachment_is_text_like accepts text and structured text extensions" {
  inspect(attachment_is_text_like("text/plain"), content="true")
  inspect(
    attachment_is_text_like(
      "application/octet-stream",
      filename=Some("brief.md"),
    ),
    content="true",
  )
  inspect(
    attachment_is_text_like("application/pdf", filename=Some("brief.pdf")),
    content="false",
  )
}

///|
test "render_materialized_attachment_manifest includes saved and extracted paths" {
  let rendered = render_materialized_attachment_manifest([
    MaterializedStarterAttachment::new(
      id="file-1",
      mime_type="text/plain",
      source_url="https://example.test/brief.txt",
      filename=Some("brief.txt"),
      saved_path=Some("/tmp/brief.txt"),
      extracted_text_path=Some("/tmp/brief.txt.extracted.txt"),
      note=Some("decoded as UTF-8"),
    ),
  ])
  inspect(rendered.contains("Saved path: /tmp/brief.txt"), content="true")
  inspect(
    rendered.contains("Extracted text path: /tmp/brief.txt.extracted.txt"),
    content="true",
  )
}
