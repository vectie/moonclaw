///|
struct FeishuChannelState {
  mut _config : @channel.ChannelConfig
  mut feishu_configs : Map[String, FeishuAccountConfig]
  clients : Map[String, FeishuClient]
  running : Map[String, Bool]
  mut user_name_cache : Map[String, String]
  mut active_monitor_connections : Map[String, @channel.WebSocketConnection]
  mut extension_context : @channel.ExtensionContext?
  recent_event_ids : Array[String]
  recent_message_ids : Array[String]
  pending_messages : Map[String, Array[QueuedFeishuMessage]]
  processing_keys : Map[String, Bool]
  cancelled_queues : Map[String, Bool]
  mut active_progress_reactions : Map[String, FeishuReactionIndicatorState]
  mut websocket_chunks : Map[String, FeishuWebSocketChunkState]
  websocket_endpoint_test_overrides : Map[String, Array[String]]
  mut message_handler : &@channel.MessageHandler?
}

///|
priv struct QueuedFeishuMessage {
  account_id : String
  message : @channel.Message
}

///|
pub struct FeishuChannel {
  priv state : FeishuChannelState
}

///|
pub fn FeishuChannel::new() -> FeishuChannel {
  FeishuChannel::{
    state: FeishuChannelState::{
      _config: @channel.default_config(),
      feishu_configs: {},
      clients: {},
      running: {},
      user_name_cache: {},
      active_monitor_connections: {},
      extension_context: None,
      recent_event_ids: [],
      recent_message_ids: [],
      pending_messages: {},
      processing_keys: {},
      cancelled_queues: {},
      active_progress_reactions: {},
      websocket_chunks: {},
      websocket_endpoint_test_overrides: {},
      message_handler: None,
    },
  }
}

///|
fn get_feishu_config(config : Json) -> FeishuAccountConfig {
  let fallback = FeishuAccountConfig::{
    app_id: "",
    app_secret: "",
    domain: "feishu",
    connection_mode: "webhook",
    dm_policy: "pairing",
    reaction_notifications: Some("own"),
    bot_name: None,
    webhook_url: None,
    websocket_url: None,
    websocket_headers: None,
    verify_token: None,
    encryption_key: None,
    enabled: false,
  }
  match config {
    { "appId": String(app_id), "appSecret": String(app_secret), .. } =>
      FeishuAccountConfig::{
        app_id,
        app_secret,
        domain: match config {
          { "domain": String(domain), .. } => domain
          _ => "feishu"
        },
        connection_mode: match config {
          { "connectionMode": String(mode), .. } => mode
          { "connection_mode": String(mode), .. } => mode
          _ => "webhook"
        },
        dm_policy: match config {
          { "dmPolicy": String(policy), .. } => policy
          { "dm_policy": String(policy), .. } => policy
          _ => "pairing"
        },
        reaction_notifications: match config {
          { "reactionNotifications": String(value), .. } => Some(value)
          { "reaction_notifications": String(value), .. } => Some(value)
          _ => Some("own")
        },
        bot_name: match config {
          { "botName": String(value), .. } => Some(value)
          { "bot_name": String(value), .. } => Some(value)
          _ => None
        },
        webhook_url: match config {
          { "webhookUrl": String(value), .. } => Some(value)
          { "webhook_url": String(value), .. } => Some(value)
          _ => None
        },
        websocket_url: match config {
          { "websocketUrl": String(value), .. } => Some(value)
          { "websocket_url": String(value), .. } => Some(value)
          _ => None
        },
        websocket_headers: match config {
          { "websocketHeaders": headers, .. } =>
            @json.from_json(headers) catch {
              _ => None
            }
          { "websocket_headers": headers, .. } =>
            @json.from_json(headers) catch {
              _ => None
            }
          _ => None
        },
        verify_token: match config {
          { "verifyToken": String(value), .. } => Some(value)
          { "verify_token": String(value), .. } => Some(value)
          _ => None
        },
        encryption_key: match config {
          { "encryptionKey": String(value), .. } => Some(value)
          { "encryption_key": String(value), .. } => Some(value)
          _ => None
        },
        enabled: match config {
          { "enabled": True, .. } => true
          { "enabled": False, .. } => false
          _ => true
        },
      }
    _ => @json.from_json(config) catch { _ => fallback }
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
pub fn FeishuChannel::with_extension(
  self : FeishuChannel,
  apply : (&@channel.ChannelExtension) -> Unit raise,
) -> Unit raise {
  apply(self)
}

///|
impl @channel.Channel for FeishuChannel with id(_self : FeishuChannel) -> @channel.ChannelId {
  "feishu"
}

///|
impl @channel.Channel for FeishuChannel with meta(_self : FeishuChannel) -> @channel.ChannelMeta {
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
impl @channel.Channel for FeishuChannel with capabilities(_self : FeishuChannel) -> @channel.ChannelCapabilities {
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
    native_commands: true,
    block_streaming: true,
  }
}

///|
impl @channel.Channel for FeishuChannel with configure(
  self : FeishuChannel,
  config : @channel.ChannelConfig,
) -> Unit {
  self.state._config = config
  self.state.feishu_configs = {}
  self.state.user_name_cache = {}
  self.state.recent_event_ids.clear()
  self.state.recent_message_ids.clear()
  self.state.pending_messages.clear()
  self.state.processing_keys.clear()
  self.state.cancelled_queues.clear()
  self.state.active_progress_reactions = {}
  self.state.websocket_chunks.clear()
  self.state.websocket_endpoint_test_overrides.clear()
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
  if feishu_config.connection_mode == "websocket" {
    self.log_info("Starting Feishu websocket runtime for account \{account_id}")
    self.ensure_websocket_runtime_client(account_id, feishu_config)
  }
  self.broadcast_monitor_status()

  Ok(())
}

///|
impl @channel.Channel for FeishuChannel with stop(
  self : FeishuChannel,
  account_id : String,
) -> Result[Unit, @channel.ChannelError] {
  self.stop_websocket_runtime_client(account_id)
  self.state.clients.remove(account_id)
  self.state.running[account_id] = false
  for key in self.state.websocket_chunks.keys().to_array() {
    if key.has_prefix("\{account_id}:") {
      self.state.websocket_chunks.remove(key)
    }
  }
  self.broadcast_monitor_status()
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
    Some(client) => {
      let stream_key = feishu_stream_key(actual_account_id, message)
      if message.content_type == "progress" {
        return self.send_stream_progress(
          client, actual_account_id, to, message, stream_key,
        )
      }
      self.clear_progress_reaction(client, actual_account_id, stream_key)
      client.send_text_message(
        to,
        message.content,
        reply_to=message.reply_to,
        reply_in_thread=match message.thread_id {
          Some(_) => true
          None => false
        },
      )
    }
    None =>
      Err(
        @channel.ChannelError::NotConfigured(
          message="Client not initialized for account: \{actual_account_id}",
        ),
      )
  }
}

///|
fn feishu_stream_key(account_id : String, message : @channel.Message) -> String {
  let reply_to = message.reply_to.unwrap_or("")
  let thread_id = message.thread_id.unwrap_or("")
  "\{account_id}:\{message.to}:\{reply_to}:\{thread_id}"
}

///|
fn feishu_typing_message_id(message : @channel.Message) -> String? {
  match message.reply_to {
    Some(message_id) if !message_id.is_blank() => Some(message_id)
    _ => None
  }
}

///|
fn feishu_progress_emoji_type(progress : String) -> String {
  match progress {
    "thinking" => "THINKING"
    "tool" => "HAMMER"
    "drafting" => "OnIt"
    _ => "THINKING"
  }
}

///|
async fn FeishuChannel::ensure_progress_reaction(
  self : FeishuChannel,
  client : FeishuClient,
  account_id : String,
  stream_key : String,
  message : @channel.Message,
) -> Unit {
  let emoji_type = feishu_progress_emoji_type(message.content)
  match feishu_typing_message_id(message) {
    Some(message_id) =>
      match self.state.active_progress_reactions.get(stream_key) {
        Some(state) if state.message_id == message_id &&
          state.emoji_type == emoji_type => ()
        Some(state) => {
          self.state.active_progress_reactions.remove(stream_key) |> ignore()
          ignore(client.remove_message_reaction(state))
          match client.add_message_reaction(message_id, emoji_type) {
            Ok(updated) =>
              self.state.active_progress_reactions[stream_key] = updated
            Err(error) =>
              self.log_warn(
                "Failed to add Feishu progress reaction for \{account_id}: \{error}",
              )
          }
        }
        None =>
          match client.add_message_reaction(message_id, emoji_type) {
            Ok(state) =>
              self.state.active_progress_reactions[stream_key] = state
            Err(error) =>
              self.log_warn(
                "Failed to add Feishu progress reaction for \{account_id}: \{error}",
              )
          }
      }
    None => ()
  }
}

///|
async fn FeishuChannel::clear_progress_reaction(
  self : FeishuChannel,
  client : FeishuClient,
  account_id : String,
  stream_key : String,
) -> Unit {
  match self.state.active_progress_reactions.get(stream_key) {
    Some(state) => {
      self.state.active_progress_reactions.remove(stream_key) |> ignore()
      match client.remove_message_reaction(state) {
        Ok(_) => ()
        Err(error) =>
          self.log_warn(
            "Failed to remove Feishu progress reaction for \{account_id}: \{error}",
          )
      }
    }
    None => ()
  }
}

///|
async fn FeishuChannel::send_stream_progress(
  self : FeishuChannel,
  client : FeishuClient,
  account_id : String,
  to : String,
  message : @channel.Message,
  stream_key : String,
) -> Result[@channel.SendResult, @channel.ChannelError] {
  ignore(to)
  self.ensure_progress_reaction(client, account_id, stream_key, message)
  let message_id = match feishu_typing_message_id(message) {
    Some(message_id) => message_id
    None => message.id
  }
  Ok(@channel.SendResult::{
    channel: "feishu",
    message_id,
    timestamp: 0,
    status: "updated",
  })
}

///|
impl @channel.Channel for FeishuChannel with handle_event(
  _self : FeishuChannel,
  _event : @channel.ChannelEvent,
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
  _self : FeishuChannel,
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
      if self.is_url_verification_request(json) {
        return self.handle_url_verification(json)
      }

      // Parse Feishu event
      let event_type = match json {
        { "header": { "event_type": String(event_type), .. }, .. } => event_type
        _ =>
          return @channel.ExtensionResponse::bad_request(
            message="Missing event_type in request",
          )
      }

      // Handle message received event
      if event_type == "im.message.receive_v1" {
        return self.handle_feishu_message(json)
      }
      if event_type == "im.message.reaction.created_v1" {
        return self.handle_reaction_event(json)
      }
      if event_type == "im.chat.member.bot.added_v1" {
        return self.handle_bot_membership_event(json, "added")
      }
      if event_type == "im.chat.member.bot.deleted_v1" {
        return self.handle_bot_membership_event(json, "removed")
      }
      if event_type == "im.chat.member.bot.removed_v1" {
        return self.handle_bot_membership_event(json, "removed")
      }
      if event_type == "card.action.trigger" {
        return self.handle_card_action_event(json)
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
async fn FeishuChannel::handle_feishu_message(
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

  let event_id = match json {
    { "header": { "event_id": String(event_id), .. }, .. } => Some(event_id)
    _ => None
  }
  if self.is_duplicate_event(event_id) {
    return @channel.ExtensionResponse::ok()
  }

  let app_id = match json {
    { "header": { "app_id": String(app_id), .. }, .. } => Some(app_id)
    _ => None
  }

  let message_data = match event_data {
    { "message": message, .. } => message
    _ =>
      return @channel.ExtensionResponse::bad_request(
        message="Missing message payload",
      )
  }

  let sender_data = match event_data {
    { "sender": sender, .. } => Some(sender)
    _ => None
  }

  let message_id = match message_data {
    { "message_id": String(id), .. } => id
    _ =>
      return @channel.ExtensionResponse::bad_request(
        message="Missing message_id",
      )
  }
  if self.is_duplicate_message_id(message_id) {
    return @channel.ExtensionResponse::ok()
  }

  let message_type = match message_data {
    { "message_type": String(message_type), .. } => message_type
    _ => "text"
  }

  let from_user_id = match sender_data {
    Some({ "sender_id": { "open_id": String(uid), .. }, .. }) => uid
    Some({ "sender_id": { "user_id": String(uid), .. }, .. }) => uid
    Some({ "sender_id": { "union_id": String(uid), .. }, .. }) => uid
    _ =>
      return @channel.ExtensionResponse::bad_request(
        message="Missing sender_id",
      )
  }

  let chat_id = match message_data {
    { "chat_id": String(cid), .. } => cid
    _ =>
      return @channel.ExtensionResponse::bad_request(message="Missing chat_id")
  }

  let timestamp_ms = match message_data {
    { "create_time": String(ts), .. } =>
      @strconv.parse_int64(ts) catch {
        _ => 0
      }
    _ => 0
  }
  if is_expired_message(timestamp_ms) {
    return @channel.ExtensionResponse::ok()
  }
  let timestamp = timestamp_ms.to_int()

  let thread_id = match message_data {
    { "thread_id": String(thread_id), .. } => Some(thread_id)
    { "msg_parent_id": String(parent_id), "message_id": String(mid), .. } if parent_id !=
      mid => Some(parent_id)
    { "msg_root_id": String(root_id), .. } => Some(root_id)
    _ => None
  }

  let account_id = match self.resolve_account_id_for_event(app_id, json) {
    Some(account_id) => account_id
    None =>
      return @channel.ExtensionResponse::bad_request(
        message="No matching Feishu account configured for event",
      )
  }

  if !self.verify_request_token(account_id, json) {
    return @channel.ExtensionResponse::bad_request(
      message="Feishu verify_token mismatch",
    )
  }

  let content = match message_data {
    { "content": String(c), .. } =>
      self.parse_event_message_content(c, message_type, account_id, message_id)
    _ => None
  }
  guard content is Some(content) else {
    return @channel.ExtensionResponse::ok()
  }

  // Create channel message
  let message = @channel.Message::{
    id: message_id,
    channel: "feishu",
    from: from_user_id,
    to: chat_id,
    content,
    content_type: message_type,
    timestamp,
    thread_id,
    reply_to: None,
    attachments: parse_feishu_attachments(
      match message_data {
        { "content": String(raw_content), .. } => raw_content
        _ => ""
      },
      message_type,
    ),
  }

  // Process through message handler if available
  match self.state.message_handler {
    Some(handler) =>
      if is_abort_text(content) {
        let queue_key = feishu_queue_key(account_id, chat_id, thread_id)
        let force = is_force_abort_text(content)
        self.request_queue_cancel(queue_key)
        self.send_cancel_acknowledgement(
          account_id,
          chat_id,
          message_id,
          thread_id,
          force~,
        )
        handler.handle_event("feishu", account_id, @channel.ChannelEvent::{
          channel: "feishu",
          account_id,
          event_type: if force {
            "force_cancel"
          } else {
            "cancel"
          },
          payload: {
            "chat_id": chat_id,
            "thread_id": thread_id.to_json(),
            "message_id": message_id,
            "content": content,
          },
          timestamp,
        })
        @channel.ExtensionResponse::ok()
      } else {
        let queue_key = feishu_queue_key(account_id, chat_id, thread_id)
        self.enqueue_message(queue_key, QueuedFeishuMessage::{
          account_id,
          message,
        })
        if self.is_processing_queue(queue_key) {
          @channel.ExtensionResponse::ok()
        } else {
          self.set_processing_queue(queue_key, true)
          defer self.finish_processing_queue(queue_key)
          self.process_queued_messages(queue_key, handler)
        }
      }
    None =>
      // No handler, just acknowledge
      @channel.ExtensionResponse::ok()
  }
}

///|
async fn FeishuChannel::handle_reaction_event(
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
  let event_id = match json {
    { "header": { "event_id": String(event_id), .. }, .. } => Some(event_id)
    _ => None
  }
  if self.is_duplicate_event(event_id) {
    return @channel.ExtensionResponse::ok()
  }

  let app_id = match json {
    { "header": { "app_id": String(app_id), .. }, .. } => Some(app_id)
    _ => None
  }
  let account_id = match self.resolve_account_id_for_event(app_id, json) {
    Some(account_id) => account_id
    None =>
      return @channel.ExtensionResponse::bad_request(
        message="No matching Feishu account configured for reaction event",
      )
  }
  if !self.verify_request_token(account_id, json) {
    return @channel.ExtensionResponse::bad_request(
      message="Feishu verify_token mismatch",
    )
  }

  match self.state.message_handler {
    Some(handler) => {
      let message_id = match event_data {
        { "message_id": String(message_id), .. } => message_id
        _ =>
          return @channel.ExtensionResponse::bad_request(
            message="Missing reaction message_id",
          )
      }
      let operator_open_id = match event_data {
        { "user_id": { "open_id": String(open_id), .. }, .. } => Some(open_id)
        _ => None
      }
      let operator_type = match event_data {
        { "operator_type": String(operator_type), .. } => Some(operator_type)
        _ => None
      }
      let emoji_type = match event_data {
        { "reaction_type": { "emoji_type": String(emoji_type), .. }, .. } =>
          Some(emoji_type)
        _ => None
      }
      if self.should_ignore_reaction_event(
          operator_type, operator_open_id, emoji_type,
        ) {
        return @channel.ExtensionResponse::ok()
      }
      let notifications = self.reaction_notifications_mode(account_id)
      if notifications == "off" {
        return @channel.ExtensionResponse::ok()
      }
      let lookup = match self.lookup_reaction_message(account_id, message_id) {
        Ok(Some(lookup)) => lookup
        Ok(None) => return @channel.ExtensionResponse::ok()
        Err(_) => return @channel.ExtensionResponse::ok()
      }
      if notifications == "own" &&
        !is_own_reaction_target(lookup, self.feishu_app_id(account_id)) {
        return @channel.ExtensionResponse::ok()
      }
      let timestamp = match event_data {
        { "action_time": String(ts), .. } =>
          @strconv.parse_int(ts) catch {
            _ => 0
          }
        _ => 0
      }
      handler.handle_event("feishu", account_id, @channel.ChannelEvent::{
        channel: "feishu",
        account_id,
        event_type: "reaction.added",
        payload: {
          "message_id": message_id,
          "chat_id": lookup.chat_id,
          "chat_type": lookup.chat_type.to_json(),
          "thread_id": lookup.thread_id.to_json(),
          "operator_open_id": operator_open_id.to_json(),
          "operator_type": operator_type.to_json(),
          "emoji_type": emoji_type.to_json(),
          "content": lookup.content.to_json(),
          "content_type": lookup.content_type.to_json(),
          "target_sender_id": lookup.sender_id.to_json(),
          "target_sender_type": lookup.sender_type.to_json(),
          "raw_event": event_data,
        },
        timestamp,
      })
      @channel.ExtensionResponse::ok()
    }
    None => @channel.ExtensionResponse::ok()
  }
}

///|
async fn FeishuChannel::handle_bot_membership_event(
  self : FeishuChannel,
  json : Json,
  action : String,
) -> @channel.ExtensionResponse {
  let event_data = match json {
    { "event": event, .. } => event
    _ =>
      return @channel.ExtensionResponse::bad_request(
        message="Missing event data",
      )
  }
  let event_id = match json {
    { "header": { "event_id": String(event_id), .. }, .. } => Some(event_id)
    _ => None
  }
  if self.is_duplicate_event(event_id) {
    return @channel.ExtensionResponse::ok()
  }

  let app_id = match json {
    { "header": { "app_id": String(app_id), .. }, .. } => Some(app_id)
    _ => None
  }
  let account_id = match self.resolve_account_id_for_event(app_id, json) {
    Some(account_id) => account_id
    None =>
      return @channel.ExtensionResponse::bad_request(
        message="No matching Feishu account configured for membership event",
      )
  }
  if !self.verify_request_token(account_id, json) {
    return @channel.ExtensionResponse::bad_request(
      message="Feishu verify_token mismatch",
    )
  }

  match self.state.message_handler {
    Some(handler) => {
      handler.handle_event("feishu", account_id, @channel.ChannelEvent::{
        channel: "feishu",
        account_id,
        event_type: "bot.\{action}",
        payload: event_data,
        timestamp: 0,
      })
      @channel.ExtensionResponse::ok()
    }
    None => @channel.ExtensionResponse::ok()
  }
}

///|
async fn FeishuChannel::handle_card_action_event(
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
  let event_id = match json {
    { "header": { "event_id": String(event_id), .. }, .. } => Some(event_id)
    _ => None
  }
  if self.is_duplicate_event(event_id) {
    return @channel.ExtensionResponse::json({
      "toast": { "type": "info", "content": "Action already processed" },
    })
  }

  let app_id = match json {
    { "header": { "app_id": String(app_id), .. }, .. } => Some(app_id)
    _ => None
  }
  let account_id = match self.resolve_account_id_for_event(app_id, json) {
    Some(account_id) => account_id
    None =>
      return @channel.ExtensionResponse::bad_request(
        message="No matching Feishu account configured for card action event",
      )
  }
  if !self.verify_request_token(account_id, json) {
    return @channel.ExtensionResponse::bad_request(
      message="Feishu verify_token mismatch",
    )
  }

  match self.state.message_handler {
    Some(handler) => {
      handler.handle_event("feishu", account_id, @channel.ChannelEvent::{
        channel: "feishu",
        account_id,
        event_type: "card.action",
        payload: event_data,
        timestamp: 0,
      })
      @channel.ExtensionResponse::json({
        "toast": { "type": "success", "content": "Action received" },
      })
    }
    None => @channel.ExtensionResponse::json({})
  }
}

///|
impl @channel.ChannelExtension for FeishuChannel with supports_websocket(
  self : FeishuChannel,
) -> Bool {
  !self.websocket_monitor_accounts().is_empty()
}

///|
impl @channel.ChannelExtension for FeishuChannel with handle_websocket(
  self : FeishuChannel,
  conn : @channel.WebSocketConnection,
) -> Unit {
  self.state.active_monitor_connections[conn.id()] = conn
  conn.on_message(bytes => self.handle_monitor_frame(conn.id(), bytes))
  conn.on_close(fn() { self.remove_monitor_connection(conn.id()) })
  conn.send(
    @encoding/utf8.encode(
      Json::object({
        "type": "feishu.monitor.ready",
        "channel": "feishu",
        "supports_websocket": self.supports_websocket().to_json(),
        "accounts": Json::array(
          self
          .websocket_monitor_accounts()
          .map(fn(account_id) { self.websocket_account_status_json(account_id) }),
        ),
      }).stringify(),
    ),
  )
}

///|
impl @channel.ChannelExtension for FeishuChannel with allowed_methods(
  _self : FeishuChannel,
) -> Array[String] {
  ["POST", "GET"]
}

///|
impl @channel.ChannelExtension for FeishuChannel with dock_config(
  _self : FeishuChannel,
) -> @channel.ChannelDockConfig {
  @channel.ChannelDockConfig::default_for_channel("feishu")
}

///|
impl @channel.ChannelExtension for FeishuChannel with on_register(
  self : FeishuChannel,
  context : @channel.ExtensionContext,
) -> Unit {
  self.state.extension_context = Some(context)
  match context.logger() {
    Some(logger) => (logger.info)("Feishu channel extension registered")
    None => ()
  }
}

///|
impl @channel.ChannelExtension for FeishuChannel with on_unregister(
  self : FeishuChannel,
) -> Unit {
  for account_id in self.state.feishu_configs.keys() {
    self.stop_websocket_runtime_client(account_id)
  }
  for _, conn in self.state.active_monitor_connections {
    conn.close()
  }
  self.state.active_monitor_connections = {}
  self.state.websocket_chunks = {}
  self.state.extension_context = None
  for account_id in self.state.running.keys() {
    self.state.clients.remove(account_id)
    self.state.running[account_id] = false
  }
}

///|
fn feishu_runtime_client_id(account_id : String) -> String {
  "feishu:\{account_id}"
}

///|
fn feishu_websocket_dial_request(
  account_id : String,
  url : String,
  config : FeishuAccountConfig,
) -> @channel.WebSocketDialRequest {
  let metadata = Json::object({
    "account_id": account_id,
    "app_id": config.app_id,
    "app_secret": config.app_secret,
    "domain": config.domain,
    "url": url,
    "headers": config.websocket_headers.to_json(),
    "verify_token": config.verify_token.to_json(),
    "encryption_key": config.encryption_key.to_json(),
    "bot_name": config.bot_name.to_json(),
  })
  @channel.WebSocketDialRequest::new(
    client_id=feishu_runtime_client_id(account_id),
    protocol="feishu",
    metadata~,
  )
}

///|
fn FeishuChannel::stop_websocket_runtime_client(
  self : FeishuChannel,
  account_id : String,
) -> Unit {
  match self.state.extension_context {
    Some(context) =>
      match context.websocket_runtime() {
        Some(runtime) => runtime.remove(feishu_runtime_client_id(account_id))
        None => ()
      }
    None => ()
  }
}

///|
fn FeishuChannel::log_info(self : FeishuChannel, message : String) -> Unit {
  match self.state.extension_context {
    Some(context) =>
      match context.logger() {
        Some(logger) => (logger.info)(message)
        None => ()
      }
    None => ()
  }
}

///|
fn FeishuChannel::log_warn(self : FeishuChannel, message : String) -> Unit {
  match self.state.extension_context {
    Some(context) =>
      match context.logger() {
        Some(logger) => (logger.warn)(message)
        None => ()
      }
    None => ()
  }
}

///|
async fn FeishuChannel::resolve_websocket_endpoint(
  self : FeishuChannel,
  config : FeishuAccountConfig,
) -> Result[FeishuWebSocketEndpointData, @channel.ChannelError] {
  match self.state.websocket_endpoint_test_overrides.get(config.app_id) {
    Some(urls) if !urls.is_empty() => {
      let url = urls[0]
      ignore(urls.remove(0))
      Ok(FeishuWebSocketEndpointData::{ url, client_config: None })
    }
    _ =>
      resolve_websocket_endpoint(
        config.app_id,
        config.app_secret,
        config.domain,
      )
  }
}

///|
fn FeishuChannel::ensure_websocket_runtime_client(
  self : FeishuChannel,
  account_id : String,
  config : FeishuAccountConfig,
) -> Unit {
  match self.state.extension_context {
    Some(context) =>
      match (context.websocket_runtime(), context.websocket_connector()) {
        (Some(runtime), Some(connector)) =>
          runtime.upsert(
            @channel.WebSocketClientRegistration::new(
              spec=@channel.WebSocketClientSpec::new(
                client_id=feishu_runtime_client_id(account_id),
                label="Feishu[\{account_id}]",
                reconnect_delay_ms=2_000,
              ),
              connect=async fn() {
                self.log_info(
                  "Resolving Feishu websocket endpoint for account \{account_id}",
                )
                let endpoint = match config.websocket_url {
                  Some(url) if !url.is_blank() =>
                    Ok(FeishuWebSocketEndpointData::{ url, client_config: None })
                  _ => self.resolve_websocket_endpoint(config)
                }
                let endpoint = match endpoint {
                  Ok(endpoint) => endpoint
                  Err(error) => {
                    let message = "Feishu websocket account \{account_id} failed to resolve websocket endpoint: \{error}"
                    self.log_warn(message)
                    return Err(message)
                  }
                }
                self.log_info(
                  "Registering Feishu websocket client for account \{account_id} -> \{endpoint.url}",
                )
                connector.connect(
                  feishu_websocket_dial_request(
                    account_id,
                    endpoint.url,
                    config,
                  ),
                )
              },
              on_connect=fn(conn) {
                self.log_info(
                  "Feishu websocket connected for account \{account_id} as \{conn.id()}",
                )
                self.bind_platform_websocket(account_id, conn)
              },
              logger=context.logger(),
            ),
          )
        (Some(_), None) =>
          self.log_warn(
            "Feishu websocket account \{account_id} is enabled but no websocket connector is available",
          )
        _ => ()
      }
    None => ()
  }
}

///|
pub fn FeishuChannel::set_test_websocket_endpoint_sequence(
  self : FeishuChannel,
  app_id : String,
  urls : Array[String],
) -> Unit {
  self.state.websocket_endpoint_test_overrides[app_id] = urls
}

///|
fn parse_feishu_text_content(raw : String) -> String {
  let parsed : Result[Json, Error] = try? @json.parse(raw)
  match parsed {
    Ok({ "text": String(text), .. }) => strip_feishu_mentions(text)
    Ok(json) => json.stringify()
    Err(_) => raw
  }
}

///|
fn parse_feishu_message_content(raw : String, message_type : String) -> String? {
  match message_type {
    "text" => Some(parse_feishu_text_content(raw))
    "post" => parse_feishu_post_content(raw)
    "interactive" => parse_feishu_interactive_content(raw)
    "image" => parse_feishu_image_content(raw)
    "file" => parse_feishu_file_content(raw)
    "media" => parse_feishu_file_content(raw)
    "audio" => parse_feishu_audio_content(raw)
    "video" => parse_feishu_video_content(raw)
    "sticker" => Some("[sticker]")
    "share_chat" => parse_feishu_share_chat_content(raw)
    "share_user" => parse_feishu_share_user_content(raw)
    "merge_forward" => Some("<forwarded_messages/>")
    _ => None
  }
}

///|
async fn FeishuChannel::parse_event_message_content(
  self : FeishuChannel,
  raw : String,
  message_type : String,
  account_id : String,
  message_id : String,
) -> String? {
  match message_type {
    "merge_forward" => self.parse_merge_forward_content(account_id, message_id)
    _ => parse_feishu_message_content(raw, message_type)
  }
}

///|
fn parse_feishu_attachments(
  raw : String,
  message_type : String,
) -> Array[@channel.Attachment] {
  let parsed : Result[Json, Error] = try? @json.parse(raw)
  match parsed {
    Ok(json) => build_feishu_attachments(json, message_type)
    Err(_) => []
  }
}

///|
fn build_feishu_attachments(
  json : Json,
  message_type : String,
) -> Array[@channel.Attachment] {
  match message_type {
    "image" =>
      match json {
        { "image_key": String(image_key), .. } if !image_key.is_blank() =>
          [
            @channel.Attachment::{
              id: image_key,
              mime_type: "image/*",
              url: "feishu://image/\{image_key}",
              filename: None,
              size: None,
            },
          ]
        _ => []
      }
    "file" | "media" =>
      match json {
        { "file_key": String(file_key), "file_name": String(file_name), .. } =>
          [
            @channel.Attachment::{
              id: file_key,
              mime_type: "application/octet-stream",
              url: "feishu://file/\{file_key}",
              filename: Some(file_name),
              size: None,
            },
          ]
        { "file_key": String(file_key), .. } =>
          [
            @channel.Attachment::{
              id: file_key,
              mime_type: "application/octet-stream",
              url: "feishu://file/\{file_key}",
              filename: None,
              size: None,
            },
          ]
        _ => []
      }
    "audio" =>
      match json {
        { "file_key": String(file_key), .. } =>
          [
            @channel.Attachment::{
              id: file_key,
              mime_type: "audio/*",
              url: "feishu://audio/\{file_key}",
              filename: None,
              size: None,
            },
          ]
        _ => []
      }
    "video" =>
      match json {
        { "file_key": String(file_key), .. } =>
          [
            @channel.Attachment::{
              id: file_key,
              mime_type: "video/*",
              url: "feishu://video/\{file_key}",
              filename: None,
              size: None,
            },
          ]
        _ => []
      }
    _ => []
  }
}

///|
fn parse_feishu_post_content(raw : String) -> String? {
  let parsed : Result[Json, Error] = try? @json.parse(raw)
  match parsed {
    Ok(json) => {
      let post = unwrap_feishu_post(json)
      match post {
        Some(post) => {
          let title = match post {
            { "title": String(title), .. } if !title.is_blank() =>
              Some("**\{title}**")
            _ => None
          }
          let body = match post {
            { "content": Array(content), .. } =>
              content
              .map(render_feishu_post_paragraph)
              .filter(fn(line) { !line.is_blank() })
              .join("\n")
            _ => ""
          }
          let pieces = []
          match title {
            Some(title) => pieces.push(title)
            None => ()
          }
          if !body.is_blank() {
            pieces.push(body)
          }
          let rendered = pieces.join("\n\n").trim().to_string()
          if rendered.is_blank() {
            Some("[rich text message]")
          } else {
            Some(rendered)
          }
        }
        None => Some("[rich text message]")
      }
    }
    Err(_) => Some("[rich text message]")
  }
}

///|
fn unwrap_feishu_post(json : Json) -> Json? {
  match json {
    { "title": _, .. } | { "content": _, .. } => Some(json)
    Object(obj) => {
      for locale in ["zh_cn", "en_us", "ja_jp"] {
        match obj.get(locale) {
          Some(value) => return Some(value)
          None => ()
        }
      }
      let values = obj.values().to_array()
      values.get(0)
    }
    _ => None
  }
}

///|
fn render_feishu_post_paragraph(paragraph : Json) -> String {
  match paragraph {
    Array(elements) =>
      elements.map(render_feishu_post_element).join("").trim().to_string()
    _ => ""
  }
}

///|
fn render_feishu_post_element(element : Json) -> String {
  match element {
    { "tag": String("text"), "text": String(text), .. } => text
    { "tag": String("a"), "text": String(text), "href": String(href), .. } =>
      "[\{text}](\{href})"
    { "tag": String("a"), "href": String(href), .. } => href
    { "tag": String("at"), "user_name": String(name), .. } => "@\{name}"
    { "tag": String("at"), "user_id": String("all"), .. } => "@all"
    { "tag": String("img"), "image_key": String(key), .. } => "![image](\{key})"
    { "tag": String("media"), "file_key": String(key), .. } => "<file:\{key}>"
    {
      "tag": String("code_block"),
      "text": String(text),
      "language": String(language),
      ..
    } => "\n```\{language}\n\{text}\n```\n"
    { "tag": String("code_block"), "text": String(text), .. } =>
      "\n```\n\{text}\n```\n"
    { "tag": String("hr"), .. } => "\n---\n"
    { "text": String(text), .. } => text
    _ => ""
  }
}

///|
fn parse_feishu_interactive_content(raw : String) -> String? {
  let parsed : Result[Json, Error] = try? @json.parse(raw)
  match parsed {
    Ok(json) => {
      let title = extract_feishu_card_title(json)
      let summary = extract_feishu_card_summary(json)
      let parts = []
      if !title.is_blank() {
        parts.push("<card title=\"\{title}\">")
      } else {
        parts.push("<card>")
      }
      if !summary.is_blank() {
        parts.push(summary)
      }
      parts.push("</card>")
      Some(parts.join("\n"))
    }
    Err(_) => Some("<card>\n[interactive card]\n</card>")
  }
}

///|
fn parse_feishu_image_content(raw : String) -> String? {
  let parsed : Result[Json, Error] = try? @json.parse(raw)
  match parsed {
    Ok({ "image_key": String(image_key), .. }) if !image_key.is_blank() =>
      Some("![image](\{image_key})")
    _ => Some("[image]")
  }
}

///|
fn parse_feishu_file_content(raw : String) -> String? {
  let parsed : Result[Json, Error] = try? @json.parse(raw)
  match parsed {
    Ok({ "file_name": String(file_name), "file_key": String(file_key), .. }) =>
      Some("[file] \{file_name} (\{file_key})")
    Ok({ "file_name": String(file_name), .. }) => Some("[file] \{file_name}")
    Ok({ "file_key": String(file_key), .. }) => Some("[file] \{file_key}")
    _ => Some("[file]")
  }
}

///|
fn parse_feishu_audio_content(raw : String) -> String? {
  let parsed : Result[Json, Error] = try? @json.parse(raw)
  match parsed {
    Ok({ "file_key": String(file_key), .. }) => Some("[audio] \{file_key}")
    _ => Some("[audio]")
  }
}

///|
fn parse_feishu_video_content(raw : String) -> String? {
  let parsed : Result[Json, Error] = try? @json.parse(raw)
  match parsed {
    Ok({ "file_key": String(file_key), .. }) => Some("[video] \{file_key}")
    _ => Some("[video]")
  }
}

///|
fn parse_feishu_share_chat_content(raw : String) -> String? {
  let parsed : Result[Json, Error] = try? @json.parse(raw)
  match parsed {
    Ok({ "chat_name": String(chat_name), .. }) =>
      Some("[shared chat] \{chat_name}")
    _ => Some("[shared chat]")
  }
}

///|
fn parse_feishu_share_user_content(raw : String) -> String? {
  let parsed : Result[Json, Error] = try? @json.parse(raw)
  match parsed {
    Ok({ "user_name": String(user_name), .. }) =>
      Some("[shared user] \{user_name}")
    _ => Some("[shared user]")
  }
}

///|
async fn FeishuChannel::parse_merge_forward_content(
  self : FeishuChannel,
  account_id : String,
  message_id : String,
) -> String? {
  match self.state.clients.get(account_id) {
    Some(client) =>
      match client.get_message_items(message_id) {
        Ok(items) if !items.is_empty() =>
          Some(
            format_merge_forward_items(
              message_id,
              items,
              sender_names=self.resolve_forward_sender_names(
                client, account_id, items,
              ),
            ),
          )
        _ => Some("<forwarded_messages/>")
      }
    None => Some("<forwarded_messages/>")
  }
}

///|
fn format_merge_forward_items(
  root_message_id : String,
  items : Array[FeishuMessageLookupItem],
  sender_names? : Map[String, String] = {},
) -> String {
  let children : Map[String, Array[FeishuMessageLookupItem]] = {}
  for item in items {
    if item.message_id == root_message_id && item.upper_message_id is None {
      continue
    }
    let parent_id = item.upper_message_id.unwrap_or(root_message_id)
    let siblings = match children.get(parent_id) {
      Some(siblings) => siblings
      None => []
    }
    siblings.push(item)
    children[parent_id] = siblings
  }
  let rendered = format_merge_forward_tree(
    root_message_id, children, sender_names,
  )
  if rendered.is_blank() {
    "<forwarded_messages/>"
  } else {
    "<forwarded_messages>\n\{rendered}\n</forwarded_messages>"
  }
}

///|
fn format_merge_forward_tree(
  parent_id : String,
  children : Map[String, Array[FeishuMessageLookupItem]],
  sender_names : Map[String, String],
) -> String {
  let items = match children.get(parent_id) {
    Some(items) => items
    None => return ""
  }
  let parts = []
  for item in items {
    let sender = resolve_merge_forward_sender_name(item, sender_names)
    let timestamp = item.create_time.unwrap_or("unknown")
    let content = match item.msg_type.unwrap_or("text") {
      "merge_forward" => {
        let nested = format_merge_forward_tree(
          item.message_id,
          children,
          sender_names,
        )
        if nested.is_blank() {
          "<forwarded_messages/>"
        } else {
          "<forwarded_messages>\n\{nested}\n</forwarded_messages>"
        }
      }
      message_type =>
        parse_feishu_message_content(
          match item.body {
            Some(body) => body.content.unwrap_or("{}")
            None => "{}"
          },
          message_type,
        ).unwrap_or("[unsupported]")
    }
    let indented = indent_text(content, "    ")
    parts.push("[\{timestamp}] \{sender}:\n\{indented}")
  }
  parts.join("\n")
}

///|
async fn FeishuChannel::resolve_forward_sender_names(
  self : FeishuChannel,
  client : FeishuClient,
  account_id : String,
  items : Array[FeishuMessageLookupItem],
) -> Map[String, String] {
  let sender_names : Map[String, String] = {}
  let sender_ids = collect_forward_sender_ids(items)
  let missing_sender_ids = []
  for sender_id in sender_ids {
    match self.cached_user_name(account_id, sender_id) {
      Some(name) if !name.is_blank() => sender_names[sender_id] = name
      Some(_) => ()
      None => missing_sender_ids.push(sender_id)
    }
  }
  if !missing_sender_ids.is_empty() {
    match client.get_user_display_names(missing_sender_ids) {
      Ok(resolved_names) =>
        for sender_id in missing_sender_ids {
          let resolved_name = resolved_names.get(sender_id).unwrap_or("")
          self.cache_user_name(account_id, sender_id, resolved_name)
          if !resolved_name.is_blank() {
            sender_names[sender_id] = resolved_name
          }
        }
      Err(_) => ()
    }
  }
  sender_names
}

///|
fn resolve_merge_forward_sender_name(
  item : FeishuMessageLookupItem,
  sender_names : Map[String, String],
) -> String {
  match item.sender {
    Some({ id: Some(sender_id), sender_type: Some("user") }) =>
      sender_names.get(sender_id).unwrap_or(sender_id)
    Some({ id: Some(sender_id), sender_type: _ }) => sender_id
    _ => "unknown"
  }
}

///|
fn collect_forward_sender_ids(
  items : Array[FeishuMessageLookupItem],
) -> Array[String] {
  let sender_ids = []
  let seen : Map[String, Bool] = {}
  for item in items {
    match item.sender {
      Some({ id: Some(sender_id), sender_type: Some("user") }) =>
        if !sender_id.is_blank() {
          match seen.get(sender_id) {
            Some(true) => ()
            _ => {
              seen[sender_id] = true
              sender_ids.push(sender_id)
            }
          }
        }
      _ => ()
    }
  }
  sender_ids
}

///|
fn feishu_user_cache_key(account_id : String, open_id : String) -> String {
  "\{account_id}:\{open_id}"
}

///|
fn FeishuChannel::cached_user_name(
  self : FeishuChannel,
  account_id : String,
  open_id : String,
) -> String? {
  self.state.user_name_cache.get(feishu_user_cache_key(account_id, open_id))
}

///|
fn FeishuChannel::cache_user_name(
  self : FeishuChannel,
  account_id : String,
  open_id : String,
  name : String,
) -> Unit {
  self.state.user_name_cache[feishu_user_cache_key(account_id, open_id)] = name
}

///|
fn indent_text(text : String, prefix : String) -> String {
  text.split("\n").map(fn(line) { "\{prefix}\{line}" }).join("\n")
}

///|
fn FeishuChannel::websocket_account_status_json(
  self : FeishuChannel,
  account_id : String,
) -> Json {
  let connection_mode = match self.state.feishu_configs.get(account_id) {
    Some(config) => config.connection_mode
    None => "webhook"
  }
  Json::object({
    "account_id": account_id,
    "connection_mode": connection_mode,
    "running": self.is_running(account_id).to_json(),
  })
}

///|
fn FeishuChannel::websocket_monitor_accounts(
  self : FeishuChannel,
) -> Array[String] {
  self.state.feishu_configs
  .keys()
  .filter(fn(account_id) {
    match self.state.feishu_configs.get(account_id) {
      Some(config) => config.connection_mode == "websocket" && config.enabled
      None => false
    }
  })
  .to_array()
}

///|
fn FeishuChannel::remove_monitor_connection(
  self : FeishuChannel,
  connection_id : String,
) -> Unit {
  self.state.active_monitor_connections.remove(connection_id)
}

///|
fn FeishuChannel::broadcast_monitor_status(self : FeishuChannel) -> Unit {
  if self.state.active_monitor_connections.is_empty() {
    return
  }
  let payload = @encoding/utf8.encode(
    Json::object({
      "type": "feishu.monitor.status",
      "channel": "feishu",
      "accounts": Json::array(
        self
        .websocket_monitor_accounts()
        .map(fn(account_id) { self.websocket_account_status_json(account_id) }),
      ),
    }).stringify(),
  )
  for _, conn in self.state.active_monitor_connections {
    conn.send(payload)
  }
}

///|
async fn FeishuChannel::handle_monitor_frame(
  self : FeishuChannel,
  connection_id : String,
  bytes : Bytes,
) -> Unit {
  let text = try @encoding/utf8.decode(bytes) catch {
    _ => {
      self.send_monitor_error(
        connection_id, "invalid_utf8", "Invalid UTF-8 monitor frame",
      )
      return
    }
  } noraise {
    text => text
  }
  let json : Json = try @json.parse(text) catch {
    _ => {
      self.send_monitor_error(
        connection_id, "invalid_json", "Invalid JSON monitor frame",
      )
      return
    }
  } noraise {
    json => json
  }
  match json {
    { "type": String("ping"), .. } =>
      self.send_monitor_frame(connection_id, {
        "type": "pong",
        "channel": "feishu",
      })
    { "type": String("feishu.event"), "event": event_json, .. } =>
      self.handle_monitor_event_frame(connection_id, event_json)
    event_json => self.handle_monitor_event_frame(connection_id, event_json)
  }
}

///|
async fn FeishuChannel::handle_monitor_event_frame(
  self : FeishuChannel,
  connection_id : String,
  event_json : Json,
) -> Unit {
  let response = self.dispatch_feishu_event_frame(event_json)
  let body_text = @encoding/utf8.decode(response.body()) catch { _ => "" }
  if response.status_code() is (200..=299) {
    self.send_monitor_frame(connection_id, {
      "type": "feishu.monitor.ack",
      "status": "ok",
      "status_code": response.status_code(),
      "body": body_text,
    })
  } else {
    self.send_monitor_error(
      connection_id,
      "event_rejected",
      body_text,
      status_code=response.status_code(),
    )
  }
}

///|
fn FeishuChannel::send_monitor_frame(
  self : FeishuChannel,
  connection_id : String,
  payload : Json,
) -> Unit {
  match self.state.active_monitor_connections.get(connection_id) {
    Some(conn) => conn.send(@encoding/utf8.encode(payload.stringify()))
    None => ()
  }
}

///|
fn FeishuChannel::send_monitor_error(
  self : FeishuChannel,
  connection_id : String,
  code : String,
  message : String,
  status_code? : Int = 400,
) -> Unit {
  self.send_monitor_frame(connection_id, {
    "type": "feishu.monitor.error",
    "error": { "code": code, "message": message, "status_code": status_code },
  })
}

///|
async fn FeishuChannel::dispatch_feishu_event_frame(
  self : FeishuChannel,
  event_json : Json,
) -> @channel.ExtensionResponse {
  match event_json {
    { "header": { "event_type": String("im.message.receive_v1"), .. }, .. } =>
      self.handle_feishu_message(event_json)
    {
      "header": { "event_type": String("im.message.reaction.created_v1"), .. },
      ..
    } => self.handle_reaction_event(event_json)
    {
      "header": { "event_type": String("im.chat.member.bot.added_v1"), .. },
      ..
    } => self.handle_bot_membership_event(event_json, "added")
    {
      "header": { "event_type": String("im.chat.member.bot.deleted_v1"), .. },
      ..
    } => self.handle_bot_membership_event(event_json, "removed")
    {
      "header": { "event_type": String("im.chat.member.bot.removed_v1"), .. },
      ..
    } => self.handle_bot_membership_event(event_json, "removed")
    { "header": { "event_type": String("card.action.trigger"), .. }, .. } =>
      self.handle_card_action_event(event_json)
    { "header": { "event_type": String(other), .. }, .. } =>
      @channel.ExtensionResponse::bad_request(
        message="Unsupported Feishu event: \{other}",
      )
    _ =>
      @channel.ExtensionResponse::bad_request(
        message="Missing Feishu event_type",
      )
  }
}

///|
fn platform_chunk_key(account_id : String, message_id : String) -> String {
  "\{account_id}:\{message_id}"
}

///|
fn parse_feishu_ws_header_int(
  frame : FeishuWebSocketFrame,
  key : String,
) -> Int? {
  match feishu_ws_header(frame, key) {
    Some(value) => Some(@strconv.parse_int(value) catch { _ => return None })
    None => None
  }
}

///|
fn FeishuChannel::merge_platform_event_chunks(
  self : FeishuChannel,
  account_id : String,
  frame : FeishuWebSocketFrame,
) -> Json? {
  let message_id = match feishu_ws_header(frame, feishu_ws_header_message_id) {
    Some(value) if !value.is_blank() => value
    _ => return None
  }
  let total = parse_feishu_ws_header_int(frame, feishu_ws_header_sum).unwrap_or(
    1,
  )
  let seq = parse_feishu_ws_header_int(frame, feishu_ws_header_seq).unwrap_or(0)
  ignore(feishu_ws_header(frame, feishu_ws_header_trace_id))
  let payload = frame.payload.unwrap_or(b"")
  if total <= 1 {
    let text = @encoding/utf8.decode(payload) catch { _ => return None }
    return Some(@json.parse(text) catch { _ => return None })
  }
  let key = platform_chunk_key(account_id, message_id)
  let chunk_state = match self.state.websocket_chunks.get(key) {
    Some(existing) => existing
    None => FeishuWebSocketChunkState::{ chunks: {} }
  }
  chunk_state.chunks[seq] = payload
  self.state.websocket_chunks[key] = chunk_state
  if chunk_state.chunks.length() != total {
    return None
  }
  let merged = @buffer.new()
  for index in 0..<total {
    match chunk_state.chunks.get(index) {
      Some(chunk) => merged.write_bytes(chunk)
      None => return None
    }
  }
  self.state.websocket_chunks.remove(key)
  let text = @encoding/utf8.decode(merged.to_bytes()) catch { _ => return None }
  Some(@json.parse(text) catch { _ => return None })
}

///|
fn ack_response_payload(response : @channel.ExtensionResponse) -> Bytes {
  let status_code = if response.status_code() is (200..=299) {
    200
  } else {
    500
  }
  let payload : Map[String, Json] = { "code": status_code.to_json() }
  if status_code == 200 && response.body().length() > 0 {
    payload["data"] = Json::string(@base64.encode(response.body()))
  }
  @encoding/utf8.encode(Json::object(payload).stringify())
}

///|
fn ack_event_frame(
  frame : FeishuWebSocketFrame,
  response : @channel.ExtensionResponse,
) -> FeishuWebSocketFrame {
  let headers = frame.headers.map(fn(header) { header })
  headers.push(FeishuWebSocketHeader::{
    key: feishu_ws_header_biz_rt,
    value: "0",
  })
  FeishuWebSocketFrame::{
    seq_id: frame.seq_id,
    log_id: frame.log_id,
    service: frame.service,
    method_id: frame.method_id,
    headers,
    payload_encoding: frame.payload_encoding,
    payload_type: frame.payload_type,
    payload: Some(ack_response_payload(response)),
    log_id_new: frame.log_id_new,
  }
}

///|
fn FeishuChannel::bind_platform_websocket(
  self : FeishuChannel,
  account_id : String,
  conn : @channel.WebSocketConnection,
) -> Unit {
  conn.on_message(bytes => {
    self.handle_platform_websocket_frame(account_id, conn, bytes)
  })
  conn.on_close(fn() {
    self.log_warn("Feishu websocket closed for account \{account_id}")
    for key in self.state.websocket_chunks.keys().to_array() {
      if key.has_prefix("\{account_id}:") {
        self.state.websocket_chunks.remove(key)
      }
    }
  })
}

///|
async fn FeishuChannel::handle_platform_websocket_frame(
  self : FeishuChannel,
  account_id : String,
  conn : @channel.WebSocketConnection,
  bytes : Bytes,
) -> Unit {
  let frame = match decode_feishu_websocket_frame(bytes) {
    Ok(frame) => frame
    Err(_) => return
  }
  if frame.method_id == feishu_ws_control_frame &&
    feishu_ws_header(frame, feishu_ws_header_type) == Some(feishu_ws_type_ping) {
    conn.send(
      encode_feishu_websocket_frame(FeishuWebSocketFrame::{
        seq_id: frame.seq_id,
        log_id: frame.log_id,
        service: frame.service,
        method_id: feishu_ws_control_frame,
        headers: [
          FeishuWebSocketHeader::{
            key: feishu_ws_header_type,
            value: feishu_ws_type_pong,
          },
        ],
        payload_encoding: frame.payload_encoding,
        payload_type: frame.payload_type,
        payload: frame.payload,
        log_id_new: frame.log_id_new,
      }),
    )
    return
  }
  guard frame.method_id == feishu_ws_data_frame else { return }
  guard feishu_ws_header(frame, feishu_ws_header_type) ==
    Some(feishu_ws_type_event) else {
    return
  }
  let event_json = match self.merge_platform_event_chunks(account_id, frame) {
    Some(event_json) => event_json
    None => return
  }
  let response = self.dispatch_feishu_event_frame(event_json)
  conn.send(encode_feishu_websocket_frame(ack_event_frame(frame, response)))
}

///|
fn extract_feishu_card_title(json : Json) -> String {
  match json {
    { "header": { "title": { "content": String(content), .. }, .. }, .. } =>
      content
    { "header": { "title": String(content), .. }, .. } => content
    { "title": String(content), .. } => content
    _ => ""
  }
}

///|
fn extract_feishu_card_summary(json : Json) -> String {
  let lines = []
  collect_feishu_card_text(json, lines)
  lines.filter(fn(line) { !line.is_blank() }).join("\n").trim().to_string()
}

///|
fn collect_feishu_card_text(json : Json, lines : Array[String]) -> Unit {
  match json {
    { "content": String(content), .. } if !content.is_blank() =>
      lines.push(content)
    { "text": String(text), .. } if !text.is_blank() => lines.push(text)
    { "label": String(label), .. } if !label.is_blank() => lines.push(label)
    { "name": String(name), .. } if !name.is_blank() => lines.push(name)
    Array(values) =>
      for value in values {
        collect_feishu_card_text(value, lines)
      }
    Object(obj) =>
      for _, value in obj {
        collect_feishu_card_text(value, lines)
      }
    _ => ()
  }
}

///|
fn FeishuChannel::resolve_account_id(self : FeishuChannel) -> String? {
  let running_ids = self.state.running
    .keys()
    .filter(fn(account_id) {
      match self.state.running.get(account_id) {
        Some(true) => true
        _ => false
      }
    })
    .to_array()
  match running_ids {
    [account_id] => Some(account_id)
    [account_id, ..] => Some(account_id)
    [] =>
      if self.state.feishu_configs.contains("default") {
        Some("default")
      } else {
        self.state.feishu_configs.keys().to_array().get(0)
      }
  }
}

///|
fn strip_feishu_mentions(text : String) -> String {
  let parts = text.split(" ").map(fn(part) { part.to_string() }).collect()
  parts
  .filter(fn(part) { !part.has_prefix("@_user_") })
  .join(" ")
  .trim()
  .to_string()
}

///|
priv struct ResolvedReactionTarget {
  chat_id : String
  chat_type : String?
  thread_id : String?
  content : String?
  content_type : String?
  sender_id : String?
  sender_type : String?
}

///|
fn feishu_queue_key(
  account_id : String,
  chat_id : String,
  thread_id : String?,
) -> String {
  match thread_id {
    Some(thread_id) if !thread_id.is_blank() =>
      "\{account_id}:\{chat_id}:thread:\{thread_id}"
    _ => "\{account_id}:\{chat_id}"
  }
}

///|
fn abort_triggers() -> Array[String] {
  [
    "stop", "esc", "abort", "wait", "exit", "interrupt", "halt", "stopp", "please stop",
    "stop please", "stop action", "stop current action", "stop run", "stop current run",
    "stop agent", "stop the agent", "停止", "やめて", "止めて",
  ]
}

///|
fn force_abort_triggers() -> Array[String] {
  [
    "/force-stop", "force stop", "force-stop", "hard stop", "hard-stop", "kill run",
    "kill agent", "kill conversation", "强制停止",
  ]
}

///|
fn normalize_abort_text(text : String) -> String {
  text
  .trim()
  .to_lower()
  .replace(old="'", new="")
  .replace(old="`", new="")
  .replace(old=",", new=" ")
  .replace(old=".", new=" ")
  .replace(old="!", new=" ")
  .replace(old="?", new=" ")
  .split(" ")
  .map(fn(part) { part.to_string() })
  .filter(fn(part) { !part.is_blank() })
  .join(" ")
}

///|
fn is_abort_text(text : String) -> Bool {
  let normalized = normalize_abort_text(text)
  normalized == "/stop" ||
  is_force_abort_text(text) ||
  abort_triggers().contains(normalized)
}

///|
fn is_force_abort_text(text : String) -> Bool {
  let normalized = normalize_abort_text(text)
  force_abort_triggers().contains(normalized)
}

///|
fn FeishuChannel::reaction_notifications_mode(
  self : FeishuChannel,
  account_id : String,
) -> String {
  match self.state.feishu_configs.get(account_id) {
    Some(config) => config.reaction_notifications.unwrap_or("own")
    None => "own"
  }
}

///|
fn FeishuChannel::feishu_app_id(
  self : FeishuChannel,
  account_id : String,
) -> String {
  match self.state.feishu_configs.get(account_id) {
    Some(config) => config.app_id
    None => ""
  }
}

///|
fn FeishuChannel::should_ignore_reaction_event(
  self : FeishuChannel,
  operator_type : String?,
  operator_open_id : String?,
  emoji_type : String?,
) -> Bool {
  ignore(self)
  match operator_type {
    Some("app") => true
    _ =>
      match emoji_type {
        Some("Typing") => true
        _ =>
          match operator_open_id {
            Some(open_id) => open_id.is_blank()
            None => true
          }
      }
  }
}

///|
async fn FeishuChannel::lookup_reaction_message(
  self : FeishuChannel,
  account_id : String,
  message_id : String,
) -> Result[ResolvedReactionTarget?, @channel.ChannelError] {
  match self.state.clients.get(account_id) {
    Some(client) =>
      match client.get_message(message_id) {
        Ok(Some(item)) =>
          Ok(
            Some(ResolvedReactionTarget::{
              chat_id: item.chat_id,
              chat_type: item.chat_type,
              thread_id: item.thread_id,
              content: parse_lookup_content(item),
              content_type: item.msg_type,
              sender_id: match item.sender {
                Some(sender) => sender.id
                None => None
              },
              sender_type: match item.sender {
                Some(sender) => sender.sender_type
                None => None
              },
            }),
          )
        Ok(None) => Ok(None)
        Err(error) => Err(error)
      }
    None =>
      Err(
        @channel.ChannelError::NotConfigured(
          message="Client not initialized for account: \{account_id}",
        ),
      )
  }
}

///|
fn parse_lookup_content(item : FeishuMessageLookupItem) -> String? {
  match item.body {
    Some(body) =>
      match body.content {
        Some(content) => Some(parse_feishu_text_content(content))
        None => None
      }
    None => None
  }
}

///|
fn is_own_reaction_target(
  target : ResolvedReactionTarget,
  app_id : String,
) -> Bool {
  if app_id.is_blank() {
    false
  } else {
    target.sender_type == Some("app") && target.sender_id == Some(app_id)
  }
}

///|
fn is_expired_message(timestamp : Int64) -> Bool {
  if timestamp <= 0 {
    false
  } else {
    @clock.epoch.now().ms() - timestamp > 15 * 60 * 1000
  }
}

///|
fn FeishuChannel::enqueue_message(
  self : FeishuChannel,
  queue_key : String,
  message : QueuedFeishuMessage,
) -> Unit {
  let queue = match self.state.pending_messages.get(queue_key) {
    Some(queue) => queue
    None => []
  }
  queue.push(message)
  self.state.pending_messages[queue_key] = queue
}

///|
fn FeishuChannel::clear_queue(self : FeishuChannel, queue_key : String) -> Unit {
  self.state.pending_messages.remove(queue_key) |> ignore()
}

///|
fn FeishuChannel::dequeue_message(
  self : FeishuChannel,
  queue_key : String,
) -> QueuedFeishuMessage? {
  match self.state.pending_messages.get(queue_key) {
    Some(queue) if !queue.is_empty() => {
      let next = queue[0]
      let remaining = queue[1:].to_array()
      if remaining.is_empty() {
        self.state.pending_messages.remove(queue_key) |> ignore()
      } else {
        self.state.pending_messages[queue_key] = remaining
      }
      Some(next)
    }
    _ => None
  }
}

///|
fn FeishuChannel::request_queue_cancel(
  self : FeishuChannel,
  queue_key : String,
) -> Unit {
  self.clear_queue(queue_key)
  if self.is_processing_queue(queue_key) {
    self.state.cancelled_queues[queue_key] = true
  } else {
    self.state.cancelled_queues.remove(queue_key) |> ignore()
  }
}

///|
fn FeishuChannel::is_queue_cancelled(
  self : FeishuChannel,
  queue_key : String,
) -> Bool {
  match self.state.cancelled_queues.get(queue_key) {
    Some(true) => true
    _ => false
  }
}

///|
fn FeishuChannel::clear_queue_cancel(
  self : FeishuChannel,
  queue_key : String,
) -> Unit {
  self.state.cancelled_queues.remove(queue_key) |> ignore()
}

///|
fn FeishuChannel::is_processing_queue(
  self : FeishuChannel,
  queue_key : String,
) -> Bool {
  match self.state.processing_keys.get(queue_key) {
    Some(true) => true
    _ => false
  }
}

///|
fn FeishuChannel::set_processing_queue(
  self : FeishuChannel,
  queue_key : String,
  processing : Bool,
) -> Unit {
  self.state.processing_keys[queue_key] = processing
}

///|
fn FeishuChannel::finish_processing_queue(
  self : FeishuChannel,
  queue_key : String,
) -> Unit {
  self.state.processing_keys.remove(queue_key) |> ignore()
}

///|
async fn FeishuChannel::process_queued_messages(
  self : FeishuChannel,
  queue_key : String,
  handler : &@channel.MessageHandler,
) -> @channel.ExtensionResponse {
  let mut last_response = @channel.ExtensionResponse::ok()
  while true {
    if self.is_queue_cancelled(queue_key) {
      self.clear_queue_cancel(queue_key)
      break
    }
    guard self.dequeue_message(queue_key) is Some(queued) else { break }
    try {
      let response_message = handler.handle_message(
        "feishu",
        queued.account_id,
        queued.message,
      )
      match
        self.send(
          response_message.to,
          response_message,
          Some(queued.account_id),
        ) {
        Ok(_) => last_response = @channel.ExtensionResponse::ok()
        Err(e) =>
          last_response = @channel.ExtensionResponse::internal_error(
            message="Failed to send response: \{e}",
          )
      }
    } catch {
      e =>
        last_response = @channel.ExtensionResponse::internal_error(
          message="Error processing message: \{e}",
        )
    }
  }
  last_response
}

///|
async fn FeishuChannel::send_cancel_acknowledgement(
  self : FeishuChannel,
  account_id : String,
  chat_id : String,
  message_id : String,
  thread_id : String?,
  force~ : Bool,
) -> Unit {
  let text = if force {
    "Force stop requested. I will stop this conversation and reset the current session."
  } else {
    "Stop requested. I will stop the current conversation after the current step."
  }
  match self.state.clients.get(account_id) {
    Some(client) =>
      match
        client.send_text_message(
          chat_id,
          text,
          reply_to=Some(message_id),
          reply_in_thread=match thread_id {
            Some(_) => true
            None => false
          },
        ) {
        Ok(_) => ()
        Err(error) =>
          self.log_warn("Failed to send Feishu stop acknowledgement: \{error}")
      }
    None => ()
  }
}

///|
fn FeishuChannel::remember_message_id(
  self : FeishuChannel,
  message_id : String,
) -> Unit {
  self.state.recent_message_ids.push(message_id)
  if self.state.recent_message_ids.length() > 256 {
    ignore(self.state.recent_message_ids.remove(0))
  }
}

///|
fn FeishuChannel::remember_event_id(
  self : FeishuChannel,
  event_id : String,
) -> Unit {
  self.state.recent_event_ids.push(event_id)
  if self.state.recent_event_ids.length() > 256 {
    ignore(self.state.recent_event_ids.remove(0))
  }
}

///|
fn FeishuChannel::is_duplicate_event(
  self : FeishuChannel,
  event_id : String?,
) -> Bool {
  match event_id {
    Some(event_id) =>
      if self.state.recent_event_ids.contains(event_id) {
        true
      } else {
        self.remember_event_id(event_id)
        false
      }
    None => false
  }
}

///|
fn FeishuChannel::is_duplicate_message_id(
  self : FeishuChannel,
  message_id : String,
) -> Bool {
  if self.state.recent_message_ids.contains(message_id) {
    true
  } else {
    self.remember_message_id(message_id)
    false
  }
}

///|
fn FeishuChannel::resolve_account_id_for_event(
  self : FeishuChannel,
  app_id : String?,
  _json : Json,
) -> String? {
  match app_id {
    Some(app_id) => {
      for account_id, config in self.state.feishu_configs {
        if config.app_id == app_id {
          return Some(account_id)
        }
      }
      None
    }
    None => self.resolve_account_id()
  }
}

///|
fn FeishuChannel::verify_request_token(
  self : FeishuChannel,
  account_id : String,
  json : Json,
) -> Bool {
  let expected = match self.state.feishu_configs.get(account_id) {
    Some(config) => config.verify_token
    None => None
  }
  match expected {
    Some(token) if token.length() > 0 =>
      match json {
        { "token": String(actual), .. } => actual == token
        { "header": { "token": String(actual), .. }, .. } => actual == token
        _ => false
      }
    _ => true
  }
}

///|
fn FeishuChannel::is_url_verification_request(
  _self : FeishuChannel,
  json : Json,
) -> Bool {
  match json {
    { "type": String(kind), "challenge": String(_), .. } =>
      kind == "url_verification"
    _ => false
  }
}

///|
fn FeishuChannel::handle_url_verification(
  self : FeishuChannel,
  json : Json,
) -> @channel.ExtensionResponse {
  let account_id = self
    .resolve_account_id_for_event(None, json)
    .unwrap_or("default")
  if !self.verify_request_token(account_id, json) {
    return @channel.ExtensionResponse::bad_request(
      message="Feishu verify_token mismatch",
    )
  }
  match json {
    { "challenge": String(challenge), .. } =>
      @channel.ExtensionResponse::json({ "challenge": challenge })
    _ =>
      @channel.ExtensionResponse::bad_request(
        message="Missing challenge in verification request",
      )
  }
}
