///|
async test "materialize_starter_attachments_for_workspace writes manifest and extracted text" {
  @fsx.with_temporary_directory("starter-ingestion-XXXXXX", async fn(dir) {
    let initial_input = Some(
      @job.job_intake_json(
        "Land acquisition estimation",
        [
          @job.E2EStarterAttachment::new(
            id="file-1",
            mime_type="text/plain",
            url="feishu://file/file-1",
            filename=Some("brief.txt"),
          ),
        ],
        channel_id=Some("feishu"),
        account_id=Some("default"),
        recipient=Some("chat:abc"),
        message_id=Some("msg-1"),
      ),
    )
    let updated = materialize_starter_attachments_for_workspace(
      dir,
      initial_input,
      fn(_attachment, _input) {
        Ok(StarterAttachmentFetchResult::{
          content: @encoding/utf8.encode("starter file body"),
          mime_type: Some("text/plain"),
          note: Some("test fetch"),
        })
      },
    )
    let output_dir = @attachment_ingestion.starter_attachment_dir(dir)
    inspect(@fsx.exists(output_dir), content="true")
    inspect(
      @fsx.read_file(
        @attachment_ingestion.starter_attachment_manifest_markdown_path(dir),
      ).contains("brief.txt"),
      content="true",
    )
    let materialized : Array[
      @attachment_ingestion.MaterializedStarterAttachment,
    ] = match updated {
      Some({ "materialized_starter_attachments": json, .. }) =>
        @json.from_json(json) catch {
          _ => []
        }
      _ => []
    }
    inspect(materialized.length().to_string(), content="1")
    inspect(materialized[0].status, content="materialized")
    inspect(materialized[0].extracted_text_path is Some(_), content="true")
  })
}

///|
async test "materialize_starter_attachments_for_workspace records unresolved attachments" {
  @fsx.with_temporary_directory("starter-ingestion-unresolved-XXXXXX", async fn(
    dir,
  ) {
    let updated = materialize_starter_attachments_for_workspace(
      dir,
      Some(
        @job.job_intake_json(
          "Land acquisition estimation",
          [
            @job.E2EStarterAttachment::new(
              id="file-2",
              mime_type="application/pdf",
              url="feishu://file/file-2",
              filename=Some("brief.pdf"),
            ),
          ],
          message_id=Some("msg-2"),
        ),
      ),
      fn(_attachment, _input) { Err("download failed") },
    )
    let materialized : Array[
      @attachment_ingestion.MaterializedStarterAttachment,
    ] = match updated {
      Some({ "materialized_starter_attachments": json, .. }) =>
        @json.from_json(json) catch {
          _ => []
        }
      _ => []
    }
    inspect(materialized.length().to_string(), content="1")
    inspect(materialized[0].status, content="unresolved")
    inspect(materialized[0].note.unwrap_or(""), content="download failed")
  })
}
