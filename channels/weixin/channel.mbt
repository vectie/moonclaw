///|
struct WeixinChannelState {
  mut _config : @channel.ChannelConfig
  mut weixin_configs : Map[String, WeixinAccountConfig]
  clients : Map[String, WeixinClient]
  running : Map[String, Bool]
  recent_message_ids : Array[String]
  mut message_handler : &@channel.MessageHandler?
}

///|
pub struct WeixinChannel {
  priv state : WeixinChannelState
}

///|
pub fn WeixinChannel::new() -> WeixinChannel {
  WeixinChannel::{
    state: WeixinChannelState::{
      _config: @channel.default_config(),
      weixin_configs: {},
      clients: {},
      running: {},
      recent_message_ids: [],
      message_handler: None,
    },
  }
}

///|
fn get_weixin_config(config : Json) -> WeixinAccountConfig {
  let fallback = WeixinAccountConfig::{
    app_id: "",
    app_secret: "",
    token: "",
    original_id: None,
    api_base_url: None,
    enabled: false,
  }
  match config {
    {
      "appId": String(app_id),
      "appSecret": String(app_secret),
      "token": String(token),
      ..
    } =>
      WeixinAccountConfig::{
        app_id,
        app_secret,
        token,
        original_id: match config {
          { "originalId": String(value), .. } => Some(value)
          { "original_id": String(value), .. } => Some(value)
          _ => None
        },
        api_base_url: match config {
          { "apiBaseUrl": String(value), .. } => Some(value)
          { "api_base_url": String(value), .. } => Some(value)
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
pub fn WeixinChannel::set_message_handler(
  self : WeixinChannel,
  handler : &@channel.MessageHandler,
) -> Unit {
  self.state.message_handler = Some(handler)
}

///|
pub fn WeixinChannel::with_extension(
  self : WeixinChannel,
  apply : (&@channel.ChannelExtension) -> Unit raise,
) -> Unit raise {
  apply(self)
}

///|
fn weixin_hex_char(n : Int) -> Char {
  if n < 10 {
    ('0'.to_int() + n).unsafe_to_char()
  } else {
    ('a'.to_int() + n - 10).unsafe_to_char()
  }
}

///|
fn lowercase_hex(bytes : FixedArray[Byte]) -> String {
  let builder = StringBuilder::new()
  for byte in bytes {
    let value = byte.to_int()
    builder.write_char(weixin_hex_char((value >> 4) & 0xF))
    builder.write_char(weixin_hex_char(value & 0xF))
  }
  builder.to_string()
}

///|
fn weixin_signature(
  token : String,
  timestamp : String,
  nonce : String,
) -> String {
  let parts = [token, timestamp, nonce]
  parts.sort()
  let digest = @crypto.sha1(@encoding/utf8.encode(parts.join("")))
  lowercase_hex(digest)
}

///|
fn verify_weixin_signature(
  token : String,
  signature : String,
  timestamp : String,
  nonce : String,
) -> Bool {
  weixin_signature(token, timestamp, nonce) ==
  signature.trim().to_lower().to_string()
}

///|
fn xml_tag_value(xml : String, tag : String) -> String? {
  let start = "<\{tag}>"
  let parts = xml.split(start).collect()
  if parts.length() < 2 {
    return None
  }
  let tail = parts[1]
  let end = "</\{tag}>"
  let end_parts = tail.split(end).collect()
  if end_parts.is_empty() {
    None
  } else {
    Some(strip_xml_cdata(end_parts[0].to_string()).trim().to_string())
  }
}

///|
fn strip_xml_cdata(text : String) -> String {
  let start = "<![CDATA["
  let end = "]]>"
  if !text.has_prefix(start) {
    return text
  }
  let tail = text[start.length():].to_string()
  let parts = tail.split(end).collect()
  if parts.is_empty() {
    text
  } else {
    parts[0].to_string()
  }
}

///|
fn parse_weixin_timestamp_ms(raw : String?) -> Int {
  match raw {
    Some(value) => (@strconv.parse_int(value) catch { _ => 0 }) * 1000
    None => 0
  }
}

///|
fn WeixinChannel::default_account_id(self : WeixinChannel) -> String? {
  if self.state.weixin_configs.contains("default") {
    return Some("default")
  }
  let ids = self.state.weixin_configs.keys().to_array()
  ids.get(0)
}

///|
fn WeixinChannel::resolve_account_from_query(
  self : WeixinChannel,
  request : @channel.ExtensionRequest,
) -> String? {
  match request.query_param("account_id") {
    Some(account_id) if self.state.weixin_configs.contains(account_id) =>
      Some(account_id)
    _ => self.default_account_id()
  }
}

///|
fn WeixinChannel::resolve_account_for_xml(
  self : WeixinChannel,
  request : @channel.ExtensionRequest,
  xml : String,
) -> String? {
  match request.query_param("account_id") {
    Some(account_id) if self.state.weixin_configs.contains(account_id) =>
      return Some(account_id)
    _ => ()
  }
  let to_user_name = xml_tag_value(xml, "ToUserName")
  for account_id, config in self.state.weixin_configs {
    match config.original_id {
      Some(original_id) if to_user_name == Some(original_id) =>
        return Some(account_id)
      _ => ()
    }
  }
  self.default_account_id()
}

///|
fn WeixinChannel::is_duplicate_message_id(
  self : WeixinChannel,
  message_id : String,
) -> Bool {
  if self.state.recent_message_ids.contains(message_id) {
    true
  } else {
    self.state.recent_message_ids.push(message_id)
    if self.state.recent_message_ids.length() > 128 {
      ignore(self.state.recent_message_ids.remove(0))
    }
    false
  }
}

///|
fn weixin_incoming_message(xml : String) -> @channel.Message? {
  let from_user = xml_tag_value(xml, "FromUserName")
  let message_id = xml_tag_value(xml, "MsgId")
  let msg_type = xml_tag_value(xml, "MsgType").unwrap_or("text")
  guard from_user is Some(from_user) else { return None }
  guard message_id is Some(message_id) else { return None }
  let content = match msg_type {
    "text" => xml_tag_value(xml, "Content").unwrap_or("")
    _ => return None
  }
  Some(@channel.Message::{
    id: message_id,
    channel: "weixin",
    from: from_user,
    to: from_user,
    content,
    content_type: msg_type,
    timestamp: parse_weixin_timestamp_ms(xml_tag_value(xml, "CreateTime")),
    thread_id: None,
    reply_to: None,
    attachments: [],
  })
}

///|
impl @channel.Channel for WeixinChannel with id(_self : WeixinChannel) -> @channel.ChannelId {
  "weixin"
}

///|
impl @channel.Channel for WeixinChannel with meta(_self : WeixinChannel) -> @channel.ChannelMeta {
  @channel.ChannelMeta::{
    id: "weixin",
    label: "Weixin",
    selection_label: "Weixin Official Account (微信公众平台)",
    docs_path: "/channels/weixin",
    docs_label: Some("weixin"),
    blurb: "微信公众号 webhook and custom-service messaging.",
    order: Some(75),
    aliases: ["wechat"],
  }
}

///|
impl @channel.Channel for WeixinChannel with capabilities(_self : WeixinChannel) -> @channel.ChannelCapabilities {
  @channel.ChannelCapabilities::{
    chat_types: [@channel.ChatType::Direct],
    polls: false,
    reactions: false,
    edit: false,
    unsend: false,
    reply: true,
    effects: false,
    group_management: false,
    threads: false,
    media: false,
    native_commands: true,
    block_streaming: false,
  }
}

///|
impl @channel.Channel for WeixinChannel with configure(
  self : WeixinChannel,
  config : @channel.ChannelConfig,
) -> Unit {
  self.state._config = config
  self.state.weixin_configs = {}
  self.state.recent_message_ids.clear()
  for account_id, account_config in config.accounts {
    self.state.weixin_configs[account_id] = get_weixin_config(account_config)
  }
}

///|
impl @channel.Channel for WeixinChannel with start(
  self : WeixinChannel,
  account_id : String,
  config : Json,
) -> Result[Unit, @channel.ChannelError] {
  let weixin_config = get_weixin_config(config)
  if !weixin_config.enabled {
    return Err(
      @channel.ChannelError::NotConfigured(message="Channel is not enabled"),
    )
  }
  self.state.clients[account_id] = WeixinClient::new(weixin_config)
  self.state.running[account_id] = true
  Ok(())
}

///|
impl @channel.Channel for WeixinChannel with stop(
  self : WeixinChannel,
  account_id : String,
) -> Result[Unit, @channel.ChannelError] {
  self.state.clients.remove(account_id)
  self.state.running[account_id] = false
  Ok(())
}

///|
impl @channel.Channel for WeixinChannel with send(
  self : WeixinChannel,
  to : String,
  message : @channel.Message,
  account_id : String?,
) -> Result[@channel.SendResult, @channel.ChannelError] {
  if message.content_type == "progress" {
    return Ok(@channel.SendResult::{
      channel: "weixin",
      message_id: message.id,
      timestamp: 0,
      status: "updated",
    })
  }
  let actual_account_id = match account_id {
    Some(id) => id
    None =>
      match self.default_account_id() {
        Some(id) => id
        None =>
          return Err(
            @channel.ChannelError::NotConfigured(
              message="No configured Weixin account available",
            ),
          )
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
impl @channel.Channel for WeixinChannel with handle_event(
  _self : WeixinChannel,
  _event : @channel.ChannelEvent,
) -> Unit {

}

///|
impl @channel.Channel for WeixinChannel with is_running(
  self : WeixinChannel,
  account_id : String,
) -> Bool {
  match self.state.running.get(account_id) {
    Some(running) => running
    None => false
  }
}

///|
impl @channel.ChannelExtension for WeixinChannel with webhook_path(
  _self : WeixinChannel,
) -> String {
  "/webhook/weixin"
}

///|
impl @channel.ChannelExtension for WeixinChannel with handle_webhook(
  self : WeixinChannel,
  request : @channel.ExtensionRequest,
) -> @channel.ExtensionResponse {
  let account_id = match request.http_method() {
    "POST" => {
      let xml = @encoding/utf8.decode(request.body()) catch {
        _ =>
          return @channel.ExtensionResponse::bad_request(
            message="Invalid UTF-8 in Weixin webhook body",
          )
      }
      let resolved = self.resolve_account_for_xml(request, xml)
      match resolved {
        Some(account_id) => {
          let config = self.state.weixin_configs.get(account_id).unwrap()
          let signature = request.query_param("signature").unwrap_or("")
          let timestamp = request.query_param("timestamp").unwrap_or("")
          let nonce = request.query_param("nonce").unwrap_or("")
          if !verify_weixin_signature(config.token, signature, timestamp, nonce) {
            return @channel.ExtensionResponse::bad_request(
              message="Weixin signature mismatch",
            )
          }
          if xml_tag_value(xml, "Encrypt") is Some(_) {
            return @channel.ExtensionResponse::bad_request(
              message="Encrypted Weixin webhooks are not supported yet",
            )
          }
          let incoming = match weixin_incoming_message(xml) {
            Some(message) => message
            None => return @channel.ExtensionResponse::text("success")
          }
          if self.is_duplicate_message_id(incoming.id) {
            return @channel.ExtensionResponse::text("success")
          }
          match self.state.message_handler {
            Some(handler) =>
              try {
                let response_message = handler.handle_message(
                  "weixin", account_id, incoming,
                )
                match
                  self.send(
                    response_message.to,
                    response_message,
                    Some(account_id),
                  ) {
                  Ok(_) => @channel.ExtensionResponse::text("success")
                  Err(error) =>
                    @channel.ExtensionResponse::internal_error(
                      message="Failed to send Weixin response: \{error}",
                    )
                }
              } catch {
                error =>
                  @channel.ExtensionResponse::internal_error(
                    message="Error processing Weixin message: \{error}",
                  )
              }
            None => @channel.ExtensionResponse::text("success")
          }
        }
        None =>
          @channel.ExtensionResponse::bad_request(
            message="No matching Weixin account configured for webhook",
          )
      }
    }
    "GET" => {
      let account_id = match self.resolve_account_from_query(request) {
        Some(account_id) => account_id
        None =>
          return @channel.ExtensionResponse::bad_request(
            message="No matching Weixin account configured for verification",
          )
      }
      let config = self.state.weixin_configs.get(account_id).unwrap()
      let signature = request.query_param("signature").unwrap_or("")
      let timestamp = request.query_param("timestamp").unwrap_or("")
      let nonce = request.query_param("nonce").unwrap_or("")
      let echostr = request.query_param("echostr").unwrap_or("")
      if !verify_weixin_signature(config.token, signature, timestamp, nonce) {
        return @channel.ExtensionResponse::bad_request(
          message="Weixin signature mismatch",
        )
      }
      @channel.ExtensionResponse::text(echostr)
    }
    _ =>
      @channel.ExtensionResponse::bad_request(
        message="Method not allowed: \{request.http_method()}",
      )
  }
  account_id
}

///|
impl @channel.ChannelExtension for WeixinChannel with supports_websocket(
  _self : WeixinChannel,
) -> Bool {
  false
}

///|
impl @channel.ChannelExtension for WeixinChannel with handle_websocket(
  _self : WeixinChannel,
  _conn : @channel.WebSocketConnection,
) -> Unit {

}

///|
impl @channel.ChannelExtension for WeixinChannel with allowed_methods(
  _self : WeixinChannel,
) -> Array[String] {
  ["GET", "POST"]
}

///|
impl @channel.ChannelExtension for WeixinChannel with dock_config(
  _self : WeixinChannel,
) -> @channel.ChannelDockConfig {
  @channel.ChannelDockConfig::default_for_channel("weixin")
}

///|
impl @channel.ChannelExtension for WeixinChannel with on_register(
  self : WeixinChannel,
  context : @channel.ExtensionContext,
) -> Unit {
  ignore(self)
  ignore(context)
}

///|
impl @channel.ChannelExtension for WeixinChannel with on_unregister(
  self : WeixinChannel,
) -> Unit {
  ignore(self)
}
