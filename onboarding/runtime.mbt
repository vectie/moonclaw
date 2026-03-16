///|
pub struct OnboardingOptions {
  primary_model : String?
  working_directory : String?
  workspace_root : String?
  gateway_port : Int?
  gateway_token : String?
  feishu_enabled : Bool?
  feishu_app_id : String?
  feishu_app_secret : String?
} derive(ToJson, FromJson, Show)

///|
pub struct OnboardingAuthProviderStatus {
  provider : String
  authenticated : Bool
  account_label : String?
  detail : String?
  default_model : String?
  available_models : Array[String]
} derive(ToJson, FromJson, Show)

///|
pub struct OnboardingAuthStatus {
  providers : Array[OnboardingAuthProviderStatus]
  issues : Array[String]
  next_steps : Array[String]
} derive(ToJson, FromJson, Show)

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
  available_models : Array[String]
  auth : OnboardingAuthStatus
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
fn default_onboarding_options() -> OnboardingOptions {
  {
    primary_model: None,
    working_directory: None,
    workspace_root: None,
    gateway_port: None,
    gateway_token: None,
    feishu_enabled: None,
    feishu_app_id: None,
    feishu_app_secret: None,
  }
}

///|
pub fn onboarding_options(
  primary_model? : String? = None,
  working_directory? : String? = None,
  workspace_root? : String? = None,
  gateway_port? : Int? = None,
  gateway_token? : String? = None,
  feishu_enabled? : Bool? = None,
  feishu_app_id? : String? = None,
  feishu_app_secret? : String? = None,
) -> OnboardingOptions {
  {
    primary_model,
    working_directory,
    workspace_root,
    gateway_port,
    gateway_token,
    feishu_enabled,
    feishu_app_id,
    feishu_app_secret,
  }
}

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
fn discover_models_from_json(json : Json?) -> Array[String] {
  let discovered : Array[String] = []
  match json {
    Some(Object(root)) =>
      match root.get("models") {
        Some(Object(models)) =>
          match models.get("providers") {
            Some(Object(providers)) =>
              for provider_id, provider in providers {
                match provider {
                  Object(provider_obj) =>
                    match provider_obj.get("models") {
                      Some(Array(models)) =>
                        for model in models {
                          match model {
                            Object(model_obj) =>
                              match model_obj.get("id") {
                                Some(String(id)) if !id.trim().is_empty() => {
                                  let candidate = "\{provider_id}/\{id.trim()}"
                                  if !discovered.contains(candidate) {
                                    discovered.push(candidate)
                                  }
                                }
                                _ => ()
                              }
                            _ => ()
                          }
                        }
                      _ => ()
                    }
                  _ => ()
                }
              }
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }
  discovered.sort()
  discovered
}

///|
fn oauth_model_choices() -> Array[String] {
  [
    "codex/gpt-5.4", "codex/gpt-5.3-codex", "copilot/gpt-5.2", "copilot/gpt-5-codex",
    "copilot/gpt-5.1-codex", "copilot/claude-sonnet-4.5", "copilot/claude-opus-4.5",
    "copilot/gemini-2.5-pro", "copilot/grok-code-fast-1",
  ]
}

///|
fn merge_model_choices(configured : Array[String]) -> Array[String] {
  let merged : Array[String] = []
  for model in configured {
    if !merged.contains(model) {
      merged.push(model)
    }
  }
  for model in oauth_model_choices() {
    if !merged.contains(model) {
      merged.push(model)
    }
  }
  merged.sort()
  merged
}

///|
fn codex_claims(id_token : String) -> @codex.IdTokenClaims? {
  Some(@codex.extract_token_claims(id_token)) catch {
    _ => None
  }
}

///|
async fn codex_auth_provider_status() -> OnboardingAuthProviderStatus {
  try {
    let credentials = @codex.load_credentials()
    match codex_claims(credentials.idToken) {
      Some(claims) =>
        {
          provider: "codex",
          authenticated: true,
          account_label: Some(claims.email),
          detail: Some("plan=\{claims.chatgptPlanType}"),
          default_model: Some("codex/gpt-5.4"),
          available_models: ["codex/gpt-5.4", "codex/gpt-5.3-codex"],
        }
      None =>
        {
          provider: "codex",
          authenticated: true,
          account_label: None,
          detail: Some("credentials detected"),
          default_model: Some("codex/gpt-5.4"),
          available_models: ["codex/gpt-5.4", "codex/gpt-5.3-codex"],
        }
    }
  } catch {
    _ =>
      {
        provider: "codex",
        authenticated: false,
        account_label: None,
        detail: Some("credentials unreadable"),
        default_model: Some("codex/gpt-5.4"),
        available_models: ["codex/gpt-5.4", "codex/gpt-5.3-codex"],
      }
  }
}

///|
async fn copilot_auth_provider_status(
  common_copilot_models : Array[String],
) -> OnboardingAuthProviderStatus {
  try {
    let credentials = @copilot.load_credentials()
    let valid = credentials.is_token_valid(@async.now())
    {
      provider: "copilot",
      authenticated: valid,
      account_label: None,
      detail: Some(if valid { "token valid" } else { "token expired" }),
      default_model: Some("copilot/gpt-5.2"),
      available_models: common_copilot_models,
    }
  } catch {
    _ =>
      {
        provider: "copilot",
        authenticated: false,
        account_label: None,
        detail: Some("credentials unreadable"),
        default_model: Some("copilot/gpt-5.2"),
        available_models: common_copilot_models,
      }
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
fn json_object_copy(raw : Json?) -> Map[String, Json] {
  let copied : Map[String, Json] = {}
  match raw {
    Some(Object(obj)) =>
      for key, value in obj {
        copied[key] = value
      }
    _ => ()
  }
  copied
}

///|
fn json_set_path(json : Json, path : Array[String], value : Json) -> Json {
  if path.is_empty() {
    return value
  }
  let current = json_object_copy(Some(json))
  let head = path[0]
  let tail = path[1:].to_array()
  current[head] = match current.get(head) {
    Some(existing) => json_set_path(existing, tail, value)
    None => json_set_path(Json::object({}), tail, value)
  }
  Json::object(current)
}

///|
fn apply_options(json : Json, options : OnboardingOptions) -> Json {
  let mut configured = json
  match options.primary_model {
    Some(model) if !model.trim().is_empty() =>
      configured = json_set_path(
        configured,
        ["agents", "defaults", "model", "primary"],
        Json::string(model.trim().to_string()),
      )
    _ => ()
  }
  match options.working_directory {
    Some(working_directory) if !working_directory.trim().is_empty() =>
      configured = json_set_path(
        configured,
        ["agents", "defaults", "cwd"],
        Json::string(working_directory.trim().to_string()),
      )
    _ => ()
  }
  match options.workspace_root {
    Some(workspace_root) if !workspace_root.trim().is_empty() =>
      configured = json_set_path(
        configured,
        ["agents", "defaults", "workspace"],
        Json::string(workspace_root.trim().to_string()),
      )
    _ => ()
  }
  match options.gateway_port {
    Some(port) =>
      configured = json_set_path(
        configured,
        ["gateway", "port"],
        Json::number(port.to_double(), repr=port.to_string()),
      )
    None => ()
  }
  match options.gateway_token {
    Some(token) if !token.trim().is_empty() =>
      configured = json_set_path(
        configured,
        ["gateway", "auth", "token"],
        Json::string(token.trim().to_string()),
      )
    _ => ()
  }
  match options.feishu_enabled {
    Some(enabled) =>
      configured = json_set_path(
        configured,
        ["channels", "feishu", "enabled"],
        enabled.to_json(),
      )
    None => ()
  }
  match options.feishu_app_id {
    Some(app_id) if !app_id.trim().is_empty() => {
      configured = json_set_path(
        configured,
        ["channels", "feishu", "appId"],
        Json::string(app_id.trim().to_string()),
      )
      if options.feishu_enabled is None {
        configured = json_set_path(
          configured,
          ["channels", "feishu", "enabled"],
          true.to_json(),
        )
      }
    }
    _ => ()
  }
  match options.feishu_app_secret {
    Some(app_secret) if !app_secret.trim().is_empty() => {
      configured = json_set_path(
        configured,
        ["channels", "feishu", "appSecret"],
        Json::string(app_secret.trim().to_string()),
      )
      if options.feishu_enabled is None {
        configured = json_set_path(
          configured,
          ["channels", "feishu", "enabled"],
          true.to_json(),
        )
      }
    }
    _ => ()
  }
  configured
}

///|
fn default_config(home : String, cwd : String) -> Json {
  let workspace_root = home |> @pathx.join("workspace")
  {
    "models": { "providers": {} },
    "agents": {
      "defaults": {
        "model": { "primary": "" },
        "cwd": cwd,
        "workspace": workspace_root,
      },
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
async fn collect_auth_status() -> OnboardingAuthStatus {
  let providers : Array[OnboardingAuthProviderStatus] = []
  let issues : Array[String] = []
  let next_steps : Array[String] = []
  let common_copilot_models = [
    "copilot/gpt-5.2", "copilot/gpt-5-codex", "copilot/claude-sonnet-4.5", "copilot/gemini-2.5-pro",
    "copilot/grok-code-fast-1",
  ]

  let codex_authenticated = @codex.credentials_exist() catch { _ => false }
  if codex_authenticated {
    providers.push(codex_auth_provider_status())
  } else {
    providers.push({
      provider: "codex",
      authenticated: false,
      account_label: None,
      detail: Some("not logged in"),
      default_model: Some("codex/gpt-5.4"),
      available_models: ["codex/gpt-5.4", "codex/gpt-5.3-codex"],
    })
    issues.push("Codex OAuth is not connected")
    next_steps.push(
      "Run `moonclaw onboard auth codex`, then `moonclaw onboard switch codex`",
    )
  }

  let copilot_authenticated = @copilot.credentials_exist() catch { _ => false }
  if copilot_authenticated {
    providers.push(copilot_auth_provider_status(common_copilot_models))
  } else {
    providers.push({
      provider: "copilot",
      authenticated: false,
      account_label: None,
      detail: Some("not logged in"),
      default_model: Some("copilot/gpt-5.2"),
      available_models: common_copilot_models,
    })
  }

  { providers, issues, next_steps }
}

///|
pub async fn auth_status() -> OnboardingAuthStatus {
  collect_auth_status()
}

///|
pub async fn start_auth_flow(provider : String) -> String {
  match provider {
    "codex" => {
      let credentials = @codex.start_oauth_flow()
      let claims = codex_claims(credentials.idToken)
      match claims {
        Some(claims) =>
          "Connected Codex OAuth for \{claims.email} (\{claims.chatgptPlanType})"
        None => "Connected Codex OAuth"
      }
    }
    "copilot" => {
      ignore(@copilot.start_oauth_flow())
      "Connected Copilot OAuth"
    }
    _ => "Unknown auth provider `\{provider}`"
  }
}

///|
pub async fn clear_auth(provider : String) -> String {
  match provider {
    "codex" => {
      @codex.delete_credentials()
      "Disconnected Codex OAuth"
    }
    "copilot" => {
      @copilot.delete_credentials()
      "Disconnected Copilot OAuth"
    }
    _ => "Unknown auth provider `\{provider}`"
  }
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
  let available_models = merge_model_choices(
    discover_models_from_json(config_json),
  )
  let has_token = has_gateway_token(config_json)
  let feishu_on = feishu_enabled(config_json)
  let feishu_ok = feishu_ready(config_json)
  let auth = collect_auth_status()
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
      if available_models.is_empty() {
        next_steps.push(
          "Add provider models, then pick one with `moonclaw onboard init --model <provider/model>`",
        )
      } else {
        next_steps.push(
          "Run `moonclaw onboard models` and choose one with `moonclaw onboard init --model <provider/model>`",
        )
      }
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
    available_models,
    auth,
    plugin_count: plugin_runtime.list().length(),
    issues,
    next_steps,
  }
}

///|
pub async fn bootstrap(home~ : String, cwd~ : String) -> OnboardingApplyResult {
  bootstrap_with_options(home~, cwd~, default_onboarding_options())
}

///|
pub async fn bootstrap_with_options(
  home~ : String,
  cwd~ : String,
  options : OnboardingOptions,
) -> OnboardingApplyResult {
  let (config_path, existing) = load_config(home, cwd)
  let defaults = default_config(home, cwd)
  let merged = match existing {
    Some(existing) => merge_missing(existing, defaults)
    None => defaults
  }
  let configured = apply_options(merged, options)
  let dir = config_dir(config_path)
  @fsx.make_directory(dir, recursive=true) catch {
    _ => ()
  }
  @fsx.write_to_file(config_path, configured.stringify(indent=2))
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
pub async fn discover_models(home~ : String, cwd~ : String) -> Array[String] {
  let (_, config_json) = load_config(home, cwd)
  merge_model_choices(discover_models_from_json(config_json))
}

///|
fn render_provider_suffix(
  account_label : String?,
  provider_detail : String?,
) -> String {
  match account_label {
    Some(account_label) =>
      match provider_detail {
        Some(provider_detail) => " (\{account_label}; \{provider_detail})"
        None => " (\{account_label})"
      }
    None =>
      match provider_detail {
        Some(provider_detail) => " (\{provider_detail})"
        None => ""
      }
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
  for provider in status.auth.providers {
    let auth_status = if provider.authenticated {
      "connected"
    } else {
      "not connected"
    }
    let detail = render_provider_suffix(provider.account_label, provider.detail)
    lines.push("OAuth \{provider.provider}: \{auth_status}\{detail}")
  }
  if !status.available_models.is_empty() {
    let available_models = status.available_models.join(", ")
    lines.push("Available models: \{available_models}")
  }
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
pub fn render_model_list(models : Array[String]) -> String {
  let lines : Array[String] = ["Available model choices"]
  if models.is_empty() {
    lines.push("")
    lines.push("No configured provider models were found.")
  } else {
    lines.push("")
    for model in models {
      lines.push("- \{model}")
    }
    lines.push("")
    lines.push("Switch with `moonclaw onboard switch <model>`.")
    lines.push("For Codex, connect first with `moonclaw onboard auth codex`.")
  }
  lines.join("\n")
}

///|
pub fn render_auth_status(status : OnboardingAuthStatus) -> String {
  let lines : Array[String] = ["MoonClaw OAuth status", ""]
  for provider in status.providers {
    let auth_state = if provider.authenticated {
      "connected"
    } else {
      "not connected"
    }
    let suffix = render_provider_suffix(provider.account_label, provider.detail)
    lines.push("- \{provider.provider}: \{auth_state}\{suffix}")
    match provider.default_model {
      Some(model) => lines.push("  default model: \{model}")
      None => ()
    }
  }
  if !status.next_steps.is_empty() {
    lines.push("")
    lines.push("Next steps:")
    for step in status.next_steps {
      lines.push("- \{step}")
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
  default_config(home, home).stringify(indent=2)
}

///|
pub fn render_config_with_options(
  home~ : String,
  options : OnboardingOptions,
) -> String {
  apply_options(default_config(home, home), options).stringify(indent=2)
}
