///|
struct ChannelEntry {
  channel : &Channel
  mut config : ChannelConfig
  mut running_accounts : Array[String]
}

///|
pub struct ChannelRegistry {
  priv channels : Map[String, ChannelEntry]
}

///|
pub fn ChannelRegistry::new() -> ChannelRegistry {
  ChannelRegistry::{ channels: {} }
}

///|
pub fn ChannelRegistry::register(
  self : ChannelRegistry,
  channel : &Channel,
) -> Unit {
  let channel_id = channel.id()
  self.channels[channel_id] = ChannelEntry::{
    channel,
    config: default_config(),
    running_accounts: [],
  }
}

///|
pub fn ChannelRegistry::get(
  self : ChannelRegistry,
  id : ChannelId,
) -> &Channel? {
  match self.channels.get(id) {
    Some(entry) => Some(entry.channel)
    None => None
  }
}

///|
pub fn ChannelRegistry::get_entry(
  self : ChannelRegistry,
  id : ChannelId,
) -> ChannelEntry? {
  self.channels.get(id)
}

///|
pub fn ChannelRegistry::configure(
  self : ChannelRegistry,
  id : ChannelId,
  config : ChannelConfig,
) -> Result[Unit, ChannelError] {
  match self.channels.get(id) {
    Some(entry) => {
      entry.config = config
      entry.channel.configure(config)
      Ok(())
    }
    None => Err(ChannelError::Unknown(message="Channel not found: \{id}"))
  }
}

///|
pub async fn ChannelRegistry::start(
  self : ChannelRegistry,
  id : ChannelId,
  account_id : String,
  config : Json,
) -> Result[Unit, ChannelError] {
  match self.channels.get(id) {
    Some(entry) =>
      match entry.channel.start(account_id, config) {
        Ok(_) => {
          if !entry.running_accounts.contains(account_id) {
            entry.running_accounts.push(account_id)
          }
          Ok(())
        }
        Err(e) => Err(e)
      }
    None => Err(ChannelError::Unknown(message="Channel not found: \{id}"))
  }
}

///|
pub async fn ChannelRegistry::stop(
  self : ChannelRegistry,
  id : ChannelId,
  account_id : String,
) -> Result[Unit, ChannelError] {
  match self.channels.get(id) {
    Some(entry) =>
      match entry.channel.stop(account_id) {
        Ok(_) => {
          entry.running_accounts = entry.running_accounts.filter(fn(acc) {
            acc != account_id
          })
          Ok(())
        }
        Err(e) => Err(e)
      }
    None => Err(ChannelError::Unknown(message="Channel not found: \{id}"))
  }
}

///|
pub fn ChannelRegistry::list_channels(
  self : ChannelRegistry,
) -> Array[ChannelDock] {
  self.channels
  .values()
  .map(fn(entry) {
    ChannelDock::{
      id: entry.channel.id(),
      meta: entry.channel.meta(),
      capabilities: entry.channel.capabilities(),
      is_configured: entry.config.enabled,
      is_running: not(entry.running_accounts.is_empty()),
      account_ids: entry.running_accounts,
      outbound: None,
      streaming: None,
    }
  })
  .to_array()
}

///|
pub fn ChannelRegistry::get_dock(
  self : ChannelRegistry,
  id : ChannelId,
) -> ChannelDock? {
  match self.channels.get(id) {
    Some(entry) =>
      Some(ChannelDock::{
        id: entry.channel.id(),
        meta: entry.channel.meta(),
        capabilities: entry.channel.capabilities(),
        is_configured: entry.config.enabled,
        is_running: not(entry.running_accounts.is_empty()),
        account_ids: entry.running_accounts,
        outbound: None,
        streaming: None,
      })
    None => None
  }
}
