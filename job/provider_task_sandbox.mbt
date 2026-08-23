///|
/// Test-owned sandbox deployments are keyed by their canonical provider
/// workspace. Production never installs entries here and therefore always
/// resolves through the operator-owned MoonFort configuration.
let provider_task_fixture_sandbox_configs : Map[
  String,
  @execution_sandbox.SandboxExecutorConfig,
] = Map([])

///|
let provider_task_fixture_sandbox_configs_lock : @semaphore.Semaphore = Semaphore(
  1,
)

///|
#warnings("-unused_value")
async fn install_provider_task_fixture_sandbox_config(
  workspace_root : String,
  config : @execution_sandbox.SandboxExecutorConfig,
) -> Unit {
  let canonical_root = @fsx.resolve(workspace_root)
  provider_task_fixture_sandbox_configs_lock.acquire()
  defer provider_task_fixture_sandbox_configs_lock.release()
  provider_task_fixture_sandbox_configs[canonical_root] = config
}

///|
async fn provider_task_fixture_sandbox_config(
  workspace_root : String,
) -> @execution_sandbox.SandboxExecutorConfig? {
  let canonical_root = @fsx.resolve(workspace_root) catch { _ => return None }
  provider_task_fixture_sandbox_configs_lock.acquire()
  defer provider_task_fixture_sandbox_configs_lock.release()
  provider_task_fixture_sandbox_configs.get(canonical_root)
}

///|
async fn provider_task_sandbox_config(
  command : ProviderTaskCommand,
  context : String,
) -> Result[@execution_sandbox.SandboxExecutorConfig, String] {
  match provider_task_fixture_sandbox_config(command.workspace_root) {
    Some(config) => return Ok(config)
    None => ()
  }
  let configured = @moonfort_config.load_sandbox_executor_config() catch {
    error =>
      return Err(
        "Provider task \{context} execution sandbox configuration failed: \{error}",
      )
  }
  match configured {
    Some(config) => Ok(config)
    None =>
      Err(
        "Provider task \{context} execution is disabled for target \{command.provider.name}: a MoonFort ExecutionSandbox grant is required",
      )
  }
}

///|
fn provider_task_execution_args(
  command : ProviderTaskCommand,
  subcommand : String,
  extra_args : Array[String],
) -> Array[String] {
  command.args +
  provider_metadata_string_array(command.provider.metadata, "task_args_prefix") +
  ["provider", "task", subcommand, command.workspace_root] +
  extra_args
}

///|
const ProviderTaskExecutionTimeoutMs : Int = 120_000

///|
async fn execute_provider_task_command(
  command : ProviderTaskCommand,
  subcommand : String,
  extra_args : Array[String],
  context : String,
) -> Result[String, String] {
  let config = match provider_task_sandbox_config(command, context) {
    Ok(config) => config
    Err(error) => return Err(error)
  }
  let working_directory = command.cwd.unwrap_or(command.workspace_root)
  let args = provider_task_execution_args(command, subcommand, extra_args)
  let execution = @execution_sandbox.run_exec(
    config,
    command.workspace_root,
    working_directory,
    command.provider.name,
    args,
    ProviderTaskExecutionTimeoutMs,
  ) catch {
    error =>
      return Err(
        "Provider task \{context} execution failed for target \{command.provider.name}: \{error}",
      )
  }
  let receipt = execution.receipt
  guard receipt.status is Exited && receipt.exit_code is Some(status) else {
    return Err(
      "Provider task \{context} did not return a terminal exit receipt for target \{command.provider.name}",
    )
  }
  guard status == 0 else {
    return Err(
      "Provider task \{context} exited with status \{status} for target \{command.provider.name}: \{receipt.output.trim().to_owned()}",
    )
  }
  guard !receipt.output_truncated else {
    return Err(
      "Provider task \{context} output exceeded the MoonFort response limit for target \{command.provider.name}",
    )
  }
  Ok(receipt.output)
}
