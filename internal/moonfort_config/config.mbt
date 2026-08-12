///|
const MaxSandboxExecutorConfigBytes : Int = 1_048_576

///|
const SandboxExecutorConfigEnv : String = "MOONCLAW_MOONFORT_CONFIG"

///|
const MoonFortPromotionConfigEnv : String = "MOONCLAW_MOONFORT_PROMOTION_CONFIG"

///|
pub(all) struct PromotionAdapterConfig {
  protocol_version : Int
  promotion_path : String
  promotion_args : Array[String]
  executor_config_path : String
  receipt_root : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
async fn read_bounded_canonical_file(path : String, limit : Int) -> String {
  guard path.has_prefix("/") && limit > 0 else {
    fail("MoonFort configuration path must be absolute")
  }
  guard @fs.kind(path, follow_symlink=false) is Regular &&
    @fs.realpath(path) == path else {
    fail("MoonFort configuration file is unavailable")
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  guard file.kind() is Regular else {
    fail("MoonFort configuration file is unavailable")
  }
  let initial_size = file.size()
  guard initial_size >= 0L && initial_size <= limit.to_int64() else {
    fail("MoonFort configuration file exceeds the size limit")
  }
  let output = @buffer.Buffer(size_hint=initial_size.to_int().min(8_192))
  for ;; {
    guard file.read_some(max_len=(limit - output.length() + 1).min(8_192))
      is Some(chunk) else {
      break
    }
    guard output.length() + chunk.length() <= limit else {
      fail("MoonFort configuration file exceeds the size limit")
    }
    output.write_bytes(chunk)
  }
  guard file.size() == initial_size &&
    @fs.kind(path, follow_symlink=false) is Regular &&
    @fs.realpath(path) == path else {
    fail("MoonFort configuration file changed during loading")
  }
  @utf8.decode(output.to_bytes())
}

///|
fn parse_sandbox_executor_config(
  text : String,
) -> @execution_sandbox.SandboxExecutorConfig raise {
  @json.from_json(@json.parse(text)) catch {
    _ => fail("MoonFort configuration is malformed")
  }
}

///|
/// Loads the operator-owned MoonFort launcher configuration. Absence disables
/// host command execution; a present but invalid configuration is a startup
/// error. The file contents are intentionally omitted from every error.
pub async fn load_sandbox_executor_config() -> @execution_sandbox.SandboxExecutorConfig? {
  let configured = @os.getenv(SandboxExecutorConfigEnv) catch {
    _ => fail("MoonFort configuration environment is unavailable")
  }
  guard configured is Some(raw_path) else { return None }
  let path = raw_path.trim().to_owned()
  guard !path.is_blank() else { fail("MoonFort configuration path is empty") }
  Some(
    parse_sandbox_executor_config(
      read_bounded_canonical_file(path, MaxSandboxExecutorConfigBytes),
    ),
  )
}

///|
/// Loads the independently operator-owned promotion launcher. Keeping this
/// separate from MoonDesk's request/config prevents UI input from selecting a
/// host executable, arguments, executor policy file, or working directory.
pub async fn load_promotion_adapter_config() -> PromotionAdapterConfig? {
  let configured = @os.getenv(MoonFortPromotionConfigEnv) catch {
    _ => fail("MoonFort promotion configuration environment is unavailable")
  }
  guard configured is Some(raw_path) else { return None }
  let path = raw_path.trim().to_owned()
  guard !path.is_blank() else {
    fail("MoonFort promotion configuration path is empty")
  }
  let config : PromotionAdapterConfig = @json.from_json(
    @json.parse(
      read_bounded_canonical_file(path, MaxSandboxExecutorConfigBytes),
    ),
  ) catch {
    _ => fail("MoonFort promotion configuration is malformed")
  }
  guard config.protocol_version == 1 &&
    config.promotion_path.has_prefix("/") &&
    config.executor_config_path.has_prefix("/") &&
    config.receipt_root.has_prefix("/") &&
    config.promotion_args.length() <= 16 &&
    config.promotion_args.all(argument => {
      !argument.contains("\u{0}") && argument.length() <= 4_096
    }) else {
    fail("MoonFort promotion configuration failed validation")
  }
  Some(config)
}
