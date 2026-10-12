///|
/// Operator-configured read-only executable. Request data never selects a
/// program, argument, working directory, registry, or workspace path.
pub struct RecoveryInspectionClient {
  path : String
  arguments : Array[String]
  config_path : String
  receipt_root : String
}

///|
pub async fn RecoveryInspectionClient::new(
  path : String,
  arguments : Array[String],
  config_path : String,
  receipt_root : String,
) -> RecoveryInspectionClient {
  validate_regular_file(path, "recovery inspector")
  validate_regular_file(config_path, "executor config")
  guard arguments.length() <= 16 &&
    arguments.all(argument => {
      !argument.contains("\u{0}") && argument.length() <= 4_096
    }) &&
    canonical_absolute_path(receipt_root) &&
    @fsx.resolve(receipt_root) == receipt_root else {
    fail("MoonFort recovery inspector configuration is invalid")
  }
  { path, arguments: arguments.copy(), config_path, receipt_root, }
}

///|
pub async fn RecoveryInspectionClient::inspect(
  self : RecoveryInspectionClient,
  request : String,
) -> ProcessResponse {
  guard @encoding/utf8.encode(request).length() <= 4_096 else {
    fail("Recovery inspection request exceeds its bound")
  }
  run_adapter_process(
    self.path,
    self.arguments,
    stdin=request,
    timeout=10_000,
    cwd=self.receipt_root,
    env={ "MOONFORT_EXECUTOR_CONFIG": self.config_path },
    stdout_limit=16_384,
  )
}
