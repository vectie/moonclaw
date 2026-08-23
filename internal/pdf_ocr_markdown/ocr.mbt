///|
pub struct OcrMarkdownOptions {
  language : String?
  dpi : Int
  timeout_ms : Int?
  page_segmentation_mode : Int?
} derive(Show, Eq)

///|
pub fn OcrMarkdownOptions::new(
  language? : String? = None,
  dpi? : Int = 200,
  timeout_ms? : Int? = Some(120_000),
  page_segmentation_mode? : Int? = None,
) -> OcrMarkdownOptions {
  OcrMarkdownOptions::{ language, dpi, timeout_ms, page_segmentation_mode }
}

///|
pub struct OcrMarkdownPage {
  page_number : Int
  text : String
  markdown : String
} derive(Show, Eq)

///|
pub struct OcrMarkdownDocument {
  source_path : String
  title : String
  markdown : String
  pages : Array[OcrMarkdownPage]
  engine : String
} derive(Show, Eq)

///|
pub(all) struct CommandRequest {
  command : String
  arguments : Array[String]
  cwd : String?
  timeout_ms : Int?
} derive(Show, Eq)

///|
pub(all) struct CommandResult {
  command : String
  arguments : Array[String]
  status : Int
  stdout : String
  stderr : String
  elapsed_ms : Int
  timeout_ms : Int?
} derive(Show, Eq)

///|
pub(all) struct CommandExecutor {
  run : async (CommandRequest) -> Result[CommandResult, String]
}

///|
pub fn CommandExecutor::new(
  run~ : async (CommandRequest) -> Result[CommandResult, String],
) -> CommandExecutor {
  CommandExecutor::{ run, }
}

///|
pub fn default_command_executor() -> CommandExecutor {
  CommandExecutor::new(run=async fn(request) {
    ignore(request)
    Err(
      "native PDF OCR refused: no configured ExecutionSandbox route is available",
    )
  })
}

///|
pub suberror PdfOcrMarkdownError {
  FileNotFound(String)
  RasterizationFailed(String)
  NoPagesGenerated(String)
  OcrFailed(String)
} derive(Show)

///|
priv struct RasterizedPage {
  page_number : Int
  path : String
}

///|
fn parse_positive_int(text : StringView) -> Int? {
  guard !text.is_blank() else { return None }
  let mut value = 0
  for ch in text.to_string().to_array() {
    guard ch >= '0' && ch <= '9' else { return None }
    value = value * 10 + ch.to_int() - '0'.to_int()
  }
  Some(value)
}

///|
fn parse_page_number(name : String) -> Int? {
  let stem = @pathx.stem(name).to_string()
  guard stem.has_prefix("page-") else { return None }
  parse_positive_int(stem[5:])
}

///|
fn collect_rasterized_pages(
  entries : Array[@fsx.DirectoryEntry],
) -> Array[RasterizedPage] {
  let pages : Array[RasterizedPage] = []
  for entry in entries {
    guard entry.kind is @fsx.FileKind::Regular else { continue }
    guard entry.name.has_suffix(".png") else { continue }
    guard parse_page_number(entry.name) is Some(page_number) else { continue }
    pages.push(RasterizedPage::{ page_number, path: entry.path })
  }
  pages.sort_by(fn(left, right) { left.page_number - right.page_number })
  pages
}

///|
fn compact_blank_lines(lines : Array[String]) -> Array[String] {
  let output = []
  let mut previous_blank = false
  for line in lines {
    let blank = line.is_blank()
    if blank && previous_blank {
      continue
    }
    output.push(line)
    previous_blank = blank
  }
  output
}

///|
fn normalized_ocr_lines(text : String) -> Array[String] {
  let cleaned = text
    .replace(old="\r\n", new="\n")
    .replace(old="\r", new="\n")
    .split("\n")
    .map(fn(line) { line.trim().to_string() })
    .to_array()
  compact_blank_lines(cleaned)
}

///|
fn bullet_content(line : String) -> String? {
  let trimmed = line.trim().to_string()
  if trimmed.has_prefix("- ") || trimmed.has_prefix("* ") {
    return Some(trimmed[2:].trim().to_string())
  }
  if trimmed.has_prefix("• ") {
    return Some(trimmed[2:].trim().to_string())
  }
  let chars = trimmed.to_array()
  let mut index = 0
  while index < chars.length() && chars[index] >= '0' && chars[index] <= '9' {
    index += 1
  }
  if index > 0 && index + 1 < chars.length() {
    let marker = chars[index]
    let space = chars[index + 1]
    if (marker == '.' || marker == ')') && space == ' ' {
      return Some(trimmed[index + 2:].trim().to_string())
    }
  }
  None
}

///|
fn looks_like_heading(text : String) -> Bool {
  let trimmed = text.trim().to_string()
  guard !trimmed.is_blank() else { return false }
  guard trimmed.length() <= 60 else { return false }
  let last = trimmed.to_array().last()
  match last {
    Some(
      '.'
      | ','
      | ';'
      | ':'
      | '!'
      | '?'
      | '。'
      | '，'
      | '；'
      | '：'
      | '！'
      | '？'
    ) => false
    _ => true
  }
}

///|
fn render_paragraph(lines : Array[String]) -> String {
  guard !lines.is_empty() else { return "" }
  let bullets = []
  let mut all_bullets = true
  for line in lines {
    match bullet_content(line) {
      Some(content) => bullets.push("- \{content}")
      None => {
        all_bullets = false
        break
      }
    }
  }
  if all_bullets {
    return bullets.join("\n")
  }
  if lines.length() == 1 {
    let line = lines[0].trim().to_string()
    if looks_like_heading(line) {
      return "### \{line}"
    }
  }
  lines.join(" ")
}

///|
fn render_page_markdown(page_number : Int, text : String) -> String {
  let lines = normalized_ocr_lines(text)
  let sections = ["## Page \{page_number}"]
  if lines.is_empty() {
    sections.push("")
    sections.push("_No OCR text extracted._")
    return sections.join("\n")
  }
  let paragraph_lines = []
  for line in lines {
    if line.is_blank() {
      if !paragraph_lines.is_empty() {
        sections.push("")
        sections.push(render_paragraph(paragraph_lines))
        paragraph_lines.clear()
      }
      continue
    }
    paragraph_lines.push(line)
  }
  if !paragraph_lines.is_empty() {
    sections.push("")
    sections.push(render_paragraph(paragraph_lines))
  }
  sections.join("\n")
}

///|
fn completed_process_detail(process : CommandResult) -> String {
  let joined_args = process.arguments.join(" ")
  let rendered_command = "Command: \{process.command} \{joined_args}"
  let lines = [rendered_command.trim().to_string(), "Status: \{process.status}"]
  if !process.stdout.trim().is_blank() {
    lines.push("STDOUT:")
    lines.push(process.stdout.trim().to_string())
  }
  if !process.stderr.trim().is_blank() {
    lines.push("STDERR:")
    lines.push(process.stderr.trim().to_string())
  }
  lines.join("\n")
}

///|
async fn run_command(
  executor : CommandExecutor,
  request : CommandRequest,
) -> CommandResult raise PdfOcrMarkdownError {
  let outcome = (executor.run)(request) catch {
    error =>
      if request.command == "pdftoppm" {
        raise RasterizationFailed(error.to_string())
      } else {
        raise OcrFailed(error.to_string())
      }
  }
  match outcome {
    Ok(process) => process
    Err(message) =>
      if request.command == "pdftoppm" {
        raise RasterizationFailed(message)
      } else {
        raise OcrFailed(message)
      }
  }
}

///|
fn title_from_pdf_path(pdf_path : String) -> String {
  let stem = @pathx.stem(@pathx.basename(pdf_path)).to_string()
  if stem.is_blank() {
    "OCR Document"
  } else {
    stem
  }
}

///|
fn raster_command(
  pdf_path : String,
  prefix : String,
  options : OcrMarkdownOptions,
) -> CommandRequest {
  CommandRequest::{
    command: "pdftoppm",
    arguments: [
      "-png",
      "-r",
      @cmp.maximum(72, options.dpi).to_string(),
      pdf_path,
      prefix,
    ],
    cwd: None,
    timeout_ms: options.timeout_ms,
  }
}

///|
fn ocr_command(
  image_path : String,
  options : OcrMarkdownOptions,
) -> CommandRequest {
  let arguments = [image_path, "stdout"]
  if options.language is Some(language) && !language.trim().is_blank() {
    arguments.push("-l")
    arguments.push(language.trim().to_string())
  }
  if options.page_segmentation_mode is Some(psm) {
    arguments.push("--psm")
    arguments.push(psm.to_string())
  }
  CommandRequest::{
    command: "tesseract",
    arguments,
    cwd: None,
    timeout_ms: options.timeout_ms,
  }
}

///|
pub async fn convert_pdf_to_markdown(
  pdf_path : String,
  options? : OcrMarkdownOptions = OcrMarkdownOptions::new(),
  executor? : CommandExecutor = default_command_executor(),
) -> OcrMarkdownDocument raise PdfOcrMarkdownError {
  let exists = @fsx.exists(pdf_path) catch { _ => false }
  guard exists else { raise FileNotFound(pdf_path) }
  @fsx.with_temporary_directory("moonclaw-pdf-ocr-XXXXXX", async fn(tmpdir) {
    let prefix = @pathx.join(tmpdir, "page")
    let raster = run_command(
      executor,
      raster_command(pdf_path, prefix, options),
    )
    guard raster.status == 0 else {
      raise RasterizationFailed(completed_process_detail(raster))
    }
    let pages = collect_rasterized_pages(@fsx.list_directory(tmpdir))
    guard !pages.is_empty() else { raise NoPagesGenerated(pdf_path) }
    let converted_pages : Array[OcrMarkdownPage] = []
    for page in pages {
      let process = run_command(executor, ocr_command(page.path, options))
      guard process.status == 0 else {
        raise OcrFailed(
          "Page \{page.page_number}\n\{completed_process_detail(process)}",
        )
      }
      let text = process.stdout.trim().to_string()
      converted_pages.push(OcrMarkdownPage::{
        page_number: page.page_number,
        text,
        markdown: render_page_markdown(page.page_number, text),
      })
    }
    let title = title_from_pdf_path(pdf_path)
    let markdown_sections = [
      "# \{title}",
      "",
      "_Source PDF:_ `\{@pathx.basename(pdf_path)}`",
      "_Engine:_ `pdftoppm + tesseract`",
      "",
      ..converted_pages.map(page => page.markdown),
    ]
    OcrMarkdownDocument::{
      source_path: pdf_path,
      title,
      markdown: markdown_sections.join("\n\n"),
      pages: converted_pages,
      engine: "pdftoppm+tesseract",
    }
  }) catch {
    FileNotFound(path) => raise FileNotFound(path)
    RasterizationFailed(detail) => raise RasterizationFailed(detail)
    NoPagesGenerated(path) => raise NoPagesGenerated(path)
    OcrFailed(detail) => raise OcrFailed(detail)
    error => raise OcrFailed(error.to_string())
  }
}
