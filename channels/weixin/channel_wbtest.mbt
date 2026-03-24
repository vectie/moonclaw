///|
struct RecordingWeixinHandler {
  handled_message_ids : Array[String]
}

///|
fn RecordingWeixinHandler::new() -> RecordingWeixinHandler {
  RecordingWeixinHandler::{ handled_message_ids: [] }
}

///|
impl @channel.MessageHandler for RecordingWeixinHandler with handle_message(
  self : RecordingWeixinHandler,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
) -> @channel.Message {
  ignore(channel_id)
  ignore(account_id)
  self.handled_message_ids.push(message.id)
  @channel.Message::{
    id: "reply-\{message.id}",
    channel: "weixin",
    from: "bot",
    to: message.to,
    content: "echo: \{message.content}",
    content_type: "text",
    timestamp: message.timestamp,
    thread_id: None,
    reply_to: Some(message.id),
    attachments: [],
  }
}

///|
impl @channel.MessageHandler for RecordingWeixinHandler with handle_event(
  _self : RecordingWeixinHandler,
  _channel_id : String,
  _account_id : String,
  _event : @channel.ChannelEvent,
) -> Unit {

}

///|
fn weixin_test_account_config() -> Json {
  {
    "app_id": "wx-app",
    "app_secret": "wx-secret",
    "token": "wx-token",
    "original_id": "gh_test",
    "enabled": true,
  }
}

///|
fn weixin_test_config() -> @channel.ChannelConfig {
  @channel.ChannelConfig::{
    enabled: true,
    accounts: { "default": weixin_test_account_config() },
    global_settings: {},
  }
}

///|
fn weixin_get_request(
  signature : String,
  timestamp : String,
  nonce : String,
  echostr : String,
) -> @channel.ExtensionRequest {
  @channel.ExtensionRequest::new(
    http_method="GET",
    path="/webhook/weixin",
    headers={},
    body=b"",
    query_params={
      "signature": signature,
      "timestamp": timestamp,
      "nonce": nonce,
      "echostr": echostr,
    },
  )
}

///|
fn weixin_text_request(
  signature : String,
  timestamp : String,
  nonce : String,
  body : String,
) -> @channel.ExtensionRequest {
  @channel.ExtensionRequest::new(
    http_method="POST",
    path="/webhook/weixin",
    headers={ "content-type": "application/xml" },
    body=@encoding/utf8.encode(body),
    query_params={
      "signature": signature,
      "timestamp": timestamp,
      "nonce": nonce,
    },
  )
}

///|
fn weixin_text_xml(msg_id : String, content : String) -> String {
  [
    "<xml>",
    "<ToUserName><![CDATA[gh_test]]></ToUserName>",
    "<FromUserName><![CDATA[user-openid]]></FromUserName>",
    "<CreateTime>1711111111</CreateTime>",
    "<MsgType><![CDATA[text]]></MsgType>",
    "<Content><![CDATA[\{content}]]></Content>",
    "<MsgId>\{msg_id}</MsgId>",
    "</xml>",
  ].join("")
}

///|
test "verify_weixin_signature matches generated signature" {
  let signature = weixin_signature("wx-token", "1711111111", "nonce-1")
  inspect(
    verify_weixin_signature("wx-token", signature, "1711111111", "nonce-1"),
    content="true",
  )
}

///|
async test "weixin webhook GET returns echostr after signature verification" {
  let channel = WeixinChannel::new()
  channel.configure(weixin_test_config())
  let signature = weixin_signature("wx-token", "1711111111", "nonce-1")
  let response = channel.handle_webhook(
    weixin_get_request(signature, "1711111111", "nonce-1", "echo-me"),
  )
  inspect(response.status_code(), content="200")
  inspect(@encoding/utf8.decode(response.body()), content="echo-me")
}

///|
async test "weixin webhook GET rejects invalid signature" {
  let channel = WeixinChannel::new()
  channel.configure(weixin_test_config())
  let response = channel.handle_webhook(
    weixin_get_request("bad", "1711111111", "nonce-1", "echo-me"),
  )
  inspect(response.status_code(), content="400")
}

///|
async test "weixin webhook POST handles plaintext text message and sends response" {
  let channel = WeixinChannel::new()
  let handler = RecordingWeixinHandler::new()
  channel.set_message_handler(handler)
  channel.configure(weixin_test_config())
  ignore(channel.start("default", weixin_test_account_config()))
  match channel.state.clients.get("default") {
    Some(client) => client.set_test_access_token("test-access-token")
    None => fail("expected default weixin client")
  }
  let xml = weixin_text_xml("1001", "hello weixin")
  let signature = weixin_signature("wx-token", "1711111111", "nonce-1")
  let response = channel.handle_webhook(
    weixin_text_request(signature, "1711111111", "nonce-1", xml),
  )
  inspect(response.status_code(), content="200")
  inspect(@encoding/utf8.decode(response.body()), content="success")
  inspect(handler.handled_message_ids.length(), content="1")
  inspect(handler.handled_message_ids[0], content="1001")
  let sent = match channel.state.clients.get("default") {
    Some(client) => client.test_sent_messages()
    None => fail("expected default weixin client")
  }
  inspect(sent.length(), content="1")
  inspect(
    sent[0].stringify().contains("\"touser\":\"user-openid\""),
    content="true",
  )
  inspect(
    sent[0].stringify().contains("\"content\":\"echo: hello weixin\""),
    content="true",
  )
}
