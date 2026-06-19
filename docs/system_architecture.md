# MoonClaw System Architecture

This document describes the current implementation, not the earlier design drafts.

Expected behavior reference:

- [expected_behaviors/README.md](expected_behaviors/README.md)
- [executable_book_runtime_boundary.md](executable_book_runtime_boundary.md)

The executable-book boundary is: MoonClaw owns agent, task, session, and runtime primitives; MoonBook owns durable book truth; Moondesk projects MoonWiki and MoonCode surfaces; Moontown coordinates standing goals and book-to-book work. The executable-book coding API is `/v1/code/*`; generic `/v1/task*` routes remain separate for background jobs.

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

For operator-facing behavior and supported flows, see:

- [expected_behaviors/chat_and_job_flow.md](expected_behaviors/chat_and_job_flow.md)
- [expected_behaviors/workspace_and_memory.md](expected_behaviors/workspace_and_memory.md)
- [expected_behaviors/use_cases.md](expected_behaviors/use_cases.md)

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
| `jobs` | generic job definitions, runs, artifacts, workflows, and scheduler state |
| `job_cancel_requests` | cooperative cancel requests for active job runs |
| `job_force_stop_requests` | force-stop requests for active job runs |
| `channel_manager` | registered channel docks |
| `extension_registry` | webhook-capable channel extensions |
| `mailbox_manager` | agent-to-agent message mailboxes |
| `coordinator` | coordination tasks and subtask state |
| `pipeline_manager` | pipeline definitions and stage state |

`gateway/server/new.mbt` creates the gateway, loads persisted state, seeds missing channel state from `.moonclaw/moonclaw.json`, auto-registers built-in channel extensions, and restores enabled channel runtime.

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
Gateway::start()
  -> start HTTP/RPC/SSE surfaces
  -> restore_channel_runtime()
```

That means a restart now preserves direct-run conversation continuity, channel-triggered conversation continuity, channel config, and which channel accounts should auto-start again.
It also means a first gateway start can bootstrap built-in channels from the same `.moonclaw/moonclaw.json` file that the local CLI/model loader already uses.
Runtime restore is intentionally started from `Gateway::start()` as a background task.
That keeps dedicated gateway instances observable through `/health`, `/v1/channels`,
and RPC probes even when an external channel such as Feishu is slow to restore.
`gateway start` also passes the configured gateway auth token into the server when
one exists, so CLI probes and the launched service use the same credential source.
For Feishu websocket-mode accounts, restore now supports both:

- manual `websocket_url` override
- native endpoint resolution from `app_id` / `app_secret` via Feishu `/callback/ws/endpoint`

Weixin currently uses the simpler Official Account webhook model:

- `GET /webhook/weixin` for handshake verification
- `POST /webhook/weixin` for inbound plaintext text messages
- outbound replies through the Weixin custom-service API

## Gateway HTTP Surface

The route table lives in `gateway/server/request.mbt`.

### Basic service routes

- `GET /`
- `GET /health`
- `GET /v1/events`
- `GET /v1/runs`
- `GET /v1/runs/{id}`
- `GET /v1/jobs`
- `GET /v1/jobs/{id}`
- `POST /v1/jobs`
- `POST /v1/jobs/{id}/update`
- `POST /v1/jobs/{id}/run`
- `POST /v1/jobs/{id}/cancel`
- `POST /v1/jobs/{id}/force-cancel`
- `GET /v1/jobs/runs`
- `GET /v1/jobs/runs/{id}`
- `POST /v1/jobs/ask`
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

Current built-in channel ids:

- `feishu`
- `weixin`

### Mailbox routes

- `POST /v1/agent/message`
- `GET /v1/agent/{agent_id}/messages`
- `POST /v1/mailbox`
- `DELETE /v1/mailbox/{mailbox_id}`
- `GET /v1/mailboxes`

### Coordination Routes

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
      -> "jobs.*" / "jobs.runs.*" / "artifacts.*"
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

## Job and Controller Routing Notes

The current job runtime is now profile-driven and workspace-local:

- job profiles load from `<cwd>/moonclaw.jobs.json`
- global runtime config stays in `~/.moonclaw/moonclaw.json`

Important current routing capabilities:

- `job.analysis` can run locally or through ACP when a step carries:
  - `execution_mode`
  - `execution_target`
- `job.delegate` can also carry:
  - `child_profile`
  - `execution_mode`
  - `execution_target`

Controller-style runs also drive the operator canvas:

- split / merge anchors
- horizontal role lanes
- company health strip
- handoff and sequence summaries

The preferred board-shaping metadata is:

- `board_lane`
- `board_order`
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

## Job Execution Call Chain

The generic job system now runs under the gateway instead of being a passive store.

Detailed job/service boundaries are documented in [job_system_architecture.md](job_system_architecture.md).

### Manual trigger path

```text
CLI / RPC / HTTP
  -> RuntimeManager::trigger_definition(...)
  -> Gateway::launch_job_run(run_id)
  -> WorkflowEngine::execute_run(...)
  -> step handlers persist step state, outputs, and artifacts
  -> JobRuntime / ArtifactStore update run + artifact indexes
```

### Scheduled path

```text
Gateway tick loop
  -> RuntimeManager::trigger_due_definitions(now_ms)
  -> create pending due runs
  -> Gateway::launch_due_job_runs(...)
  -> WorkflowEngine::execute_run(...)
```

### Chat-initiated job path

```text
Feishu message
  -> FeishuChannel webhook/websocket ingress
  -> Gateway::handle_message(...)
    -> Gateway::handle_job_chat_command(...)
      -> job.parse_job_chat_action(...)
      -> job.dispatch_job_chat_action(...)
        -> "/plan-job" -> GatewayJobApp::plan_proposal(...)
        -> "/e2e" -> GatewayJobApp::plan_e2e_proposal(...)
        -> persist JobProposal
        -> reply with rendered draft plan
  -> user confirms or revises
    -> explicit slash command or reply-thread shortcut
    -> resolve proposal by id or proposal message id
    -> "/confirm" -> GatewayJobApp::confirm_proposal(...)
      -> compile proposal
      -> register definition/workflow
      -> save bindings
      -> RuntimeManager::trigger_definition(...)
      -> Gateway::launch_job_run(...)
    -> "/revise" -> GatewayJobApp::revise_draft_proposal(...)
```

Notification path for chat-originated jobs:

```text
execute_run_lifecycle(...)
  -> execution_notification_hooks(...)
    -> send start message

WorkflowEngine::log_run_event(...)
  -> SystemStore::append_run_event(...)
Gateway tick loop
  -> maybe_notify_active_jobs()
    -> read new run events
    -> send heartbeat / long-running warning
    -> in verbose mode send step progress messages
run finishes
  -> execution_notification_hooks(...)
    -> send final completion / failure / cancel message
```

### Current job module boundaries

```text
gateway/server
  -> HTTP/RPC/channel adapters
  -> reply message construction
  -> background run launch
  -> channel send integration

job/application.mbt
  -> proposal planning / confirm / revise / reject
  -> workflow engine assembly

job/chat_service.mbt
  -> chat parsing, dispatch, notification policy, reply formatting

job/query_service.mbt
  -> status/list rendering and target resolution

job/control_service.mbt
  -> stop/list/status command behavior

job/executor.mbt
  -> run lifecycle execution and start/finish hook wiring

job/runtime.mbt + job/system_storage.mbt
  -> persistent job definitions, runs, artifacts, proposals, bindings, events
```

## Research Job Family

`job/research.mbt` is the first concrete job family built on the generic job platform.

Implemented research step kinds:

- `research.topic.sync`
- `research.paper.fetch`
- `research.paper.parse`
- `research.paper.analyze`

Implemented research chat bindings:

- `research.topic.ask:<topic_id>`
- `research.paper.ask:<paper_id>`

Research call chain:

```text
job definition or workflow bundle
  -> gateway job runtime / workflow engine
    -> research.topic.sync
      -> ArxivClient.search(...)
      -> persist topic feed artifact
      -> persist paper metadata artifacts
      -> optionally download PDF artifacts
      -> create/update topic chat binding
    -> research.paper.fetch
      -> fetch one paper from arXiv
      -> persist paper metadata + PDF artifacts
      -> create/update paper chat binding
    -> research.paper.parse
      -> load paper metadata + PDF artifact
      -> PaperTextExtractor.extract(...)
      -> persist `research.paper.text`
      -> persist `research.paper.chunks`
    -> research.paper.analyze
      -> load paper metadata + parsed text artifacts
      -> AnalysisExecutor.run(...)
      -> persist analysis report + structured result artifacts
```

Research artifact types currently persisted include:

- `research.topic.feed`
- `research.paper.meta`
- `research.paper.pdf`
- `research.paper.text`
- `research.paper.chunks`
- `research.paper.analysis.summary.report`
- `research.paper.analysis.summary.result`

The default parse path uses `pdftotext` when it is available, and falls back to metadata-derived text when PDF text extraction is unavailable.

```text
POST /v1/jobs/{id}/run or RPC jobs.run
  -> Gateway::handle_run_job / handle_jobs_run_method
  -> Gateway::trigger_job_definition(job_id)
  -> RuntimeManager::trigger_definition(...)
  -> persist JobRun
  -> Gateway::launch_job_run(run_id)
  -> spawn background execute_job_run_async(...)
  -> WorkflowEngine::execute_run(...)
  -> registered step handlers run
  -> ArtifactStore persists outputs
  -> JobRun / JobStepRun state saved back to disk
```

### Scheduled path

```text
gateway tick
  -> Gateway::schedule_due_jobs()
  -> RuntimeManager::trigger_due_definitions(...)
  -> create due JobRun values
  -> Gateway::launch_job_run(run_id) for each due run
  -> WorkflowEngine::execute_run(...)
```

### Cancellation path

```text
POST /v1/jobs/{id}/cancel or RPC jobs.cancel
  -> Gateway::cancel_job_definition_run(job_id, force=false)
  -> pending run: mark cancelled immediately
  -> active run: set cooperative cancel flag
  -> WorkflowExecutionControl observes the flag and exits cleanly

POST /v1/jobs/{id}/force-cancel or RPC jobs.force_cancel
  -> Gateway::cancel_job_definition_run(job_id, force=true)
  -> active run sees force-stop flag through WorkflowExecutionControl
```

Current built-in step registration is intentionally narrow: the gateway workflow engine registers the generic analysis step handler by default. Additional job-family step kinds can be registered on top of the same runtime later without changing the gateway control plane.

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

Background delegated work also gets stable derived keys:

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
    -> terminal submit / ctrl-c / ctrl-d / ctrl-o callbacks
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

MoonClaw does not yet implement the full MoonClaw plugin runtime. The current extension model is smaller:

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
- media/thread/action parity with the older gateway reference

## Current Reality vs Older Docs

These are the most important corrections relative to older drafts:

- gateway default port is `18123`, not `18123`
- gateway CLI supports `start`, `connect`, `agent`, `health`, `help`, `version`
- no built-in `gateway status` subcommand exists
- no built-in gateway detach/background flag exists
- gateway does implement channels, extensions, mailboxes, coordination, and pipelines
- pipeline template syntax is `${stage}.output`, not `$stage.output`
- Feishu is no longer reference-only; a webhook-based implementation exists
