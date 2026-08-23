///|
pub struct UnlimitedOcrResult {
  ocr_engine : String
  pdf_path : String
  output_dir : String
  infer_script : String
  command : String
  status : Int
  stdout : String
  stderr : String
} derive(ToJson, FromJson)

///|
pub impl Show for UnlimitedOcrResult with fn output(
  result : UnlimitedOcrResult,
  logger : &Logger,
) -> Unit {
  let lines = [
    "OCR engine: \{result.ocr_engine}",
    "PDF: \{result.pdf_path}",
    "Output dir: \{result.output_dir}",
    "Infer script: \{result.infer_script}",
    "Status: \{result.status}",
    "Command: \{result.command}",
  ]
  if !result.stdout.trim().is_empty() {
    lines.push("")
    lines.push("STDOUT:")
    lines.push(result.stdout)
  }
  if !result.stderr.trim().is_empty() {
    lines.push("")
    lines.push("STDERR:")
    lines.push(result.stderr)
  }
  logger.write_string(lines.join("\n"))
}

///|
pub fn new(cwd : String) -> @tool.Tool[UnlimitedOcrResult] {
  ignore(cwd)
  @tool.new(
    name="unlimited_ocr",
    description="Run Unlimited-OCR as MoonClaw's default PDF OCR extractor. It renders/scans PDFs through Unlimited-OCR's infer.py entrypoint and writes extracted artifacts to the requested output directory.",
    schema~,
    ToolFn(args => {
      ignore(args)
      @tool.error(
        "Unlimited-OCR native execution refused: no configured ExecutionSandbox route is available",
      )
    }),
  )
}
