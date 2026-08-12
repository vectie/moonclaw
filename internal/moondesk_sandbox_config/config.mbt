///|
const MaxMoonDeskSandboxConfigBytes : Int = 65_536

///|
const MoonDeskSandboxConfigEnv : String = "MOONDESK_EXECUTION_SANDBOX_CONFIG"

///|
pub(all) struct Config {
  protocol_version : Int
  instance_id : String
  auth_token : String
  workspace_id : String
  workspace_root : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
fn safe_hex(value : String, length : Int) -> Bool {
  value.length() == length &&
  value.all(character => {
    character.is_ascii_digit() || (character >= 'a' && character <= 'f')
  })
}

///|
fn safe_identifier(value : String) -> Bool {
  value.length() >= 1 &&
  value.length() <= 128 &&
  value.all(character => {
    character.is_ascii_alphabetic() ||
    character.is_ascii_digit() ||
    character == '-' ||
    character == '_'
  })
}

///|
fn control_root_from_environment(
  app_data_root : String,
  home : String,
) -> String {
  let app_root = if app_data_root.trim() != "" {
    @pathx.normalize(app_data_root)
  } else if home.trim() != "" {
    @pathx.join(
      @pathx.normalize(home),
      "Library/Application Support/app.vectie.moondesk",
    )
  } else {
    ""
  }
  if app_root == "" {
    ""
  } else {
    @pathx.join(app_root, "control/execution-sandbox")
  }
}

///|
async fn read_bounded_file(path : String) -> String {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  guard file.kind() is Regular else { fail("sandbox config is not regular") }
  let initial_size = file.size()
  guard initial_size >= 0L &&
    initial_size <= MaxMoonDeskSandboxConfigBytes.to_int64() else {
    fail("sandbox config exceeds the size limit")
  }
  let output = @buffer.Buffer(size_hint=initial_size.to_int().min(8_192))
  for ;; {
    guard file.read_some(
        max_len=(MaxMoonDeskSandboxConfigBytes - output.length() + 1).min(8_192),
      )
      is Some(chunk) else {
      break
    }
    guard output.length() + chunk.length() <= MaxMoonDeskSandboxConfigBytes else {
      fail("sandbox config exceeds the size limit")
    }
    output.write_bytes(chunk)
  }
  guard file.size() == initial_size else {
    fail("sandbox config changed while it was read")
  }
  @utf8.decode(output.to_bytes())
}

///|
async fn load_from_path(path : String, control_root : String) -> Config {
  guard control_root != "" &&
    @pathx.dirname(path).to_owned() == control_root &&
    @fs.kind(control_root, follow_symlink=false) is Directory &&
    @fs.realpath(control_root) == control_root &&
    @fs.kind(path, follow_symlink=false) is Regular &&
    @fs.realpath(path) == path else {
    fail("MoonDesk sandbox config must be a canonical private control file")
  }
  // The target is exact and already proven to be below the private app-support
  // control root, so tightening its permissions cannot affect workspace data.
  @fs.chmod(control_root, 0o700)
  @fs.chmod(path, 0o600)
  let config : Config = @json.from_json(@json.parse(read_bounded_file(path))) catch {
    _ => fail("MoonDesk sandbox config is malformed")
  }
  guard config.protocol_version == 1 &&
    safe_hex(config.instance_id, 32) &&
    safe_hex(config.auth_token, 64) &&
    safe_identifier(config.workspace_id) &&
    config.workspace_root.has_prefix("/") &&
    @fs.kind(config.workspace_root, follow_symlink=false) is Directory &&
    @fs.realpath(config.workspace_root) == config.workspace_root else {
    fail("MoonDesk sandbox config failed validation")
  }
  config
}

///|
pub async fn load() -> Config? {
  let configured = @os.getenv(MoonDeskSandboxConfigEnv) catch {
    _ => fail("MoonDesk sandbox config environment is unavailable")
  }
  guard configured is Some(raw_path) else { return None }
  let path = raw_path.trim().to_owned()
  guard path.has_prefix("/") else {
    fail("MoonDesk sandbox config path must be absolute")
  }
  let app_data_root = @os.getenv("LEPUSA_APP_DATA_DIR").unwrap_or("") catch {
    _ => ""
  }
  let home = @os.getenv("HOME").unwrap_or("") catch { _ => "" }
  Some(load_from_path(path, control_root_from_environment(app_data_root, home)))
}
