///|
async test "bootstrap_channel_states_from_moonclaw_config normalizes camelCase feishu config" {
  @fsx.with_temporary_directory("gateway-bootstrap-XXXXXX", dir => {
    let home_config_dir = @path.Path(dir)
      .join(@path.Path(".moonclaw"))
      .to_string()
    @fsx.make_directory(home_config_dir, recursive=true)
    let config_path = @path.Path(home_config_dir)
      .join(@path.Path("moonclaw.json"))
      .to_string()
    @fsx.write_to_file(
      config_path,
      Json::object({
        "channels": {
          "feishu": {
            "enabled": true,
            "appId": "cli_app",
            "appSecret": "cli_secret",
            "domain": "feishu",
            "dmPolicy": "open",
            "groupPolicy": "open",
            "allowFrom": ["*"],
          },
        },
      }).stringify(),
    )

    let states = bootstrap_channel_states_from_moonclaw_config(
      dir, "/tmp/no-project",
    )
    inspect(states.length(), content="1")
    let state = states[0]
    inspect(state.channel_id, content="feishu")
    inspect(state.config.enabled, content="true")
    inspect(state.accounts.length(), content="1")
    inspect(state.accounts[0].account_id, content="default")
    inspect(
      state.accounts[0].config.stringify().contains("\"app_id\":\"cli_app\""),
      content="true",
    )
    inspect(
      state.accounts[0].config
      .stringify()
      .contains("\"app_secret\":\"cli_secret\""),
      content="true",
    )
    inspect(
      state.config.global_settings
      .stringify()
      .contains("\"group_policy\":\"open\""),
      content="true",
    )
    inspect(
      state.config.global_settings
      .stringify()
      .contains("\"allow_from\":[\"*\"]"),
      content="true",
    )
  })
}

///|
async test "bootstrap_channel_states_from_moonclaw_config reads moonclaw root home" {
  @fsx.with_temporary_directory("gateway-bootstrap-root-home-XXXXXX", dir => {
    let config_path = @path.Path(dir)
      .join(@path.Path("moonclaw.json"))
      .to_string()
    @fsx.write_to_file(
      config_path,
      Json::object({
        "channels": {
          "feishu": {
            "enabled": true,
            "appId": "root_app",
            "appSecret": "root_secret",
            "domain": "feishu",
            "connectionMode": "websocket",
          },
        },
      }).stringify(),
    )

    let states = bootstrap_channel_states_from_moonclaw_config(
      dir, "/tmp/no-project",
    )
    inspect(states.length(), content="1")
    inspect(
      states[0].accounts[0].config
      .stringify()
      .contains("\"connection_mode\":\"websocket\""),
      content="true",
    )
    inspect(
      states[0].accounts[0].config
      .stringify()
      .contains("\"app_id\":\"root_app\""),
      content="true",
    )
  })
}

///|
async test "bootstrap_channel_states_from_moonclaw_config merges base and account overrides" {
  @fsx.with_temporary_directory("gateway-bootstrap-accounts-XXXXXX", dir => {
    let home_config_dir = @path.Path(dir)
      .join(@path.Path(".moonclaw"))
      .to_string()
    @fsx.make_directory(home_config_dir, recursive=true)
    let config_path = @path.Path(home_config_dir)
      .join(@path.Path("moonclaw.json"))
      .to_string()
    @fsx.write_to_file(
      config_path,
      Json::object({
        "channels": {
          "feishu": {
            "enabled": true,
            "appId": "base-app",
            "appSecret": "base-secret",
            "domain": "feishu",
            "dmPolicy": "open",
            "accounts": {
              "ops": { "appId": "ops-app", "appSecret": "ops-secret" },
              "audit": { "dmPolicy": "pairing" },
            },
          },
        },
      }).stringify(),
    )

    let states = bootstrap_channel_states_from_moonclaw_config(
      dir, "/tmp/no-project",
    )
    inspect(states.length(), content="1")
    let state = states[0]
    inspect(state.config.accounts.length().to_string(), content="3")
    inspect(
      state.config.accounts
      .get("default")
      .unwrap()
      .stringify()
      .contains("\"app_id\":\"base-app\""),
      content="true",
    )
    inspect(
      state.config.accounts
      .get("ops")
      .unwrap()
      .stringify()
      .contains("\"app_id\":\"ops-app\""),
      content="true",
    )
    inspect(
      state.config.accounts
      .get("audit")
      .unwrap()
      .stringify()
      .contains("\"app_secret\":\"base-secret\""),
      content="true",
    )
  })
}

///|
async test "seed_channel_state_from_moonclaw_config preserves persisted state" {
  let store = ChannelStateStore::{
    path: "/tmp/unused/channels.json",
    states: {
      "feishu": PersistedChannelState::{
        channel_id: "feishu",
        config: @channel.ChannelConfig::{
          enabled: true,
          accounts: {
            "default": {
              "app_id": "persisted",
              "app_secret": "persisted-secret",
              "domain": "feishu",
              "connection_mode": "webhook",
              "dm_policy": "pairing",
              "enabled": true,
            },
          },
          global_settings: {},
        },
        accounts: [],
      },
    },
  }
  seed_channel_state_from_moonclaw_config(store, "/tmp/no-home", "/tmp/no-cwd")
  let state = match store.states.get("feishu") {
    Some(state) => state
    None => fail("expected feishu state")
  }
  inspect(
    state.config.accounts
    .get("default")
    .unwrap()
    .stringify()
    .contains("\"app_id\":\"persisted\""),
    content="true",
  )
}

///|
async test "bootstrap_channel_states_from_moonclaw_config normalizes weixin config" {
  @fsx.with_temporary_directory("gateway-bootstrap-weixin-XXXXXX", dir => {
    let home_config_dir = @path.Path(dir)
      .join(@path.Path(".moonclaw"))
      .to_string()
    @fsx.make_directory(home_config_dir, recursive=true)
    let config_path = @path.Path(home_config_dir)
      .join(@path.Path("moonclaw.json"))
      .to_string()
    @fsx.write_to_file(
      config_path,
      Json::object({
        "channels": {
          "weixin": {
            "enabled": true,
            "appId": "wx-app",
            "appSecret": "wx-secret",
            "token": "wx-token",
            "originalId": "gh_test",
            "allowFrom": ["openid-1"],
          },
        },
      }).stringify(),
    )

    let states = bootstrap_channel_states_from_moonclaw_config(
      dir, "/tmp/no-project",
    )
    inspect(states.length(), content="1")
    let state = states[0]
    inspect(state.channel_id, content="weixin")
    inspect(
      state.accounts[0].config.stringify().contains("\"app_id\":\"wx-app\""),
      content="true",
    )
    inspect(
      state.accounts[0].config
      .stringify()
      .contains("\"original_id\":\"gh_test\""),
      content="true",
    )
    inspect(
      state.config.global_settings
      .stringify()
      .contains("\"allow_from\":[\"openid-1\"]"),
      content="true",
    )
  })
}
