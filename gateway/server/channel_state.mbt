///|
fn ChannelStateStore::state_file(self : ChannelStateStore) -> String {
  self.path
}

///|
pub async fn ChannelStateStore::load(self : ChannelStateStore) -> Unit {
  if !@fsx.exists(self.state_file()) {
    return
  }
  let content = @fsx.read_file(self.state_file())
  let loaded : Array[PersistedChannelState] = @json.from_json(
    @json.parse(content),
  ) catch {
    error =>
      fail("Failed to load channel state from \{self.state_file()}: \{error}")
  }
  let existing = self.states.keys().to_array()
  for key in existing {
    self.states.remove(key)
  }
  for state in loaded {
    self.states.set(state.channel_id, state)
  }
}

///|
pub async fn ChannelStateStore::save(self : ChannelStateStore) -> Unit {
  let states : Array[PersistedChannelState] = self.states.values().to_array()
  @fsx.write_to_file(self.state_file(), states.to_json().stringify())
}

///|
fn ensure_channel_state(
  store : ChannelStateStore,
  channel_id : String,
) -> PersistedChannelState {
  match store.states.get(channel_id) {
    Some(state) => state
    None =>
      PersistedChannelState::{
        channel_id,
        config: @channel.default_config(),
        accounts: [],
      }
  }
}

///|
pub async fn ChannelStateStore::save_config(
  self : ChannelStateStore,
  channel_id : String,
  config : @channel.ChannelConfig,
) -> Unit {
  let state = ensure_channel_state(self, channel_id)
  let allowed_accounts = config.accounts.keys().to_array()
  let accounts = state.accounts.filter(fn(account) {
    allowed_accounts.contains(account.account_id)
  })
  self.states.set(channel_id, PersistedChannelState::{
    channel_id,
    config,
    accounts,
  })
  self.save()
}

///|
pub async fn ChannelStateStore::save_account_runtime(
  self : ChannelStateStore,
  channel_id : String,
  account_id : String,
  config : Json,
  auto_start : Bool,
) -> Unit {
  let state = ensure_channel_state(self, channel_id)
  let accounts = state.accounts.filter(fn(account) {
    account.account_id != account_id
  })
  accounts.push(PersistedChannelAccount::{ account_id, config, auto_start })
  self.states.set(channel_id, PersistedChannelState::{
    channel_id,
    config: state.config,
    accounts,
  })
  self.save()
}

///|
pub fn ChannelStateStore::list_states(
  self : ChannelStateStore,
) -> Array[PersistedChannelState] {
  self.states.values().to_array()
}

///|
pub async fn ChannelManager::restore_states(
  self : ChannelManager,
  logger : @pino.Logger,
  states : Array[PersistedChannelState],
) -> Unit {
  for state in states {
    match self.configure_channel(state.channel_id, state.config) {
      Ok(_) => ()
      Err(error) => {
        logger.warn(
          "Failed to restore channel config for \{state.channel_id}: \{error}",
        )
        continue
      }
    }
    for account in state.accounts {
      if !account.auto_start {
        continue
      }
      match
        self.start_channel(state.channel_id, account.account_id, account.config) {
        Ok(_) => ()
        Err(error) =>
          logger.warn(
            "Failed to restore channel account \{state.channel_id}/\{account.account_id}: \{error}",
          )
      }
    }
  }
}

///|
pub async fn Gateway::restore_channel_runtime(self : Gateway) -> Unit {
  self.channel_manager.restore_states(
    self.logger,
    self.channel_state.list_states(),
  )
}
