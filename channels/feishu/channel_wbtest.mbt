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
fn feishu_camelcase_config() -> @channel.ChannelConfig {
  @channel.ChannelConfig::{
    enabled: true,
    accounts: {
      "default": {
        "appId": "app-camel",
        "appSecret": "secret-camel",
        "domain": "feishu",
        "connectionMode": "webhook",
        "dmPolicy": "pairing",
        "verifyToken": "verify-test",
        "enabled": true,
      },
    },
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
test "feishu_stream_key is stable for reply target" {
  let message = @channel.Message::{
    id: "reply-1",
    channel: "feishu",
    from: "bot",
    to: "chat-1",
    content: "Thinking...",
    content_type: "progress",
    timestamp: 1,
    thread_id: Some("thread-1"),
    reply_to: Some("incoming-1"),
    attachments: [],
  }
  inspect(
    feishu_stream_key("default", message),
    content="default:chat-1:incoming-1:thread-1",
  )
}

///|
test "feishu_typing_message_id uses reply target only" {
  inspect(
    feishu_typing_message_id(@channel.Message::{
      id: "reply-1",
      channel: "feishu",
      from: "bot",
      to: "chat-1",
      content: "Thinking...",
      content_type: "progress",
      timestamp: 1,
      thread_id: Some("thread-1"),
      reply_to: Some("incoming-1"),
      attachments: [],
    }),
    content="Some(\"incoming-1\")",
  )
  inspect(
    feishu_typing_message_id(@channel.Message::{
      id: "reply-2",
      channel: "feishu",
      from: "bot",
      to: "chat-1",
      content: "Thinking...",
      content_type: "progress",
      timestamp: 1,
      thread_id: None,
      reply_to: None,
      attachments: [],
    }),
    content="None",
  )
}

///|
test "feishu_progress_emoji_type maps phases to emoji names" {
  inspect(feishu_progress_emoji_type("thinking"), content="THINKING")
  inspect(feishu_progress_emoji_type("tool"), content="HAMMER")
  inspect(feishu_progress_emoji_type("drafting"), content="OnIt")
  inspect(feishu_progress_emoji_type("unknown"), content="THINKING")
}

///|
test "build_streaming_card_json contains content element" {
  inspect(
    build_streaming_card_json("Thinking...").stringify(),
    content="{\"schema\":\"2.0\",\"config\":{\"streaming_mode\":true,\"summary\":{\"content\":\"[Generating...]\"},\"streaming_config\":{\"print_frequency_ms\":{\"default\":50},\"print_step\":{\"default\":1}}},\"body\":{\"elements\":[{\"tag\":\"markdown\",\"content\":\"Thinking...\",\"element_id\":\"content\"}]}}",
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
async test "Feishu webhook routes force-stop text to force_cancel events without invoking message handling" {
  let channel = FeishuChannel::new()
  channel.configure(feishu_test_config())
  let handler = RecordingHandler::new()
  channel.set_message_handler(handler)

  let response = channel.handle_webhook(
    feishu_message_request(
      "event-force-abort",
      "message-force-abort",
      "/force-stop",
      @clock.epoch.now().ms().to_string(),
    ),
  )

  inspect(response.status_code(), content="200")
  inspect(handler.handled_message_ids.length(), content="0")
  json_inspect(handler.event_types, content=["force_cancel"])
}

///|
test "Feishu queue cancel clears pending work and marks active queue for stop" {
  let channel = FeishuChannel::new()
  let queue_key = feishu_queue_key("default", "chat-1", None)
  channel.enqueue_message(queue_key, QueuedFeishuMessage::{
    account_id: "default",
    message: @channel.Message::{
      id: "msg-1",
      channel: "feishu",
      from: "user",
      to: "chat-1",
      content: "first",
      content_type: "text",
      timestamp: 1,
      thread_id: None,
      reply_to: None,
      attachments: [],
    },
  })
  channel.set_processing_queue(queue_key, true)

  channel.request_queue_cancel(queue_key)

  inspect(channel.dequeue_message(queue_key) is None, content="true")
  inspect(channel.is_queue_cancelled(queue_key), content="true")
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
async test "Feishu webhook resolves accounts from camelCase appId/appSecret config" {
  let channel = FeishuChannel::new()
  channel.configure(feishu_camelcase_config())
  let handler = RecordingHandler::new()
  channel.set_message_handler(handler)

  let payload : Json = {
    "schema": "2.0",
    "header": {
      "event_id": "event-camel",
      "event_type": "im.message.receive_v1",
      "app_id": "app-camel",
      "token": "verify-test",
    },
    "event": {
      "sender": {
        "sender_id": { "open_id": "ou_sender", "user_id": "user_sender" },
      },
      "message": {
        "message_id": "message-camel",
        "message_type": "text",
        "chat_id": "chat-test",
        "chat_type": "p2p",
        "create_time": @clock.epoch.now().ms().to_string(),
        "content": Json::object({ "text": "hello camel" }).stringify(),
      },
    },
    "token": "verify-test",
  }
  let response = channel.handle_webhook(
    @channel.ExtensionRequest::new(
      http_method="POST",
      path="/webhook/feishu",
      headers={ "content-type": "application/json" },
      body=@encoding/utf8.encode(payload.stringify()),
    ),
  )

  inspect(response.status_code(), content="500")
  json_inspect(handler.handled_message_ids, content=["message-camel"])
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

///|
test "Feishu merge_forward formatter prefers resolved sender names over raw ids" {
  let rendered = format_merge_forward_items(
    "root",
    [
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
          content: Some(Json::object({ "text": "hello" }).stringify()),
        }),
        sender: Some(FeishuMessageLookupSender::{
          id: Some("ou_sender"),
          sender_type: Some("user"),
        }),
      },
    ],
    sender_names={ "ou_sender": "Alice" },
  )

  inspect(
    rendered,
    content="<forwarded_messages>\n[1000] Alice:\n    hello\n</forwarded_messages>",
  )
}

///|
test "Feishu forward sender helpers deduplicate ids and use account scoped cache keys" {
  let sender_ids = collect_forward_sender_ids([
    FeishuMessageLookupItem::{
      message_id: "a",
      chat_id: "chat-test",
      chat_type: Some("group"),
      create_time: Some("1"),
      thread_id: None,
      upper_message_id: None,
      msg_type: Some("text"),
      body: None,
      sender: Some(FeishuMessageLookupSender::{
        id: Some("ou_sender"),
        sender_type: Some("user"),
      }),
    },
    FeishuMessageLookupItem::{
      message_id: "b",
      chat_id: "chat-test",
      chat_type: Some("group"),
      create_time: Some("2"),
      thread_id: None,
      upper_message_id: None,
      msg_type: Some("text"),
      body: None,
      sender: Some(FeishuMessageLookupSender::{
        id: Some("ou_sender"),
        sender_type: Some("user"),
      }),
    },
    FeishuMessageLookupItem::{
      message_id: "c",
      chat_id: "chat-test",
      chat_type: Some("group"),
      create_time: Some("3"),
      thread_id: None,
      upper_message_id: None,
      msg_type: Some("text"),
      body: None,
      sender: Some(FeishuMessageLookupSender::{
        id: Some("bot-id"),
        sender_type: Some("app"),
      }),
    },
  ])

  json_inspect(sender_ids, content=["ou_sender"])

  let channel = FeishuChannel::new()
  channel.cache_user_name("account-a", "ou_sender", "Alice")
  channel.cache_user_name("account-b", "ou_sender", "Bob")
  inspect(
    channel.cached_user_name("account-a", "ou_sender"),
    content="Some(\"Alice\")",
  )
  inspect(
    channel.cached_user_name("account-b", "ou_sender"),
    content="Some(\"Bob\")",
  )
}

///|
test "Feishu websocket monitor support follows configured websocket accounts" {
  let channel = FeishuChannel::new()
  channel.configure(feishu_test_config())
  inspect(channel.supports_websocket(), content="false")

  channel.configure(@channel.ChannelConfig::{
    enabled: true,
    accounts: {
      "websocket": {
        "app_id": "app-ws",
        "app_secret": "secret-ws",
        "domain": "feishu",
        "connection_mode": "websocket",
        "dm_policy": "pairing",
        "enabled": true,
      },
    },
    global_settings: {},
  })
  inspect(channel.supports_websocket(), content="true")
  json_inspect(channel.websocket_monitor_accounts(), content=["websocket"])
}

///|
async test "Feishu websocket monitor connections receive ready and status updates" {
  let channel = FeishuChannel::new()
  channel.configure(@channel.ChannelConfig::{
    enabled: true,
    accounts: {
      "websocket": {
        "app_id": "app-ws",
        "app_secret": "secret-ws",
        "domain": "feishu",
        "connection_mode": "websocket",
        "dm_policy": "pairing",
        "enabled": true,
      },
    },
    global_settings: {},
  })

  let sent : Array[String] = []
  let close_calls : Array[Int] = []
  let mut on_close : (() -> Unit)? = None
  let conn = @channel.WebSocketConnection::new(
    id="monitor-1",
    send=fn(bytes) {
      let text = @encoding/utf8.decode(bytes) catch { _ => "" }
      sent.push(text)
    },
    close=fn() { close_calls.push(1) },
    on_close=fn(handler) { on_close = Some(handler) },
  )

  channel.handle_websocket(conn)
  inspect(sent.length(), content="1")
  inspect(sent[0].contains("\"type\":\"feishu.monitor.ready\""), content="true")
  inspect(sent[0].contains("\"account_id\":\"websocket\""), content="true")

  let _ = channel.start(
    "websocket",
    Json::object({
      "app_id": "app-ws",
      "app_secret": "secret-ws",
      "domain": "feishu",
      "connection_mode": "websocket",
      "dm_policy": "pairing",
      "enabled": true,
    }),
  )
  inspect(sent.length(), content="2")
  inspect(
    sent[1].contains("\"type\":\"feishu.monitor.status\""),
    content="true",
  )
  inspect(sent[1].contains("\"running\":true"), content="true")

  channel.on_unregister()
  inspect(close_calls.length(), content="1")
  match on_close {
    Some(handler) => handler()
    None => ()
  }
  inspect(channel.state.active_monitor_connections.is_empty(), content="true")
}

///|
async test "Feishu websocket monitor routes inbound message events and ping frames" {
  let channel = FeishuChannel::new()
  channel.configure(feishu_test_config())
  let handler = RecordingHandler::new()
  channel.set_message_handler(handler)

  let sent : Array[String] = []
  let mut inbound : (async (Bytes) -> Unit)? = None
  let conn = @channel.WebSocketConnection::new(
    id="monitor-inbound",
    send=fn(bytes) {
      let text = @encoding/utf8.decode(bytes) catch { _ => "" }
      sent.push(text)
    },
    close=fn() {  },
    on_message=fn(handler) { inbound = Some(handler) },
  )

  channel.handle_websocket(conn)
  match inbound {
    Some(handle_frame) => {
      handle_frame(@encoding/utf8.encode("{\"type\":\"ping\"}"))
      handle_frame(
        @encoding/utf8.encode(
          Json::object({
            "header": {
              "event_id": "monitor-message",
              "event_type": "im.message.receive_v1",
              "app_id": "app-test",
              "token": "verify-test",
            },
            "event": {
              "sender": {
                "sender_id": {
                  "open_id": "ou_sender",
                  "user_id": "user_sender",
                },
              },
              "message": {
                "message_id": "message-monitor",
                "message_type": "text",
                "chat_id": "chat-test",
                "chat_type": "p2p",
                "create_time": @clock.epoch.now().ms().to_string(),
                "content": Json::object({ "text": "hello from ws" }).stringify(),
              },
            },
            "token": "verify-test",
          }).stringify(),
        ),
      )
    }
    None => abort("expected inbound websocket handler")
  }

  inspect(handler.handled_message_ids.length(), content="1")
  inspect(handler.handled_message_ids[0], content="message-monitor")
  inspect(sent[1].contains("\"type\":\"pong\""), content="true")
  inspect(sent[2].contains("\"type\":\"feishu.monitor.error\""), content="true")
  inspect(sent[2].contains("\"code\":\"event_rejected\""), content="true")
}

///|
async test "Feishu websocket runtime starts websocket accounts through extension context" {
  let manager = @channel.WebSocketClientRuntimeManager::new()
  let runtime = manager.controller()
  let channel = FeishuChannel::new()
  channel.configure(@channel.ChannelConfig::{
    enabled: true,
    accounts: {
      "websocket": {
        "app_id": "app-ws",
        "app_secret": "secret-ws",
        "domain": "feishu",
        "connection_mode": "websocket",
        "websocket_url": "ws://127.0.0.1:18080/feishu",
        "websocket_headers": { "Authorization": "Bearer test-token" },
        "dm_policy": "pairing",
        "verify_token": "verify-ws",
        "enabled": true,
      },
    },
    global_settings: {},
  })
  let handler = RecordingHandler::new()
  channel.set_message_handler(handler)

  let sent : Array[Bytes] = []
  let mut inbound : (async (Bytes) -> Unit)? = None
  let connector = @channel.WebSocketClientConnector::new(connect=request => {
    inspect(request.protocol(), content="feishu")
    inspect(request.client_id(), content="feishu:websocket")
    inspect(
      request
      .metadata()
      .stringify()
      .contains("\"url\":\"ws://127.0.0.1:18080/feishu\""),
      content="true",
    )
    inspect(
      request
      .metadata()
      .stringify()
      .contains("\"Authorization\":\"Bearer test-token\""),
      content="true",
    )
    Ok(
      @channel.WebSocketManagedConnection::new(
        connection=@channel.WebSocketConnection::new(
          id="runtime-monitor",
          send=fn(bytes) { sent.push(bytes) },
          close=fn() {  },
          on_message=fn(handler) { inbound = Some(handler) },
        ),
      ),
    )
  })

  @async.with_task_group(group => {
    group.spawn_bg(() => manager.start(), no_wait=true, allow_failure=true)
    channel.on_register(
      @channel.ExtensionContext::new(
        gateway_url="http://localhost:18123",
        home_dir="/tmp",
        cwd="/tmp",
        websocket_connector=Some(connector),
        websocket_runtime=Some(runtime),
      ),
    )
    let _ = channel.start(
      "websocket",
      Json::object({
        "app_id": "app-ws",
        "app_secret": "secret-ws",
        "domain": "feishu",
        "connection_mode": "websocket",
        "websocket_url": "ws://127.0.0.1:18080/feishu",
        "websocket_headers": { "Authorization": "Bearer test-token" },
        "dm_policy": "pairing",
        "verify_token": "verify-ws",
        "enabled": true,
      }),
    )
    @async.sleep(50)
    match inbound {
      Some(handle_frame) =>
        handle_frame(
          encode_feishu_websocket_frame(FeishuWebSocketFrame::{
            seq_id: 1,
            log_id: 2,
            service: 3,
            method_id: feishu_ws_data_frame,
            headers: [
              FeishuWebSocketHeader::{
                key: feishu_ws_header_type,
                value: feishu_ws_type_event,
              },
              FeishuWebSocketHeader::{
                key: feishu_ws_header_message_id,
                value: "runtime-monitor-message",
              },
              FeishuWebSocketHeader::{ key: feishu_ws_header_sum, value: "1" },
              FeishuWebSocketHeader::{ key: feishu_ws_header_seq, value: "0" },
              FeishuWebSocketHeader::{
                key: feishu_ws_header_trace_id,
                value: "trace-1",
              },
            ],
            payload_encoding: None,
            payload_type: None,
            payload: Some(
              @encoding/utf8.encode(
                Json::object({
                  "header": {
                    "event_id": "runtime-monitor-message",
                    "event_type": "im.message.receive_v1",
                    "app_id": "app-ws",
                    "token": "verify-ws",
                  },
                  "event": {
                    "sender": {
                      "sender_id": {
                        "open_id": "ou_sender",
                        "user_id": "user_sender",
                      },
                    },
                    "message": {
                      "message_id": "message-runtime-monitor",
                      "message_type": "text",
                      "chat_id": "chat-test",
                      "chat_type": "p2p",
                      "create_time": @clock.epoch.now().ms().to_string(),
                      "content": Json::object({
                        "text": "hello from runtime ws",
                      }).stringify(),
                    },
                  },
                  "token": "verify-ws",
                }).stringify(),
              ),
            ),
            log_id_new: None,
          }),
        )
      None => abort("expected runtime websocket inbound handler")
    }
    @async.sleep(50)
    inspect(handler.handled_message_ids[0], content="message-runtime-monitor")
    inspect(sent.length() >= 1, content="true")
    let ack = sent
      .map(fn(bytes) { decode_feishu_websocket_frame(bytes) })
      .filter_map(fn(result) {
        match result {
          Ok(frame) if frame.method_id == feishu_ws_data_frame => Some(frame)
          _ => None
        }
      })
      .get(0)
      .unwrap()
    inspect(ack.method_id, content="1")
    inspect(
      match ack.payload {
        Some(payload) => payload.length() > 0
        None => false
      },
      content="true",
    )
    runtime.stop_all()
    group.return_immediately(())
  })
}

///|
async test "Feishu websocket runtime requires websocket_url or platform endpoint resolution" {
  let manager = @channel.WebSocketClientRuntimeManager::new()
  let runtime = manager.controller()
  let channel = FeishuChannel::new()
  channel.configure(@channel.ChannelConfig::{
    enabled: true,
    accounts: {
      "websocket": {
        "app_id": "app-ws",
        "app_secret": "secret-ws",
        "domain": "feishu",
        "connection_mode": "websocket",
        "dm_policy": "pairing",
        "verify_token": "verify-ws",
        "enabled": true,
      },
    },
    global_settings: {},
  })
  let connect_calls : Array[String] = []
  let connector = @channel.WebSocketClientConnector::new(connect=fn(request) {
    connect_calls.push(request.client_id())
    Ok(
      @channel.WebSocketManagedConnection::new(
        connection=@channel.WebSocketConnection::new(
          id="unexpected",
          send=fn(_) {  },
          close=fn() {  },
        ),
      ),
    )
  })

  @async.with_task_group(group => {
    group.spawn_bg(() => manager.start(), no_wait=true, allow_failure=true)
    channel.on_register(
      @channel.ExtensionContext::new(
        gateway_url="http://localhost:18123",
        home_dir="/tmp",
        cwd="/tmp",
        websocket_connector=Some(connector),
        websocket_runtime=Some(runtime),
      ),
    )
    let _ = channel.start(
      "websocket",
      Json::object({
        "app_id": "app-ws",
        "app_secret": "secret-ws",
        "domain": "feishu",
        "connection_mode": "websocket",
        "dm_policy": "pairing",
        "verify_token": "verify-ws",
        "enabled": true,
      }),
    )
    @async.sleep(50)
    inspect(connect_calls.length(), content="0")
    runtime.stop_all()
    group.return_immediately(())
  })
}

///|
async test "Feishu websocket runtime refreshes resolved endpoint on reconnect" {
  let manager = @channel.WebSocketClientRuntimeManager::new()
  let runtime = manager.controller()
  let channel = FeishuChannel::new()
  channel.configure(@channel.ChannelConfig::{
    enabled: true,
    accounts: {
      "websocket": {
        "app_id": "app-ws-refresh",
        "app_secret": "secret-ws",
        "domain": "feishu",
        "connection_mode": "websocket",
        "dm_policy": "pairing",
        "verify_token": "verify-ws",
        "enabled": true,
      },
    },
    global_settings: {},
  })
  channel.set_test_websocket_endpoint_sequence("app-ws-refresh", [
    "ws://127.0.0.1:18080/first", "ws://127.0.0.1:18080/second",
  ])
  let dialed_urls : Array[String] = []
  let connector = @channel.WebSocketClientConnector::new(connect=request => {
    match request.metadata() {
      { "url": String(url), .. } => dialed_urls.push(url)
      _ => ()
    }
    Ok(
      @channel.WebSocketManagedConnection::new(
        connection=@channel.WebSocketConnection::new(
          id="refresh-monitor-\{dialed_urls.length()}",
          send=fn(_) {  },
          close=fn() {  },
        ),
        wait_until_closed=async fn() { @async.sleep(10) },
      ),
    )
  })

  @async.with_task_group(group => {
    group.spawn_bg(() => manager.start(), no_wait=true, allow_failure=true)
    channel.on_register(
      @channel.ExtensionContext::new(
        gateway_url="http://localhost:18123",
        home_dir="/tmp",
        cwd="/tmp",
        websocket_connector=Some(connector),
        websocket_runtime=Some(runtime),
      ),
    )
    let _ = channel.start(
      "websocket",
      Json::object({
        "app_id": "app-ws-refresh",
        "app_secret": "secret-ws",
        "domain": "feishu",
        "connection_mode": "websocket",
        "dm_policy": "pairing",
        "verify_token": "verify-ws",
        "enabled": true,
      }),
    )
    @async.sleep(2_250)
    inspect(dialed_urls.length() >= 2, content="true")
    inspect(dialed_urls[0], content="ws://127.0.0.1:18080/first")
    inspect(dialed_urls[1], content="ws://127.0.0.1:18080/second")
    runtime.stop_all()
    group.return_immediately(())
  })
}
