///|
pub struct ChannelManager {
  registry : @channel.ChannelRegistry
}

///|
pub fn ChannelManager::new(_logger : @pino.Logger) -> ChannelManager {
  ChannelManager::{ registry: @channel.ChannelRegistry::new() }
}

///|
pub fn ChannelManager::register_channel(
  self : ChannelManager,
  channel : &@channel.Channel,
) -> Unit {
  ignore(channel.id())
  self.registry.register(channel)
}

///|
pub fn ChannelManager::configure_channel(
  self : ChannelManager,
  id : @channel.ChannelId,
  config : @channel.ChannelConfig,
) -> Result[Unit, @channel.ChannelError] {
  self.registry.configure(id, config)
}

///|
pub async fn ChannelManager::start_channel(
  self : ChannelManager,
  id : @channel.ChannelId,
  account_id : String,
  config : Json,
) -> Result[Unit, @channel.ChannelError] {
  self.registry.start(id, account_id, config)
}

///|
pub async fn ChannelManager::stop_channel(
  self : ChannelManager,
  id : @channel.ChannelId,
  account_id : String,
) -> Result[Unit, @channel.ChannelError] {
  self.registry.stop(id, account_id)
}

///|
pub fn ChannelManager::list_channels(
  self : ChannelManager,
) -> Array[@channel.ChannelDock] {
  self.registry.list_channels()
}

///|
pub fn ChannelManager::get_channel_dock(
  self : ChannelManager,
  id : @channel.ChannelId,
) -> @channel.ChannelDock? {
  self.registry.get_dock(id)
}

///|
pub async fn ChannelManager::send_message(
  self : ChannelManager,
  channel_id : @channel.ChannelId,
  to : String,
  message : @channel.Message,
  account_id : String?,
) -> Result[@channel.SendResult, @channel.ChannelError] {
  match self.registry.get(channel_id) {
    Some(channel) => channel.send(to, message, account_id)
    None =>
      Err(
        @channel.ChannelError::NotConfigured(
          message="Channel not found: \{channel_id}",
        ),
      )
  }
}
