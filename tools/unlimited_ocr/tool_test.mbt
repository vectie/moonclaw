///|
async test "unlimited_ocr fails closed without ExecutionSandbox" {
  let result = new("/").call({ "pdf_path": "sample.pdf" })
  match result {
    Ok(_) => fail("expected ExecutionSandbox refusal")
    Error(_, message) => assert_true(message.contains("ExecutionSandbox"))
  }
}
