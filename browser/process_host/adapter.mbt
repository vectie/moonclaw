///|
pub struct ProcessBrowserHost {
  executable : String
  arguments : Array[String]
  cwd : String?
}

///|
pub fn ProcessBrowserHost::new(
  executable~ : String,
  arguments? : Array[String] = [],
  cwd? : String,
) -> ProcessBrowserHost {
  { executable, arguments, cwd }
}

///|
pub async fn ProcessBrowserHost::execute(
  self : ProcessBrowserHost,
  command : @browser.BrowserHostCommand,
  timeout_ms? : Int = 30000,
) -> Result[@browser.BrowserHostResult, String] {
  let input = command.to_json().stringify() + "\n"
  let args = self.arguments.map(value => value[:])
  let process = @spawn.spawn(
    self.executable,
    args,
    stdin=input,
    timeout=timeout_ms,
    cwd?=self.cwd.map(value => value[:]),
  ) catch {
    error => return Err("browser host process failed: " + error.to_string())
  }
  if process.status != 0 {
    return Err(
      "browser host exited with status " +
      process.status.to_string() +
      (if process.stderr == "" {
        ""
      } else {
        ": " + process.stderr.trim().to_owned()
      }),
    )
  }
  let json : Json = @json.parse(process.stdout.trim()) catch {
    error => return Err("browser host returned invalid JSON: " + error.to_string())
  }
  let result : @browser.BrowserHostResult = @json.from_json(json) catch {
    error => return Err("browser host returned invalid result: " + error.to_string())
  }
  Ok(result)
}
