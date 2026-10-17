///|
/// Fixed read-only capability. No executable, argument, or path is accepted
/// from a run request. Only the original signed receipt protocol reaches Fort.
pub struct CommandOutputClient {
  path : String
  config_path : String
  receipt_root : String
}

///|
pub async fn CommandOutputClient::new(
  path : String,
  config_path : String,
  receipt_root : String,
) -> CommandOutputClient {
  validate_regular_file(path, "command output reader")
  validate_regular_file(config_path, "executor config")
  guard canonical_absolute_path(receipt_root) &&
    @fsx.resolve(receipt_root) == receipt_root else {
    fail("MoonFort receipt root must be canonical and absolute")
  }
  { path, config_path, receipt_root, }
}

///|
pub async fn CommandOutputClient::inspect(
  self : CommandOutputClient,
  request : String,
) -> ProcessResponse {
  guard @encoding/utf8.encode(request).length() <= 65_536 else {
    fail("Output request exceeds its bound")
  }
  run_adapter_process(
    self.path,
    [],
    stdin=request,
    timeout=10_000,
    cwd=self.receipt_root,
    env={ "MOONFORT_EXECUTOR_CONFIG": self.config_path },
    stdout_limit=65_536,
  )
}

///|
pub async fn CommandOutputClient::export(
  self : CommandOutputClient,
  request : String,
  max_bytes : Int32,
) -> Bytes {
  guard @encoding/utf8.encode(request).length() <= 65_536 &&
    max_bytes >= 0 &&
    max_bytes <= 64 * 1024 * 1024 else {
    fail("Output export exceeds its bound")
  }
  let result = run_adapter_process_bytes(
    self.path,
    ["--export"],
    stdin=request,
    timeout=60_000,
    cwd=self.receipt_root,
    env={ "MOONFORT_EXECUTOR_CONFIG": self.config_path },
    stdout_limit=max_bytes.max(1),
  )
  guard result.status == 0 else {
    fail(
      "Retained output became unavailable during export; retry without rerunning",
    )
  }
  result.stdout
}
