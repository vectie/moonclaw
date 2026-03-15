///|
test "configured dm policy prefers runtime account config" {
  let store = ChannelStateStore::{ path: "unused", states: {} }
  store.states["feishu"] = PersistedChannelState::{
    channel_id: "feishu",
    config: @channel.ChannelConfig::{
      enabled: true,
      accounts: { "default": { "dm_policy": "open" } },
      global_settings: {},
    },
    accounts: [
      PersistedChannelAccount::{
        account_id: "default",
        config: { "dm_policy": "pairing" },
        auto_start: true,
      },
    ],
  }
  inspect(configured_dm_policy(store, "feishu", "default"), content="pairing")
}

///|
test "configured dm policy falls back to persisted channel config" {
  let store = ChannelStateStore::{ path: "unused", states: {} }
  store.states["feishu"] = PersistedChannelState::{
    channel_id: "feishu",
    config: @channel.ChannelConfig::{
      enabled: true,
      accounts: { "default": { "dmPolicy": "open" } },
      global_settings: {},
    },
    accounts: [],
  }
  inspect(configured_dm_policy(store, "feishu", "default"), content="open")
}
