# Weixin Channel: Current MoonClaw Scope

This document describes the first Weixin channel slice implemented in MoonClaw.

It is intentionally smaller than a full MoonClaw production extension. The goal is:

- receive Weixin Official Account webhooks
- verify the handshake signature
- normalize inbound plaintext text messages into `@channel.Message`
- route them through the existing gateway message handler
- send the reply back through the Weixin custom-service API

## Implemented Files

- `channels/weixin/types.mbt`
- `channels/weixin/client.mbt`
- `channels/weixin/channel.mbt`
- `gateway/server/new.mbt`
- `gateway/server/channel_bootstrap.mbt`

## Current Supported Scope

Implemented today:

- Weixin Official Account webhook endpoint at `/webhook/weixin`
- GET handshake verification using `signature`, `timestamp`, `nonce`, `echostr`
- POST plaintext XML handling for `MsgType=text`
- outbound text replies through `/cgi-bin/message/custom/send`
- persisted channel bootstrap from `moonclaw.json`

Not implemented yet:

- encrypted / safe mode webhook decryption
- rich media messages
- event callbacks beyond plaintext text messages
- outbound message edit or reaction semantics
- websocket or streaming semantics

## Config Shape

Current bootstrap config lives under `channels.weixin` inside `moonclaw.json`.

Example:

```json
{
  "channels": {
    "weixin": {
      "enabled": true,
      "appId": "wx_your_app_id",
      "appSecret": "your_app_secret",
      "token": "your_webhook_token",
      "originalId": "gh_xxxxxxxx"
    }
  }
}
```

Also supported:

- `accounts`
- `original_id`
- `apiBaseUrl`
- `allowFrom`

`originalId` / `original_id` is used to match inbound `ToUserName` to the correct configured account when there is more than one account.

## Current Runtime Flow

```text
Gateway::new()
  -> WeixinChannel::new()
  -> weixin_channel.set_message_handler(gateway)
  -> gateway.register_extension(extension)

GET /webhook/weixin
  -> verify signature
  -> return echostr

POST /webhook/weixin
  -> verify signature
  -> parse XML
  -> build @channel.Message
  -> Gateway::handle_message(...)
  -> WeixinChannel::send(...)
  -> Weixin custom-service API
```

## Normalized Message Shape

Inbound plaintext text messages are normalized as:

- `channel = "weixin"`
- `from = FromUserName`
- `to = FromUserName`
- `content = Content`
- `content_type = "text"`
- `timestamp = CreateTime * 1000`

`to` is set to the sender openid because outbound replies need to target the same Weixin user directly.

## Signature Verification

The current implementation follows the standard Weixin pattern:

1. take `token`, `timestamp`, `nonce`
2. sort lexicographically
3. concatenate
4. compute lowercase SHA1 hex
5. compare with `signature`

## Current Delivery Model

MoonClaw does not use passive XML reply messages in this first slice.

Instead it:

- acknowledges the webhook with plain text `success`
- sends the actual reply asynchronously through the Weixin custom-service send API

That keeps the implementation aligned with the existing channel abstraction, where the gateway produces a reply message and the channel adapter transports it.

## Test Coverage Added

Current tests cover:

- signature generation and verification
- GET handshake success and failure
- POST plaintext text message parsing
- message handler invocation
- outbound reply payload capture
- bootstrap config normalization
- channel restore through `ChannelManager`

## Practical Limitation

If the Official Account is configured for encrypted / safe mode, the current implementation will reject those callbacks with a clear error instead of trying to partially process them.

That is intentional. The first slice is plaintext-only.
