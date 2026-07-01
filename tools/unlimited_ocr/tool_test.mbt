///|
async test "unlimited_ocr requires configured infer script" {
  @fsx.with_temporary_directory("moonclaw-unlimited-ocr-test-XXXXXX", dir => {
    let pdf_path = @pathx.join(dir, "sample.pdf")
    @fsx.write_to_file(pdf_path, "%PDF-1.7\n")
    let tool = new(dir)
    let result = tool.call({ "pdf_path": "sample.pdf" })
    match result {
      Ok(_) => fail("expected missing configuration error")
      Error(_, message) =>
        assert_true(message.contains("Unlimited-OCR is not configured"))
    }
  })
}

///|
async test "unlimited_ocr invokes infer script and reports metadata" {
  @fsx.with_temporary_directory("moonclaw-unlimited-ocr-test-XXXXXX", dir => {
    let pdf_path = @pathx.join(dir, "sample.pdf")
    let script_path = @pathx.join(dir, "infer.py")
    @fsx.write_to_file(pdf_path, "%PDF-1.7\n")
    @fsx.write_to_file(script_path, "#!/bin/sh\nprintf 'ocr ok %s\\n' \"$*\"\n")
    let tool = new(dir)
    let result = tool.call({
      "pdf_path": "sample.pdf",
      "output_dir": "raw/extracted",
      "infer_script": "infer.py",
      "python": "/bin/sh",
      "timeout_ms": 5000,
      "extra_args": ["--mock-mode"],
    })
    match result {
      Ok(output) => {
        assert_eq(output.ocr_engine, "unlimited-ocr")
        assert_true(output.pdf_path.has_suffix("/sample.pdf"))
        assert_true(output.output_dir.has_suffix("/raw/extracted"))
        assert_true(output.infer_script.has_suffix("/infer.py"))
        assert_true(output.command.contains("--mock-mode"))
        assert_true(output.stdout.contains("ocr ok"))
      }
      Error(_, message) => fail("unexpected tool error: \{message}")
    }
  })
}
