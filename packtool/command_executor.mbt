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
fn validate_installed_pack_command(
  installed : InstalledPackWorkflow,
  max_timeout_ms : Int,
  request : PackToolExecutionRequest,
) -> Result[Unit, String] {
  let config : PackToolCommandConfig = @json.from_json(request.config) catch {
    error => return Err("invalid pack tool command config: \{error}")
  }
  if config.contract != "moonsuite.pack-tool-command.v1" {
    return Err("unsupported pack tool command config contract")
  }
  ignore(
    match
      require_installed_artifact(installed, config.executable, "executable") {
      Ok(path) => path
      Err(error) => return Err(error)
    },
  )
  ignore(
    match require_installed_artifact(installed, config.input, "input") {
      Ok(path) => path
      Err(error) => return Err(error)
    },
  )
  ignore(
    match command_timeout(config, max_timeout_ms) {
      Ok(timeout) => timeout
      Err(error) => return Err(error)
    },
  )
  Ok(())
}

///|
/// Build a generic executor for verified commands declared by an installed
/// pack workflow.
pub fn installed_pack_command_executor(
  installed : InstalledPackWorkflow,
  max_timeout_ms~ : Int,
) -> PackToolExecutor {
  PackToolExecutor::new(run=request => {
    match validate_installed_pack_command(installed, max_timeout_ms, request) {
      Err(error) => Err(error)
      Ok(_) =>
        Err(
          "installed pack native execution requires an explicit sandbox adapter",
        )
    }
  })
}
