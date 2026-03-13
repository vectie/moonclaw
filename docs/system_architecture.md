# MoonClaw System Architecture

This document describes the current implementation, not the earlier design drafts.

## Top-Level Entry Points

`cmd/main/main.mbt` dispatches into five user-facing modes:

| Mode | Entry | Purpose |
|---|---|---|
| `interactive` | `cmd/main/interactive/interactive.mbt` | simple local chat loop |
| `tui` | `cmd/main/tui/tui.mbt` | terminal UI on top of a local `Moonclaw` instance |
| `daemon` | `cmd/daemon/main.mbt` | long-running process/task supervisor |
| `gateway` | `cmd/gateway/main.mbt` | long-running HTTP/RPC gateway with channel and orchestration support |
| `server` | `cmd/server/main.mbt` | lighter HTTP server for direct task interaction |

Actual dispatch:

```text
cmd/main/main.mbt
  -> ["gateway", ..rest] -> @gateway.start(rest)
  -> ["tui", ..rest] -> @tui.tui_interactive(rest)
  -> ["daemon", ..rest] -> @daemon.start(rest)
  -> ["server", ..rest] -> @server.start(rest)
  -> default -> @interactive.interactive(rest)
```

## Core Runtime Layers

```text
CLI / TUI / Gateway / Daemon / Server
  -> Moonclaw session lifecycle
    -> agent/Agent
      -> model loader
      -> tool registry
      -> event stream
      -> conversation state
```

The shared unit is `@moonclaw.Moonclaw`:

- `Moonclaw::new(...)` creates a fresh agent session
- `Moonclaw::resume_(...)` restores a prior conversation by UUID
- `moonclaw.start()` runs one conversation cycle
- `moonclaw.close()` releases resources

## Gateway Runtime Structure

`gateway/server/gateway.mbt` defines the main server state:

| Field | Role |
|---|---|
| `httpx` | HTTP listener |
| `events` | gateway lifecycle broadcast |
| `agent_events` | per-agent SSE broadcast |
| `sessions` | session key -> conversation/model/cwd state |
| `dedupe` | run/idempotency cache |
| `agent_runs` | run status and final payloads |
| `channel_manager` | registered channel docks |
| `extension_registry` | webhook-capable channel extensions |
| `mailbox_manager` | agent-to-agent message mailboxes |
| `coordinator` | coordination tasks and subtask state |
| `pipeline_manager` | pipeline definitions and stage state |

`gateway/server/new.mbt` creates the gateway, loads persisted state, seeds missing Feishu channel state from `.moonclaw/moonclaw.json`, auto-registers the Feishu extension, and restores enabled channel runtime.

## Gateway Persistent State

The gateway keeps two JSON-backed state files under `home/gateway/`:

| File | Owner | Purpose |
|---|---|---|
| `gateway/sessions/sessions.json` | `SessionManager` | session key -> conversation/model/provider/cwd state |
| `gateway/channels.json` | `ChannelStateStore` | channel config plus per-account runtime intent |

Startup sequence:

```text
Gateway::new(...)
  -> create gateway/session directories
  -> sessions.load()
  -> channel_state.load()
  -> seed missing channel state from `{cwd}/.moonclaw/moonclaw.json`
  -> fallback seed from `{home}/.moonclaw/moonclaw.json`
  -> register Feishu extension
  -> restore_channel_runtime()
```

That means a restart now preserves direct-run conversation continuity, channel-triggered conversation continuity, channel config, and which channel accounts should auto-start again.
It also means a first gateway start can bootstrap Feishu from the same `.moonclaw/moonclaw.json` file that the local CLI/model loader already uses.
For Feishu websocket-mode accounts, restore now supports both:

- manual `websocket_url` override
- native endpoint resolution from `app_id` / `app_secret` via Feishu `/callback/ws/endpoint`

## Gateway HTTP Surface

The route table lives in `gateway/server/request.mbt`.

### Basic service routes

- `GET /`
- `GET /health`
- `GET /v1/events`
- `GET /v1/runs`
- `GET /v1/runs/{id}`
- `POST /v1/agent`
- `POST /v1/rpc`
- `POST /v1/shutdown`

### Channel and extension routes

- `GET /v1/channels`
- `GET /v1/channels/{id}`
- `POST /v1/channels/{id}/configure`
- `POST /v1/channels/{id}/start`
- `POST /v1/channels/{id}/stop`
- `GET /v1/extensions`
- `GET /v1/extensions/{id}`
- `POST|GET /webhook/{channel_id}/...`

### Mailbox routes

- `POST /v1/agent/message`
- `GET /v1/agent/{agent_id}/messages`
- `POST /v1/mailbox`
- `DELETE /v1/mailbox/{mailbox_id}`
- `GET /v1/mailboxes`

### Multi-agent routes

- `POST /v1/coordination`
- `GET /v1/coordination`
- `GET /v1/coordination/{id}`
- `POST /v1/coordination/{id}/start`
- `POST /v1/coordination/{id}/cancel`
- `POST /v1/coordination/{id}/subtask/{task_id}`
- `GET /v1/coordination/{id}/results`

- `POST /v1/pipeline`
- `GET /v1/pipeline`
- `GET /v1/pipeline/{id}`
- `POST /v1/pipeline/{id}/start`
- `POST /v1/pipeline/{id}/cancel`
- `POST /v1/pipeline/{id}/advance`
- `POST /v1/pipeline/{id}/fail`
- `GET /v1/pipeline/{id}/next`

## Gateway Call Chain

### 1. CLI to gateway process

```text
cmd/main/main.mbt
  -> cmd/gateway/main.mbt::start(args)
    -> "start" -> start_gateway(args)
      -> @server.Gateway::new(...)
      -> gateway.start()
```

### 2. HTTP request to route handler

```text
gateway.start()
  -> httpx.serve(cors(handler))
    -> Gateway::handle_request(r, w)
      -> path/method match
      -> concrete handler
```

### 3. JSON-RPC request path

```text
POST /v1/rpc
  -> Gateway::handle_rpc
    -> parse_frame(json)
    -> Gateway::handle_request_frame
      -> "connect" / "agent" / "agent.wait" / "sessions.list" / ...
```

### 4. Direct HTTP agent path

```text
POST /v1/agent
  -> Gateway::handle_agent
    -> parse AgentParams
    -> create run_id + idempotency_key
    -> write 202 Accepted immediately
    -> spawn background execute_agent_async(...)
```

### 5. Agent execution path

```text
Gateway::execute_agent_async
  -> Gateway::execute_agent
    -> resolve cwd
    -> resolve session_key
    -> sessions.get_or_create(...)
    -> resolve model override / default model
    -> @model.load(...)
    -> @agent.new(...)
    -> attach event listener
    -> agent.start()
    -> agent.close()
    -> store final run payload into agent_runs
    -> store dedupe entry
    -> emit gateway events
```

The final run payload currently includes:

- `run_id`
- `status`
- `session_key`
- `model`
- `content`
- `conversation_id`
- `completed_at`

## Session Routing and Write-Back Flow

Session-key derivation is centralized in `gateway/server/session_route.mbt`.

### Direct runs

```text
Client / HTTP agent request
  -> direct_session_key(session_key?, run_id)
  -> sessions.get_or_create(...)
  -> execute agent
  -> sessions.save_entry(session_key, SessionEntry{ conversation_id, model, cwd, ... })
```

Rules:

- if the caller supplies `session_key`, that key is used
- otherwise the gateway falls back to `run_id`
- the final conversation id is written back into the persistent session store

### Channel-triggered runs

```text
Webhook message
  -> message_session_key(channel_id, account_id, message)
  -> sessions.get(session_key)
  -> resume existing conversation if present
  -> else create new Moonclaw session
  -> execute agent
  -> store_channel_session(...)
  -> sessions.save_entry(...)
```

Current channel key format:

```text
{channel_id}:{account_id}:{chat_id}
{channel_id}:{account_id}:{chat_id}:{thread_id}
```

### Orchestration runs

Background multi-agent work also gets stable derived keys:

```text
coordination_session_key(coordination_id, task_id)
pipeline_stage_session_key(pipeline_id, stage_name)
```

That keeps orchestration runs in separate conversation lanes instead of sharing generic session ids.

## TUI Call Chain

```text
cmd/main/main.mbt
  -> cmd/main/tui/tui.mbt::tui_interactive(args)
    -> @model.load(...)
    -> Moonclaw::new(...) or Moonclaw::resume_(...)
    -> @tui.TUI::new()
    -> wire submit / ctrl-c / ctrl-d / ctrl-o callbacks
    -> attach moonclaw.agent event listener
    -> spawn TUI event loop
    -> loop moonclaw.agent.start() while running
```

Important current behavior:

- header/footer/status are refreshed during `TUI::render()`
- `Ctrl-C` requests a clean exit
- `Ctrl-O` toggles tool expansion state
- TUI state is initialized from the live agent model/session/id
- assistant/tool events update the chat log incrementally

## Channel Message Flow

The implemented channel path today is Feishu webhook -> gateway -> local Moonclaw session -> Feishu reply.

```text
Feishu webhook request
  -> Gateway::handle_webhook
    -> ExtensionRegistry::handle_webhook
      -> FeishuChannel::handle_webhook
        -> FeishuChannel::handle_feishu_message
          -> MessageHandler::handle_message (Gateway impl)
            -> derive channel session key
            -> load session entry
            -> load model
            -> Moonclaw::new/resume_
            -> run agent
            -> capture last assistant text
            -> persist session mapping
            -> return @channel.Message reply
          -> FeishuChannel::send(...)
```

Session continuity is keyed by:

```text
{channel_id}:{account_id}:{chat_id}
or
{channel_id}:{account_id}:{chat_id}:{thread_id}
```

## Channel Config and Runtime Restore Flow

Channel lifecycle now has both a durable write path and a startup restore path.

Write path:

```text
channels.configure
  -> ChannelManager.configure_channel(...)
  -> ChannelStateStore.save_config(...)

channels.start
  -> ChannelManager.start_channel(...)
  -> ChannelStateStore.save_account_runtime(..., auto_start=true)

channels.stop
  -> ChannelManager.stop_channel(...)
  -> ChannelStateStore.save_account_runtime(..., auto_start=false)
```

Restore path:

```text
Gateway::restore_channel_runtime
  -> ChannelStateStore.list_states()
  -> ChannelManager.restore_states(...)
    -> configure all persisted channels
    -> start only accounts with auto_start=true
```

Important runtime behavior:

- removing an account from channel config prunes its persisted runtime entry
- stopping a channel account keeps the config but disables auto-start
- restart restores channel configuration first, then only runnable accounts

## Mailbox Message Flow

```text
POST /v1/agent/message
  -> Gateway::handle_agent_message
    -> parse SendMessageParams
    -> build AgentMessage
    -> mailbox_manager.deliver_sync(...)

GET /v1/agent/{agent_id}/messages
  -> Gateway::handle_get_messages
    -> mailbox_manager.get(agent_id)
    -> mailbox.try_get()
```

This is implemented as a lightweight agent-to-agent mailbox, not a full bus with persistence or replay.

## Coordination Flow

```text
POST /v1/coordination
  -> create CoordinationTask with subtasks in Pending

POST /v1/coordination/{id}/start
  -> Coordinator::start_task(...)
  -> spawn_bg(no_wait=true, run_coordination(id))

Gateway::run_coordination(id)
  -> list pending subtasks
  -> for each subtask:
     -> mark Running
     -> execute_agent(...)
     -> mark Completed or Failed
  -> Coordinator::update_subtask_status(...)
     finalizes parent task when all subtasks are done
```

Important current semantics:

- `pending_count()` means strictly `Pending`
- start can return `429` if `max_concurrent` is exhausted
- invalid subtask updates return `404`
- stale or cancelled subtasks are guarded against late write-back in the runner

## Pipeline Flow

```text
POST /v1/pipeline
  -> create Pipeline with stages in Pending

POST /v1/pipeline/{id}/start
  -> PipelineManager::start_pipeline(...)
  -> first stage becomes Running
  -> spawn_bg(no_wait=true, run_pipeline(id))

Gateway::run_pipeline(id)
  -> fetch current stage
  -> resolve input_template against prior results
  -> execute_agent(...)
  -> on success: advance_stage(...)
  -> on error: fail_stage(...)
  -> next stage becomes Running automatically
```

Current template syntax is:

```text
${stage_name}.output
```

Example:

```text
"Summarize ${research}.output"
```

Important current semantics:

- start marks stage 0 as `Running`
- `advance_stage` starts the next stage automatically
- invalid manual `advance` / `fail` requests return `409`
- stale or cancelled pipelines are guarded against late async write-back

## Feishu Extension Architecture

MoonClaw does not yet implement the full OpenClaw-style plugin runtime. The current extension model is smaller:

```text
ChannelExtension trait
  -> webhook_path()
  -> async handle_webhook(...)
  -> allowed_methods()
  -> dock_config()
  -> on_register() / on_unregister()
```

The Feishu implementation currently provides:

- webhook ingress at `/webhook/feishu`
- POST and GET handling
- URL verification challenge response
- Feishu text payload parsing from nested JSON string content
- sender/account resolution
- gateway callback through `MessageHandler`
- outbound text reply through `FeishuClient`

It does not currently provide:

- WebSocket mode
- richer security verification
- media/thread/action parity with the OpenClaw reference

## Current Reality vs Older Docs

These are the most important corrections relative to older drafts:

- gateway default port is `18789`, not `18123`
- gateway CLI supports `start`, `connect`, `agent`, `health`, `help`, `version`
- no built-in `gateway status` subcommand exists
- no built-in gateway detach/background flag exists
- gateway does implement channels, extensions, mailboxes, coordination, and pipelines
- pipeline template syntax is `${stage}.output`, not `$stage.output`
- Feishu is no longer reference-only; a webhook-based implementation exists
