///|
pub struct FeishuClient {
  config : FeishuAccountConfig
}

///|
pub struct FeishuStreamingCardSession {
  card_id : String
  message_id : String
  sequence : Int
  current_text : String
} derive(Show)

///|
pub struct FeishuTypingIndicatorState {
  message_id : String
  reaction_id : String
} derive(Show)

///|
pub struct FeishuReactionIndicatorState {
  message_id : String
  reaction_id : String
  emoji_type : String
} derive(Show)

///|
pub fn FeishuClient::new(config : FeishuAccountConfig) -> FeishuClient {
  FeishuClient::{ config, }
}

///|
fn websocket_endpoint_request_payload(
  app_id : String,
  app_secret : String,
) -> Json {
  { "AppID": app_id, "AppSecret": app_secret }
}

///|
fn parse_feishu_websocket_client_config(
  json : Json,
) -> FeishuWebSocketClientConfig? {
  match json {
    Object(obj) =>
      Some(FeishuWebSocketClientConfig::{
        ping_interval: obj.get("PingInterval").bind(parse_json_int),
        reconnect_count: obj.get("ReconnectCount").bind(parse_json_int),
        reconnect_interval: obj.get("ReconnectInterval").bind(parse_json_int),
        reconnect_nonce: obj.get("ReconnectNonce").bind(parse_json_int),
      })
    _ => None
  }
}

///|
fn parse_feishu_websocket_endpoint_data(
  json : Json,
) -> FeishuWebSocketEndpointData? {
  match json {
    { "URL": String(url), .. } if !url.is_blank() =>
      Some(FeishuWebSocketEndpointData::{
        url,
        client_config: match json {
          { "ClientConfig": client_config, .. } =>
            parse_feishu_websocket_client_config(client_config)
          _ => None
        },
      })
    _ => None
  }
}

///|
fn parse_json_int(json : Json) -> Int? {
  match json {
    Number(number, ..) => Some(number.to_int())
    String(number) =>
      Some(@strconv.parse_int(number) catch { _ => return None })
    _ => None
  }
}

///|
fn feishu_base_url(domain : String) -> String {
  match domain {
    "lark" => "https://open.larksuite.com"
    "feishu" => "https://open.feishu.cn"
    _ =>
      if domain.has_prefix("http://") || domain.has_prefix("https://") {
        domain
      } else {
        "https://\{domain}"
      }
  }
}

///|
fn detect_receive_id_type(target : String) -> (String, String) {
  if target.has_prefix("chat:") {
    ("chat_id", target[5:].to_string())
  } else if target.has_prefix("user:") {
    ("open_id", target[5:].to_string())
  } else if target.has_prefix("open_id:") {
    ("open_id", target[8:].to_string())
  } else if target.has_prefix("user_id:") {
    ("user_id", target[8:].to_string())
  } else if target.has_prefix("ou_") {
    ("open_id", target)
  } else {
    ("chat_id", target)
  }
}

///|
fn build_text_content(text : String) -> Json {
  { "text": text }
}

///|
fn build_streaming_card_content(card_id : String) -> Json {
  { "type": "card", "data": { "card_id": card_id } }
}

///|
fn build_streaming_card_json(initial_text : String) -> Json {
  {
    "schema": "2.0",
    "config": {
      "streaming_mode": true,
      "summary": { "content": "[Generating...]" },
      "streaming_config": {
        "print_frequency_ms": { "default": 50 },
        "print_step": { "default": 1 },
      },
    },
    "body": {
      "elements": [
        { "tag": "markdown", "content": initial_text, "element_id": "content" },
      ],
    },
  }
}

///|
fn truncate_stream_summary(text : String, max_chars? : Int = 50) -> String {
  let clean = text.replace(old="\n", new=" ").trim().to_string()
  if clean.is_blank() {
    "[Generating...]"
  } else if clean.length() <= max_chars {
    clean
  } else {
    clean[:max_chars - 3].trim().to_string() + "..."
  }
}

///|
fn parse_json_code_msg(
  response_json : Json,
  error_prefix : String,
) -> Result[(Int, String), @channel.ChannelError] {
  let code = match response_json {
    { "code": Number(code, ..), .. } => code.to_int()
    { "code": String(code), .. } =>
      @strconv.parse_int(code) catch {
        _ =>
          return Err(
            @channel.ChannelError::SendMessageFailed(
              message="\{error_prefix}: invalid response code",
            ),
          )
      }
    _ =>
      return Err(
        @channel.ChannelError::SendMessageFailed(
          message="\{error_prefix}: missing response code",
        ),
      )
  }
  let msg = match response_json {
    { "msg": String(msg), .. } => msg
    _ => ""
  }
  Ok((code, msg))
}

///|
fn parse_card_id(
  response_json : Json,
  error_prefix : String,
) -> Result[String, @channel.ChannelError] {
  match response_json {
    { "data": { "card_id": String(card_id), .. }, .. } if !card_id.is_blank() =>
      Ok(card_id)
    _ =>
      Err(
        @channel.ChannelError::SendMessageFailed(
          message="\{error_prefix}: missing card_id",
        ),
      )
  }
}

///|
fn parse_reaction_id(
  response_json : Json,
  error_prefix : String,
) -> Result[String, @channel.ChannelError] {
  match response_json {
    { "data": { "reaction_id": String(reaction_id), .. }, .. } if !reaction_id.is_blank() =>
      Ok(reaction_id)
    _ =>
      Err(
        @channel.ChannelError::SendMessageFailed(
          message="\{error_prefix}: missing reaction_id",
        ),
      )
  }
}

///|
async fn authed_feishu_http_client(
  config : FeishuAccountConfig,
) -> Result[@http.Client, @channel.ChannelError] {
  let token = match FeishuClient::new(config).load_tenant_access_token() {
    Ok(token) => token
    Err(error) => return Err(error)
  }
  let base_url = feishu_base_url(config.domain)
  let client = @http.Client::new(base_url, headers={
    "Authorization": "Bearer \{token}",
    "Content-Type": "application/json",
    "Connection": "close",
  }) catch {
    error =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to create Feishu HTTP client: \{error}",
        ),
      )
  }
  Ok(client)
}

///|
fn pick_feishu_user_name(user : FeishuUser) -> String {
  let primary = user.name.unwrap_or("")
  if !primary.is_blank() {
    primary
  } else {
    let display = user.display_name.unwrap_or("")
    if !display.is_blank() {
      display
    } else {
      let nickname = user.nickname.unwrap_or("")
      if !nickname.is_blank() {
        nickname
      } else {
        let english_name = user.en_name.unwrap_or("")
        if !english_name.is_blank() {
          english_name
        } else {
          ""
        }
      }
    }
  }
}

///|
async fn parse_send_response(
  response : @http.Response,
  client : @http.Client,
) -> Result[@channel.SendResult, @channel.ChannelError] {
  let body_text = client.read_all().text() catch {
      error =>
        return Err(
          @channel.ChannelError::SendMessageFailed(
            message="Failed to read Feishu response body: \{error}",
          ),
        )
    }
  guard response.code is (200..=299) else {
    return Err(
      @channel.ChannelError::SendMessageFailed(
        message="Feishu API error \{response.code}: \{body_text}",
      ),
    )
  }
  let response_json : Json = @json.parse(body_text) catch {
    _ =>
      return Err(
        @channel.ChannelError::SendMessageFailed(
          message="Invalid Feishu response: \{body_text}",
        ),
      )
  }
  let parsed : FeishuSendMessageResponse = @json.from_json(response_json) catch {
    _ =>
      return Err(
        @channel.ChannelError::SendMessageFailed(
          message="Failed to decode Feishu response: \{body_text}",
        ),
      )
  }
  if parsed.code != 0 {
    return Err(
      @channel.ChannelError::SendMessageFailed(
        message="Feishu send failed: \{parsed.msg}",
      ),
    )
  }
  Ok(@channel.SendResult::{
    channel: "feishu",
    message_id: parsed.data.map(fn(data) { data.message_id }).unwrap_or(""),
    timestamp: 0,
    status: "sent",
  })
}

///|
async fn parse_lookup_response(
  response : @http.Response,
  client : @http.Client,
) -> Result[FeishuMessageLookupItem?, @channel.ChannelError] {
  let body_text = client.read_all().text() catch {
      error =>
        return Err(
          @channel.ChannelError::ConnectionFailed(
            message="Failed to read Feishu lookup response body: \{error}",
          ),
        )
    }
  guard response.code is (200..=299) else {
    return Err(
      @channel.ChannelError::ConnectionFailed(
        message="Feishu lookup API error \{response.code}: \{body_text}",
      ),
    )
  }
  let response_json : Json = @json.parse(body_text) catch {
    _ =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Invalid Feishu lookup response: \{body_text}",
        ),
      )
  }
  let parsed : FeishuMessageLookupResponse = @json.from_json(response_json) catch {
    _ =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to decode Feishu lookup response: \{body_text}",
        ),
      )
  }
  if parsed.code != 0 {
    return Err(
      @channel.ChannelError::ConnectionFailed(
        message="Feishu lookup failed: \{parsed.msg}",
      ),
    )
  }
  Ok(parsed.data.bind(fn(data) { data.items.get(0) }))
}

///|
async fn parse_lookup_items_response(
  response : @http.Response,
  client : @http.Client,
) -> Result[Array[FeishuMessageLookupItem], @channel.ChannelError] {
  let body_text = client.read_all().text() catch {
      error =>
        return Err(
          @channel.ChannelError::ConnectionFailed(
            message="Failed to read Feishu lookup response body: \{error}",
          ),
        )
    }
  guard response.code is (200..=299) else {
    return Err(
      @channel.ChannelError::ConnectionFailed(
        message="Feishu lookup API error \{response.code}: \{body_text}",
      ),
    )
  }
  let response_json : Json = @json.parse(body_text) catch {
    _ =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Invalid Feishu lookup response: \{body_text}",
        ),
      )
  }
  let parsed : FeishuMessageLookupResponse = @json.from_json(response_json) catch {
    _ =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to decode Feishu lookup response: \{body_text}",
        ),
      )
  }
  if parsed.code != 0 {
    return Err(
      @channel.ChannelError::ConnectionFailed(
        message="Feishu lookup failed: \{parsed.msg}",
      ),
    )
  }
  Ok(parsed.data.map(fn(data) { data.items }).unwrap_or([]))
}

///|
async fn parse_user_lookup_response(
  response : @http.Response,
  client : @http.Client,
) -> Result[String?, @channel.ChannelError] {
  let body_text = client.read_all().text() catch {
      error =>
        return Err(
          @channel.ChannelError::ConnectionFailed(
            message="Failed to read Feishu user lookup response body: \{error}",
          ),
        )
    }
  guard response.code is (200..=299) else {
    return Err(
      @channel.ChannelError::ConnectionFailed(
        message="Feishu user lookup API error \{response.code}: \{body_text}",
      ),
    )
  }
  let response_json : Json = @json.parse(body_text) catch {
    _ =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Invalid Feishu user lookup response: \{body_text}",
        ),
      )
  }
  let parsed : FeishuUserLookupResponse = @json.from_json(response_json) catch {
    _ =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to decode Feishu user lookup response: \{body_text}",
        ),
      )
  }
  if parsed.code != 0 {
    return Err(
      @channel.ChannelError::ConnectionFailed(
        message="Feishu user lookup failed: \{parsed.msg}",
      ),
    )
  }
  let user = parsed.data.bind(fn(data) { data.user })
  Ok(
    user
    .map(pick_feishu_user_name)
    .bind(fn(name) { if name.is_blank() { None } else { Some(name) } }),
  )
}

///|
pub async fn resolve_websocket_endpoint(
  app_id : String,
  app_secret : String,
  domain : String,
) -> Result[FeishuWebSocketEndpointData, @channel.ChannelError] {
  let base_url = feishu_base_url(domain)
  let (response, data) = @http.post(
    "\{base_url}/callback/ws/endpoint",
    websocket_endpoint_request_payload(app_id, app_secret),
    headers={ "Content-Type": "application/json", "locale": "zh" },
  ) catch {
    error =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to fetch Feishu websocket endpoint: \{error}",
        ),
      )
  }
  let body_text = data.text()
  guard response.code is (200..=299) else {
    return Err(
      @channel.ChannelError::ConnectionFailed(
        message="Feishu websocket endpoint API error \{response.code}: \{body_text}",
      ),
    )
  }
  let response_json : Json = @json.parse(body_text) catch {
    _ =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Invalid Feishu websocket endpoint response: \{body_text}",
        ),
      )
  }
  let parsed : FeishuWebSocketEndpointResponse = @json.from_json(response_json) catch {
    _ =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to decode Feishu websocket endpoint response: \{body_text}",
        ),
      )
  }
  if parsed.code != 0 {
    return Err(
      @channel.ChannelError::ConnectionFailed(
        message="Feishu websocket endpoint lookup failed: \{parsed.msg}",
      ),
    )
  }
  match parsed.data {
    Some(data) =>
      match parse_feishu_websocket_endpoint_data(data) {
        Some(endpoint_data) => Ok(endpoint_data)
        None =>
          Err(
            @channel.ChannelError::ConnectionFailed(
              message="Feishu websocket endpoint response is missing data.URL",
            ),
          )
      }
    None =>
      Err(
        @channel.ChannelError::ConnectionFailed(
          message="Feishu websocket endpoint response is missing data.URL",
        ),
      )
  }
}

///|
async fn parse_user_batch_lookup_response(
  response : @http.Response,
  client : @http.Client,
) -> Result[Map[String, String], @channel.ChannelError] {
  let body_text = client.read_all().text() catch {
      error =>
        return Err(
          @channel.ChannelError::ConnectionFailed(
            message="Failed to read Feishu user batch lookup response body: \{error}",
          ),
        )
    }
  guard response.code is (200..=299) else {
    return Err(
      @channel.ChannelError::ConnectionFailed(
        message="Feishu user batch lookup API error \{response.code}: \{body_text}",
      ),
    )
  }
  let response_json : Json = @json.parse(body_text) catch {
    _ =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Invalid Feishu user batch lookup response: \{body_text}",
        ),
      )
  }
  let parsed : FeishuUserBatchLookupResponse = @json.from_json(response_json) catch {
    _ =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to decode Feishu user batch lookup response: \{body_text}",
        ),
      )
  }
  if parsed.code != 0 {
    return Err(
      @channel.ChannelError::ConnectionFailed(
        message="Feishu user batch lookup failed: \{parsed.msg}",
      ),
    )
  }
  let resolved : Map[String, String] = {}
  for user in parsed.data.map(fn(data) { data.items }).unwrap_or([]) {
    let open_id = user.open_id.unwrap_or("")
    let name = pick_feishu_user_name(user)
    if !open_id.is_blank() && !name.is_blank() {
      resolved[open_id] = name
    }
  }
  Ok(resolved)
}

///|
async fn FeishuClient::load_tenant_access_token(
  self : FeishuClient,
) -> Result[String, @channel.ChannelError] {
  let base_url = feishu_base_url(self.config.domain)
  let body : Json = {
    "app_id": self.config.app_id,
    "app_secret": self.config.app_secret,
  }
  let (response, data) = @http.post(
    "\{base_url}/open-apis/auth/v3/tenant_access_token/internal",
    body,
    headers={ "Content-Type": "application/json" },
  ) catch {
    error =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to load Feishu access token: \{error}",
        ),
      )
  }
  guard response.code is (200..=299) else {
    return Err(
      @channel.ChannelError::ConnectionFailed(
        message="Feishu auth failed: \{response.code} - \{data.text()}",
      ),
    )
  }
  let parsed : FeishuAccessTokenResponse = @json.from_json(data.json()) catch {
    _ =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to decode Feishu auth response",
        ),
      )
  }
  if parsed.code != 0 {
    return Err(
      @channel.ChannelError::ConnectionFailed(
        message="Feishu auth failed: \{parsed.msg}",
      ),
    )
  }
  match parsed.tenant_access_token {
    Some(token) if token.length() > 0 => Ok(token)
    _ =>
      Err(
        @channel.ChannelError::ConnectionFailed(
          message="Feishu auth response missing tenant_access_token",
        ),
      )
  }
}

///|
pub async fn FeishuClient::add_typing_indicator(
  self : FeishuClient,
  message_id : String,
) -> Result[FeishuTypingIndicatorState, @channel.ChannelError] {
  let state = match self.add_message_reaction(message_id, "Typing") {
    Ok(state) => state
    Err(error) => return Err(error)
  }
  Ok(FeishuTypingIndicatorState::{
    message_id: state.message_id,
    reaction_id: state.reaction_id,
  })
}

///|
pub async fn FeishuClient::add_message_reaction(
  self : FeishuClient,
  message_id : String,
  emoji_type : String,
) -> Result[FeishuReactionIndicatorState, @channel.ChannelError] {
  let client = match authed_feishu_http_client(self.config) {
    Ok(client) => client
    Err(error) => return Err(error)
  }
  defer client.close()

  let response = client.post(
    "/open-apis/im/v1/messages/\{message_id}/reactions",
    Json::object({ "reaction_type": Json::object({ "emoji_type": emoji_type }) }),
  ) catch {
    error =>
      return Err(
        @channel.ChannelError::SendMessageFailed(
          message="Failed to add Feishu reaction: \{error}",
        ),
      )
  }
  let body_text = client.read_all().text() catch {
      error =>
        return Err(
          @channel.ChannelError::SendMessageFailed(
            message="Failed to read Feishu reaction response: \{error}",
          ),
        )
    }
  guard response.code is (200..=299) else {
    return Err(
      @channel.ChannelError::SendMessageFailed(
        message="Feishu reaction API error \{response.code}: \{body_text}",
      ),
    )
  }
  let response_json : Json = @json.parse(body_text) catch {
    _ =>
      return Err(
        @channel.ChannelError::SendMessageFailed(
          message="Invalid Feishu reaction response: \{body_text}",
        ),
      )
  }
  let (code, msg) = match
    parse_json_code_msg(response_json, "Failed to add Feishu reaction") {
    Ok(pair) => pair
    Err(error) => return Err(error)
  }
  if code != 0 {
    return Err(
      @channel.ChannelError::SendMessageFailed(
        message="Feishu reaction failed: \{msg}",
      ),
    )
  }
  let reaction_id = match
    parse_reaction_id(response_json, "Failed to add Feishu reaction") {
    Ok(reaction_id) => reaction_id
    Err(error) => return Err(error)
  }
  Ok(FeishuReactionIndicatorState::{ message_id, reaction_id, emoji_type })
}

///|
pub async fn FeishuClient::remove_typing_indicator(
  self : FeishuClient,
  state : FeishuTypingIndicatorState,
) -> Result[Unit, @channel.ChannelError] {
  self.remove_message_reaction(FeishuReactionIndicatorState::{
    message_id: state.message_id,
    reaction_id: state.reaction_id,
    emoji_type: "Typing",
  })
}

///|
pub async fn FeishuClient::remove_message_reaction(
  self : FeishuClient,
  state : FeishuReactionIndicatorState,
) -> Result[Unit, @channel.ChannelError] {
  let client = match authed_feishu_http_client(self.config) {
    Ok(client) => client
    Err(error) => return Err(error)
  }
  defer client.close()

  client.request(
    @http.RequestMethod::Delete,
    "/open-apis/im/v1/messages/\{state.message_id}/reactions/\{state.reaction_id}",
  ) catch {
    error =>
      return Err(
        @channel.ChannelError::SendMessageFailed(
          message="Failed to remove Feishu reaction: \{error}",
        ),
      )
  }
  let response = client.end_request() catch {
    error =>
      return Err(
        @channel.ChannelError::SendMessageFailed(
          message="Failed to finish Feishu reaction removal request: \{error}",
        ),
      )
  }
  let body_text = client.read_all().text() catch {
      error =>
        return Err(
          @channel.ChannelError::SendMessageFailed(
            message="Failed to read Feishu reaction removal response: \{error}",
          ),
        )
    }
  guard response.code is (200..=299) else {
    return Err(
      @channel.ChannelError::SendMessageFailed(
        message="Feishu reaction removal API error \{response.code}: \{body_text}",
      ),
    )
  }
  let response_json : Json = @json.parse(body_text) catch {
    _ =>
      return Err(
        @channel.ChannelError::SendMessageFailed(
          message="Invalid Feishu reaction removal response: \{body_text}",
        ),
      )
  }
  let (code, msg) = match
    parse_json_code_msg(response_json, "Failed to remove Feishu reaction") {
    Ok(pair) => pair
    Err(error) => return Err(error)
  }
  if code != 0 {
    return Err(
      @channel.ChannelError::SendMessageFailed(
        message="Feishu reaction removal failed: \{msg}",
      ),
    )
  }
  Ok(())
}

///|
pub async fn FeishuClient::send_text_message(
  self : FeishuClient,
  receive_id : String,
  text : String,
  reply_to? : String? = None,
  reply_in_thread? : Bool = false,
) -> Result[@channel.SendResult, @channel.ChannelError] {
  let token = match self.load_tenant_access_token() {
    Ok(token) => token
    Err(error) => return Err(error)
  }
  let base_url = feishu_base_url(self.config.domain)
  let client = @http.Client::new(base_url, headers={
    "Authorization": "Bearer \{token}",
    "Content-Type": "application/json",
    "Connection": "close",
  }) catch {
    error =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to create Feishu HTTP client: \{error}",
        ),
      )
  }
  defer client.close()

  let response = match reply_to {
    Some(message_id) if message_id.length() > 0 =>
      client.post(
        "/open-apis/im/v1/messages/\{message_id}/reply",
        Json::object({
          "content": build_text_content(text).stringify(),
          "msg_type": "text",
          "reply_in_thread": reply_in_thread.to_json(),
        }),
      ) catch {
        error =>
          return Err(
            @channel.ChannelError::SendMessageFailed(
              message="Failed to send Feishu reply: \{error}",
            ),
          )
      }
    _ => {
      let (receive_id_type, target_id) = detect_receive_id_type(receive_id)
      client.post(
        "/open-apis/im/v1/messages?receive_id_type=\{receive_id_type}",
        Json::object({
          "receive_id": target_id,
          "msg_type": "text",
          "content": build_text_content(text).stringify(),
        }),
      ) catch {
        error =>
          return Err(
            @channel.ChannelError::SendMessageFailed(
              message="Failed to send Feishu message: \{error}",
            ),
          )
      }
    }
  }

  parse_send_response(response, client)
}

///|
pub async fn FeishuClient::start_streaming_card(
  self : FeishuClient,
  receive_id : String,
  initial_text : String,
  reply_to? : String? = None,
  reply_in_thread? : Bool = false,
) -> Result[FeishuStreamingCardSession, @channel.ChannelError] {
  let client = match authed_feishu_http_client(self.config) {
    Ok(client) => client
    Err(error) => return Err(error)
  }
  defer client.close()

  let card_response = client.post(
    "/open-apis/cardkit/v1/cards",
    Json::object({
      "type": "card_json",
      "data": build_streaming_card_json(initial_text).stringify(),
    }),
  ) catch {
    error =>
      return Err(
        @channel.ChannelError::SendMessageFailed(
          message="Failed to create Feishu streaming card: \{error}",
        ),
      )
  }
  let card_body_text = client.read_all().text() catch {
      error =>
        return Err(
          @channel.ChannelError::SendMessageFailed(
            message="Failed to read Feishu streaming card response: \{error}",
          ),
        )
    }
  guard card_response.code is (200..=299) else {
    return Err(
      @channel.ChannelError::SendMessageFailed(
        message="Feishu streaming card API error \{card_response.code}: \{card_body_text}",
      ),
    )
  }
  let card_json : Json = @json.parse(card_body_text) catch {
    _ =>
      return Err(
        @channel.ChannelError::SendMessageFailed(
          message="Invalid Feishu streaming card response: \{card_body_text}",
        ),
      )
  }
  let (card_code, card_msg) = match
    parse_json_code_msg(card_json, "Failed to create Feishu streaming card") {
    Ok(pair) => pair
    Err(error) => return Err(error)
  }
  if card_code != 0 {
    return Err(
      @channel.ChannelError::SendMessageFailed(
        message="Feishu streaming card creation failed: \{card_msg}",
      ),
    )
  }
  let card_id = match
    parse_card_id(card_json, "Failed to create Feishu streaming card") {
    Ok(card_id) => card_id
    Err(error) => return Err(error)
  }

  let message_response = match reply_to {
    Some(message_id) if !message_id.is_blank() =>
      client.post(
        "/open-apis/im/v1/messages/\{message_id}/reply",
        Json::object({
          "content": build_streaming_card_content(card_id).stringify(),
          "msg_type": "interactive",
          "reply_in_thread": reply_in_thread.to_json(),
        }),
      ) catch {
        error =>
          return Err(
            @channel.ChannelError::SendMessageFailed(
              message="Failed to send Feishu streaming card reply: \{error}",
            ),
          )
      }
    _ => {
      let (receive_id_type, target_id) = detect_receive_id_type(receive_id)
      client.post(
        "/open-apis/im/v1/messages?receive_id_type=\{receive_id_type}",
        Json::object({
          "receive_id": target_id,
          "msg_type": "interactive",
          "content": build_streaming_card_content(card_id).stringify(),
        }),
      ) catch {
        error =>
          return Err(
            @channel.ChannelError::SendMessageFailed(
              message="Failed to send Feishu streaming card message: \{error}",
            ),
          )
      }
    }
  }
  let sent = match parse_send_response(message_response, client) {
    Ok(sent) => sent
    Err(error) => return Err(error)
  }
  Ok(FeishuStreamingCardSession::{
    card_id,
    message_id: sent.message_id,
    sequence: 1,
    current_text: initial_text,
  })
}

///|
pub async fn FeishuClient::update_streaming_card(
  self : FeishuClient,
  session : FeishuStreamingCardSession,
  text : String,
) -> Result[FeishuStreamingCardSession, @channel.ChannelError] {
  let client = match authed_feishu_http_client(self.config) {
    Ok(client) => client
    Err(error) => return Err(error)
  }
  defer client.close()

  let next_sequence = session.sequence + 1
  let response = client.put(
    "/open-apis/cardkit/v1/cards/\{session.card_id}/elements/content/content",
    Json::object({
      "content": text,
      "sequence": next_sequence,
      "uuid": "s_\{session.card_id}_\{next_sequence}",
    }),
  ) catch {
    error =>
      return Err(
        @channel.ChannelError::SendMessageFailed(
          message="Failed to update Feishu streaming card: \{error}",
        ),
      )
  }
  let body_text = client.read_all().text() catch {
      error =>
        return Err(
          @channel.ChannelError::SendMessageFailed(
            message="Failed to read Feishu streaming card update response: \{error}",
          ),
        )
    }
  guard response.code is (200..=299) else {
    return Err(
      @channel.ChannelError::SendMessageFailed(
        message="Feishu streaming card update API error \{response.code}: \{body_text}",
      ),
    )
  }
  let response_json : Json = @json.parse(body_text) catch {
    _ =>
      return Err(
        @channel.ChannelError::SendMessageFailed(
          message="Invalid Feishu streaming card update response: \{body_text}",
        ),
      )
  }
  let (code, msg) = match
    parse_json_code_msg(response_json, "Failed to update Feishu streaming card") {
    Ok(pair) => pair
    Err(error) => return Err(error)
  }
  if code != 0 {
    return Err(
      @channel.ChannelError::SendMessageFailed(
        message="Feishu streaming card update failed: \{msg}",
      ),
    )
  }
  Ok(FeishuStreamingCardSession::{
    ..session,
    sequence: next_sequence,
    current_text: text,
  })
}

///|
pub async fn FeishuClient::close_streaming_card(
  self : FeishuClient,
  session : FeishuStreamingCardSession,
  final_text : String,
) -> Result[@channel.SendResult, @channel.ChannelError] {
  let session = match self.update_streaming_card(session, final_text) {
    Ok(session) => session
    Err(error) => return Err(error)
  }
  let client = match authed_feishu_http_client(self.config) {
    Ok(client) => client
    Err(error) => return Err(error)
  }
  defer client.close()
  let next_sequence = session.sequence + 1
  client.request(
    @http.RequestMethod::Patch,
    "/open-apis/cardkit/v1/cards/\{session.card_id}/settings",
  ) catch {
    error =>
      return Err(
        @channel.ChannelError::SendMessageFailed(
          message="Failed to close Feishu streaming card: \{error}",
        ),
      )
  }
  client.write(
    Json::object({
      "settings": Json::object({
        "config": {
          "streaming_mode": false,
          "summary": { "content": truncate_stream_summary(final_text) },
        },
      }).stringify(),
      "sequence": next_sequence,
      "uuid": "c_\{session.card_id}_\{next_sequence}",
    }),
  )
  let response = client.end_request() catch {
    error =>
      return Err(
        @channel.ChannelError::SendMessageFailed(
          message="Failed to finish Feishu streaming card close request: \{error}",
        ),
      )
  }
  let body_text = client.read_all().text() catch {
      error =>
        return Err(
          @channel.ChannelError::SendMessageFailed(
            message="Failed to read Feishu streaming card close response: \{error}",
          ),
        )
    }
  guard response.code is (200..=299) else {
    return Err(
      @channel.ChannelError::SendMessageFailed(
        message="Feishu streaming card close API error \{response.code}: \{body_text}",
      ),
    )
  }
  let response_json : Json = @json.parse(body_text) catch {
    _ =>
      return Err(
        @channel.ChannelError::SendMessageFailed(
          message="Invalid Feishu streaming card close response: \{body_text}",
        ),
      )
  }
  let (code, msg) = match
    parse_json_code_msg(response_json, "Failed to close Feishu streaming card") {
    Ok(pair) => pair
    Err(error) => return Err(error)
  }
  if code != 0 {
    return Err(
      @channel.ChannelError::SendMessageFailed(
        message="Feishu streaming card close failed: \{msg}",
      ),
    )
  }
  Ok(@channel.SendResult::{
    channel: "feishu",
    message_id: session.message_id,
    timestamp: 0,
    status: "updated",
  })
}

///|
pub async fn FeishuClient::get_message(
  self : FeishuClient,
  message_id : String,
) -> Result[FeishuMessageLookupItem?, @channel.ChannelError] {
  let token = match self.load_tenant_access_token() {
    Ok(token) => token
    Err(error) => return Err(error)
  }
  let base_url = feishu_base_url(self.config.domain)
  let client = @http.Client::new(base_url, headers={
    "Authorization": "Bearer \{token}",
    "Connection": "close",
  }) catch {
    error =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to create Feishu HTTP client: \{error}",
        ),
      )
  }
  defer client.close()

  let response = client.get(
    "/open-apis/im/v1/messages/mget?message_ids=\{message_id}&user_id_type=open_id&card_msg_content_type=raw_card_content",
  ) catch {
    error =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to fetch Feishu message: \{error}",
        ),
      )
  }
  parse_lookup_response(response, client)
}

///|
pub async fn FeishuClient::get_message_items(
  self : FeishuClient,
  message_id : String,
) -> Result[Array[FeishuMessageLookupItem], @channel.ChannelError] {
  let token = match self.load_tenant_access_token() {
    Ok(token) => token
    Err(error) => return Err(error)
  }
  let base_url = feishu_base_url(self.config.domain)
  let client = @http.Client::new(base_url, headers={
    "Authorization": "Bearer \{token}",
    "Connection": "close",
  }) catch {
    error =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to create Feishu HTTP client: \{error}",
        ),
      )
  }
  defer client.close()

  let response = client.get(
    "/open-apis/im/v1/messages/\{message_id}?user_id_type=open_id&card_msg_content_type=raw_card_content",
  ) catch {
    error =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to fetch Feishu message items: \{error}",
        ),
      )
  }
  parse_lookup_items_response(response, client)
}

///|
pub async fn FeishuClient::get_user_display_name(
  self : FeishuClient,
  open_id : String,
) -> Result[String?, @channel.ChannelError] {
  let token = match self.load_tenant_access_token() {
    Ok(token) => token
    Err(error) => return Err(error)
  }
  let base_url = feishu_base_url(self.config.domain)
  let client = @http.Client::new(base_url, headers={
    "Authorization": "Bearer \{token}",
    "Connection": "close",
  }) catch {
    error =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to create Feishu HTTP client: \{error}",
        ),
      )
  }
  defer client.close()

  let response = client.get(
    "/open-apis/contact/v3/users/\{open_id}?user_id_type=open_id",
  ) catch {
    error =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to fetch Feishu user: \{error}",
        ),
      )
  }
  parse_user_lookup_response(response, client)
}

///|
pub async fn FeishuClient::get_user_display_names(
  self : FeishuClient,
  open_ids : Array[String],
) -> Result[Map[String, String], @channel.ChannelError] {
  if open_ids.is_empty() {
    return Ok({})
  }
  let token = match self.load_tenant_access_token() {
    Ok(token) => token
    Err(error) => return Err(error)
  }
  let base_url = feishu_base_url(self.config.domain)
  let client = @http.Client::new(base_url, headers={
    "Authorization": "Bearer \{token}",
    "Connection": "close",
  }) catch {
    error =>
      return Err(
        @channel.ChannelError::ConnectionFailed(
          message="Failed to create Feishu HTTP client: \{error}",
        ),
      )
  }
  defer client.close()

  let resolved : Map[String, String] = {}
  let total = open_ids.length()
  let mut start = 0
  while start < total {
    let end = if start + 50 < total { start + 50 } else { total }
    let chunk = open_ids[start:end]
    let joined_ids = chunk.join(",")
    let response = client.get(
      "/open-apis/contact/v3/users/batch?user_id_type=open_id&user_ids=\{joined_ids}",
    ) catch {
      error =>
        return Err(
          @channel.ChannelError::ConnectionFailed(
            message="Failed to fetch Feishu users: \{error}",
          ),
        )
    }
    match parse_user_batch_lookup_response(response, client) {
      Ok(names) =>
        for open_id, name in names {
          resolved[open_id] = name
        }
      Err(error) => return Err(error)
    }
    start = end
  }
  Ok(resolved)
}
