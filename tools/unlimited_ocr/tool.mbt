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
fn json_string_arg(args : Json, name : String) -> String? {
  match args {
    Object(fields) =>
      match fields.get(name) {
        Some(String(value)) if !value.trim().is_empty() => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
fn json_number_arg(args : Json, name : String) -> Int? {
  match args {
    Object(fields) =>
      match fields.get(name) {
        Some(Number(value, ..)) => Some(value.to_int())
        _ => None
      }
    _ => None
  }
}

///|
fn json_string_array_arg(args : Json, name : String) -> Array[String] {
  let result : Array[String] = []
  match args {
    Object(fields) =>
      match fields.get(name) {
        Some(Array(values)) =>
          for value in values {
            match value {
              String(text) if !text.trim().is_empty() => result.push(text)
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  result
}

///|
fn resolve_path(cwd : String, path : String) -> String {
  if @pathx.is_absolute(path) {
    path
  } else {
    @pathx.join(cwd, path)
  }
}

///|
fn env_unlimited_ocr_root() -> String? {
  @os.getenv("UNLIMITED_OCR_ROOT") catch {
    _ => None
  }
}

///|
fn infer_script_from_args(cwd : String, args : Json) -> String? {
  match json_string_arg(args, "infer_script") {
    Some(path) => Some(resolve_path(cwd, path))
    None => {
      let root = match json_string_arg(args, "unlimited_ocr_root") {
        Some(root) => Some(root)
        None => env_unlimited_ocr_root()
      }
      root.map(root => @pathx.join(resolve_path(cwd, root), "infer.py"))
    }
  }
}

///|
fn shell_quote(value : String) -> String {
  "'" + value.replace(old="'", new="'\\''").to_string() + "'"
}

///|
fn render_command(program : String, argv : Array[String]) -> String {
  let parts = [shell_quote(program)]
  for arg in argv {
    parts.push(shell_quote(arg))
  }
  parts.join(" ")
}

///|
pub fn new(cwd : String) -> @tool.Tool[UnlimitedOcrResult] {
  @tool.new(
    name="unlimited_ocr",
    description="Run Unlimited-OCR as MoonClaw's default PDF OCR extractor. It renders/scans PDFs through Unlimited-OCR's infer.py entrypoint and writes extracted artifacts to the requested output directory.",
    schema~,
    ToolFn(async fn(args) -> @tool.ToolResult[UnlimitedOcrResult] noraise {
      let pdf_path = match json_string_arg(args, "pdf_path") {
        Some(path) => resolve_path(cwd, path)
        None => return @tool.error("Error: 'pdf_path' parameter is required")
      }
      guard (@fsx.exists_as_file(pdf_path) catch { _ => false }) else {
        return @tool.error("PDF not found: \{pdf_path}")
      }
      let output_dir = resolve_path(
        cwd,
        json_string_arg(args, "output_dir").unwrap_or("raw/extracted"),
      )
      @fsx.make_directory(output_dir, recursive=true, exists_ok=true) catch {
        error =>
          return @tool.error(
            "Could not create output directory '\{output_dir}': \{error}",
            error~,
          )
      }
      let infer_script = match infer_script_from_args(cwd, args) {
        Some(path) => path
        None =>
          return @tool.error(
            "Unlimited-OCR is not configured. Set UNLIMITED_OCR_ROOT, pass unlimited_ocr_root, or pass infer_script.",
          )
      }
      guard (@fsx.exists_as_file(infer_script) catch { _ => false }) else {
        return @tool.error("Unlimited-OCR infer.py not found: \{infer_script}")
      }
      let python = json_string_arg(args, "python").unwrap_or("python3")
      let timeout = json_number_arg(args, "timeout_ms").unwrap_or(1_800_000)
      if timeout <= 0 {
        return @tool.error("'timeout_ms' must be a positive integer")
      }
      let argv = [infer_script, "--pdf", pdf_path, "--output_dir", output_dir]
      argv.append(json_string_array_arg(args, "extra_args"))
      let command = render_command(python, argv)
      let spawn_args = argv.map(fn(arg) { arg[:] })
      let process = @spawn.spawn(python[:], spawn_args, timeout~) catch {
        @spawn.TimedOut(timeout~, stdout~, stderr~) =>
          return @tool.error(
            "Unlimited-OCR timed out after \{timeout} ms.\nSTDOUT:\n\{stdout}\nSTDERR:\n\{stderr}",
          )
        error =>
          return @tool.error(
            "Failed to run Unlimited-OCR command \{command}: \{error}",
            error~,
          )
      }
      if process.status != 0 {
        return @tool.error(
          "Unlimited-OCR exited with status \{process.status}.\nCommand: \{command}\nSTDOUT:\n\{process.stdout}\nSTDERR:\n\{process.stderr}",
        )
      }
      @tool.ok({
        ocr_engine: "unlimited-ocr",
        pdf_path,
        output_dir,
        infer_script,
        command,
        status: process.status,
        stdout: process.stdout,
        stderr: process.stderr,
      })
    }),
  )
}
