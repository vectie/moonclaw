///|
pub(all) struct RecoveryInspectionConfig {
  protocol_version : Int
  inspector_path : String
  inspector_args : Array[String]
  executor_config_path : String
  receipt_root : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
/// Independently configured by the trusted operator, never by a host request.
pub async fn load_recovery_inspection_config() -> RecoveryInspectionConfig? {
  let configured = @os.getenv("MOONCLAW_MOONFORT_RECOVERY_CONFIG") catch {
    _ => fail("MoonFort recovery configuration environment is unavailable")
  }
  guard configured is Some(path) else { return None }
  let config : RecoveryInspectionConfig = @json.from_json(
    @json.parse(
      read_bounded_canonical_file(path, MaxSandboxExecutorConfigBytes),
    ),
  ) catch {
    _ => fail("MoonFort recovery configuration is unavailable")
  }
  guard config.protocol_version == 1 &&
    config.inspector_path.has_prefix("/") &&
    config.executor_config_path.has_prefix("/") &&
    config.receipt_root.has_prefix("/") &&
    config.inspector_args.length() <= 16 &&
    config.inspector_args.all(argument => {
      !argument.contains("\u{0}") && argument.length() <= 4_096
    }) else {
    fail("MoonFort recovery configuration failed validation")
  }
  Some(config)
}
