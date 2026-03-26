# MoonClaw Gateway Usage

This guide matches the current implementation in `cmd/gateway` and `gateway/server`.

Architecture reference:

- [system_architecture.md](system_architecture.md)
- [job_system_architecture.md](job_system_architecture.md)
- [expected_behaviors/README.md](expected_behaviors/README.md)

## What the Gateway Is

The gateway is a long-running HTTP/RPC service that:

- accepts agent execution requests
- persists lightweight session state by `session_key`
- exposes SSE for agent events
- exposes mailbox, coordination, and pipeline APIs
- hosts channel extensions such as Feishu and Weixin
- persists channel configuration and channel account runtime intent
- supports chat-initiated job planning and lifecycle notifications through channel integrations

Default address:

```text
http://localhost:18123
```

## CLI Commands

Implemented subcommands in `cmd/gateway/main.mbt`:

```bash
moonclaw gateway start [--port PORT] [--cwd DIR] [--home DIR]
moonclaw gateway connect [--url URL] [--token TOKEN]
moonclaw gateway agent --message "..." [--session KEY] [--cwd DIR] [--model NAME] [--wait] [--timeout MS]
moonclaw gateway runs [--url URL] [--token TOKEN]
moonclaw gateway run --id RUN_ID [--url URL] [--token TOKEN]
moonclaw gateway jobs [--url URL] [--token TOKEN]
moonclaw gateway job --id JOB_ID [--url URL] [--token TOKEN]
moonclaw gateway job-create --definition-json '{...}' [--url URL] [--token TOKEN]
moonclaw gateway job-update --definition-json '{...}' [--url URL] [--token TOKEN]
moonclaw gateway job-run --id JOB_ID [--url URL] [--token TOKEN]
moonclaw gateway job-cancel --id JOB_ID [--url URL] [--token TOKEN]
moonclaw gateway job-force-cancel --id JOB_ID [--url URL] [--token TOKEN]
moonclaw gateway job-runs [--url URL] [--token TOKEN]
moonclaw gateway job-run-status --run-id RUN_ID [--url URL] [--token TOKEN]
moonclaw gateway artifacts [--url URL] [--token TOKEN]
moonclaw gateway artifact --id ARTIFACT_ID [--url URL] [--token TOKEN]
moonclaw gateway job-ask --question "..." [--binding BINDING_ID] [--url URL] [--token TOKEN]
moonclaw gateway channels [--url URL] [--token TOKEN]
moonclaw gateway channel --id CHANNEL_ID [--url URL] [--token TOKEN]
moonclaw gateway channel-configure --id CHANNEL_ID --config-json '{...}' [--url URL] [--token TOKEN]
moonclaw gateway channel-start --id CHANNEL_ID --account ACCOUNT_ID --config-json '{...}' [--url URL] [--token TOKEN]
moonclaw gateway channel-stop --id CHANNEL_ID --account ACCOUNT_ID [--url URL] [--token TOKEN]
moonclaw gateway health [--url URL] [--token TOKEN]
moonclaw gateway help
moonclaw gateway version
```

There is no built-in `status` or `detach` subcommand today.

## Service Startup Call Chain

```text
moonclaw gateway start
  -> cmd/gateway/main.mbt::start_gateway
    -> Gateway::new(...)
      -> build http server
      -> create session/dedupe/mailbox/coordinator/pipeline managers
      -> load `gateway/sessions/sessions.json`
      -> load `gateway/channels.json`
      -> register built-in channel extensions
      -> restore enabled channel accounts
    -> Gateway::start()
      -> serve HTTP requests
      -> run tick loop
      -> listen for shutdown event
```

## Basic Usage

### Start the gateway

```bash
moonclaw gateway start
moonclaw gateway start --port 19000
moonclaw gateway start --cwd /path/to/project --home ~/.moonclaw
```

### Health check

```bash
moonclaw gateway health
```

### Connect using RPC handshake

```bash
moonclaw gateway connect
moonclaw gateway connect --url http://localhost:19000
```

### Submit an agent run

```bash
moonclaw gateway agent --message "Review this repository" --wait
moonclaw gateway agent --message "Continue" --session repo-review --wait
moonclaw gateway agent --message "Use a specific model" --model default --wait
```

### Inspect runs and channels

```bash
moonclaw gateway runs
moonclaw gateway run --id run-123
moonclaw gateway jobs
moonclaw gateway job --id nightly-research
moonclaw gateway job-runs
moonclaw gateway job-run-status --run-id run-123
moonclaw gateway artifacts
moonclaw gateway artifact --id artifact-123
moonclaw gateway job-ask --binding research-topic --question "What changed this week?"
moonclaw gateway channels
moonclaw gateway channel --id feishu
```

### Define and run jobs

```bash
moonclaw gateway job-create \
  --definition-json '{"id":"nightly-research","kind":"research.topic.sync","enabled":true,"schedule":{"interval_ms":3600000},"workflow_id":"research-sync"}'

moonclaw gateway job-update \
  --definition-json '{"id":"nightly-research","kind":"research.topic.sync","enabled":false,"schedule":{"interval_ms":3600000},"workflow_id":"research-sync"}'

moonclaw gateway job-run --id nightly-research
moonclaw gateway job-cancel --id nightly-research
moonclaw gateway job-force-cancel --id nightly-research
```

### Profile-driven job runtime

The current job runtime is generic and profile-driven.

The main extension boundary is:

- `<cwd>/moonclaw.jobs.json`

Current important step kinds:

- `job.analysis`
- `job.delegate`

Current important routing controls:

- `execution_mode`
- `execution_target`
- `child_profile`

That means:

- analysis steps can run locally or through ACP
- delegated workers can select a named child profile
- delegated workers can also carry ACP routing intent

For concrete current examples, see:

- [docs/examples/research_job_test_guide.md](/Users/kq/Workspace/moonclaw/docs/examples/research_job_test_guide.md)
- [docs/examples/opc_job_test_guide.md](/Users/kq/Workspace/moonclaw/docs/examples/opc_job_test_guide.md)
- [docs/moonclaw_jobs_json.md](/Users/kq/Workspace/moonclaw/docs/moonclaw_jobs_json.md)

### Feishu chat job flow

When Feishu is configured, jobs can now be drafted and controlled from chat without executing immediately.

Commands:

```text
/plan-job <description>
/e2e <description>
/confirm <proposal_id>
/reject <proposal_id>
/revise <proposal_id> <extra guidance>
/job-status <job_id>
/job-notify <off|normal|verbose>
```

Reply-thread shortcuts:

- reply `confirm` to a proposal message
- reply `reject` to a proposal message
- reply `revise <extra guidance>` to a proposal message

Behavior:

- `/plan-job` creates a classic persisted draft proposal and replies with the step plan
- `/e2e` creates an end-to-end draft proposal with job-level preprocess and optional postprocess stages
- proposals are not executed until confirmed
- `/job-notify` changes notification verbosity for the current chat/thread scope
- `verbose` mode sends step progress messages derived from workflow run events
- long-running jobs send a warning without interrupting execution
- if a run pauses in `WaitingForInput`, the status reply tells you to either:
  - reply in that Feishu thread with `/resume` followed by the missing text
  - optionally attach files to that same `/resume` reply
- `/resume` resumes the same run in place from the blocked step; it does not create a fresh run
- operator guidance like `/resume guess missing data` is treated as permission to continue with clearly labeled assumptions when a usable screening result is still possible
- after `/resume`, Feishu should move on to fresh step progress updates rather than repeating a stale `WaitingForInput` snapshot
- normal non-reply chat still falls through to the usual MoonClaw conversation
  path
- normal channel chat uses the configured primary model from `~/.moonclaw/moonclaw.json`; stale bare session model ids are normalized instead of overriding that config

Current message flow:

```text
Feishu message
  -> gateway job chat adapter
  -> job chat parser + dispatcher
  -> GatewayJobApp classic planning or E2E planning / confirm / revise / reject
  -> runtime launch if confirmed
  -> execution notifications routed back to the same chat/thread
```

### Operator flow for jobs

```text
define or update a job
  -> create/update stored definition
  -> gateway scheduler sees enabled definitions on tick
  -> RuntimeManager::trigger_due_definitions(...) creates a run when due
  -> Gateway::launch_job_run(...) executes the workflow in background
  -> workflow steps persist step state and artifacts
  -> inspect run/artifact state through RPC, HTTP, or CLI
  -> ask grounded questions over produced artifacts with jobs.ask / job-ask
```

Scheduled jobs are not metadata-only. Once a due run is created, the gateway immediately launches it in the background.

### Configure and control channel runtime

```bash
moonclaw gateway channel-configure \
  --id feishu \
  --config-json '{"enabled":true,"accounts":{"default":{"app_id":"...","app_secret":"...","domain":"feishu","connection_mode":"webhook","dm_policy":"pairing","enabled":true}},"global_settings":{}}'

moonclaw gateway channel-start \
  --id feishu \
  --account default \
  --config-json '{"app_id":"...","app_secret":"...","domain":"feishu","connection_mode":"webhook","dm_policy":"pairing","enabled":true}'

moonclaw gateway channel-stop --id feishu --account default
```

For websocket-mode Feishu accounts, use `connection_mode = "websocket"`. The gateway now resolves the upstream Feishu websocket endpoint from `app_id` / `app_secret` automatically. `websocket_url` is optional and acts as a manual override. Optional handshake headers can be supplied with `websocket_headers`.

Weixin currently uses webhook mode only, not websocket mode.

Its callback path is:

```text
/webhook/weixin
```

and the current implementation expects plaintext Official Account callbacks.

```bash
moonclaw gateway channel-configure \
  --id feishu \
  --config-json '{"enabled":true,"accounts":{"monitor":{"app_id":"...","app_secret":"...","domain":"feishu","connection_mode":"websocket","dm_policy":"pairing","enabled":true}},"global_settings":{}}'
```

If you need to force a specific websocket endpoint during testing or proxying, add:

```json
{
  "websocket_url": "wss://example.invalid/feishu/ws",
  "websocket_headers": {
    "Authorization": "Bearer ..."
  }
}
```

### Bootstrap from `.moonclaw/moonclaw.json`

At startup, the gateway also checks:

- `{cwd}/.moonclaw/moonclaw.json`
- then `{home}/.moonclaw/moonclaw.json`

It understands the OpenClaw-style Feishu config shape under `channels.feishu`, for example:

```json
{
  "channels": {
    "feishu": {
      "enabled": true,
      "appId": "cli_app",
      "appSecret": "cli_secret",
      "domain": "feishu",
      "dmPolicy": "open",
      "groupPolicy": "open",
      "allowFrom": ["*"]
    }
  }
}
```

That shape is normalized into the internal gateway channel state:

- `appId` -> `app_id`
- `appSecret` -> `app_secret`
- `dmPolicy` -> `dm_policy`
- `groupPolicy` -> `global_settings.group_policy`
- `allowFrom` -> `global_settings.allow_from`

When `channels.feishu.connectionMode` is `"websocket"`, the gateway can start the long-lived Feishu connection from `appId` and `appSecret` alone. A `websocketUrl` entry is optional and only overrides the resolved endpoint.

If no explicit `accounts` map is present, the gateway seeds a `default` Feishu account automatically. Existing `home/gateway/channels.json` state still wins over this bootstrap seed.

## HTTP and RPC Surfaces

### Direct HTTP endpoints

| Endpoint | Method | Meaning |
|---|---|---|
| `/` | `GET` | service info |
| `/health` | `GET` | health payload |
| `/v1/events` | `GET` | SSE event stream |
| `/v1/runs` | `GET` | list runs |
| `/v1/runs/{id}` | `GET` | get run payload |
| `/v1/jobs` | `GET` | list job definitions |
| `/v1/jobs/{id}` | `GET` | get one job definition |
| `/v1/jobs` | `POST` | create a job definition |
| `/v1/jobs/{id}/update` | `POST` | update a job definition |
| `/v1/jobs/{id}/run` | `POST` | trigger a job now |
| `/v1/jobs/{id}/cancel` | `POST` | request cooperative cancel |
| `/v1/jobs/{id}/force-cancel` | `POST` | request force-stop |
| `/v1/jobs/runs` | `GET` | list job runs |
| `/v1/jobs/runs/{id}` | `GET` | inspect one job run with steps and artifacts |
| `/v1/jobs/ask` | `POST` | ask a grounded question over bound artifacts |
| `/v1/agent` | `POST` | accept an agent request |
| `/v1/rpc` | `POST` | JSON-RPC entrypoint |
| `/v1/shutdown` | `POST` | graceful shutdown |

### Channel and extension endpoints

| Endpoint | Method | Meaning |
|---|---|---|
| `/v1/channels` | `GET` | list registered channels |
| `/v1/channels/{id}` | `GET` | get one channel |
| `/v1/channels/{id}/configure` | `POST` | configure one channel |
| `/v1/channels/{id}/start` | `POST` | start one channel account |
| `/v1/channels/{id}/stop` | `POST` | stop one channel account |
| `/v1/extensions` | `GET` | list registered extensions |
| `/v1/extensions/{id}` | `GET` | get one extension |
| `/webhook/{channel_id}/...` | `GET/POST` | extension webhook ingress |

### Mailbox and orchestration endpoints

| Endpoint | Method | Meaning |
|---|---|---|
| `/v1/agent/message` | `POST` | send mailbox message |
| `/v1/agent/{agent_id}/messages` | `GET` | poll mailbox |
| `/v1/mailbox` | `POST` | create mailbox |
| `/v1/mailbox/{id}` | `DELETE` | delete mailbox |
| `/v1/mailboxes` | `GET` | list mailboxes |
| `/v1/coordination...` | mixed | coordination lifecycle |
| `/v1/pipeline...` | mixed | pipeline lifecycle |

### RPC methods

Handled by `gateway/server/rpc.mbt` and `gateway/server/methods.mbt`.

Implemented methods:

- `connect`
- `agent`
- `agent.wait`
- `sessions.list`
- `sessions.reset`
- `config.get`
- `config.set`
- `health`
- `runs.list`
- `runs.get`
- `jobs.list`
- `jobs.get`
- `jobs.create`
- `jobs.update`
- `jobs.run`
- `jobs.cancel`
- `jobs.force_cancel`
- `jobs.runs.list`
- `jobs.runs.get`
- `jobs.ask`
- `artifacts.list`
- `artifacts.get`
- `channels.list`
- `channels.get`
- `channels.configure`
- `channels.start`
- `channels.stop`

## Agent Request Flow

### CLI path

```text
moonclaw gateway agent --message ...
  -> gateway/client/Client::connect()
  -> POST /v1/rpc method=connect
  -> gateway/client/Client::agent(...)
  -> POST /v1/rpc method=agent
  -> optional gateway/client/Client::wait_agent(...)
  -> POST /v1/rpc method=agent.wait
```

### Server path

```text
agent method or POST /v1/agent
  -> parse AgentParams
  -> assign run_id
  -> check dedupe cache
  -> return accepted response
  -> background execute_agent_async(...)
  -> execute_agent(...)
    -> resolve session/model/cwd
    -> create or resume conversation
    -> attach event listener
    -> run agent
    -> store final payload and dedupe entry
```

Final payload fields:

```json
{
  "run_id": "...",
  "status": "completed",
  "session_key": "...",
  "model": "...",
  "content": "...",
  "conversation_id": "...",
  "completed_at": 0
}
```

## Session Model

The gateway keeps lightweight persisted session entries in `home/gateway/sessions/sessions.json`:

- `session_id`
- `updated_at`
- `channel`
- `model_override`
- `provider_override`
- `cwd`

For direct agent usage, `session_key` is supplied by the caller.

For channel-triggered usage, the gateway derives a session key from channel/account/chat/thread.

Current routing helpers:

- direct runs: `direct_session_key(session_key?, run_id)`
- channel messages: `message_session_key(channel_id, account_id, message)`
- coordination subtasks: `coordination_session_key(coordination_id, task_id)`
- pipeline stages: `pipeline_stage_session_key(pipeline_id, stage_name)`

Direct write-back flow:

```text
agent request
  -> resolve direct session key
  -> sessions.get_or_create(...)
  -> execute agent
  -> save_entry(...conversation_id/model/cwd...)
```

Channel write-back flow:

```text
webhook message
  -> derive channel session key
  -> lookup prior SessionEntry
  -> resume or create Moonclaw conversation
  -> execute agent
  -> save_entry(...conversation_id/channel/cwd...)
```

## Channel Runtime Persistence

Channel config and runtime intent are stored in `home/gateway/channels.json`.

Persisted data includes:

- channel config
- account-specific runtime config
- whether that account should auto-start after restart

Restore flow:

```text
Gateway::new
  -> channel_state.load()
  -> seed missing channel state from `.moonclaw/moonclaw.json`
  -> register extensions/channels
  -> restore_channel_runtime()
    -> configure all persisted channels
    -> start only accounts with auto_start=true
```

Operational consequence:

- `channel-start` makes that account restart with the gateway
- `channel-stop` keeps the config but disables auto-start for that account
- removing an account from channel config prunes its persisted runtime entry

## SSE Event Flow

`GET /v1/events` opens an `EventStreamWriter` and listens to `agent_events`.

Current event stream purpose:

- broadcast agent lifecycle data to external observers
- expose serialized agent events as they occur during a run

## Mailbox Flow

Mailbox support is a simple in-memory message layer for agent-to-agent coordination:

```text
POST /v1/mailbox
  -> create mailbox for agent_id

POST /v1/agent/message
  -> build AgentMessage
  -> deliver to target mailbox or broadcast to all other mailboxes

GET /v1/agent/{id}/messages
  -> non-blocking single-message poll
```

This is not durable and should be treated as process-local state.

## Coordination Flow

### Create

```bash
curl -X POST http://localhost:18123/v1/coordination \
  -H "Content-Type: application/json" \
  -d '{
    "parent_agent": "coord-1",
    "subtasks": [
      {"task_id": "a", "message": "inspect file a"},
      {"task_id": "b", "message": "inspect file b"}
    ]
  }'
```

### Start

```bash
curl -X POST http://localhost:18123/v1/coordination/<id>/start
```

Server flow:

```text
start
  -> Coordinator::start_task
  -> spawn_bg(no_wait=true, run_coordination)
  -> each pending subtask executes via execute_agent
  -> subtask completion/failure updates parent task
  -> parent finalizes when all subtasks are done
```

Important behavior:

- `429 coordination_limit_reached` when `max_concurrent` is exhausted
- `404 subtask_not_found` for invalid subtask updates
- late async writes are blocked if the task is no longer runnable

## Pipeline Flow

### Create

```bash
curl -X POST http://localhost:18123/v1/pipeline \
  -H "Content-Type: application/json" \
  -d '{
    "name": "code-review",
    "stages": [
      {"name": "read", "message": "read repository"},
      {"name": "analyze", "message": "analyze repository", "input_template": "${read}.output"},
      {"name": "report", "message": "write report", "input_template": "${analyze}.output"}
    ]
  }'
```

### Start

```bash
curl -X POST http://localhost:18123/v1/pipeline/<id>/start
```

Server flow:

```text
start
  -> PipelineManager::start_pipeline
  -> mark first stage Running
  -> spawn_bg(no_wait=true, run_pipeline)
  -> resolve input_template using prior results
  -> execute current stage
  -> advance to next stage or fail pipeline
```

Important behavior:

- template syntax is `${stage}.output`
- manual `advance` / `fail` validate current stage and return `409` on mismatch
- next stage becomes `Running` automatically on advance
- late async writes are blocked if the pipeline is no longer runnable

## Feishu Integration

The gateway auto-registers the Feishu extension at construction time.

Ingress flow:

```text
POST /webhook/feishu
  -> ExtensionRegistry::handle_webhook
  -> FeishuChannel::handle_webhook
  -> FeishuChannel::handle_feishu_message
  -> Gateway::handle_message (MessageHandler impl)
  -> Moonclaw run
  -> FeishuChannel::send reply
```

Current Feishu support is webhook-based text messaging. It is not yet a full OpenClaw-compatible channel runtime.

## Known Gaps

- many gateway package warnings remain, though the core package compiles and targeted orchestration tests pass
- no built-in daemon-style background supervisor features exist in `cmd/gateway`
- mailbox/orchestration state is in-memory only
