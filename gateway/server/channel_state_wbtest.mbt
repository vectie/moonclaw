///|
async test "ChannelStateStore persists channel config and runtime intent" {
  @fsx.with_temporary_directory("gateway-channel-state-XXXXXX", dir => {
    let path = @path.Path(dir).join(@path.Path("channels.json")).to_string()
    let store = ChannelStateStore::{ path, states: {} }
    let account_config : Json = {
      "app_id": "app-1",
      "app_secret": "secret-1",
      "domain": "feishu",
      "connection_mode": "webhook",
      "dm_policy": "pairing",
      "enabled": true,
    }
    let config = @channel.ChannelConfig::{
      enabled: true,
      accounts: { "default": account_config },
      global_settings: {},
    }
    store.save_config("feishu", config)
    store.save_account_runtime("feishu", "default", account_config, true)

    let reloaded = ChannelStateStore::{ path, states: {} }
    reloaded.load()
    let state = match reloaded.states.get("feishu") {
      Some(state) => state
      None => fail("expected persisted channel state")
    }
    inspect(state.config.enabled, content="true")
    inspect(state.accounts.length(), content="1")
    inspect(state.accounts[0].account_id, content="default")
    inspect(state.accounts[0].auto_start, content="true")
  })
}

///|
async test "ChannelManager::restore_states restores configured running accounts" {
  @fsx.with_temporary_directory("gateway-home-XXXXXX", dir => {
    let gateway_dir = @path.Path(dir).join(@path.Path("gateway")).to_string()
    @fsx.make_directory(gateway_dir, recursive=true)
    let path = @path.Path(gateway_dir)
      .join(@path.Path("channels.json"))
      .to_string()
    let store = ChannelStateStore::{ path, states: {} }
    let account_config : Json = {
      "app_id": "app-1",
      "app_secret": "secret-1",
      "domain": "feishu",
      "connection_mode": "webhook",
      "dm_policy": "pairing",
      "enabled": true,
    }
    let config = @channel.ChannelConfig::{
      enabled: true,
      accounts: { "default": account_config },
      global_settings: {},
    }
    store.save_config("feishu", config)
    store.save_account_runtime("feishu", "default", account_config, true)
    store.load()

    let manager = ChannelManager::new(
      @pino.logger("channel-manager-test", @pino.Transport::console()),
    )
    let feishu_channel = @feishu.FeishuChannel::new()
    feishu_channel.with_extension(extension => {
      manager.register_channel(extension)
    })
    let weixin_channel = @weixin.WeixinChannel::new()
    weixin_channel.with_extension(extension => {
      manager.register_channel(extension)
    })
    manager.restore_states(
      @pino.logger("channel-restore-test", @pino.Transport::console()),
      store.list_states(),
    )
    let dock = match manager.get_channel_dock("feishu") {
      Some(dock) => dock
      None => fail("expected feishu dock after restore")
    }
    inspect(dock.is_configured, content="true")
    inspect(dock.is_running, content="true")
    json_inspect(dock.account_ids, content=["default"])
  })
}

///|
async test "ChannelStateStore keeps stopped accounts persisted but not auto-started on restore" {
  @fsx.with_temporary_directory("gateway-home-XXXXXX", dir => {
    let gateway_dir = @path.Path(dir).join(@path.Path("gateway")).to_string()
    @fsx.make_directory(gateway_dir, recursive=true)
    let path = @path.Path(gateway_dir)
      .join(@path.Path("channels.json"))
      .to_string()
    let store = ChannelStateStore::{ path, states: {} }
    let account_config : Json = {
      "app_id": "app-1",
      "app_secret": "secret-1",
      "domain": "feishu",
      "connection_mode": "webhook",
      "dm_policy": "pairing",
      "enabled": true,
    }
    let config = @channel.ChannelConfig::{
      enabled: true,
      accounts: { "default": account_config },
      global_settings: {},
    }
    store.save_config("feishu", config)
    store.save_account_runtime("feishu", "default", account_config, true)
    store.save_account_runtime("feishu", "default", {}, false)

    let reloaded = ChannelStateStore::{ path, states: {} }
    reloaded.load()
    let state = match reloaded.states.get("feishu") {
      Some(state) => state
      None => fail("expected persisted channel state")
    }
    inspect(state.accounts.length(), content="1")
    inspect(state.accounts[0].auto_start, content="false")

    let manager = ChannelManager::new(
      @pino.logger("channel-manager-test", @pino.Transport::console()),
    )
    let feishu_channel = @feishu.FeishuChannel::new()
    feishu_channel.with_extension(extension => {
      manager.register_channel(extension)
    })
    let weixin_channel = @weixin.WeixinChannel::new()
    weixin_channel.with_extension(extension => {
      manager.register_channel(extension)
    })
    manager.restore_states(
      @pino.logger("channel-restore-test", @pino.Transport::console()),
      reloaded.list_states(),
    )
    let dock = match manager.get_channel_dock("feishu") {
      Some(dock) => dock
      None => fail("expected feishu dock after restore")
    }
    inspect(dock.is_configured, content="true")
    inspect(dock.is_running, content="false")
    json_inspect(dock.account_ids, content=[])
  })
}

///|
async test "ChannelStateStore prunes runtime state for accounts removed from config" {
  @fsx.with_temporary_directory("gateway-channel-state-XXXXXX", dir => {
    let path = @path.Path(dir).join(@path.Path("channels.json")).to_string()
    let store = ChannelStateStore::{ path, states: {} }
    let default_account : Json = {
      "app_id": "app-1",
      "app_secret": "secret-1",
      "domain": "feishu",
      "connection_mode": "webhook",
      "dm_policy": "pairing",
      "enabled": true,
    }
    let backup_account : Json = {
      "app_id": "app-2",
      "app_secret": "secret-2",
      "domain": "feishu",
      "connection_mode": "webhook",
      "dm_policy": "pairing",
      "enabled": true,
    }
    store.save_config("feishu", @channel.ChannelConfig::{
      enabled: true,
      accounts: { "default": default_account, "backup": backup_account },
      global_settings: {},
    })
    store.save_account_runtime("feishu", "default", default_account, true)
    store.save_account_runtime("feishu", "backup", backup_account, true)
    store.save_config("feishu", @channel.ChannelConfig::{
      enabled: true,
      accounts: { "default": default_account },
      global_settings: {},
    })

    let reloaded = ChannelStateStore::{ path, states: {} }
    reloaded.load()
    let state = match reloaded.states.get("feishu") {
      Some(state) => state
      None => fail("expected persisted channel state")
    }
    inspect(state.accounts.length(), content="1")
    inspect(state.accounts[0].account_id, content="default")
    inspect(state.accounts[0].auto_start, content="true")
  })
}

///|
async test "ChannelManager::restore_states restores configured Weixin account" {
  @fsx.with_temporary_directory("gateway-weixin-home-XXXXXX", dir => {
    let gateway_dir = @path.Path(dir).join(@path.Path("gateway")).to_string()
    @fsx.make_directory(gateway_dir, recursive=true)
    let path = @path.Path(gateway_dir)
      .join(@path.Path("channels.json"))
      .to_string()
    let store = ChannelStateStore::{ path, states: {} }
    let account_config : Json = {
      "app_id": "wx-app",
      "app_secret": "wx-secret",
      "token": "wx-token",
      "original_id": "gh_test",
      "enabled": true,
    }
    let config = @channel.ChannelConfig::{
      enabled: true,
      accounts: { "default": account_config },
      global_settings: {},
    }
    store.save_config("weixin", config)
    store.save_account_runtime("weixin", "default", account_config, true)
    store.load()

    let manager = ChannelManager::new(
      @pino.logger("channel-manager-test", @pino.Transport::console()),
    )
    let weixin_channel = @weixin.WeixinChannel::new()
    weixin_channel.with_extension(extension => {
      manager.register_channel(extension)
    })
    manager.restore_states(
      @pino.logger("channel-restore-test", @pino.Transport::console()),
      store.list_states(),
    )
    let dock = match manager.get_channel_dock("weixin") {
      Some(dock) => dock
      None => fail("expected weixin dock after restore")
    }
    inspect(dock.is_configured, content="true")
    inspect(dock.is_running, content="true")
    json_inspect(dock.account_ids, content=["default"])
  })
}
