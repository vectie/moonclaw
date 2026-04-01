///|
priv struct StarterAttachmentFetchResult {
  content : Bytes
  mime_type : String?
  note : String?
}

///|
async fn run_process(
  command : String,
  arguments : Array[String],
  cwd? : String? = None,
) -> Result[@spawn.CompletedProcess, String] {
  Ok(
    @spawn.spawn(
      command[:],
      arguments.map(fn(arg) { arg[:] }),
      cwd?=cwd.map(fn(path) { path[:] }),
    ) catch {
      error => return Err(error.to_string())
    },
  )
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
async fn extract_pdf_text_from_saved_file(
  saved_path : String,
  output_dir : String,
  run_command : async (String, Array[String], String?) -> Result[
    @spawn.CompletedProcess,
    String,
  ],
) -> (String?, String?) {
  let extracted_text_path = @attachment_ingestion.starter_attachment_extracted_text_path(
    saved_path,
  )
  let direct = run_command("pdftotext", [saved_path, extracted_text_path], None)
  match direct {
    Ok(process) if process.status == 0 &&
      (@fsx.exists(extracted_text_path) catch { _ => false }) =>
      return (Some(extracted_text_path), Some("Extracted text with pdftotext"))
    _ => ()
  }

  let ppm_dir = output_dir + "/ocr-pages"
  @fsx.make_directory(ppm_dir, recursive=true, exists_ok=true) catch {
    _ => ()
  }
  let prefix = ppm_dir + "/page"
  let rasterized = run_command("pdftoppm", ["-png", saved_path, prefix], None)
  match rasterized {
    Ok(process) if process.status == 0 => ()
    _ =>
      return (
        None,
        Some(
          "PDF remained binary: install pdftotext or pdftoppm+tesseract to extract text",
        ),
      )
  }

  let pages = (@fsx.list_directory(ppm_dir) catch { _ => [] }).filter(fn(
    entry,
  ) {
    entry.kind is @fsx.FileKind::Regular && entry.name.has_suffix(".png")
  })
  if pages.is_empty() {
    return (
      None,
      Some("PDF OCR could not run because pdftoppm produced no page images"),
    )
  }
  let sections : Array[String] = []
  for page in pages {
    let output_base = page.path[:page.path.length() - 4].to_string()
    let ocr = run_command("tesseract", [page.path, output_base], None)
    match ocr {
      Ok(process) if process.status == 0 => {
        let page_text_path = "\{output_base}.txt"
        let page_text_exists = @fsx.exists(page_text_path) catch { _ => false }
        if page_text_exists {
          let page_text = @fsx.read_file(page_text_path)
          if !page_text.trim().to_string().is_blank() {
            sections.push("## \{page.name}")
            sections.push("")
            sections.push(page_text.trim_end().to_string())
            sections.push("")
          }
        }
      }
      _ => ()
    }
  }
  if sections.is_empty() {
    return (
      None,
      Some("PDF OCR could not extract readable text with tesseract"),
    )
  }
  @fsx.write_to_file(extracted_text_path, sections.join("\n")) catch {
    _ => ()
  }
  (
    Some(extracted_text_path),
    Some("Extracted text with OCR (pdftoppm + tesseract)"),
  )
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
          let (text_path, extraction_note) = extract_pdf_text_from_saved_file(
            saved_path,
            output_dir,
            async fn(command, args, cwd) { run_process(command, args, cwd~) },
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
  materialize_starter_attachments_for_workspace(workspace_dir, initial_input, async fn(
    attachment,
    input,
  ) {
    self.fetch_starter_attachment(attachment, input)
  })
}
