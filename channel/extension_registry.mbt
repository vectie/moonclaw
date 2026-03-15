///|
/// Registry for managing channel extensions
pub struct ExtensionRegistry {
  priv extensions : Map[String, &ChannelExtension]
  priv path_to_channel : Map[String, String]
  mut message_handler : &MessageHandler?
  mut context : ExtensionContext?
}

///|
pub fn ExtensionRegistry::new() -> ExtensionRegistry {
  ExtensionRegistry::{
    extensions: {},
    path_to_channel: {},
    message_handler: None,
    context: None,
  }
}

///|
/// Set the extension context for lifecycle callbacks
pub fn ExtensionRegistry::set_context(
  self : ExtensionRegistry,
  context : ExtensionContext,
) -> Unit {
  self.context = Some(context)
}

///|
/// Register a channel extension
pub fn ExtensionRegistry::register(
  self : ExtensionRegistry,
  extension : &ChannelExtension,
) -> Unit raise {
  let channel_id = extension.id()
  let webhook_path = extension.webhook_path()

  match self.path_to_channel.get(webhook_path) {
    Some(existing) =>
      if existing != channel_id {
        raise ExtensionError(
          message="Webhook path '\{webhook_path}' is already registered by channel '\{existing}'",
        )
      }
    None => ()
  }

  self.extensions[channel_id] = extension
  self.path_to_channel[webhook_path] = channel_id

  match self.context {
    Some(ctx) => extension.on_register(ctx)
    None => ()
  }
}

///|
/// Register a channel extension with context
pub fn ExtensionRegistry::register_with_context(
  self : ExtensionRegistry,
  extension : &ChannelExtension,
  context : ExtensionContext,
) -> Unit raise {
  let channel_id = extension.id()
  let webhook_path = extension.webhook_path()

  match self.path_to_channel.get(webhook_path) {
    Some(existing) =>
      if existing != channel_id {
        raise ExtensionError(
          message="Webhook path '\{webhook_path}' is already registered by channel '\{existing}'",
        )
      }
    None => ()
  }

  self.extensions[channel_id] = extension
  self.path_to_channel[webhook_path] = channel_id
  extension.on_register(context)
}

///|
/// Unregister a channel extension
pub fn ExtensionRegistry::unregister(
  self : ExtensionRegistry,
  channel_id : String,
) -> Unit {
  match self.extensions.get(channel_id) {
    Some(extension) => {
      extension.on_unregister()
      let path = extension.webhook_path()
      self.path_to_channel.remove(path)
      self.extensions.remove(channel_id)
    }
    None => ()
  }
}

///|
/// Get an extension by channel ID
pub fn ExtensionRegistry::get(
  self : ExtensionRegistry,
  channel_id : String,
) -> &ChannelExtension? {
  self.extensions.get(channel_id)
}

///|
/// Get an extension by webhook path
pub fn ExtensionRegistry::get_by_path(
  self : ExtensionRegistry,
  path : String,
) -> &ChannelExtension? {
  match self.path_to_channel.get(path) {
    Some(channel_id) => self.extensions.get(channel_id)
    None => None
  }
}

///|
/// Check if a webhook path is registered
pub fn ExtensionRegistry::has_path(
  self : ExtensionRegistry,
  path : String,
) -> Bool {
  self.path_to_channel.contains(path)
}

///|
/// Get all registered webhook paths
pub fn ExtensionRegistry::get_webhook_paths(
  self : ExtensionRegistry,
) -> Array[String] {
  self.path_to_channel.keys().to_array()
}

///|
/// Get all registered extensions
pub fn ExtensionRegistry::list_extensions(
  self : ExtensionRegistry,
) -> Array[ExtensionInfo] {
  self.extensions
  .values()
  .map(fn(extension) {
    ExtensionInfo::{
      channel_id: extension.id(),
      webhook_path: extension.webhook_path(),
      supports_websocket: extension.supports_websocket(),
      allowed_methods: extension.allowed_methods(),
      dock_config: extension.dock_config(),
    }
  })
  .to_array()
}

///|
/// Set the message handler for processing incoming messages
pub fn ExtensionRegistry::set_message_handler(
  self : ExtensionRegistry,
  handler : &MessageHandler,
) -> Unit {
  self.message_handler = Some(handler)
}

///|
/// Get the current message handler
pub fn ExtensionRegistry::get_message_handler(
  self : ExtensionRegistry,
) -> &MessageHandler? {
  self.message_handler
}

///|
/// Handle a webhook request by path
pub async fn ExtensionRegistry::handle_webhook(
  self : ExtensionRegistry,
  path : String,
  request : ExtensionRequest,
) -> ExtensionResponse {
  match self.get_by_path(path) {
    Some(extension) => extension.handle_webhook(request)
    None =>
      raise ExtensionError(message="No extension registered for path: \{path}")
  }
}

///|
/// Get dock configuration for a channel
pub fn ExtensionRegistry::get_dock_config(
  self : ExtensionRegistry,
  channel_id : String,
) -> ChannelDockConfig? {
  match self.extensions.get(channel_id) {
    Some(extension) => Some(extension.dock_config())
    None => None
  }
}

///|
/// Get all dock configurations
pub fn ExtensionRegistry::list_dock_configs(
  self : ExtensionRegistry,
) -> Map[String, ChannelDockConfig] {
  let result : Map[String, ChannelDockConfig] = {}
  for channel_id, extension in self.extensions {
    result[channel_id] = extension.dock_config()
  }
  result
}

///|
/// Information about a registered extension
pub(all) struct ExtensionInfo {
  channel_id : String
  webhook_path : String
  supports_websocket : Bool
  allowed_methods : Array[String]
  dock_config : ChannelDockConfig
}

///|
pub fn ExtensionInfo::channel_id(self : ExtensionInfo) -> String {
  self.channel_id
}

///|
pub fn ExtensionInfo::webhook_path(self : ExtensionInfo) -> String {
  self.webhook_path
}

///|
pub fn ExtensionInfo::supports_websocket(self : ExtensionInfo) -> Bool {
  self.supports_websocket
}

///|
pub fn ExtensionInfo::allowed_methods(self : ExtensionInfo) -> Array[String] {
  self.allowed_methods
}

///|
pub fn ExtensionInfo::dock_config(self : ExtensionInfo) -> ChannelDockConfig {
  self.dock_config
}
