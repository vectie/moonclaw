///|
async fn moonclaw_config_json(home : String, cwd : String) -> Json? {
  let project_path = @path.Path(cwd)
    .join(@path.Path(".moonclaw"))
    .join(@path.Path("moonclaw.json"))
    .to_string()
  let home_root_path = @path.Path(home)
    .join(@path.Path("moonclaw.json"))
    .to_string()
  let user_path = @path.Path(home)
    .join(@path.Path(".moonclaw"))
    .join(@path.Path("moonclaw.json"))
    .to_string()

  let home_root_json = if @fsx.exists(home_root_path) {
    let text = @fsx.read_file(home_root_path) catch { _ => return None }
    Some(@json.parse(text) catch { _ => return None })
  } else {
    None
  }
  let user_json = if @fsx.exists(user_path) {
    let text = @fsx.read_file(user_path) catch { _ => return home_root_json }
    Some(@json.parse(text) catch { _ => return home_root_json })
  } else {
    home_root_json
  }
  let project_json = if @fsx.exists(project_path) {
    let text = @fsx.read_file(project_path) catch { _ => return user_json }
    Some(@json.parse(text) catch { _ => return user_json })
  } else {
    None
  }
  match project_json {
    Some(json) => Some(json)
    None => user_json
  }
}

///|
fn json_string_field(value : Json, snake : String, camel : String) -> String? {
  match value {
    Object(obj) =>
      match (obj.get(snake), obj.get(camel)) {
        (Some(String(text)), _) if !text.is_blank() => Some(text)
        (_, Some(String(text))) if !text.is_blank() => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
fn json_bool_field(value : Json, snake : String, camel : String) -> Bool? {
  match value {
    Object(obj) =>
      match (obj.get(snake), obj.get(camel)) {
        (Some(True), _) => Some(true)
        (Some(False), _) => Some(false)
        (_, Some(True)) => Some(true)
        (_, Some(False)) => Some(false)
        _ => None
      }
    _ => None
  }
}

///|
fn json_value_field(value : Json, snake : String, camel : String) -> Json? {
  match value {
    Object(obj) =>
      match (obj.get(snake), obj.get(camel)) {
        (Some(field), _) => Some(field)
        (_, Some(field)) => Some(field)
        _ => None
      }
    _ => None
  }
}

///|
fn merged_string_field(
  primary : Json,
  fallback : Json,
  snake : String,
  camel : String,
) -> String? {
  match json_string_field(primary, snake, camel) {
    Some(value) => Some(value)
    None => json_string_field(fallback, snake, camel)
  }
}

///|
fn merged_bool_field(
  primary : Json,
  fallback : Json,
  snake : String,
  camel : String,
) -> Bool? {
  match json_bool_field(primary, snake, camel) {
    Some(value) => Some(value)
    None => json_bool_field(fallback, snake, camel)
  }
}

///|
fn merged_value_field(
  primary : Json,
  fallback : Json,
  snake : String,
  camel : String,
) -> Json? {
  match json_value_field(primary, snake, camel) {
    Some(value) => Some(value)
    None => json_value_field(fallback, snake, camel)
  }
}

///|
fn set_json_field(obj : Map[String, Json], key : String, value : Json?) -> Unit {
  match value {
    Some(value) => obj[key] = value
    None => ()
  }
}

///|
fn set_string_field(
  obj : Map[String, Json],
  key : String,
  value : String?,
) -> Unit {
  match value {
    Some(value) => obj[key] = Json::string(value)
    None => ()
  }
}

///|
fn bootstrap_feishu_account_config(
  config : Json,
  fallback? : Json = {},
) -> Json? {
  let app_id = match merged_string_field(config, fallback, "app_id", "appId") {
    Some(value) => value
    None => return None
  }
  let app_secret = match
    merged_string_field(config, fallback, "app_secret", "appSecret") {
    Some(value) => value
    None => return None
  }
  let domain = merged_string_field(config, fallback, "domain", "domain").unwrap_or(
    "feishu",
  )
  let connection_mode = merged_string_field(
    config, fallback, "connection_mode", "connectionMode",
  ).unwrap_or("webhook")
  let dm_policy = merged_string_field(config, fallback, "dm_policy", "dmPolicy").unwrap_or(
    "pairing",
  )
  let enabled = merged_bool_field(config, fallback, "enabled", "enabled").unwrap_or(
    true,
  )
  let account : Map[String, Json] = {
    "app_id": Json::string(app_id),
    "app_secret": Json::string(app_secret),
    "domain": Json::string(domain),
    "connection_mode": Json::string(connection_mode),
    "dm_policy": Json::string(dm_policy),
    "enabled": enabled.to_json(),
  }
  set_string_field(
    account,
    "webhook_url",
    merged_string_field(config, fallback, "webhook_url", "webhookUrl"),
  )
  set_string_field(
    account,
    "websocket_url",
    merged_string_field(config, fallback, "websocket_url", "websocketUrl"),
  )
  set_json_field(
    account,
    "websocket_headers",
    merged_value_field(
      config, fallback, "websocket_headers", "websocketHeaders",
    ),
  )
  set_string_field(
    account,
    "verify_token",
    merged_string_field(config, fallback, "verify_token", "verifyToken"),
  )
  set_string_field(
    account,
    "encryption_key",
    merged_string_field(config, fallback, "encryption_key", "encryptionKey"),
  )
  set_string_field(
    account,
    "bot_name",
    merged_string_field(config, fallback, "bot_name", "botName"),
  )
  set_string_field(
    account,
    "reaction_notifications",
    merged_string_field(
      config, fallback, "reaction_notifications", "reactionNotifications",
    ),
  )
  Some(Json::object(account))
}

///|
fn bootstrap_feishu_channel_state(config : Json) -> PersistedChannelState? {
  let channel_enabled = json_bool_field(config, "enabled", "enabled").unwrap_or(
    true,
  )
  let accounts : Map[String, Json] = {}
  let runtimes : Array[PersistedChannelAccount] = []

  match json_value_field(config, "accounts", "accounts") {
    Some(Object(account_map)) => {
      let has_default = account_map.contains("default")
      let base_account = bootstrap_feishu_account_config(config)
      if !has_default {
        match base_account {
          Some(account) => {
            accounts["default"] = account
            if channel_enabled {
              runtimes.push(PersistedChannelAccount::{
                account_id: "default",
                config: account,
                auto_start: true,
              })
            }
          }
          None => ()
        }
      }
      for account_id, account_override in account_map {
        let account = match
          bootstrap_feishu_account_config(account_override, fallback=config) {
          Some(account) => account
          None => continue
        }
        accounts[account_id] = account
        if channel_enabled {
          runtimes.push(PersistedChannelAccount::{
            account_id,
            config: account,
            auto_start: true,
          })
        }
      }
    }
    _ =>
      match bootstrap_feishu_account_config(config) {
        Some(account) => {
          accounts["default"] = account
          if channel_enabled {
            runtimes.push(PersistedChannelAccount::{
              account_id: "default",
              config: account,
              auto_start: true,
            })
          }
        }
        None => return None
      }
  }
  let global_settings_map : Map[String, Json] = {}
  set_string_field(
    global_settings_map,
    "group_policy",
    json_string_field(config, "group_policy", "groupPolicy"),
  )
  set_json_field(
    global_settings_map,
    "allow_from",
    json_value_field(config, "allow_from", "allowFrom"),
  )
  let global_settings = Json::object(global_settings_map)
  let channel_config = @channel.ChannelConfig::{
    enabled: channel_enabled,
    accounts,
    global_settings,
  }
  Some(PersistedChannelState::{
    channel_id: "feishu",
    config: channel_config,
    accounts: runtimes,
  })
}

///|
fn bootstrap_weixin_account_config(
  config : Json,
  fallback? : Json = {},
) -> Json? {
  let app_id = match merged_string_field(config, fallback, "app_id", "appId") {
    Some(value) => value
    None => return None
  }
  let app_secret = match
    merged_string_field(config, fallback, "app_secret", "appSecret") {
    Some(value) => value
    None => return None
  }
  let token = match merged_string_field(config, fallback, "token", "token") {
    Some(value) => value
    None => return None
  }
  let enabled = merged_bool_field(config, fallback, "enabled", "enabled").unwrap_or(
    true,
  )
  let account : Map[String, Json] = {
    "app_id": Json::string(app_id),
    "app_secret": Json::string(app_secret),
    "token": Json::string(token),
    "enabled": enabled.to_json(),
  }
  set_string_field(
    account,
    "original_id",
    merged_string_field(config, fallback, "original_id", "originalId"),
  )
  set_string_field(
    account,
    "api_base_url",
    merged_string_field(config, fallback, "api_base_url", "apiBaseUrl"),
  )
  Some(Json::object(account))
}

///|
fn bootstrap_weixin_channel_state(config : Json) -> PersistedChannelState? {
  let channel_enabled = json_bool_field(config, "enabled", "enabled").unwrap_or(
    true,
  )
  let accounts : Map[String, Json] = {}
  let runtimes : Array[PersistedChannelAccount] = []

  match json_value_field(config, "accounts", "accounts") {
    Some(Object(account_map)) => {
      let has_default = account_map.contains("default")
      let base_account = bootstrap_weixin_account_config(config)
      if !has_default {
        match base_account {
          Some(account) => {
            accounts["default"] = account
            if channel_enabled {
              runtimes.push(PersistedChannelAccount::{
                account_id: "default",
                config: account,
                auto_start: true,
              })
            }
          }
          None => ()
        }
      }
      for account_id, account_override in account_map {
        let account = match
          bootstrap_weixin_account_config(account_override, fallback=config) {
          Some(account) => account
          None => continue
        }
        accounts[account_id] = account
        if channel_enabled {
          runtimes.push(PersistedChannelAccount::{
            account_id,
            config: account,
            auto_start: true,
          })
        }
      }
    }
    _ =>
      match bootstrap_weixin_account_config(config) {
        Some(account) => {
          accounts["default"] = account
          if channel_enabled {
            runtimes.push(PersistedChannelAccount::{
              account_id: "default",
              config: account,
              auto_start: true,
            })
          }
        }
        None => return None
      }
  }
  let global_settings_map : Map[String, Json] = {}
  set_json_field(
    global_settings_map,
    "allow_from",
    json_value_field(config, "allow_from", "allowFrom"),
  )
  let global_settings = Json::object(global_settings_map)
  let channel_config = @channel.ChannelConfig::{
    enabled: channel_enabled,
    accounts,
    global_settings,
  }
  Some(PersistedChannelState::{
    channel_id: "weixin",
    config: channel_config,
    accounts: runtimes,
  })
}

///|
async fn bootstrap_channel_states_from_moonclaw_config(
  home : String,
  cwd : String,
) -> Array[PersistedChannelState] {
  let json = match moonclaw_config_json(home, cwd) {
    Some(json) => json
    None => return []
  }
  match json {
    { "channels": Object(channels), .. } => {
      let states : Array[PersistedChannelState] = []
      match channels.get("feishu") {
        Some(feishu) =>
          match bootstrap_feishu_channel_state(feishu) {
            Some(state) => states.push(state)
            None => ()
          }
        None => ()
      }
      match channels.get("weixin") {
        Some(weixin) =>
          match bootstrap_weixin_channel_state(weixin) {
            Some(state) => states.push(state)
            None => ()
          }
        None => ()
      }
      states
    }
    _ => []
  }
}

///|
async fn Gateway::seed_channel_state_from_moonclaw_config(
  self : Gateway,
) -> Unit {
  seed_channel_state_from_moonclaw_config(
    self.channel_state,
    self.home,
    self.cwd,
  )
}

///|
async fn seed_channel_state_from_moonclaw_config(
  store : ChannelStateStore,
  home : String,
  cwd : String,
) -> Unit {
  let bootstrap_states = bootstrap_channel_states_from_moonclaw_config(
    home, cwd,
  )
  for state in bootstrap_states {
    if store.states.get(state.channel_id) is None {
      store.states.set(state.channel_id, state)
    }
  }
}
