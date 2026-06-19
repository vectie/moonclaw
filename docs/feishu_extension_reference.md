# Feishu Extension: Reference vs Current MoonClaw Implementation

This document used to be a pure MoonClaw design survey. It now documents both:

- the MoonClaw ideas that informed the design
- the actual MoonClaw Feishu implementation that exists today

## Current MoonClaw Scope

Implemented files:

- `channel/extension.mbt`
- `channel/extension_registry.mbt`
- `channels/feishu/channel.mbt`
- `channels/feishu/client.mbt`
- `gateway/server/new.mbt`
- `gateway/server/channel_message_handler.mbt`

Implemented runtime today:

```text
Gateway::new()
  -> FeishuChannel::new()
  -> feishu_channel.set_message_handler(gateway)
  -> gateway.register_extension(extension)

POST /webhook/feishu
  -> Gateway::handle_webhook
  -> ExtensionRegistry::handle_webhook
  -> FeishuChannel::handle_webhook
  -> FeishuChannel::handle_feishu_message
  -> Gateway::handle_message
  -> FeishuChannel::send
```

## MoonClaw Extension Contract

MoonClaw does not yet expose the full MoonClaw plugin runtime. The current extension contract is smaller and centered on webhook handling.

### `ChannelExtension`

Current required behavior:

- identify the channel
- expose a webhook path
- handle webhook requests asynchronously
- declare allowed HTTP methods
- provide a dock configuration
- run register/unregister lifecycle hooks

The important implementation detail is that `handle_webhook` is `async`, because webhook handling can call back into model loading and agent execution through the gateway message handler.

## Feishu Channel Capabilities

Defined in `channels/feishu/channel.mbt`.

Current metadata:

- `id = "feishu"`
- aliases include `lark`
- docs path `/channels/feishu`

Current capability flags:

- direct + channel chat types
- reactions enabled
- edit enabled
- reply enabled
- threads enabled
- media enabled
- no websocket support

## Current Message Flow

### 1. Webhook ingress

```text
HTTP POST /webhook/feishu
  -> Gateway::handle_webhook
    -> build ExtensionRequest
    -> ExtensionRegistry::handle_webhook("/webhook/feishu", request)
```

### 2. Feishu event parsing

```text
FeishuChannel::handle_webhook
  -> parse request JSON
  -> inspect request.http_method()
  -> if url_verification:
       return challenge JSON
  -> if im.message.receive_v1:
       handle_feishu_message(json)
  -> else:
       return OK
```

### 3. Message normalization

`FeishuChannel::handle_feishu_message` currently extracts:

- `message_id`
- `chat_type`
- `content`
- sender id
- `chat_id`
- `create_time`

Important current parsing rules:

- `content` arrives as a JSON string from Feishu and is converted by `parse_feishu_text_content`
- sender ID is accepted from multiple shapes:
  - `sender.sender_id.open_id`
  - `sender.sender_id.user_id`
  - `sender_id.open_id`
  - `sender_id.user_id`

### 4. Gateway handoff

```text
FeishuChannel::handle_feishu_message
  -> build @channel.Message
  -> resolve_account_id()
  -> message_handler.handle_message("feishu", account_id, message)
```

The configured `message_handler` is the gateway itself.

### 5. Gateway channel message handling

```text
Gateway::handle_message
  -> derive channel session key
  -> lookup prior session entry
  -> resolve cwd and model
  -> load model
  -> resume or create Moonclaw session
  -> capture assistant text from agent events
  -> moonclaw.start()
  -> persist conversation id into SessionManager
  -> return @channel.Message reply
```

Session key format:

```text
feishu:{account_id}:{chat_id}
or
feishu:{account_id}:{chat_id}:{thread_id}
```

### 6. Outbound reply

```text
FeishuChannel::handle_feishu_message
  -> self.send(response_message.to, response_message, Some(account_id))
    -> FeishuClient::send_text_message(...)
```

Important current behavior:

- replies are sent to `response_message.to`
- the gateway reply message uses `reply_to = Some(original_message.id)`
- the actual account id is resolved instead of using a hardcoded default when possible

## What Was Fixed Relative to the Earlier Draft

The following are now true in code:

- Feishu is no longer reference-only; a working webhook path exists
- webhook handling is async-capable end to end
- Feishu text payloads are parsed from nested JSON string content
- sender ID extraction supports both nested and flat Feishu shapes
- gateway stores channel session state for follow-up continuity
- replies are sent to the real chat target, not the wrong source field

## What Is Still Missing Compared to MoonClaw

MoonClaw does not yet implement the broader MoonClaw Feishu surface such as:

- stronger webhook security verification
- richer account configuration and status probes
- advanced outbound targeting helpers
- thread/media/action parity
- plugin-defined gateway method registration
- live runtime reload and richer operational tooling

## Practical Mental Model

Today, MoonClaw Feishu should be understood as:

```text
webhook adapter + websocket monitor adapter + message normalization + gateway callback + text reply transport
```

It is not yet:

```text
full MoonClaw multi-adapter Feishu runtime
```

Current websocket-mode contract in MoonClaw:

- set `connection_mode = "websocket"`
- provide `websocket_url`
- optional `websocket_headers` are forwarded into the generic gateway websocket connector
- the connection is supervised by the shared extension websocket runtime and delivered through the same Feishu monitor event handlers used by manual websocket attachments
