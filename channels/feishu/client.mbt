///|
pub struct FeishuClient {
  config : FeishuAccountConfig
}

///|
pub fn FeishuClient::new(config : FeishuAccountConfig) -> FeishuClient {
  FeishuClient::{ config, }
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
  Ok(parsed.data.map(fn(data) { data.items.get(0) }).flatten())
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
