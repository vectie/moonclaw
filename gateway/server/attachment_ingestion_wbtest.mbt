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

///|
async test "persist_starter_attachment_artifacts writes extracted text and manifests" {
  @fsx.with_temporary_directory("starter-ingestion-artifacts-XXXXXX", async fn(
    dir,
  ) {
    let workspace_dir = dir + "/workspace"
    @fsx.make_directory(workspace_dir, recursive=true, exists_ok=true) catch {
      _ => ()
    }
    let saved_path = @attachment_ingestion.starter_attachment_saved_path(
      workspace_dir,
      "file-1",
      Some("brief.txt"),
    )
    let extracted_text_path = @attachment_ingestion.starter_attachment_extracted_text_path(
      saved_path,
    )
    @fsx.make_directory(
      @attachment_ingestion.starter_attachment_dir(workspace_dir),
      recursive=true,
      exists_ok=true,
    ) catch {
      _ => ()
    }
    @fsx.write_to_file(extracted_text_path, "# Extracted") catch {
      _ => ()
    }
    @fsx.write_to_file(
      @attachment_ingestion.starter_attachment_manifest_json_path(workspace_dir),
      "[{\"id\":\"file-1\"}]",
    ) catch {
      _ => ()
    }
    @fsx.write_to_file(
      @attachment_ingestion.starter_attachment_manifest_markdown_path(
        workspace_dir,
      ),
      "- brief.txt",
    ) catch {
      _ => ()
    }
    let store = @job.SystemStore::new(root=dir + "/jobs")
    let updated = persist_starter_attachment_artifacts(
      store,
      "job-1",
      "run-1",
      workspace_dir,
      Some({
        "materialized_starter_attachments": [
          @attachment_ingestion.MaterializedStarterAttachment::new(
            id="file-1",
            mime_type="text/plain",
            source_url="feishu://file/file-1",
            filename=Some("brief.txt"),
            saved_path=Some(saved_path),
            extracted_text_path=Some(extracted_text_path),
          ),
        ],
      }),
    )
    let persisted_entries = match updated {
      Some({ "starter_attachment_artifacts": Json::Array(entries), .. }) =>
        entries
      _ => []
    }
    inspect(persisted_entries.length().to_string(), content="3")
    let digest_artifact_id = match updated {
      Some({ "starter_attachment_digest_artifact_id": String(id), .. }) => id
      _ => ""
    }
    inspect(digest_artifact_id.is_blank().to_string(), content="false")
    let first_attachment = match persisted_entries[0] {
      { "artifact_ids": Json::Array(ids), .. } => ids
      _ => []
    }
    inspect(first_attachment.length().to_string(), content="2")
    let artifact_store = @job.ArtifactStore::new(store~)
    inspect(
      artifact_store
      .list(query=@job.ArtifactQuery::new(run_id=Some("run-1")))
      .length()
      .to_string(),
      content="5",
    )
  })
}
