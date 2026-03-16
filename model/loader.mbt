///|
struct Loader {
  home : StringView
  cwd : StringView
  models : Array[Model]
  providers : Map[String, ProviderConfig]
}

///|
/// Create a model loader scoped to the given home directory and
/// current working directory.
///
/// Parameters:
///
/// - home: Absolute path to the user's home directory.
/// - cwd: Absolute path to the current project directory.
///
/// Returns a Loader instance with an empty model cache that can be
/// populated by calling `load`.
///
/// Populate the loader's in-memory model cache by reading project and
/// user model configuration files.
///
/// The loader looks for `.moonclaw/models/models.json` inside the
/// current working directory first, then the user's home directory. If
/// either file exists, the models defined there are appended to the
/// loader's cache.
pub async fn Loader::new(home? : StringView, cwd? : StringView) -> Loader {
  let home = match home {
    Some(home) => home
    None => @os.home()
  }
  let cwd = match cwd {
    Some(cwd) => cwd
    None => @os.cwd()
  }
  let loader = Loader::{ home, cwd, models: [], providers: Map::new() }
  loader.load()
  loader
}

///|
fn moonclaw_root_config_path(root : StringView) -> String {
  root |> @pathx.join("moonclaw.json")
}

///|
fn moonclaw_nested_config_path(root : StringView) -> String {
  root |> @pathx.join(".moonclaw") |> @pathx.join("moonclaw.json")
}

///|
fn moonclaw_root_models_path(root : StringView) -> String {
  root |> @pathx.join("models") |> @pathx.join("models.json")
}

///|
fn moonclaw_nested_models_path(root : StringView) -> String {
  root
  |> @pathx.join(".moonclaw")
  |> @pathx.join("models")
  |> @pathx.join("models.json")
}

///|
fn moonclaw_config_paths(root : StringView) -> Array[String] {
  [moonclaw_root_config_path(root), moonclaw_nested_config_path(root)]
}

///|
fn moonclaw_models_paths(root : StringView) -> Array[String] {
  [moonclaw_root_models_path(root), moonclaw_nested_models_path(root)]
}

///|
fn merge_providers(
  into : Map[String, ProviderConfig],
  providers : Map[String, ProviderConfig],
) -> Unit {
  for name, config in providers {
    into.set(name, config)
  }
}

///|
async fn Loader::load(self : Loader) -> Unit {
  self.models.clear()
  self.providers.clear()

  async fn load_from_path(path : StringView) -> Array[Model] {
    let text = @fsx.read_file(path) catch { _ => return [] }
    let json = @json.parse(text) catch { _ => return [] }
    guard json is Array(_) else { return [] }
    @json.from_json(json) catch {
      _ => []
    }
  }

  async fn load_providers_from_path(
    path : StringView,
  ) -> Map[String, ProviderConfig] {
    let text = @fsx.read_file(path) catch { _ => return Map::new() }
    let json = @json.parse(text) catch { _ => return Map::new() }
    guard json is Object(obj) else { return Map::new() }
    if obj.get("providers") is Some(_) {
      let providers_file : ProvidersFile = @json.from_json(json) catch {
        _ => return Map::new()
      }
      providers_file.providers
    } else {
      Map::new()
    }
  }

  async fn load_providers_from_moonclaw_config(
    path : StringView,
  ) -> Map[String, ProviderConfig] {
    let text = @fsx.read_file(path) catch { _ => return Map::new() }
    let json = @json.parse(text) catch { _ => return Map::new() }
    guard json is Object(obj) else { return Map::new() }
    guard obj.get("models") is Some(models_json) else { return Map::new() }
    guard models_json is Object(models_obj) else { return Map::new() }
    guard models_obj.get("providers") is Some(providers_json) else {
      return Map::new()
    }
    @json.from_json(providers_json) catch {
      _ => Map::new()
    }
  }

  for path in moonclaw_models_paths(self.cwd) {
    if @fsx.exists(path) {
      self.models.append(load_from_path(path))
      merge_providers(self.providers, load_providers_from_path(path))
    }
  }
  for path in moonclaw_models_paths(self.home) {
    if @fsx.exists(path) {
      self.models.append(load_from_path(path))
      merge_providers(self.providers, load_providers_from_path(path))
    }
  }
  for path in moonclaw_config_paths(self.cwd) {
    if @fsx.exists(path) {
      merge_providers(self.providers, load_providers_from_moonclaw_config(path))
    }
  }
  for path in moonclaw_config_paths(self.home) {
    if @fsx.exists(path) {
      merge_providers(self.providers, load_providers_from_moonclaw_config(path))
    }
  }
}

///|
async fn Loader::load_moonclaw_api_key(self : Loader) -> String? {
  async fn load_from_path(path : String) -> String? {
    if not(@fsx.exists(path)) {
      return None
    }
    let text = @fsx.read_file(path) catch { _ => return None }
    let json = @json.parse(text) catch { _ => return None }
    guard json is Object(obj) else { return None }
    if obj.get("api_key") is Some(api_key_json) {
      guard api_key_json is String(api_key) else { return None }
      return Some(api_key)
    }
    if obj.get("env") is Some(env_json) {
      guard env_json is Object(env) else { return None }
      if env.get("OPEN_ROUTER_API_KEY") is Some(api_key_json) {
        guard api_key_json is String(api_key) else { return None }
        return Some(api_key)
      }
      if env.get("OPENROUTER_API_KEY") is Some(api_key_json) {
        guard api_key_json is String(api_key) else { return None }
        return Some(api_key)
      }
      if env.get("QWEN_API_KEY") is Some(api_key_json) {
        guard api_key_json is String(api_key) else { return None }
        return Some(api_key)
      }
    }
    None
  }
  for path in moonclaw_config_paths(self.cwd) {
    if load_from_path(path) is Some(api_key) {
      logger.info("Loaded API key from project MoonClaw config")
      return Some(api_key)
    }
  }
  for path in moonclaw_config_paths(self.home) {
    if load_from_path(path) is Some(api_key) {
      logger.info("Loaded API key from user MoonClaw config")
      return Some(api_key)
    }
  }
  None
}

///|
async fn Loader::load_qwen_api_key(self : Loader) -> String? {
  async fn load_from_path(path : String) -> String? {
    if not(@fsx.exists(path)) {
      return None
    }
    let text = @fsx.read_file(path) catch { _ => return None }
    let json = @json.parse(text) catch { _ => return None }
    guard json is Object(obj) else { return None }
    if obj.get("qwen_api_key") is Some(api_key_json) {
      guard api_key_json is String(api_key) else { return None }
      return Some(api_key)
    }
    if obj.get("env") is Some(env_json) {
      guard env_json is Object(env) else { return None }
      if env.get("QWEN_API_KEY") is Some(api_key_json) {
        guard api_key_json is String(api_key) else { return None }
        return Some(api_key)
      }
      if env.get("DASHSCOPE_API_KEY") is Some(api_key_json) {
        guard api_key_json is String(api_key) else { return None }
        return Some(api_key)
      }
    }
    None
  }
  for path in moonclaw_config_paths(self.cwd) {
    if load_from_path(path) is Some(api_key) {
      logger.info("Loaded Qwen API key from project MoonClaw config")
      return Some(api_key)
    }
  }
  for path in moonclaw_config_paths(self.home) {
    if load_from_path(path) is Some(api_key) {
      logger.info("Loaded Qwen API key from user MoonClaw config")
      return Some(api_key)
    }
  }
  if @os.getenv("QWEN_API_KEY") is Some(api_key) {
    return Some(api_key)
  }
  if @os.getenv("DASHSCOPE_API_KEY") is Some(api_key) {
    return Some(api_key)
  }
  None
}

///|
async fn Loader::load_kimi_api_key(self : Loader) -> String? {
  async fn load_from_path(path : String) -> String? {
    if not(@fsx.exists(path)) {
      return None
    }
    let text = @fsx.read_file(path) catch { _ => return None }
    let json = @json.parse(text) catch { _ => return None }
    guard json is Object(obj) else { return None }
    if obj.get("kimi_api_key") is Some(api_key_json) {
      guard api_key_json is String(api_key) else { return None }
      return Some(api_key)
    }
    if obj.get("env") is Some(env_json) {
      guard env_json is Object(env) else { return None }
      if env.get("KIMI_API_KEY") is Some(api_key_json) {
        guard api_key_json is String(api_key) else { return None }
        return Some(api_key)
      }
      if env.get("MOONSHOT_API_KEY") is Some(api_key_json) {
        guard api_key_json is String(api_key) else { return None }
        return Some(api_key)
      }
    }
    None
  }
  for path in moonclaw_config_paths(self.cwd) {
    if load_from_path(path) is Some(api_key) {
      logger.info("Loaded Kimi API key from project MoonClaw config")
      return Some(api_key)
    }
  }
  for path in moonclaw_config_paths(self.home) {
    if load_from_path(path) is Some(api_key) {
      logger.info("Loaded Kimi API key from user MoonClaw config")
      return Some(api_key)
    }
  }
  if @os.getenv("KIMI_API_KEY") is Some(api_key) {
    return Some(api_key)
  }
  if @os.getenv("MOONSHOT_API_KEY") is Some(api_key) {
    return Some(api_key)
  }
  None
}

///|
async fn Loader::load_kimi_coding_api_key(self : Loader) -> String? {
  async fn load_from_path(path : String) -> String? {
    if not(@fsx.exists(path)) {
      return None
    }
    let text = @fsx.read_file(path) catch { _ => return None }
    let json = @json.parse(text) catch { _ => return None }
    guard json is Object(obj) else { return None }
    if obj.get("kimi_coding_api_key") is Some(api_key_json) {
      guard api_key_json is String(api_key) else { return None }
      return Some(api_key)
    }
    if obj.get("env") is Some(env_json) {
      guard env_json is Object(env) else { return None }
      if env.get("KIMI_CODING_API_KEY") is Some(api_key_json) {
        guard api_key_json is String(api_key) else { return None }
        return Some(api_key)
      }
    }
    None
  }
  for path in moonclaw_config_paths(self.cwd) {
    if load_from_path(path) is Some(api_key) {
      logger.info("Loaded Kimi Coding API key from project MoonClaw config")
      return Some(api_key)
    }
  }
  for path in moonclaw_config_paths(self.home) {
    if load_from_path(path) is Some(api_key) {
      logger.info("Loaded Kimi Coding API key from user MoonClaw config")
      return Some(api_key)
    }
  }
  if @os.getenv("KIMI_CODING_API_KEY") is Some(api_key) {
    return Some(api_key)
  }
  None
}

///|
async fn Loader::load_from_providers(self : Loader, name : String) -> Model? {
  let (target_provider, model_id) = if name.contains("/") {
    let parts = name.split("/").to_array()
    let provider_name = parts.get(0).unwrap_or("").to_string()
    let id = parts.get(1).unwrap_or(name).to_string()
    (Some(provider_name), id)
  } else {
    (None, name)
  }
  for provider_name, config in self.providers {
    if target_provider is Some(target) && provider_name != target {
      continue
    }
    for model_config in config.models {
      if model_config.id == model_id {
        let api_key = match config.apiKey {
          Some(key) => key
          None => return None
        }
        let base_url = match config.baseUrl {
          Some(url) => url
          None => return None
        }
        let safe_zone_tokens = match model_config.contextWindow {
          Some(window) => window
          None => 128_000
        }
        let model_type = match config.api {
          Some("anthropic-messages") => SaaS(Anthropic)
          Some("openai") => SaaS(OpenAI)
          Some("openai-completions") => SaaS(OpenAI)
          _ => SaaS(OpenAI)
        }
        logger.info(
          "Loaded model '\{model_id}' from provider '\{provider_name}'",
        )
        let model = Model::new(
          api_key~,
          base_url~,
          name~,
          model_name=model_config.id,
          model_type~,
          safe_zone_tokens~,
        )
        return Some(model)
      }
    }
  }
  None
}

///|
async fn Loader::load_first_provider_model(self : Loader) -> Model? {
  for provider_name, config in self.providers {
    let api_key = match config.apiKey {
      Some(key) => key
      None => continue
    }
    let base_url = match config.baseUrl {
      Some(url) => url
      None => continue
    }
    if config.models.get(0) is Some(model_config) {
      let safe_zone_tokens = match model_config.contextWindow {
        Some(window) => window
        None => 128_000
      }
      let model_type = match config.api {
        Some("anthropic-messages") => SaaS(Anthropic)
        Some("openai") => SaaS(OpenAI)
        _ => SaaS(OpenAI)
      }
      logger.info(
        "Auto-detected model '\{model_config.id}' from provider '\{provider_name}'",
      )
      let model = Model::new(
        api_key~,
        base_url~,
        name=model_config.id,
        model_name=model_config.id,
        model_type~,
        safe_zone_tokens~,
      )
      return Some(model)
    }
  }
  None
}

///|
/// Retrieve a model from the loader's cache, optionally overriding
/// selected fields.
///
/// Parameters:
/// - name: Model name to look up. When omitted, the first cached model
///   is returned (if any).
/// - api_key: Optional API key override for the returned model.
/// - base_url: Optional base URL override for the returned model.
///
/// Returns the matching model with overrides applied, or `None` when no
/// model is available.
pub async fn Loader::get_model(self : Loader, name? : String) -> Model? {
  self.load()
  if name is Some(model_name) {
    if self.load_from_providers(model_name) is Some(model) {
      return Some(model)
    }
  }
  let configured_model = if name is Some(name) {
    for model in self.models {
      if model.name == name {
        logger.info("Loaded model '\{name}' from configuration")
        break Some(model)
      }
    } nobreak {
      None
    }
  } else {
    self.models.get(0)
  }
  if configured_model is Some(model) {
    return Some(model)
  }
  if name is Some(model_name) && model_name.has_prefix("codex/") {
    return self.load_codex_model(model_name, allow_auto_login=true)
  }
  if name is Some(model_name) && model_name.has_prefix("copilot/") {
    return self.load_copilot_model(model_name, allow_auto_login=true)
  }
  if name is Some(model_name) && model_name.has_prefix("qwen/") {
    return self.load_qwen_model(model_name)
  }
  if name is Some(model_name) && model_name.has_prefix("kimi/") {
    return self.load_kimi_model(model_name)
  }
  if name is Some(model_name) && model_name.has_prefix("kimi-coding/") {
    return self.load_kimi_coding_model(model_name)
  }
  if name is Some(model_name) {
    return self.load_openrouter_model(Some(model_name))
  }
  logger.info("No model specified, auto-detecting...")
  if self.load_first_provider_model() is Some(model) {
    return Some(model)
  }
  if self.load_qwen_model("qwen/qwen3-coder-plus") is Some(model) {
    return Some(model)
  }
  if self.load_kimi_model("kimi/kimi-k2.5") is Some(model) {
    return Some(model)
  }
  if self.load_kimi_coding_model("kimi-coding/k2p5") is Some(model) {
    return Some(model)
  }
  if self.load_openrouter_model(None) is Some(model) {
    return Some(model)
  }
  if self.load_codex_model("codex/gpt-5.4", allow_auto_login=false)
    is Some(model) {
    return Some(model)
  }
  if self.load_copilot_model(
      "copilot/claude-sonnet-4.5",
      allow_auto_login=false,
    )
    is Some(model) {
    return Some(model)
  }
  logger.error(
    "No API key found. Set QWEN_API_KEY/KIMI_API_KEY/KIMI_CODING_API_KEY/OPENROUTER_API_KEY/OPENAI_API_KEY environment variable or use a codex/ or copilot/ model to authenticate via OAuth.",
  )
  None
}

///|
async fn Loader::load_openrouter_model(self : Loader, name : String?) -> Model? {
  let api_key = if self.load_moonclaw_api_key() is Some(api_key) {
    Some(api_key)
  } else if @os.getenv("OPENROUTER_API_KEY") is Some(api_key) {
    Some(api_key)
  } else if @os.getenv("OPENAI_API_KEY") is Some(api_key) {
    Some(api_key)
  } else {
    None
  }
  guard api_key is Some(api_key) else { return None }
  let base_url = "https://openrouter.ai/api/v1"
  let (model_name, safe_zone_tokens, supports_anthropic_prompt_caching) = match
    name {
    Some("qwen/qwen3-coder-plus") => ("qwen/qwen3-coder-plus", 128_000, false)
    Some("qwen/qwen3-coder-flash") => ("qwen/qwen3-coder-flash", 128_000, false)
    Some("x-ai/grok-4-fast") => ("x-ai/grok-4-fast", 2_000_000, false)
    Some("x-ai/grok-code-fast-1") => ("x-ai/grok-code-fast-1", 256_000, false)
    Some("anthropic/claude-haiku-4.5") =>
      ("anthropic/claude-haiku-4.5", 200_000, true)
    Some("anthropic/claude-sonnet-4.5") =>
      ("anthropic/claude-sonnet-4.5", 200_000, true)
    Some("anthropic/claude-opus-4.5") =>
      ("anthropic/claude-opus-4.5", 200_000, true)
    Some("openai/gpt-5-codex") => ("openai/gpt-5-codex", 400_000, false)
    Some("openai/gpt-5") => ("openai/gpt-5", 400_000, false)
    Some("openai/gpt-5-mini") => ("openai/gpt-5-mini", 400_000, false)
    Some("openai/gpt-5-nano") => ("openai/gpt-5-nano", 400_000, false)
    Some("moonshotai/kimi-k2-0905") =>
      ("moonshotai/kimi-k2-0905", 262_144, false)
    Some("z-ai/glm-4.6") => ("z-ai/glm-4.6", 202_752, false)
    Some("minimax/minimax-m2") => ("minimax/minimax-m2", 204_800, false)
    Some("deepseek/deepseek-v3.2") => ("deepseek/deepseek-v3.2", 200_000, false)
    None => ("anthropic/claude-sonnet-4.5", 200_000, true)
    Some(other) => (other, 128_000, false)
  }
  logger.info("Using OpenRouter model '\{model_name}'")
  let model = Model::new(
    api_key~,
    base_url~,
    name=model_name,
    safe_zone_tokens~,
    supports_anthropic_prompt_caching~,
  )
  Some(model)
}

///|
async fn Loader::load_codex_model(
  _self : Loader,
  name : String,
  allow_auto_login~ : Bool,
) -> Model? {
  let credentials = @codex.load_credentials() catch {
    _ => {
      if not(allow_auto_login) {
        return None
      }
      logger.info("Codex OAuth credentials not found, starting login...")
      @codex.start_oauth_flow() catch {
        err => {
          logger.error("OAuth login failed: \{err}")
          return None
        }
      }
    }
  }
  let codex_model = match name {
    "codex/gpt-5.4" => CodexModels::Gpt5_4
    "codex/gpt-5.3-codex" => CodexModels::Gpt5_3Codex
    "codex/gpt-5.2" => {
      logger.warn("Codex model `codex/gpt-5.2` is deprecated, using gpt-5.4")
      CodexModels::Gpt5_4
    }
    _ => {
      logger.warn("Unknown Codex model '\{name}', using gpt-5.4")
      CodexModels::Gpt5_4
    }
  }
  logger.info("Using Codex OAuth model '\{codex_model}'")
  let model = codex_oauth_model(
    access_token=credentials.accessToken,
    account_id=credentials.accountId,
    refresh_token=credentials.refreshToken,
    id_token=credentials.idToken,
    name=codex_model,
  )
  Some(model)
}

///|
async fn Loader::load_copilot_model(
  _self : Loader,
  name : String,
  allow_auto_login~ : Bool,
) -> Model? {
  let credentials = @copilot.get_valid_credentials() catch {
    _ => {
      if not(allow_auto_login) {
        return None
      }
      logger.info("Copilot credentials not found, starting login...")
      @copilot.start_oauth_flow() catch {
        err => {
          logger.error("Copilot OAuth login failed: \{err}")
          return None
        }
      }
    }
  }
  let selected_model : CopilotModels = match name {
    // OpenAI models
    "copilot/gpt-4.1" => Gpt4_1
    "copilot/gpt-4o" => Gpt4o
    "copilot/gpt-5" => Gpt5
    "copilot/gpt-5-mini" => Gpt5Mini
    "copilot/gpt-5-codex" => Gpt5Codex
    "copilot/gpt-5.1" => Gpt5_1
    "copilot/gpt-5.1-codex" => Gpt5_1Codex
    "copilot/gpt-5.1-codex-max" => Gpt5_1CodexMax
    "copilot/gpt-5.1-codex-mini" => Gpt5_1CodexMini
    "copilot/gpt-5.2" => Gpt5_2
    "copilot/o3" => O3
    "copilot/o3-mini" => O3Mini
    "copilot/o4-mini" => O4Mini
    // Anthropic models
    "copilot/claude-3.5-sonnet" => Claude3_5Sonnet
    "copilot/claude-3.7-sonnet" => Claude3_7Sonnet
    "copilot/claude-3.7-sonnet-thought" => Claude3_7SonnetThought
    "copilot/claude-haiku-4.5" => ClaudeHaiku4_5
    "copilot/claude-opus-4" => ClaudeOpus4
    "copilot/claude-opus-4.5" => ClaudeOpus4_5
    "copilot/claude-opus-41" => ClaudeOpus41
    "copilot/claude-sonnet-4" => ClaudeSonnet4
    "copilot/claude-sonnet-4.5" => ClaudeSonnet4_5
    // Google models
    "copilot/gemini-2.0-flash-001" => Gemini2_0Flash
    "copilot/gemini-2.5-pro" => Gemini2_5Pro
    "copilot/gemini-3-flash-preview" => Gemini3FlashPreview
    "copilot/gemini-3-pro-preview" => Gemini3ProPreview
    // xAI models
    "copilot/grok-code-fast-1" => GrokCodeFast1
    _ => {
      logger.warn("Unknown Copilot model '\{name}', using gpt-4.1")
      Gpt4_1
    }
  }
  logger.info("Using Copilot model '\{selected_model}'")
  let model = copilot_model(
    copilot_token=credentials.copilot_token,
    github_token=credentials.github_token,
    name=selected_model,
  )
  Some(model)
}

///|
async fn Loader::load_qwen_model(self : Loader, name : String) -> Model? {
  let api_key = self.load_qwen_api_key()
  guard api_key is Some(api_key) else { return None }
  let base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1"
  let (model_name, safe_zone_tokens) = match name {
    "qwen/qwen3-coder-plus" => ("qwen3-coder-plus", 128_000)
    "qwen/qwen3-coder-flash" => ("qwen3-coder-flash", 128_000)
    "qwen/qwen3-235b-a22b" => ("qwen3-235b-a22b", 128_000)
    "qwen/qwen3-32b" => ("qwen3-32b", 128_000)
    "qwen/qwen-max" => ("qwen-max", 32_000)
    "qwen/qwen-plus" => ("qwen-plus", 128_000)
    "qwen/qwen-turbo" => ("qwen-turbo", 128_000)
    "qwen/qwen-long" => ("qwen-long", 1_000_000)
    _ => {
      let model_name = name.strip_prefix("qwen/").unwrap_or(name).to_string()
      (model_name, 128_000)
    }
  }
  logger.info("Using Qwen model '\{model_name}'")
  let model = Model::new(
    api_key~,
    base_url~,
    name=model_name,
    model_name~,
    model_type=SaaS(Qwen),
    safe_zone_tokens~,
  )
  Some(model)
}

///|
async fn Loader::load_kimi_model(self : Loader, name : String) -> Model? {
  let api_key = self.load_kimi_api_key()
  guard api_key is Some(api_key) else { return None }
  let base_url = "https://api.moonshot.cn/v1"
  let (model_name, safe_zone_tokens) = match name {
    "kimi/kimi-k2-0905" => ("kimi-k2-0905", 262_144)
    "kimi/kimi-k2.5" => ("kimi-k2.5", 262_144)
    "kimi/moonshot-v1-8k" => ("moonshot-v1-8k", 8_000)
    "kimi/moonshot-v1-32k" => ("moonshot-v1-32k", 32_000)
    "kimi/moonshot-v1-128k" => ("moonshot-v1-128k", 128_000)
    _ => {
      let model_name = name.strip_prefix("kimi/").unwrap_or(name).to_string()
      (model_name, 128_000)
    }
  }
  logger.info("Using Kimi model '\{model_name}'")
  let model = Model::new(
    api_key~,
    base_url~,
    name=model_name,
    model_name~,
    model_type=SaaS(Kimi),
    safe_zone_tokens~,
  )
  Some(model)
}

///|
async fn Loader::load_kimi_coding_model(self : Loader, name : String) -> Model? {
  let api_key = self.load_kimi_coding_api_key()
  guard api_key is Some(api_key) else { return None }
  let base_url = "https://api.moonshot.cn/v1"
  let (model_name, safe_zone_tokens) = match name {
    "kimi-coding/k2p5" => ("kimi-k2.5", 262_144)
    "kimi-coding/k2-0905" => ("kimi-k2-0905", 262_144)
    _ => {
      let model_name = name
        .strip_prefix("kimi-coding/")
        .unwrap_or(name)
        .to_string()
      (model_name, 262_144)
    }
  }
  logger.info("Using Kimi Coding model '\{model_name}'")
  let model = Model::new(
    api_key~,
    base_url~,
    name=model_name,
    model_name~,
    model_type=SaaS(KimiCoding),
    safe_zone_tokens~,
  )
  Some(model)
}

///|
/// Returns a read-only view of all models currently cached in the loader.
///
/// Parameters:
///
/// * `self` : The loader instance to get models from.
///
/// Returns an `ArrayView[Model]` containing all cached models.
pub async fn Loader::models(self : Loader) -> ArrayView[Model] {
  self.load()
  self.models
}

///|
pub async fn load(
  home? : StringView,
  cwd? : StringView,
  name? : String,
) -> Model? {
  Loader::new(home?, cwd?).get_model(name?)
}
