///|
struct RecordingHandler {
  handled_message_ids : Array[String]
  event_types : Array[String]
}

///|
fn RecordingHandler::new() -> RecordingHandler {
  RecordingHandler::{ handled_message_ids: [], event_types: [] }
}

///|
impl @channel.MessageHandler for RecordingHandler with handle_message(
  self : RecordingHandler,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
) -> @channel.Message {
  ignore(channel_id)
  ignore(account_id)
  self.handled_message_ids.push(message.id)
  @channel.Message::{
    id: "reply-\{message.id}",
    channel: message.channel,
    from: "bot",
    to: message.to,
    content: "echo: \{message.content}",
    content_type: "text",
    timestamp: message.timestamp,
    thread_id: message.thread_id,
    reply_to: Some(message.id),
    attachments: [],
  }
}

///|
impl @channel.MessageHandler for RecordingHandler with handle_event(
  self : RecordingHandler,
  channel_id : String,
  account_id : String,
  event : @channel.ChannelEvent,
) -> Unit {
  ignore(channel_id)
  ignore(account_id)
  self.event_types.push(event.event_type)
}

///|
fn feishu_test_account_config() -> Json {
  {
    "app_id": "app-test",
    "app_secret": "secret-test",
    "domain": "feishu",
    "connection_mode": "webhook",
    "dm_policy": "pairing",
    "verify_token": "verify-test",
    "enabled": true,
  }
}

///|
fn feishu_test_config() -> @channel.ChannelConfig {
  @channel.ChannelConfig::{
    enabled: true,
    accounts: { "default": feishu_test_account_config() },
    global_settings: {},
  }
}

///|
fn feishu_message_request(
  event_id : String,
  message_id : String,
  text : String,
  create_time : String,
) -> @channel.ExtensionRequest {
  let content : Json = { "text": text }
  let payload : Json = {
    "schema": "2.0",
    "header": {
      "event_id": event_id,
      "event_type": "im.message.receive_v1",
      "app_id": "app-test",
      "token": "verify-test",
    },
    "event": {
      "sender": {
        "sender_id": { "open_id": "ou_sender", "user_id": "user_sender" },
      },
      "message": {
        "message_id": message_id,
        "message_type": "text",
        "chat_id": "chat-test",
        "chat_type": "p2p",
        "create_time": create_time,
        "content": content.stringify(),
      },
    },
    "token": "verify-test",
  }
  @channel.ExtensionRequest::new(
    http_method="POST",
    path="/webhook/feishu",
    headers={ "content-type": "application/json" },
    body=@encoding/utf8.encode(payload.stringify()),
  )
}

///|
fn feishu_event_request(
  event_type : String,
  event_id : String,
  event : Json,
) -> @channel.ExtensionRequest {
  let payload : Json = {
    "schema": "2.0",
    "header": {
      "event_id": event_id,
      "event_type": event_type,
      "app_id": "app-test",
      "token": "verify-test",
    },
    "event": event,
    "token": "verify-test",
  }
  @channel.ExtensionRequest::new(
    http_method="POST",
    path="/webhook/feishu",
    headers={ "content-type": "application/json" },
    body=@encoding/utf8.encode(payload.stringify()),
  )
}

///|
async test "Feishu webhook routes abort text to cancel events without invoking message handling" {
  let channel = FeishuChannel::new()
  channel.configure(feishu_test_config())
  let handler = RecordingHandler::new()
  channel.set_message_handler(handler)

  let response = channel.handle_webhook(
    feishu_message_request(
      "event-abort",
      "message-abort",
      "/stop",
      @clock.epoch.now().ms().to_string(),
    ),
  )

  inspect(response.status_code(), content="200")
  inspect(handler.handled_message_ids.length(), content="0")
  json_inspect(handler.event_types, content=["cancel"])
}

///|
async test "Feishu webhook deduplicates duplicate message ids before handler execution" {
  let channel = FeishuChannel::new()
  channel.configure(feishu_test_config())
  let handler = RecordingHandler::new()
  channel.set_message_handler(handler)

  let first = channel.handle_webhook(
    feishu_message_request(
      "event-1",
      "message-1",
      "hello",
      @clock.epoch.now().ms().to_string(),
    ),
  )
  let second = channel.handle_webhook(
    feishu_message_request(
      "event-2",
      "message-1",
      "hello again",
      @clock.epoch.now().ms().to_string(),
    ),
  )

  inspect(first.status_code(), content="500")
  inspect(second.status_code(), content="200")
  json_inspect(handler.handled_message_ids, content=["message-1"])
}

///|
async test "Feishu webhook ignores stale replayed messages" {
  let channel = FeishuChannel::new()
  channel.configure(feishu_test_config())
  let handler = RecordingHandler::new()
  channel.set_message_handler(handler)
  let response = channel.handle_webhook(
    feishu_message_request("event-expired", "message-expired", "old hello", "1"),
  )

  inspect(response.status_code(), content="200")
  inspect(handler.handled_message_ids.length(), content="0")
  inspect(channel.state.pending_messages.length(), content="0")
}

///|
async test "Feishu webhook forwards reaction events through the channel event handler" {
  let channel = FeishuChannel::new()
  channel.configure(feishu_test_config())
  let handler = RecordingHandler::new()
  channel.set_message_handler(handler)

  let response = channel.handle_webhook(
    feishu_event_request("im.message.reaction.created_v1", "event-reaction", {
      "message_id": "message-1",
      "action_time": "42",
      "reaction_type": { "emoji_type": "THUMBSUP" },
      "user_id": { "open_id": "ou_reactor" },
    }),
  )

  inspect(response.status_code(), content="200")
  json_inspect(handler.event_types, content=["reaction.added"])
  inspect(handler.handled_message_ids.length(), content="0")
}

///|
async test "Feishu webhook forwards bot membership events through the channel event handler" {
  let channel = FeishuChannel::new()
  channel.configure(feishu_test_config())
  let handler = RecordingHandler::new()
  channel.set_message_handler(handler)

  let added = channel.handle_webhook(
    feishu_event_request("im.chat.member.bot.added_v1", "event-bot-added", {
      "chat_id": "chat-test",
      "operator_id": { "open_id": "ou_operator" },
    }),
  )
  let removed = channel.handle_webhook(
    feishu_event_request("im.chat.member.bot.removed_v1", "event-bot-removed", {
      "chat_id": "chat-test",
      "operator_id": { "open_id": "ou_operator" },
    }),
  )

  inspect(added.status_code(), content="200")
  inspect(removed.status_code(), content="200")
  json_inspect(handler.event_types, content=["bot.added", "bot.removed"])
}
