///|
async test "extract_text_from_pdf reports missing local tools" {
  @fsx.with_temporary_directory("pdf-ocr-missing-tools-XXXXXX", async fn(dir) {
    let saved_path = dir + "/brief.pdf"
    let extracted_path = dir + "/brief.extracted.txt"
    @fsx.write_bytes_to_file(saved_path, @encoding/utf8.encode("pdf")) catch {
      _ => ()
    }
    let (text_path, note) = extract_text_from_pdf(
      saved_path,
      extracted_path,
      dir,
      fn(_command, _args, _cwd) { Err("missing tool") },
    )
    inspect(text_path is None, content="true")
    inspect(
      note
      .unwrap_or("")
      .contains("install pdftotext, Python+pypdf, or pdftoppm+tesseract"),
      content="true",
    )
  })
}

///|
async test "default PDF OCR process route fails closed" {
  let result = run_process("pdftotext", ["input.pdf", "output.txt"])
  guard result is Err(message) else {
    fail("expected ExecutionSandbox refusal")
  }
  assert_true(message.contains("ExecutionSandbox"))
}

///|
async test "extract_text_from_pdf uses pdftotext output when available" {
  @fsx.with_temporary_directory("pdf-ocr-pdftotext-XXXXXX", async fn(dir) {
    let saved_path = dir + "/brief.pdf"
    let extracted_path = dir + "/brief.extracted.txt"
    @fsx.write_bytes_to_file(saved_path, @encoding/utf8.encode("pdf")) catch {
      _ => ()
    }
    let (text_path, note) = extract_text_from_pdf(
      saved_path,
      extracted_path,
      dir,
      async fn(command, _args, _cwd) {
        if command == "pdftotext" {
          @fsx.write_to_file(extracted_path, "converted text") catch {
            _ => ()
          }
          Ok(PdfOcrProcess::{ status: 0 })
        } else {
          Err("unexpected command")
        }
      },
    )
    inspect(text_path.unwrap_or(""), content=extracted_path)
    inspect(note.unwrap_or(""), content="Extracted text with pdftotext")
  })
}

///|
async test "extract_text_from_pdf uses pypdf when pdftotext is unavailable" {
  @fsx.with_temporary_directory("pdf-ocr-pypdf-XXXXXX", async fn(dir) {
    let saved_path = dir + "/brief.pdf"
    let extracted_path = dir + "/brief.extracted.txt"
    @fsx.write_bytes_to_file(saved_path, @encoding/utf8.encode("pdf")) catch {
      _ => ()
    }
    let (text_path, note) = extract_text_from_pdf(
      saved_path,
      extracted_path,
      dir,
      async fn(command, _args, _cwd) {
        if command == "pdftotext" {
          Err("pdftotext unavailable")
        } else if command == "python3" {
          @fsx.write_to_file(extracted_path, "converted with pypdf") catch {
            _ => ()
          }
          Ok(PdfOcrProcess::{ status: 0 })
        } else {
          Err("unexpected command")
        }
      },
    )
    inspect(text_path.unwrap_or(""), content=extracted_path)
    inspect(note.unwrap_or(""), content="Extracted text with pypdf")
  })
}
