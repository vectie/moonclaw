///|
priv struct StarterAttachmentFetchResult {
  content : Bytes
  mime_type : String?
  note : String?
}

///|
fn intake_string_field(input : Json?, key : String) -> String? {
  match input {
    Some(Object(obj)) =>
      match obj.get(key) {
        Some(String(value)) if !value.trim().to_string().is_blank() =>
          Some(value.trim().to_string())
        _ => None
      }
    _ => None
  }
}

///|
fn starter_attachments_from_input(
  initial_input : Json?,
) -> Array[@job.E2EStarterAttachment] {
  match initial_input {
    Some(Object(obj)) =>
      match obj.get("starter_attachments") {
        Some(json) => @json.from_json(json) catch { _ => [] }
        None => []
      }
    _ => []
  }
}

///|
fn materialized_starter_attachments_from_input(
  initial_input : Json?,
) -> Array[@attachment_ingestion.MaterializedStarterAttachment] {
  match initial_input {
    Some(Object(obj)) =>
      match obj.get("materialized_starter_attachments") {
        Some(json) => @json.from_json(json) catch { _ => [] }
        None => []
      }
    _ => []
  }
}

///|
fn merge_materialized_starter_attachments_into_input(
  initial_input : Json?,
  workspace_dir : String,
  attachments : Array[@attachment_ingestion.MaterializedStarterAttachment],
) -> Json {
  let merged : Map[String, Json] = {}
  match initial_input {
    Some(Object(obj)) =>
      for key, value in obj {
        merged.set(key, value)
      }
    _ => ()
  }
  merged.set("materialized_starter_attachments", attachments.to_json())
  merged.set(
    "starter_attachment_manifest_path",
    @attachment_ingestion.starter_attachment_manifest_json_path(workspace_dir).to_json(),
  )
  merged.set(
    "starter_attachment_manifest_markdown_path",
    @attachment_ingestion.starter_attachment_manifest_markdown_path(
      workspace_dir,
    ).to_json(),
  )
  Json::object(merged)
}

///|
fn merge_starter_attachment_artifacts_into_input(
  initial_input : Json?,
  artifact_manifest : Json,
  digest_artifact_id : String?,
  digest_path : String?,
) -> Json {
  let merged : Map[String, Json] = {}
  match initial_input {
    Some(Object(obj)) =>
      for key, value in obj {
        merged.set(key, value)
      }
    _ => ()
  }
  merged.set("starter_attachment_artifacts", artifact_manifest)
  match digest_artifact_id {
    Some(artifact_id) =>
      merged.set("starter_attachment_digest_artifact_id", artifact_id.to_json())
    None => ()
  }
  match digest_path {
    Some(path) => merged.set("starter_attachment_digest_path", path.to_json())
    None => ()
  }
  Json::object(merged)
}

///|
fn materialized_starter_attachment_string_field(value : String?) -> Json {
  match value {
    Some(value) => value.to_json()
    None => null
  }
}

///|
async fn persist_starter_attachment_artifacts(
  store : @job.SystemStore,
  job_id : String,
  run_id : String,
  workspace_dir : String,
  initial_input : Json?,
) -> Json? {
  let attachments = materialized_starter_attachments_from_input(initial_input)
  if attachments.is_empty() {
    return initial_input
  }
  let artifacts = @job.ArtifactStore::new(store~)
  let now_ms = current_time_ms()
  let entries : Array[Json] = []
  let summary_entries : Array[(String, String)] = []
  for attachment in attachments {
    let entry : Map[String, Json] = {
      "id": attachment.id.to_json(),
      "filename": attachment.filename.to_json(),
      "status": attachment.status.to_json(),
      "saved_path": materialized_starter_attachment_string_field(
        attachment.saved_path,
      ),
      "extracted_text_path": materialized_starter_attachment_string_field(
        attachment.extracted_text_path,
      ),
      "artifact_ids": Json::array([]),
    }
    let artifact_ids : Array[String] = []
    match attachment.extracted_text_path {
      Some(text_path) if @fsx.exists(text_path) => {
        let extracted_text = @fsx.read_file(text_path)
        let file_name = match attachment.filename {
          Some(filename) => Some("\{filename}.md")
          None => Some("starter_attachment.md")
        }
        let artifact = artifacts.write(
          @job.ArtifactWriteRequest::new(
            run_id~,
            job_id~,
            artifact_type="starter_attachment.text",
            content=extracted_text,
            logical_key=Some("starter-attachment:\{attachment.id}:text"),
            content_type="text/markdown",
            file_name~,
            metadata={
              "attachment_id": attachment.id,
              "filename": attachment.filename,
              "saved_path": attachment.saved_path,
              "extracted_text_path": attachment.extracted_text_path,
            },
            scope=["starter_attachment", attachment.id],
          ),
          "artifact-\{run_id}-starter-\{attachment.id}-text",
          now_ms,
        )
        artifact_ids.push(artifact.id)
        let summary_markdown = @attachment_ingestion.starter_attachment_summary_markdown(
          attachment, extracted_text,
        )
        let summary_artifact = artifacts.write(
          @job.ArtifactWriteRequest::new(
            run_id~,
            job_id~,
            artifact_type="starter_attachment.summary",
            content=summary_markdown,
            logical_key=Some("starter-attachment:\{attachment.id}:summary"),
            content_type="text/markdown",
            file_name=Some(
              @attachment_ingestion.starter_attachment_summary_file_name(
                attachment.filename,
              ),
            ),
            metadata={
              "attachment_id": attachment.id,
              "filename": attachment.filename,
              "saved_path": attachment.saved_path,
              "extracted_text_path": attachment.extracted_text_path,
            },
            scope=["starter_attachment", attachment.id, "summary"],
          ),
          "artifact-\{run_id}-starter-\{attachment.id}-summary",
          now_ms,
        )
        artifact_ids.push(summary_artifact.id)
        summary_entries.push((attachment.id, summary_markdown))
      }
      _ => ()
    }
    entry.set(
      "artifact_ids",
      artifact_ids.map(fn(id) { id.to_json() }).to_json(),
    )
    entries.push(Json::object(entry))
  }

  let manifest_json_path = @attachment_ingestion.starter_attachment_manifest_json_path(
    workspace_dir,
  )
  if @fsx.exists(manifest_json_path) {
    let artifact = artifacts.write(
      @job.ArtifactWriteRequest::new(
        run_id~,
        job_id~,
        artifact_type="starter_attachment.manifest",
        content=@fsx.read_file(manifest_json_path),
        logical_key=Some("starter-attachment:manifest:json"),
        content_type="application/json",
        file_name=Some("starter_attachment_manifest.json"),
        metadata={ "kind": "json", "path": manifest_json_path },
        scope=["starter_attachment", "manifest"],
      ),
      "artifact-\{run_id}-starter-manifest-json",
      now_ms,
    )
    entries.push({
      "kind": "manifest_json",
      "path": manifest_json_path,
      "artifact_id": artifact.id,
    })
  }

  let manifest_markdown_path = @attachment_ingestion.starter_attachment_manifest_markdown_path(
    workspace_dir,
  )
  if @fsx.exists(manifest_markdown_path) {
    let artifact = artifacts.write(
      @job.ArtifactWriteRequest::new(
        run_id~,
        job_id~,
        artifact_type="starter_attachment.manifest",
        content=@fsx.read_file(manifest_markdown_path),
        logical_key=Some("starter-attachment:manifest:markdown"),
        content_type="text/markdown",
        file_name=Some("starter_attachment_manifest.md"),
        metadata={ "kind": "markdown", "path": manifest_markdown_path },
        scope=["starter_attachment", "manifest"],
      ),
      "artifact-\{run_id}-starter-manifest-markdown",
      now_ms,
    )
    entries.push({
      "kind": "manifest_markdown",
      "path": manifest_markdown_path,
      "artifact_id": artifact.id,
    })
  }

  let (digest_artifact_id, digest_path) = if summary_entries.is_empty() {
    (None, None)
  } else {
    let digest_markdown = @attachment_ingestion.starter_attachment_digest_markdown(
      attachments, summary_entries,
    )
    let digest_path = @attachment_ingestion.starter_attachment_digest_path(
      workspace_dir,
    )
    @fsx.write_to_file(digest_path, digest_markdown) catch {
      _ => ()
    }
    let artifact = artifacts.write(
      @job.ArtifactWriteRequest::new(
        run_id~,
        job_id~,
        artifact_type="starter_attachment.digest",
        content=digest_markdown,
        logical_key=Some("starter-attachment:digest"),
        content_type="text/markdown",
        file_name=Some("starter_attachment_digest.md"),
        metadata={
          "attachment_count": attachments.length(),
          "path": digest_path,
        },
        scope=["starter_attachment", "digest"],
      ),
      "artifact-\{run_id}-starter-digest",
      now_ms,
    )
    (Some(artifact.id), Some(digest_path))
  }

  Some(
    merge_starter_attachment_artifacts_into_input(
      initial_input,
      Json::array(entries),
      digest_artifact_id,
      digest_path,
    ),
  )
}

///|
fn feishu_resource_type_for_attachment(
  attachment : @job.E2EStarterAttachment,
) -> String? {
  if attachment.url.has_prefix("feishu://file/") {
    Some("file")
  } else if attachment.url.has_prefix("feishu://image/") {
    Some("image")
  } else if attachment.url.has_prefix("feishu://audio/") {
    Some("audio")
  } else if attachment.url.has_prefix("feishu://video/") {
    Some("video")
  } else {
    None
  }
}

///|
fn Gateway::feishu_account_config(
  self : Gateway,
  channel_id : String,
  account_id : String,
) -> @feishu.FeishuAccountConfig? {
  guard channel_id == "feishu" else { return None }
  for state in self.channel_state.list_states() {
    if state.channel_id != channel_id {
      continue
    }
    for account in state.accounts {
      if account.account_id == account_id {
        return Some(@feishu.account_config_from_json(account.config))
      }
    }
  }
  None
}

///|
async fn Gateway::fetch_starter_attachment(
  self : Gateway,
  attachment : @job.E2EStarterAttachment,
  initial_input : Json?,
) -> Result[StarterAttachmentFetchResult, String] {
  match feishu_resource_type_for_attachment(attachment) {
    Some(resource_type) => {
      let message_id = match intake_string_field(initial_input, "message_id") {
        Some(message_id) => message_id
        None =>
          return Err(
            "Missing message_id for Feishu starter attachment \{attachment.id}",
          )
      }
      let channel_id = match intake_string_field(initial_input, "channel_id") {
        Some(channel_id) => channel_id
        None =>
          return Err(
            "Missing channel_id for starter attachment \{attachment.id}",
          )
      }
      let account_id = match intake_string_field(initial_input, "account_id") {
        Some(account_id) => account_id
        None =>
          return Err(
            "Missing account_id for starter attachment \{attachment.id}",
          )
      }
      let config = match self.feishu_account_config(channel_id, account_id) {
        Some(config) => config
        None =>
          return Err(
            "No runtime Feishu account config found for \{channel_id}/\{account_id}",
          )
      }
      let client = @feishu.FeishuClient::new(config)
      let (content, fetched_mime_type) = match
        client.download_message_resource(
          message_id,
          attachment.id,
          resource_type,
        ) {
        Ok(result) => result
        Err(error) => return Err(error.to_string())
      }
      Ok(StarterAttachmentFetchResult::{
        content,
        mime_type: fetched_mime_type,
        note: None,
      })
    }
    None =>
      Err(
        "Unsupported starter attachment source for \{attachment.filename.unwrap_or(attachment.id)}: \{attachment.url}",
      )
  }
}

///|
async fn materialize_starter_attachments_for_workspace(
  workspace_dir : String,
  initial_input : Json?,
  fetch : async (@job.E2EStarterAttachment, Json?) -> Result[
    StarterAttachmentFetchResult,
    String,
  ],
) -> Json? {
  let attachments = starter_attachments_from_input(initial_input)
  if attachments.is_empty() {
    return initial_input
  }
  let output_dir = @attachment_ingestion.starter_attachment_dir(workspace_dir)
  @fsx.make_directory(output_dir, recursive=true, exists_ok=true) catch {
    _ => ()
  }
  let materialized : Array[@attachment_ingestion.MaterializedStarterAttachment] = []
  let seen : Map[String, Bool] = {}
  for attachment in materialized_starter_attachments_from_input(initial_input) {
    let key = if attachment.id.is_blank() {
      attachment.source_url
    } else {
      attachment.id
    }
    if !seen.contains(key) {
      seen.set(key, true)
      materialized.push(attachment)
    }
  }
  for attachment in attachments {
    let key = if attachment.id.is_blank() {
      attachment.url
    } else {
      attachment.id
    }
    if seen.contains(key) {
      continue
    }
    seen.set(key, true)
    let saved_path = @attachment_ingestion.starter_attachment_saved_path(
      workspace_dir,
      attachment.id,
      attachment.filename,
    )
    match fetch(attachment, initial_input) {
      Ok(result) => {
        let resolved_mime_type = result.mime_type.unwrap_or(
          attachment.mime_type,
        )
        let write_error = try {
          @fsx.write_bytes_to_file(saved_path, result.content)
          None
        } catch {
          error => Some(error.to_string())
        }
        match write_error {
          Some(error) => {
            materialized.push(
              @attachment_ingestion.MaterializedStarterAttachment::new(
                id=attachment.id,
                mime_type=resolved_mime_type,
                source_url=attachment.url,
                filename=attachment.filename,
                status="unresolved",
                note=Some("Failed to write starter attachment: \{error}"),
                size=attachment.size,
              ),
            )
            continue
          }
          None => ()
        }
        let extracted_text_path = if @attachment_ingestion.attachment_is_text_like(
            resolved_mime_type,
            filename=attachment.filename,
          ) {
          let decoded_text = try? @encoding/utf8.decode(result.content)
          match decoded_text {
            Ok(text) => {
              let text_path = @attachment_ingestion.starter_attachment_extracted_text_path(
                saved_path,
              )
              @fsx.write_to_file(text_path, text) catch {
                _ => ()
              }
              Some(text_path)
            }
            Err(_) => None
          }
        } else if @attachment_ingestion.attachment_is_pdf(
            resolved_mime_type,
            filename=attachment.filename,
          ) {
          let extracted_text_path = @attachment_ingestion.starter_attachment_extracted_text_path(
            saved_path,
          )
          let (text_path, extraction_note) = @pdf_ocr.extract_text_from_pdf(
            saved_path,
            extracted_text_path,
            output_dir,
            async fn(command, args, cwd) {
              @pdf_ocr.run_process(command, args, cwd~)
            },
          )
          let merged_note = match (result.note, extraction_note) {
            (Some(left), Some(right)) if !left.trim().to_string().is_blank() =>
              Some("\{left}; \{right}")
            (Some(left), _) => Some(left)
            (_, Some(right)) => Some(right)
            _ => None
          }
          materialized.push(
            @attachment_ingestion.MaterializedStarterAttachment::new(
              id=attachment.id,
              mime_type=resolved_mime_type,
              source_url=attachment.url,
              filename=attachment.filename,
              saved_path=Some(saved_path),
              extracted_text_path=text_path,
              note=merged_note,
              size=attachment.size,
            ),
          )
          continue
        } else {
          None
        }
        materialized.push(
          @attachment_ingestion.MaterializedStarterAttachment::new(
            id=attachment.id,
            mime_type=resolved_mime_type,
            source_url=attachment.url,
            filename=attachment.filename,
            saved_path=Some(saved_path),
            extracted_text_path~,
            note=result.note,
            size=attachment.size,
          ),
        )
      }
      Err(error) =>
        materialized.push(
          @attachment_ingestion.MaterializedStarterAttachment::new(
            id=attachment.id,
            mime_type=attachment.mime_type,
            source_url=attachment.url,
            filename=attachment.filename,
            status="unresolved",
            note=Some(error),
            size=attachment.size,
          ),
        )
    }
  }
  @fsx.write_to_file(
    @attachment_ingestion.starter_attachment_manifest_json_path(workspace_dir),
    materialized.to_json().stringify(),
  ) catch {
    _ => ()
  }
  @fsx.write_to_file(
    @attachment_ingestion.starter_attachment_manifest_markdown_path(
      workspace_dir,
    ),
    @attachment_ingestion.render_materialized_attachment_manifest(materialized),
  ) catch {
    _ => ()
  }
  Some(
    merge_materialized_starter_attachments_into_input(
      initial_input, workspace_dir, materialized,
    ),
  )
}

///|
async fn Gateway::materialize_starter_attachments_for_run(
  self : Gateway,
  run_id : String,
  initial_input : Json?,
) -> Json? {
  let run = match self.job_runtime().store().get_run(run_id) {
    Some(run) => run
    None => return initial_input
  }
  let definition = match self.job_runtime().store().get_definition(run.job_id) {
    Some(definition) => definition
    None => return initial_input
  }
  let prepared_run = @job.prepare_run_workspace(
    self.job_runtime().store(),
    definition,
    run,
  )
  let workspace_dir = prepared_run.workspace_dir.unwrap_or(self.cwd)
  let materialized = materialize_starter_attachments_for_workspace(
    workspace_dir,
    initial_input,
    async fn(attachment, input) {
      self.fetch_starter_attachment(attachment, input)
    },
  )
  persist_starter_attachment_artifacts(
    self.job_runtime().store(),
    definition.id,
    run.id,
    workspace_dir,
    materialized,
  )
}
