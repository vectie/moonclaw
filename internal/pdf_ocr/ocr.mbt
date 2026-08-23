///|
pub(all) struct PdfOcrProcess {
  status : Int
}

///|
#warnings("-unused_async")
pub async fn run_process(
  command : String,
  arguments : Array[String],
  cwd? : String? = None,
) -> Result[PdfOcrProcess, String] {
  ignore(command)
  ignore(arguments)
  ignore(cwd)
  Err(
    "native PDF extraction refused: no configured ExecutionSandbox route is available",
  )
}

///|
pub async fn extract_text_from_pdf(
  saved_path : String,
  extracted_text_path : String,
  scratch_dir : String,
  run_command : async (String, Array[String], String?) -> Result[
    PdfOcrProcess,
    String,
  ],
) -> (String?, String?) {
  let direct = run_command("pdftotext", [saved_path, extracted_text_path], None)
  match direct {
    Ok(process) if process.status == 0 &&
      (@fsx.exists(extracted_text_path) catch { _ => false }) =>
      return (Some(extracted_text_path), Some("Extracted text with pdftotext"))
    _ => ()
  }

  // pypdf is a deterministic text-layer extractor and is commonly available
  // in Python runtimes even when Poppler's pdftotext binary is absent. Keep
  // this as a fixed-purpose argv invocation; no user-authored shell is run.
  let pypdf_script = "from pypdf import PdfReader\nimport sys\nreader = PdfReader(sys.argv[1])\ntext = '\\n\\n'.join((page.extract_text() or '') for page in reader.pages)\nwith open(sys.argv[2], 'w', encoding='utf-8') as output:\n    output.write(text)\n"
  let pypdf = run_command(
    "python3",
    ["-c", pypdf_script, saved_path, extracted_text_path],
    None,
  )
  match pypdf {
    Ok(process) if process.status == 0 &&
      (@fsx.exists(extracted_text_path) catch { _ => false }) => {
      let text = @fsx.read_file(extracted_text_path) catch { _ => "" }
      if !text.trim().to_owned().is_blank() {
        return (Some(extracted_text_path), Some("Extracted text with pypdf"))
      }
    }
    _ => ()
  }

  let ppm_dir = scratch_dir + "/ocr-pages"
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
          "PDF remained binary: install pdftotext, Python+pypdf, or pdftoppm+tesseract to extract text",
        ),
      )
  }

  let pages = (@fsx.list_directory(ppm_dir) catch { _ => [] }).filter(fn(
    entry,
  ) {
    entry.kind is Regular && entry.name.has_suffix(".png")
  })
  if pages.is_empty() {
    return (
      None,
      Some("PDF OCR could not run because pdftoppm produced no page images"),
    )
  }
  let sections : Array[String] = []
  for page in pages {
    let output_base = page.path[:page.path.length() - 4].to_owned()
    let ocr = run_command("tesseract", [page.path, output_base], None)
    match ocr {
      Ok(process) if process.status == 0 => {
        let page_text_path = "\{output_base}.txt"
        let page_text_exists = @fsx.exists(page_text_path) catch { _ => false }
        if page_text_exists {
          let page_text = @fsx.read_file(page_text_path)
          if !page_text.trim().to_owned().is_blank() {
            sections.push("## \{page.name}")
            sections.push("")
            sections.push(page_text.trim_end().to_owned())
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
