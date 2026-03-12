///|
struct FeishuChannelState {
  mut config : @channel.ChannelConfig
  mut feishu_configs : Map[String, FeishuAccountConfig]
  clients : Map[String, FeishuClient]
  running : Map[String, Bool]
  recent_event_ids : Array[String]
  recent_message_ids : Array[String]
  pending_messages : Map[String, Array[QueuedFeishuMessage]]
  processing_keys : Map[String, Bool]
  mut message_handler : &@channel.MessageHandler?
}

///|
struct QueuedFeishuMessage {
  account_id : String
  chat_id : String
  thread_id : String?
  message_id : String
  content : String
  timestamp : Int
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
      config: @channel.default_config(),
      feishu_configs: {},
      clients: {},
      running: {},
      recent_event_ids: [],
      recent_message_ids: [],
      pending_messages: {},
      processing_keys: {},
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
        reaction_notifications: Some("own"),
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
pub fn FeishuChannel::with_extension(
  self : FeishuChannel,
  apply : (&@channel.ChannelExtension) -> Unit raise,
) -> Unit raise {
  apply(self)
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
    native_commands: true,
    block_streaming: true,
  }
}

///|
impl @channel.Channel for FeishuChannel with configure(
  self : FeishuChannel,
  config : @channel.ChannelConfig,
) -> Unit {
  self.state.config = config
  self.state.feishu_configs = {}
  self.state.recent_event_ids.clear()
  self.state.recent_message_ids.clear()
  self.state.pending_messages.clear()
  self.state.processing_keys.clear()
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
    Some(client) =>
      client.send_text_message(
        to,
        message.content,
        reply_to=message.reply_to,
        reply_in_thread=match message.thread_id {
          Some(_) => true
          None => false
        },
      )
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

  let content = match message_data {
    { "content": String(c), .. } =>
      parse_feishu_message_content(c, message_type)
    _ => None
  }
  guard content is Some(content) else {
    return @channel.ExtensionResponse::ok()
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
        handler.handle_event("feishu", account_id, @channel.ChannelEvent::{
          channel: "feishu",
          account_id,
          event_type: "cancel",
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
          chat_id,
          thread_id,
          message_id,
          content,
          timestamp,
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
    self.state.clients.remove(account_id)
    self.state.running[account_id] = false
  }
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
struct ResolvedReactionTarget {
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
  normalized == "/stop" || abort_triggers().contains(normalized)
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
  while self.dequeue_message(queue_key) is Some(queued) {
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
  self : FeishuChannel,
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
