///|
/// Versioned command configuration stored in a pack workflow tool step.
///
/// Both paths are relative to the verified installed pack root. `arguments`
/// are passed directly without a shell. `timeout_ms` may lower, but never
/// raise, the host timeout.
pub(all) struct PackToolCommandConfig {
  contract : String
  executable : String
  input : String
  arguments : Array[String]
  timeout_ms : Int?
} derive(Debug, ToJson, FromJson)

///|
/// Stdin contract sent to an installed pack tool command.
pub(all) struct PackToolCommandInvocation {
  contract : String
  pack_id : String
  run_id : String
  tool_id : String
  input : Json
} derive(Debug, ToJson, FromJson)

///|
/// Stdout contract accepted from an installed pack tool command.
///
/// Identity fields are optional for small commands, but when present they must
/// match the invocation. A successful result may expose `output`; otherwise
/// the complete result object becomes the workflow step output.
pub(all) struct PackToolCommandResult {
  contract : String
  pack_id : String?
  run_id : String?
  tool_id : String?
  ok : Bool?
  output : Json?
  error : String?
  summary : String?
  metrics : Json?
  logs : Array[String]?
} derive(Debug, ToJson, FromJson)

///|
fn require_installed_artifact(
  installed : InstalledPackWorkflow,
  path : String,
  purpose : String,
) -> Result[String, String] {
  if !@pack.safe_artifact_path(path) {
    return Err("unsafe pack tool command \{purpose} path: \{path}")
  }
  if !installed.receipt.artifacts.any(artifact => artifact.path == path) {
    return Err(
      "pack tool command \{purpose} is not a verified installed artifact: \{path}",
    )
  }
  Ok(@pathx.join(installed.pointer.installed_root, path))
}

///|
fn command_timeout(
  config : PackToolCommandConfig,
  max_timeout_ms : Int,
) -> Result[Int, String] {
  if max_timeout_ms <= 0 {
    return Err("pack tool command host timeout must be positive")
  }
  match config.timeout_ms {
    Some(timeout_ms) if timeout_ms <= 0 =>
      Err("pack tool command timeout must be positive")
    Some(timeout_ms) => Ok(timeout_ms.min(max_timeout_ms))
    None => Ok(max_timeout_ms)
  }
}

///|
fn command_result_error(
  result : PackToolCommandResult,
  request : PackToolExecutionRequest,
) -> String? {
  if result.contract != "moonsuite.pack-tool-result.v1" {
    return Some("unsupported pack tool command result contract")
  }
  if result.pack_id is Some(pack_id) && pack_id != request.binding.pack_id {
    return Some("pack tool command result pack_id does not match invocation")
  }
  if result.run_id is Some(run_id) && run_id != request.run_id {
    return Some("pack tool command result run_id does not match invocation")
  }
  if result.tool_id is Some(tool_id) && tool_id != request.binding.tool_id {
    return Some("pack tool command result tool_id does not match invocation")
  }
  match result.ok {
    Some(false) =>
      Some(result.error.unwrap_or("pack tool command reported failure"))
    _ => None
  }
}

///|
async fn execute_installed_pack_command(
  installed : InstalledPackWorkflow,
  max_timeout_ms : Int,
  request : PackToolExecutionRequest,
) -> Result[PackToolExecutionResult, String] {
  let config : PackToolCommandConfig = @json.from_json(request.config) catch {
    error => return Err("invalid pack tool command config: \{error}")
  }
  if config.contract != "moonsuite.pack-tool-command.v1" {
    return Err("unsupported pack tool command config contract")
  }
  let executable = match
    require_installed_artifact(installed, config.executable, "executable") {
    Ok(path) => path
    Err(error) => return Err(error)
  }
  let input_path = match
    require_installed_artifact(installed, config.input, "input") {
    Ok(path) => path
    Err(error) => return Err(error)
  }
  let input = @json.parse(@fsx.read_file(input_path)) catch {
    error => return Err("invalid pack tool command input JSON: \{error}")
  }
  let timeout = match command_timeout(config, max_timeout_ms) {
    Ok(timeout) => timeout
    Err(error) => return Err(error)
  }
  let invocation : PackToolCommandInvocation = {
    contract: "moonsuite.pack-tool-invocation.v1",
    pack_id: request.binding.pack_id,
    run_id: request.run_id,
    tool_id: request.binding.tool_id,
    input,
  }
  @fs.chmod(executable, 0o500) catch {
    error =>
      return Err(
        "failed to make verified pack tool command executable: \{error}",
      )
  }
  let process = @spawn.spawn(
    executable,
    config.arguments.map(argument => argument[:]),
    stdin=invocation.to_json().stringify() + "\n",
    timeout~,
    cwd=installed.pointer.installed_root,
  ) catch {
    error => return Err("failed to execute pack tool command: \{error}")
  }
  if process.status != 0 {
    let detail = if !process.stderr.trim().is_blank() {
      process.stderr.trim().to_owned()
    } else if !process.stdout.trim().is_blank() {
      process.stdout.trim().to_owned()
    } else {
      "exit status \{process.status}"
    }
    return Err("pack tool command failed: " + detail)
  }
  let result_json = @json.parse(process.stdout.trim().to_owned()) catch {
    error => return Err("invalid pack tool command result JSON: \{error}")
  }
  let result : PackToolCommandResult = @json.from_json(result_json) catch {
    error => return Err("invalid pack tool command result: \{error}")
  }
  match command_result_error(result, request) {
    Some(error) => return Err(error)
    None => ()
  }
  let logs = result.logs.unwrap_or([])
  if !process.stderr.trim().is_blank() {
    logs.push(process.stderr.trim().to_owned())
  }
  Ok(
    PackToolExecutionResult::new(
      output=result.output.unwrap_or(result_json),
      summary=result.summary,
      metrics=result.metrics.unwrap_or({}),
      logs~,
    ),
  )
}

///|
/// Build a generic executor for verified commands declared by an installed
/// pack workflow.
pub fn installed_pack_command_executor(
  installed : InstalledPackWorkflow,
  max_timeout_ms~ : Int,
) -> PackToolExecutor {
  PackToolExecutor::new(run=request => {
    execute_installed_pack_command(installed, max_timeout_ms, request)
  })
}
