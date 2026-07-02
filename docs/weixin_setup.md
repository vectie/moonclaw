# Weixin Setup Guide

This guide explains how to configure and test the current Weixin Official Account channel.

## Current Scope

Implemented today:

- Official Account webhook callback at `/webhook/weixin`
- handshake verification
- plaintext text-message intake
- outbound text replies through the custom-service API

Not implemented yet:

- encrypted / safe mode
- media and richer event handling
- websocket or long-connection semantics

## Config

Put Weixin config into:

- `/path/to/MoonSuiteRoot/.moonsuite/products/moonclaw/moonclaw.json`

under:

- `channels.weixin`

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

## Start the Gateway

```bash
moon run cmd/main -- gateway start --home /path/to/MoonSuiteRoot --cwd /your/workspace
```

The callback path is:

```text
/webhook/weixin
```

So your public callback URL should look like:

```text
https://your-domain/webhook/weixin
```

## Important Weixin Console Setting

Use plaintext or compatible mode for the current implementation.

If the account is set to encrypted / safe mode, MoonClaw will reject the callback.

## How the Handshake Works

Weixin sends a `GET` request with:

- `signature`
- `timestamp`
- `nonce`
- `echostr`

MoonClaw verifies the signature and returns `echostr` when valid.

If the Weixin console accepts your callback URL, the handshake path is working.

## Test Flow

1. Configure `channels.weixin` in `/path/to/MoonSuiteRoot/.moonsuite/products/moonclaw/moonclaw.json`.
2. Start the gateway.
3. Expose the gateway publicly over HTTPS.
4. Put the callback URL into the Weixin Official Account console.
5. Confirm the console accepts the URL.
6. Send a plain text message to the Official Account from a real Weixin user.
7. Check that MoonClaw receives the webhook and replies.

## What to Verify

Successful first test:

- callback verification succeeds
- incoming text message reaches the gateway
- MoonClaw produces a normal channel message
- reply is sent through the Weixin custom-service API

## Feishu and Weixin Together

MoonClaw supports both channels at once.

They run on different webhook paths:

- `/webhook/feishu`
- `/webhook/weixin`

So a single gateway instance can host both if both are configured.

## Related Docs

- [docs/moonclaw_weixin_reference.md](/Users/kq/Workspace/moonclaw/docs/moonclaw_weixin_reference.md)
- [docs/GATEWAY_USAGE.md](/Users/kq/Workspace/moonclaw/docs/GATEWAY_USAGE.md)
