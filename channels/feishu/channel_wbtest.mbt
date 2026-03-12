///|
struct RecordingHandler {
  handled_message_ids : Array[String]
  attachment_counts : Array[Int]
  event_types : Array[String]
}

///|
fn RecordingHandler::new() -> RecordingHandler {
  RecordingHandler::{
    handled_message_ids: [],
    attachment_counts: [],
    event_types: [],
  }
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
  self.attachment_counts.push(message.attachments.length())
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
    "reaction_notifications": "own",
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
fn feishu_message_request_with_type(
  event_id : String,
  message_id : String,
  message_type : String,
  content : String,
  create_time : String,
) -> @channel.ExtensionRequest {
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
        "message_type": message_type,
        "chat_id": "chat-test",
        "chat_type": "p2p",
        "create_time": create_time,
        "content": content,
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
async test "Feishu webhook accepts post messages and normalizes them to text" {
  let channel = FeishuChannel::new()
  channel.configure(feishu_test_config())
  let handler = RecordingHandler::new()
  channel.set_message_handler(handler)

  let response = channel.handle_webhook(
    feishu_message_request_with_type(
      "event-post",
      "message-post",
      "post",
      Json::object({
        "zh_cn": Json::object({
          "title": "日报",
          "content": Json::array([
            Json::array([
              Json::object({ "tag": "text", "text": "进度更新 " }),
              Json::object({
                "tag": "a",
                "text": "详情",
                "href": "https://example.com",
              }),
            ]),
          ]),
        }),
      }).stringify(),
      @clock.epoch.now().ms().to_string(),
    ),
  )

  inspect(response.status_code(), content="500")
  json_inspect(handler.handled_message_ids, content=["message-post"])
}

///|
async test "Feishu webhook accepts interactive card messages and normalizes them to text" {
  let channel = FeishuChannel::new()
  channel.configure(feishu_test_config())
  let handler = RecordingHandler::new()
  channel.set_message_handler(handler)

  let response = channel.handle_webhook(
    feishu_message_request_with_type(
      "event-card-message",
      "message-card",
      "interactive",
      Json::object({
        "header": Json::object({
          "title": Json::object({ "content": "审批卡片" }),
        }),
        "elements": Json::array([
          Json::object({
            "tag": "div",
            "text": Json::object({ "content": "请确认本次操作" }),
          }),
        ]),
      }).stringify(),
      @clock.epoch.now().ms().to_string(),
    ),
  )

  inspect(response.status_code(), content="500")
  json_inspect(handler.handled_message_ids, content=["message-card"])
}

///|
async test "Feishu webhook accepts image messages and normalizes them to text" {
  let channel = FeishuChannel::new()
  channel.configure(feishu_test_config())
  let handler = RecordingHandler::new()
  channel.set_message_handler(handler)

  let response = channel.handle_webhook(
    feishu_message_request_with_type(
      "event-image",
      "message-image",
      "image",
      Json::object({ "image_key": "img_123" }).stringify(),
      @clock.epoch.now().ms().to_string(),
    ),
  )

  inspect(response.status_code(), content="500")
  json_inspect(handler.handled_message_ids, content=["message-image"])
  json_inspect(handler.attachment_counts, content=[1])
}

///|
async test "Feishu webhook accepts file messages and normalizes them to text" {
  let channel = FeishuChannel::new()
  channel.configure(feishu_test_config())
  let handler = RecordingHandler::new()
  channel.set_message_handler(handler)

  let response = channel.handle_webhook(
    feishu_message_request_with_type(
      "event-file",
      "message-file",
      "file",
      Json::object({ "file_name": "report.pdf", "file_key": "file_123" }).stringify(),
      @clock.epoch.now().ms().to_string(),
    ),
  )

  inspect(response.status_code(), content="500")
  json_inspect(handler.handled_message_ids, content=["message-file"])
  json_inspect(handler.attachment_counts, content=[1])
}

///|
async test "Feishu webhook ignores reaction events when lookup context is unavailable" {
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
  inspect(handler.event_types.length(), content="0")
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
  let deleted = channel.handle_webhook(
    feishu_event_request("im.chat.member.bot.deleted_v1", "event-bot-deleted", {
      "chat_id": "chat-test",
      "operator_id": { "open_id": "ou_operator" },
    }),
  )

  inspect(added.status_code(), content="200")
  inspect(removed.status_code(), content="200")
  inspect(deleted.status_code(), content="200")
  json_inspect(handler.event_types, content=[
    "bot.added", "bot.removed", "bot.removed",
  ])
}

///|
async test "Feishu webhook forwards card actions and returns a Feishu-compatible ack" {
  let channel = FeishuChannel::new()
  channel.configure(feishu_test_config())
  let handler = RecordingHandler::new()
  channel.set_message_handler(handler)

  let response = channel.handle_webhook(
    feishu_event_request("card.action.trigger", "event-card", {
      "open_message_id": "om_123",
      "open_chat_id": "oc_123",
      "operator": { "open_id": "ou_operator" },
      "action": { "value": { "intent": "approve" } },
    }),
  )

  inspect(response.status_code(), content="200")
  inspect(
    @encoding/utf8.decode(response.body()) catch {
      _ => ""
    },
    content="{\"toast\":{\"type\":\"success\",\"content\":\"Action received\"}}",
  )
  json_inspect(handler.event_types, content=["card.action"])
}

///|
test "Feishu reaction helpers ignore unsupported operators and enforce own-message target matching" {
  let channel = FeishuChannel::new()
  channel.configure(feishu_test_config())

  inspect(channel.reaction_notifications_mode("default"), content="own")
  inspect(
    channel.should_ignore_reaction_event(
      Some("app"),
      Some("ou_app"),
      Some("THUMBSUP"),
    ),
    content="true",
  )
  inspect(
    channel.should_ignore_reaction_event(None, Some("ou_user"), Some("Typing")),
    content="true",
  )
  inspect(
    channel.should_ignore_reaction_event(
      None,
      Some("ou_user"),
      Some("THUMBSUP"),
    ),
    content="false",
  )

  inspect(
    is_own_reaction_target(
      ResolvedReactionTarget::{
        chat_id: "chat-test",
        chat_type: Some("group"),
        thread_id: None,
        content: Some("hello"),
        content_type: Some("text"),
        sender_id: Some("app-test"),
        sender_type: Some("app"),
      },
      "app-test",
    ),
    content="true",
  )
  inspect(
    is_own_reaction_target(
      ResolvedReactionTarget::{
        chat_id: "chat-test",
        chat_type: Some("group"),
        thread_id: None,
        content: Some("hello"),
        content_type: Some("text"),
        sender_id: Some("ou_user"),
        sender_type: Some("user"),
      },
      "app-test",
    ),
    content="false",
  )
}

///|
test "Feishu merge_forward formatter expands nested forwarded messages in place" {
  let rendered = format_merge_forward_items("root", [
    FeishuMessageLookupItem::{
      message_id: "root",
      chat_id: "chat-test",
      chat_type: Some("group"),
      create_time: Some("0"),
      thread_id: None,
      upper_message_id: None,
      msg_type: Some("merge_forward"),
      body: Some(FeishuMessageLookupBody::{ content: Some("{}") }),
      sender: Some(FeishuMessageLookupSender::{
        id: Some("ou_root"),
        sender_type: Some("user"),
      }),
    },
    FeishuMessageLookupItem::{
      message_id: "text-1",
      chat_id: "chat-test",
      chat_type: Some("group"),
      create_time: Some("1000"),
      thread_id: None,
      upper_message_id: None,
      msg_type: Some("text"),
      body: Some(FeishuMessageLookupBody::{
        content: Some(Json::object({ "text": "first" }).stringify()),
      }),
      sender: Some(FeishuMessageLookupSender::{
        id: Some("ou_first"),
        sender_type: Some("user"),
      }),
    },
    FeishuMessageLookupItem::{
      message_id: "nested-root",
      chat_id: "chat-test",
      chat_type: Some("group"),
      create_time: Some("2000"),
      thread_id: None,
      upper_message_id: None,
      msg_type: Some("merge_forward"),
      body: Some(FeishuMessageLookupBody::{ content: Some("{}") }),
      sender: Some(FeishuMessageLookupSender::{
        id: Some("ou_nested"),
        sender_type: Some("user"),
      }),
    },
    FeishuMessageLookupItem::{
      message_id: "text-2",
      chat_id: "chat-test",
      chat_type: Some("group"),
      create_time: Some("3000"),
      thread_id: None,
      upper_message_id: Some("nested-root"),
      msg_type: Some("text"),
      body: Some(FeishuMessageLookupBody::{
        content: Some(Json::object({ "text": "nested" }).stringify()),
      }),
      sender: Some(FeishuMessageLookupSender::{
        id: Some("ou_child"),
        sender_type: Some("user"),
      }),
    },
  ])

  inspect(
    rendered,
    content="<forwarded_messages>\n[1000] ou_first:\n    first\n[2000] ou_nested:\n    <forwarded_messages>\n    [3000] ou_child:\n        nested\n    </forwarded_messages>\n</forwarded_messages>",
  )
}
