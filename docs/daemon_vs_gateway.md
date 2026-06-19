# Daemon vs Gateway

This comparison reflects the current codebase.

## Short Version

- use `daemon` when you want the older task/process supervisor model
- use `gateway` when you want HTTP/RPC, SSE, channels, mailboxes, and orchestration APIs
- do not merge them right now; Feishu/channel work should continue in `gateway`

## Current Focus

### Daemon

Primary traits:

- process-oriented
- workspace/task supervision
- OAuth-related flows
- task registry and daemon lock handling

### Gateway

Primary traits:

- HTTP + JSON-RPC
- agent run tracking
- SSE event stream
- channel extension hosting
- mailbox, coordination, pipeline APIs

## Current Gateway Structure

```text
Gateway
  -> HTTP server
  -> sessions
  -> dedupe cache
  -> agent_runs
  -> agent_events broadcast
  -> channel_manager
  -> extension_registry
  -> mailbox_manager
  -> coordinator
  -> pipeline_manager
```

## Current Daemon Structure

See `cmd/daemon/*` for the actual implementation, but conceptually:

```text
Daemon
  -> HTTP server
  -> process manager
  -> by_cwd / by_id task maps
  -> conversation manager
  -> auth providers
```

## Feature Comparison

| Capability | Daemon | Gateway |
|---|---|---|
| Long-running service | yes | yes |
| HTTP API | yes | yes |
| JSON-RPC | yes | yes |
| SSE | limited / task oriented | yes, `/v1/events` |
| Agent run registry | task-centric | `agent_runs` |
| Idempotent agent requests | not the main abstraction | yes, dedupe cache |
| Channel extension hosting | no | yes |
| Feishu webhook integration | no | yes |
| Agent mailboxes | no | yes |
| Coordination API | no | yes |
| Pipeline API | no | yes |

## Operational Differences

### Daemon

- oriented around task lifecycle and local process management
- more supervisor-like

### Gateway

- oriented around request/response and integration surfaces
- more suitable for external clients or channel adapters

## Important Corrections

Older drafts had these wrong:

- gateway default port is `18123`
- gateway does not have a built-in `--detach` mode
- gateway does not have a built-in `status` subcommand
- gateway is no longer “HTTP API only”; it also exposes channels/extensions/mailboxes/orchestration

## When to Choose Gateway

Choose gateway if you need:

- RPC-friendly remote control
- a stable HTTP surface
- SSE agent events
- webhook-hosted channels such as Feishu
- mailbox or orchestration APIs
- Feishu or other channel runtime that should survive as a background service

For an MoonClaw always-on Feishu backend, `gateway` is the correct service entrypoint. Keep `daemon` separate; strengthen `gateway` instead of merging the two runtimes.
The current Feishu websocket startup path also lives in `gateway`: it can resolve the upstream Feishu websocket endpoint from `appId` / `appSecret` and keep that long-lived connection under the gateway-managed extension runtime.

## When to Choose Daemon

Choose daemon if you need:

- process/task supervision semantics
- existing daemon-oriented operational flows
- the daemon-specific task APIs and lock-file model
