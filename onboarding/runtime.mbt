///|
pub struct OnboardingStatus {
  home : String
  cwd : String
  config_path : String
  config_exists : Bool
  workspace_root : String
  workspace_configured_from : String
  workspace_files : Array[String]
  primary_model : String?
  provider_count : Int
  gateway_port : Int?
  has_gateway_token : Bool
  feishu_enabled : Bool
  feishu_ready : Bool
  plugin_count : Int
  issues : Array[String]
  next_steps : Array[String]
} derive(ToJson, FromJson, Show)

///|
pub struct OnboardingApplyResult {
  status : String
  config_path : String
  workspace_root : String
  created : Array[String]
  preserved : Array[String]
  onboarding : OnboardingStatus
} derive(ToJson, FromJson, Show)

///|
fn root_config_path(root : String) -> String {
  root |> @pathx.join("moonclaw.json")
}

///|
fn nested_config_path(root : String) -> String {
  root |> @pathx.join(".moonclaw") |> @pathx.join("moonclaw.json")
}

///|
fn config_candidates(home : String, cwd : String) -> Array[String] {
  [
    root_config_path(home),
    nested_config_path(home),
    root_config_path(cwd),
    nested_config_path(cwd),
  ]
}

///|
fn preferred_config_path(home : String) -> String {
  root_config_path(home)
}

///|
async fn load_config(home : String, cwd : String) -> (String, Json?) {
  for path in config_candidates(home, cwd) {
    let exists = @fsx.exists(path) catch { _ => false }
    if !exists {
      continue
    }
    let text = @fsx.read_file(path) catch { _ => continue }
    let json = @json.parse(text) catch { _ => continue }
    return (path, Some(json))
  }
  (preferred_config_path(home), None)
}

///|
fn json_string_field(value : Json, field : String) -> String? {
  match value {
    Object(obj) =>
      match obj.get(field) {
        Some(String(text)) if !text.trim().is_empty() =>
          Some(text.trim().to_string())
        _ => None
      }
    _ => None
  }
}

///|
fn json_bool_field(value : Json, field : String) -> Bool? {
  match value {
    Object(obj) =>
      match obj.get(field) {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
    _ => None
  }
}

///|
fn find_primary_model(json : Json?) -> String? {
  match json {
    Some(Object(root)) =>
      match root.get("agents") {
        Some(Object(agents)) =>
          match agents.get("defaults") {
            Some(Object(defaults)) =>
              match defaults.get("model") {
                Some(model) => json_string_field(model, "primary")
                _ => None
              }
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn provider_count(json : Json?) -> Int {
  match json {
    Some(Object(root)) =>
      match root.get("models") {
        Some(Object(models)) =>
          match models.get("providers") {
            Some(Object(providers)) => providers.length()
            _ => 0
          }
        _ => 0
      }
    _ => 0
  }
}

///|
fn gateway_port(json : Json?) -> Int? {
  match json {
    Some(Object(root)) =>
      match root.get("gateway") {
        Some(Object(gateway)) =>
          match gateway.get("port") {
            Some(Number(port, ..)) => Some(port.to_int())
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn has_gateway_token(json : Json?) -> Bool {
  match json {
    Some(Object(root)) =>
      match root.get("gateway") {
        Some(Object(gateway)) =>
          match gateway.get("auth") {
            Some(Object(auth)) =>
              match auth.get("token") {
                Some(String(token)) => !token.trim().is_empty()
                _ => false
              }
            _ => false
          }
        _ => false
      }
    _ => false
  }
}

///|
fn feishu_enabled(json : Json?) -> Bool {
  match json {
    Some(Object(root)) =>
      match root.get("channels") {
        Some(Object(channels)) =>
          match channels.get("feishu") {
            Some(feishu) => json_bool_field(feishu, "enabled").unwrap_or(true)
            _ => false
          }
        _ => false
      }
    _ => false
  }
}

///|
fn feishu_ready(json : Json?) -> Bool {
  match json {
    Some(Object(root)) =>
      match root.get("channels") {
        Some(Object(channels)) =>
          match channels.get("feishu") {
            Some(feishu) =>
              json_string_field(feishu, "appId") is Some(_) &&
              json_string_field(feishu, "appSecret") is Some(_)
            _ => false
          }
        _ => false
      }
    _ => false
  }
}

///|
fn generate_gateway_token() -> String {
  let bytes = @rand.bytes(24) catch { _ => return "token-\{@async.now()}" }
  @base64.encode(bytes)
}

///|
fn default_config(home : String) -> Json {
  let workspace_root = home |> @pathx.join("workspace")
  {
    "models": { "providers": {} },
    "agents": {
      "defaults": { "model": { "primary": "" }, "workspace": workspace_root },
    },
    "commands": {
      "native": "auto",
      "nativeSkills": "auto",
      "restart": true,
      "ownerDisplay": "raw",
    },
    "session": { "dmScope": "per-channel-peer" },
    "gateway": {
      "port": 18123,
      "auth": { "mode": "token", "token": generate_gateway_token() },
    },
    "plugins": { "entries": {} },
  }
}

///|
fn merge_missing(existing : Json, defaults : Json) -> Json {
  match (existing, defaults) {
    (Object(existing_obj), Object(default_obj)) => {
      let merged : Map[String, Json] = {}
      for key, value in default_obj {
        match existing_obj.get(key) {
          Some(existing_value) =>
            merged[key] = merge_missing(existing_value, value)
          None => merged[key] = value
        }
      }
      for key, value in existing_obj {
        if !merged.contains(key) {
          merged[key] = value
        }
      }
      Json::object(merged)
    }
    (existing, _) => existing
  }
}

///|
fn collect_preserved_keys(
  existing : Json,
  defaults : Json,
  path : String,
) -> Array[String] {
  match (existing, defaults) {
    (Object(existing_obj), Object(default_obj)) => {
      let preserved : Array[String] = []
      for key, existing_value in existing_obj {
        let next_path = if path.is_empty() { key } else { "\{path}.\{key}" }
        match default_obj.get(key) {
          Some(default_value) =>
            for
              nested in collect_preserved_keys(
                existing_value, default_value, next_path,
              ) {
              preserved.push(nested)
            }
          None => preserved.push(next_path)
        }
      }
      preserved
    }
    (_, _) => []
  }
}

///|
fn config_dir(path : String) -> String {
  @pathx.dirname(path).to_string()
}

///|
pub async fn collect_status(home~ : String, cwd~ : String) -> OnboardingStatus {
  let (config_path, config_json) = load_config(home, cwd)
  let workspace_runtime = @workspace.WorkspaceRuntime::new(home~, cwd~)
  let plugin_runtime = @plugin.PluginRuntime::new(home~, cwd~)
  let security_runtime = @security.SecurityRuntime::new(home~, cwd~)
  ignore(security_runtime)
  let snapshot = workspace_runtime.snapshot()
  let issues : Array[String] = []
  let next_steps : Array[String] = []
  let primary_model = find_primary_model(config_json)
  let providers = provider_count(config_json)
  let has_token = has_gateway_token(config_json)
  let feishu_on = feishu_enabled(config_json)
  let feishu_ok = feishu_ready(config_json)
  if config_json is None {
    issues.push("Missing moonclaw.json configuration")
    next_steps.push("Run `moonclaw onboard init` to create a baseline config")
  }
  if providers == 0 {
    issues.push("No model providers configured")
    next_steps.push("Add at least one provider under `models.providers`")
  }
  match primary_model {
    Some(model) if !model.is_blank() => ()
    _ => {
      issues.push("No primary model configured")
      next_steps.push(
        "Set `agents.defaults.model.primary` to a usable model id",
      )
    }
  }
  if !has_token {
    issues.push("Gateway auth token is missing")
    next_steps.push("Run `moonclaw onboard init` or add `gateway.auth.token`")
  }
  if feishu_on && !feishu_ok {
    issues.push("Feishu is enabled but appId/appSecret are incomplete")
    next_steps.push(
      "Fill `channels.feishu.appId` and `channels.feishu.appSecret`",
    )
  }
  for plugin in plugin_runtime.list() {
    if plugin.enabled && plugin.status == "missing_install" {
      issues.push("Plugin `\{plugin.id}` is enabled but not installed")
      next_steps.push("Install or disable plugin `\{plugin.id}`")
    }
  }
  if snapshot.files.length() == 0 {
    issues.push("Workspace files are missing")
    next_steps.push("Run `moonclaw onboard init` to bootstrap workspace files")
  }
  OnboardingStatus::{
    home,
    cwd,
    config_path,
    config_exists: config_json is Some(_),
    workspace_root: snapshot.root,
    workspace_configured_from: snapshot.configured_from,
    workspace_files: snapshot.files.map(fn(file) { file.name }),
    primary_model,
    provider_count: providers,
    gateway_port: gateway_port(config_json),
    has_gateway_token: has_token,
    feishu_enabled: feishu_on,
    feishu_ready: feishu_ok,
    plugin_count: plugin_runtime.list().length(),
    issues,
    next_steps,
  }
}

///|
pub async fn bootstrap(home~ : String, cwd~ : String) -> OnboardingApplyResult {
  let (config_path, existing) = load_config(home, cwd)
  let defaults = default_config(home)
  let merged = match existing {
    Some(existing) => merge_missing(existing, defaults)
    None => defaults
  }
  let dir = config_dir(config_path)
  @fsx.make_directory(dir, recursive=true) catch {
    _ => ()
  }
  @fsx.write_to_file(config_path, merged.stringify())
  let workspace_runtime = @workspace.WorkspaceRuntime::new(home~, cwd~)
  workspace_runtime.load()
  let created : Array[String] = []
  if existing is None {
    created.push(config_path)
  }
  if workspace_runtime.root().has_prefix(home) {
    created.push(workspace_runtime.root())
  }
  let preserved = match existing {
    Some(existing) => collect_preserved_keys(existing, defaults, "")
    None => []
  }
  let onboarding = collect_status(home~, cwd~)
  OnboardingApplyResult::{
    status: if existing is Some(_) {
      "updated"
    } else {
      "created"
    },
    config_path,
    workspace_root: workspace_runtime.root(),
    created,
    preserved,
    onboarding,
  }
}

///|
pub fn render_status(status : OnboardingStatus) -> String {
  let lines : Array[String] = []
  let primary_model = status.primary_model.unwrap_or("<missing>")
  let gateway_token_status = if status.has_gateway_token {
    "configured"
  } else {
    "missing"
  }
  let workspace_files = status.workspace_files.join(", ")
  let feishu_status = if status.feishu_enabled {
    if status.feishu_ready {
      "enabled+ready"
    } else {
      "enabled+incomplete"
    }
  } else {
    "disabled"
  }
  lines.push("MoonClaw onboarding status")
  lines.push("")
  lines.push("Config: \{status.config_path}")
  lines.push("Config exists: \{status.config_exists}")
  lines.push("Workspace: \{status.workspace_root}")
  lines.push("Workspace source: \{status.workspace_configured_from}")
  lines.push("Primary model: \{primary_model}")
  lines.push("Providers: \{status.provider_count}")
  lines.push("Gateway auth token: \{gateway_token_status}")
  lines.push("Feishu: \{feishu_status}")
  lines.push("Plugins discovered: \{status.plugin_count}")
  if !status.workspace_files.is_empty() {
    lines.push("Workspace files: \{workspace_files}")
  }
  if status.issues.is_empty() {
    lines.push("")
    lines.push("Status: ready")
  } else {
    lines.push("")
    lines.push("Issues:")
    for issue in status.issues {
      lines.push("- \{issue}")
    }
    if !status.next_steps.is_empty() {
      lines.push("")
      lines.push("Next steps:")
      for step in status.next_steps {
        lines.push("- \{step}")
      }
    }
  }
  lines.join("\n")
}

///|
pub fn render_bootstrap_result(result : OnboardingApplyResult) -> String {
  let lines : Array[String] = []
  lines.push("Onboarding \{result.status}")
  lines.push("Config: \{result.config_path}")
  lines.push("Workspace: \{result.workspace_root}")
  if !result.created.is_empty() {
    lines.push("Created:")
    for item in result.created {
      lines.push("- \{item}")
    }
  }
  if !result.preserved.is_empty() {
    lines.push("Preserved existing settings:")
    for item in result.preserved {
      lines.push("- \{item}")
    }
  }
  lines.push("")
  lines.push(render_status(result.onboarding))
  lines.join("\n")
}

///|
pub fn render_default_config(home~ : String) -> String {
  default_config(home).stringify(indent=2)
}
