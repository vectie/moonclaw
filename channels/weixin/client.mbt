///|
pub struct WeixinClient {
  config : WeixinAccountConfig
  mut test_access_token : String?
  test_sent_messages : Array[Json]
}

///|
pub fn WeixinClient::new(config : WeixinAccountConfig) -> WeixinClient {
  { config, test_access_token: None, test_sent_messages: [] }
}

///|
pub fn WeixinClient::set_test_access_token(
  self : WeixinClient,
  token : String,
) -> Unit {
  self.test_access_token = Some(token)
}

///|
pub fn WeixinClient::test_sent_messages(self : WeixinClient) -> Array[Json] {
  self.test_sent_messages.copy()
}

///|
fn weixin_api_base_url(config : WeixinAccountConfig) -> String {
  match config.api_base_url {
    Some(url) if !url.trim().to_owned().is_blank() => url.trim().to_owned()
    _ => "https://api.weixin.qq.com"
  }
}

///|
fn weixin_access_token_url(config : WeixinAccountConfig) -> String {
  let base = weixin_api_base_url(config)
  "\{base}/cgi-bin/token?grant_type=client_credential&appid=\{config.app_id}&secret=\{config.app_secret}"
}

///|
fn weixin_custom_send_url(
  config : WeixinAccountConfig,
  access_token : String,
) -> String {
  let base = weixin_api_base_url(config)
  "\{base}/cgi-bin/message/custom/send?access_token=\{access_token}"
}

///|
fn parse_weixin_error_message(payload : Json, fallback : String) -> String {
  match payload {
    { "errmsg": String(message), .. } if !message.is_blank() => message
    _ => fallback
  }
}

///|
pub async fn WeixinClient::load_access_token(
  self : WeixinClient,
) -> Result[String, @channel.ChannelError] {
  match self.test_access_token {
    Some(token) => return Ok(token)
    None => ()
  }
  let (response, data) = @http.get(weixin_access_token_url(self.config)) catch {
    error =>
      return Err(
        ConnectionFailed(
          message="Failed to fetch Weixin access token: \{error}",
        ),
      )
  }
  let body_text = data.text()
  guard response.code is (200..=299) else {
    return Err(
      ConnectionFailed(
        message="Weixin access token API error \{response.code}: \{body_text}",
      ),
    )
  }
  let payload : Json = @json.parse(body_text) catch {
    _ =>
      return Err(
        ConnectionFailed(
          message="Invalid Weixin access token response: \{body_text}",
        ),
      )
  }
  match payload {
    { "access_token": String(token), .. } if !token.is_blank() => Ok(token)
    _ =>
      Err(
        ConnectionFailed(
          message="Weixin access token lookup failed: \{parse_weixin_error_message(payload, body_text)}",
        ),
      )
  }
}

///|
pub async fn WeixinClient::send_text_message(
  self : WeixinClient,
  to : String,
  text : String,
) -> Result[@channel.SendResult, @channel.ChannelError] {
  let payload : Json = {
    "touser": to,
    "msgtype": "text",
    "text": { "content": text },
  }
  match self.test_access_token {
    Some(_) => {
      self.test_sent_messages.push(payload)
      return Ok({
        channel: "weixin",
        message_id: "mock:\{self.test_sent_messages.length()}",
        timestamp: 0,
        status: "sent",
      })
    }
    None => ()
  }
  let access_token = match self.load_access_token() {
    Ok(token) => token
    Err(error) => return Err(error)
  }
  let (response, data) = @http.post(
    weixin_custom_send_url(self.config, access_token),
    payload,
    headers={ "Content-Type": "application/json" },
  ) catch {
    error =>
      return Err(
        SendMessageFailed(message="Failed to send Weixin message: \{error}"),
      )
  }
  let body_text = data.text()
  guard response.code is (200..=299) else {
    return Err(
      SendMessageFailed(
        message="Weixin send API error \{response.code}: \{body_text}",
      ),
    )
  }
  let response_json : Json = @json.parse(body_text) catch {
    _ =>
      return Err(
        SendMessageFailed(message="Invalid Weixin send response: \{body_text}"),
      )
  }
  match response_json {
    { "errcode": Number(code, ..), .. } if code.to_int() == 0 =>
      Ok({
        channel: "weixin",
        message_id: "wx:\{to}",
        timestamp: 0,
        status: "sent",
      })
    { "errcode": String(code), .. } if code == "0" =>
      Ok({
        channel: "weixin",
        message_id: "wx:\{to}",
        timestamp: 0,
        status: "sent",
      })
    _ =>
      Err(
        SendMessageFailed(
          message="Weixin send failed: \{parse_weixin_error_message(response_json, body_text)}",
        ),
      )
  }
}
