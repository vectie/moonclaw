///|
fn fake_process(
  exec : String,
  args : Array[String],
  stdout? : String = "",
  stderr? : String = "",
  status? : Int = 0,
) -> CommandResult {
  {
    command: exec,
    arguments: args,
    status,
    stdout,
    stderr,
    elapsed_ms: 1,
    timeout_ms: None,
  }
}

///|
async test "convert_pdf_to_markdown rasterizes pages and renders markdown" {
  @fsx.with_temporary_directory("moonclaw-pdf-ocr-test-XXXXXX", async fn(
    tmpdir,
  ) {
    let pdf_path = @pathx.join(tmpdir, "parcel-brief.pdf")
    @fsx.write_to_file(pdf_path, "fake pdf bytes")
    let calls : Array[String] = []
    let executor = CommandExecutor::new(run=async fn(request) {
      let joined_arguments = request.arguments.join(" ")
      calls.push("\{request.command} \{joined_arguments}")
      match request.command {
        "pdftoppm" => {
          let prefix = request.arguments.last().unwrap()
          @fsx.write_to_file("\{prefix}-2.png", "fake page 2")
          @fsx.write_to_file("\{prefix}-1.png", "fake page 1")
          Ok(fake_process(request.command, request.arguments))
        }
        "tesseract" => {
          let image = request.arguments[0]
          if image.has_suffix("page-1.png") {
            Ok(
              fake_process(
                request.command,
                request.arguments,
                stdout="Executive Summary\n\n- parcel located near transit\n- seller motivated",
              ),
            )
          } else {
            Ok(
              fake_process(
                request.command,
                request.arguments,
                stdout="Risk review\n\nComparable evidence remains limited.",
              ),
            )
          }
        }
        _ => Err("unexpected command")
      }
    })
    let document = convert_pdf_to_markdown(
      pdf_path,
      executor~,
      options=OcrMarkdownOptions::new(language=Some("eng")),
    )
    inspect(document.title, content="parcel-brief")
    inspect(document.pages.length(), content="2")
    inspect(document.pages[0].page_number, content="1")
    inspect(document.pages[1].page_number, content="2")
    inspect(document.markdown.contains("# parcel-brief"), content="true")
    inspect(document.markdown.contains("## Page 1"), content="true")
    inspect(document.markdown.contains("### Executive Summary"), content="true")
    inspect(
      document.markdown.contains("- parcel located near transit"),
      content="true",
    )
    inspect(document.markdown.contains("## Page 2"), content="true")
    inspect(document.markdown.contains("Risk review"), content="true")
    inspect(calls.length(), content="3")
    inspect(calls[0].has_prefix("pdftoppm "), content="true")
    inspect(calls[1].has_prefix("tesseract "), content="true")
    inspect(calls[2].has_prefix("tesseract "), content="true")
  })
}

///|
async test "convert_pdf_to_markdown raises when rasterization yields no pages" {
  @fsx.with_temporary_directory("moonclaw-pdf-ocr-test-XXXXXX", async fn(
    tmpdir,
  ) {
    let pdf_path = @pathx.join(tmpdir, "empty.pdf")
    @fsx.write_to_file(pdf_path, "fake pdf bytes")
    let executor = CommandExecutor::new(run=fn(request) {
      Ok(fake_process(request.command, request.arguments))
    })
    let result = try {
      ignore(convert_pdf_to_markdown(pdf_path, executor~))
      "completed"
    } catch {
      NoPagesGenerated(path) => "no-pages:\{path}"
      error => "unexpected:\{error}"
    }
    inspect(result, content="no-pages:\{pdf_path}")
  })
}

///|
async test "convert_pdf_to_markdown raises when input file is missing" {
  let result = try {
    ignore(convert_pdf_to_markdown("/tmp/does-not-exist.pdf"))
    "completed"
  } catch {
    FileNotFound(path) => "missing:\{path}"
    error => "unexpected:\{error}"
  }
  inspect(result, content="missing:/tmp/does-not-exist.pdf")
}

///|
async test "default PDF markdown OCR route fails closed" {
  @fsx.with_temporary_directory("moonclaw-pdf-ocr-test-XXXXXX", async fn(
    tmpdir,
  ) {
    let pdf_path = @pathx.join(tmpdir, "sandbox-required.pdf")
    @fsx.write_to_file(pdf_path, "fake pdf bytes")
    let result = try {
      ignore(convert_pdf_to_markdown(pdf_path))
      "completed"
    } catch {
      RasterizationFailed(detail) => detail
      error => "unexpected:\{error}"
    }
    assert_true(result.contains("ExecutionSandbox"))
  })
}
