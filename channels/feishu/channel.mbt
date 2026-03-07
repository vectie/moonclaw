///|
struct FeishuChannelState {
  mut config : @channel.ChannelConfig
  mut feishu_configs : Map[String, FeishuAccountConfig]
  clients : Map[String, FeishuClient]
  running : Map[String, Bool]
  mut message_handler : &@channel.MessageHandler?
}

///|
pub struct FeishuChannel {
  priv state : FeishuChannelState
}

///|
pub fn FeishuChannel::new() -> FeishuChannel {
  FeishuChannel::{
    state: FeishuChannelState::{
      config: @channel.default_config(),
      feishu_configs: {},
      clients: {},
      running: {},
      message_handler: None,
    },
  }
}

///|
fn get_feishu_config(config : Json) -> FeishuAccountConfig {
  @json.from_json(config) catch {
    _ =>
      FeishuAccountConfig::{
        app_id: "",
        app_secret: "",
        domain: "feishu",
        connection_mode: "webhook",
        dm_policy: "pairing",
        bot_name: None,
        webhook_url: None,
        verify_token: None,
        encryption_key: None,
        enabled: false,
      }
  }
}

///|
pub fn FeishuChannel::set_message_handler(
  self : FeishuChannel,
  handler : &@channel.MessageHandler,
) -> Unit {
  self.state.message_handler = Some(handler)
}

///|
impl @channel.Channel for FeishuChannel with id(self : FeishuChannel) -> @channel.ChannelId {
  "feishu"
}

///|
impl @channel.Channel for FeishuChannel with meta(self : FeishuChannel) -> @channel.ChannelMeta {
  @channel.ChannelMeta::{
    id: "feishu",
    label: "Feishu",
    selection_label: "Feishu/Lark (飞书)",
    docs_path: "/channels/feishu",
    docs_label: Some("feishu"),
    blurb: "飞书/Lark enterprise messaging.",
    order: Some(70),
    aliases: ["lark"],
  }
}

///|
impl @channel.Channel for FeishuChannel with capabilities(self : FeishuChannel) -> @channel.ChannelCapabilities {
  @channel.ChannelCapabilities::{
    chat_types: [@channel.ChatType::Direct, @channel.ChatType::Channel],
    polls: false,
    reactions: true,
    edit: true,
    unsend: false,
    reply: true,
    effects: false,
    group_management: false,
    threads: true,
    media: true,
    native_commands: false,
    block_streaming: false,
  }
}

///|
impl @channel.Channel for FeishuChannel with configure(
  self : FeishuChannel,
  config : @channel.ChannelConfig,
) -> Unit {
  self.state.config = config
  self.state.feishu_configs = {}
  for account_id, account_config in config.accounts {
    self.state.feishu_configs[account_id] = get_feishu_config(account_config)
  }
}

///|
impl @channel.Channel for FeishuChannel with start(
  self : FeishuChannel,
  account_id : String,
  config : Json,
) -> Result[Unit, @channel.ChannelError] {
  let feishu_config = get_feishu_config(config)
  if !feishu_config.enabled {
    return Err(
      @channel.ChannelError::NotConfigured(message="Channel is not enabled"),
    )
  }

  let client = FeishuClient::new(feishu_config)
  self.state.clients[account_id] = client
  self.state.running[account_id] = true

  Ok(())
}

///|
impl @channel.Channel for FeishuChannel with stop(
  self : FeishuChannel,
  account_id : String,
) -> Result[Unit, @channel.ChannelError] {
  self.state.clients.remove(account_id)
  self.state.running[account_id] = false
  Ok(())
}

///|
impl @channel.Channel for FeishuChannel with send(
  self : FeishuChannel,
  to : String,
  message : @channel.Message,
  account_id : String?,
) -> Result[@channel.SendResult, @channel.ChannelError] {
  let actual_account_id = match account_id {
    Some(id) => id
    None => {
      let running_keys = self.state.running
        .keys()
        .filter(fn(k) {
          match self.state.running.get(k) {
            Some(true) => true
            _ => false
          }
        })
        .to_array()
      if running_keys.length() > 0 {
        running_keys[0]
      } else {
        return Err(
          @channel.ChannelError::NotConfigured(
            message="No running account available",
          ),
        )
      }
    }
  }

  match self.state.clients.get(actual_account_id) {
    Some(client) => client.send_text_message(to, message.content)
    None =>
      Err(
        @channel.ChannelError::NotConfigured(
          message="Client not initialized for account: \{actual_account_id}",
        ),
      )
  }
}

///|
impl @channel.Channel for FeishuChannel with handle_event(
  self : FeishuChannel,
  event : @channel.ChannelEvent,
) -> Unit {

}

///|
impl @channel.Channel for FeishuChannel with is_running(
  self : FeishuChannel,
  account_id : String,
) -> Bool {
  match self.state.running.get(account_id) {
    Some(running) => running
    None => false
  }
}

///|
impl @channel.ChannelExtension for FeishuChannel with webhook_path(
  self : FeishuChannel,
) -> String {
  "/webhook/feishu"
}

///|
impl @channel.ChannelExtension for FeishuChannel with handle_webhook(
  self : FeishuChannel,
  request : @channel.ExtensionRequest,
) -> @channel.ExtensionResponse {
  let json = request.json() catch {
    _ => return @channel.ExtensionResponse::bad_request(message="Invalid JSON")
  }

  match request.http_method() {
    "POST" => {
      // Parse Feishu event
      let event_type = match json {
        { "header": { "event_type": String(event_type), .. }, .. } => event_type
        _ =>
          return @channel.ExtensionResponse::bad_request(
            message="Missing event_type in request",
          )
      }

      // Handle URL verification challenge
      if event_type == "url_verification" {
        let challenge = match json {
          { "challenge": String(challenge), .. } => challenge
          _ =>
            return @channel.ExtensionResponse::bad_request(
              message="Missing challenge in verification request",
            )
        }
        return @channel.ExtensionResponse::json({ "challenge": challenge })
      }

      // Handle message received event
      if event_type == "im.message.receive_v1" {
        return self.handle_feishu_message(json)
      }

      // For other events, just acknowledge
      @channel.ExtensionResponse::ok()
    }
    "GET" =>
      // Health check
      @channel.ExtensionResponse::ok()
    _ =>
      @channel.ExtensionResponse::bad_request(
        message="Method not allowed: \{request.http_method()}",
      )
  }
}

///|
fn FeishuChannel::handle_feishu_message(
  self : FeishuChannel,
  json : Json,
) -> @channel.ExtensionResponse {
  let event_data = match json {
    { "event": event, .. } => event
    _ =>
      return @channel.ExtensionResponse::bad_request(
        message="Missing event data",
      )
  }

  let message_id = match event_data {
    { "message_id": String(id), .. } => id
    _ =>
      return @channel.ExtensionResponse::bad_request(
        message="Missing message_id",
      )
  }

  let chat_type = match event_data {
    { "chat_type": String(ct), .. } => ct
    _ => "personal"
  }

  let content = match event_data {
    { "content": String(c), .. } => c
    _ =>
      return @channel.ExtensionResponse::bad_request(message="Missing content")
  }

  let from_user_id = match event_data {
    { "sender_id": { "user_id": String(uid), .. }, .. } => uid
    _ =>
      return @channel.ExtensionResponse::bad_request(
        message="Missing sender_id",
      )
  }

  let chat_id = match event_data {
    { "chat_id": String(cid), .. } => cid
    _ =>
      return @channel.ExtensionResponse::bad_request(message="Missing chat_id")
  }

  let timestamp = match event_data {
    { "create_time": String(ts), .. } => @strconv.parse_int(ts) catch { _ => 0 }
    _ => 0
  }

  // Create channel message
  let message = @channel.Message::{
    id: message_id,
    channel: "feishu",
    from: from_user_id,
    to: chat_id,
    content,
    content_type: "text",
    timestamp,
    thread_id: None,
    reply_to: None,
    attachments: [],
  }

  // Process through message handler if available
  match self.state.message_handler {
    Some(handler) => {
      let account_id = "default" // TODO: Extract from event
      try {
        let response_message = handler.handle_message(
          "feishu", account_id, message,
        )
        // Send response back through Feishu
        match self.send(response_message.from, response_message, None) {
          Ok(_) => @channel.ExtensionResponse::ok()
          Err(e) =>
            @channel.ExtensionResponse::internal_error(
              message="Failed to send response: \{e}",
            )
        }
      } catch {
        e =>
          @channel.ExtensionResponse::internal_error(
            message="Error processing message: \{e}",
          )
      }
    }
    None =>
      // No handler, just acknowledge
      @channel.ExtensionResponse::ok()
  }
}

///|
impl @channel.ChannelExtension for FeishuChannel with supports_websocket(
  self : FeishuChannel,
) -> Bool {
  false
}

///|
impl @channel.ChannelExtension for FeishuChannel with handle_websocket(
  self : FeishuChannel,
  conn : @channel.WebSocketConnection,
) -> Unit {

}

///|
impl @channel.ChannelExtension for FeishuChannel with allowed_methods(
  self : FeishuChannel,
) -> Array[String] {
  ["POST", "GET"]
}

///|
impl @channel.ChannelExtension for FeishuChannel with dock_config(
  self : FeishuChannel,
) -> @channel.ChannelDockConfig {
  @channel.ChannelDockConfig::default_for_channel("feishu")
}

///|
impl @channel.ChannelExtension for FeishuChannel with on_register(
  self : FeishuChannel,
  context : @channel.ExtensionContext,
) -> Unit {
  match context.logger() {
    Some(logger) => (logger.info)("Feishu channel extension registered")
    None => ()
  }
}

///|
impl @channel.ChannelExtension for FeishuChannel with on_unregister(
  self : FeishuChannel,
) -> Unit {
  for account_id in self.state.running.keys() {
    ignore(self.stop(account_id.to_string()))
  }
}
