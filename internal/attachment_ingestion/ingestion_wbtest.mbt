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
test "attachment_is_pdf accepts mime type and file extension" {
  inspect(attachment_is_pdf("application/pdf"), content="true")
  inspect(
    attachment_is_pdf("application/octet-stream", filename=Some("brief.pdf")),
    content="true",
  )
  inspect(
    attachment_is_pdf("text/plain", filename=Some("brief.txt")),
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

///|
test "starter_attachment_digest_markdown includes per-file summaries" {
  let rendered = starter_attachment_digest_markdown(
    [
      MaterializedStarterAttachment::new(
        id="file-1",
        mime_type="application/pdf",
        source_url="feishu://file/file-1",
        filename=Some("parcel.pdf"),
        saved_path=Some("/tmp/parcel.pdf"),
        extracted_text_path=Some("/tmp/parcel.pdf.extracted.txt"),
      ),
    ],
    [
      (
        "file-1", "# Starter Attachment Summary\n\n## Extracted Preview\n\nParcel digest",
      ),
    ],
  )
  inspect(rendered.contains("# Starter Attachment Digest"), content="true")
  inspect(rendered.contains("## parcel.pdf"), content="true")
  inspect(rendered.contains("### Summary"), content="true")
  inspect(rendered.contains("Parcel digest"), content="true")
}

///|
test "starter_attachment_digest_excerpt truncates long digest text" {
  let excerpt = starter_attachment_digest_excerpt(
    "abcdefghijklmnopqrstuvwxyz",
    limit=20,
  )
  inspect(excerpt, content="abcdefghijklmnopqrst...")
}
