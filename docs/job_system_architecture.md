# Job Architecture

This document describes the current job architecture after the gateway-thinning refactor.

Operator behavior and use-case reference:

- [expected_behaviors/README.md](expected_behaviors/README.md)

The important boundary is:

- `gateway/server` is transport and runtime wiring
- `job` owns job planning, compilation, execution, storage, notification policy, and chat command behavior

## High-Level Shape

```text
Feishu / CLI / HTTP / RPC
  -> gateway/server adapters
    -> job application + services
      -> proposal planning
      -> proposal compilation
      -> workflow runtime
      -> artifact store
      -> query/control services
    -> channel send adapter
```

## Main Job Modules

### `job/application.mbt`

`GatewayJobApp` is the main application facade used by the gateway.

It owns:

- proposal planning
- draft revision
- proposal confirmation
- proposal rejection
- workflow engine construction
- access to the shared job runtime/state

Gateway-facing methods:

- `plan_proposal(...)`
- `revise_draft_proposal(...)`
- `confirm_proposal(...)`
- `reject_proposal(...)`
- `new_workflow_engine()`

### `job/proposal.mbt`

Owns proposal lifecycle and proposal rendering:

- `draft_job_proposal(...)`
- `plan_job_proposal(...)`
- `revise_job_proposal(...)`
- `ensure_draft_proposal(...)`
- `save_confirmed_job_proposal(...)`
- `save_rejected_job_proposal(...)`
- `render_job_proposal_for_chat(...)`

This is the layer that guarantees chat-created jobs stay in `Draft` until explicit confirmation.

### `job/compiler.mbt`

Owns proposal-to-workflow compilation.

Current responsibilities:

- infer family and template
- infer required capabilities
- choose specialized vs delegated vs generic templates
- compile `JobDefinition`, `WorkflowDefinition`, and `ChatBinding`s

Current families/templates include:

- `research.topic_watch`
- `research.topic_review`
- delegated research variants
- `generic.analysis`
- `generic.tool_workflow`
- delegated generic variants

### `job/runtime.mbt`

Owns persistent runtime execution state:

- definitions
- workflows
- runs
- retries
- due scheduling
- active-run tracking

This is the low-level runtime manager. It does not know about Feishu or gateway transport.

### `job/executor.mbt`

Owns run lifecycle execution:

- validate definition/workflow presence
- run workflow engine
- mark failures on thrown execution errors
- emit start/finish notifications through hook wiring

Gateway no longer constructs lifecycle hooks itself; it calls `execution_notification_hooks(...)`.

### `job/chat_service.mbt`

Owns chat-specific policy and rendering:

- slash/reply command parsing
- command dispatch
- proposal/message correlation
- notification preference persistence
- progress notification decisions
- reply/help/error formatting

### `job/query_service.mbt`

Owns read-side query logic:

- current step resolution
- child-run lookup
- status rendering
- active-run rendering
- job-or-run target resolution

### `job/control_service.mbt`

Owns command-side control policy:

- `/jobs` rendering
- `/job-status` reply shaping
- `/job-stop` and `/job-force-stop` target resolution and reply shaping

### `job/system_storage.mbt`

Owns durable on-disk storage:

- definitions
- workflows
- runs
- step runs
- artifacts
- chat bindings
- notification preferences
- job proposals
- run event logs

## Gateway Boundary

`gateway/server` still owns these responsibilities:

- receive HTTP/RPC/channel messages
- create reply `Message` values
- send channel messages/notifications
- schedule background launch of job runs
- provide cancel/force-stop callbacks
- host the HTTP/RPC route table

It no longer owns most job policy.

The current split is:

```text
gateway/server/job_chat.mbt
  -> parse inbound channel message
  -> call job services / application methods
  -> wrap returned text as channel reply

gateway/server/job_runtime.mbt
  -> launch background run
  -> provide cancel/force-stop closures
  -> provide channel-send/log callbacks
  -> call job executor
```

## Message Flow

### 1. Feishu message to job proposal

```text
Feishu webhook / websocket event
  -> channel_message_handler.mbt
  -> Gateway::handle_job_chat_command(...)
  -> job.parse_job_chat_action(...)
  -> job.dispatch_job_chat_action(...)
  -> GatewayJobApp::plan_proposal(...)
  -> proposal planner
  -> persisted JobProposal
  -> render_job_proposal_for_chat(...)
  -> channel reply back to Feishu
```

Effects:

- proposal is saved in `job_proposals.json`
- presented proposal message id is saved for reply-thread correlation
- no workflow is executed yet

### 2. Proposal confirmation to running workflow

```text
Feishu `/confirm <proposal_id>` or reply `confirm`
  -> Gateway::handle_confirm_job_command(...)
  -> job.resolve_target_proposal(...)
  -> GatewayJobApp::confirm_proposal(...)
    -> ensure_draft_proposal(...)
    -> compile_proposal(...)
    -> runtime.register_definition(...)
    -> runtime.register_workflow(...)
    -> save chat bindings
    -> launch callback -> gateway trigger_job_definition(...)
    -> save_confirmed_job_proposal(...)
  -> render_confirmed_job_reply(...)
  -> channel reply back to Feishu
```

Effects:

- draft becomes `Confirmed`
- `JobDefinition` and `WorkflowDefinition` become durable runtime state
- a `JobRun` is created and launched

### 3. Job run execution

```text
Gateway::launch_job_run(run_id)
  -> Gateway::execute_job_run_async(run_id)
  -> job.execute_run_lifecycle(...)
    -> engine factory from GatewayJobApp::new_workflow_engine()
    -> step handlers execute
    -> step runs and artifacts persist
    -> run events append to events.jsonl
    -> run finishes with Succeeded / Failed / Cancelled
```

Current workflow engine handlers include:

- `job.analysis`
- `job.delegate`
- `research.topic.sync`
- `research.paper.fetch`
- `research.paper.parse`
- `research.paper.analyze`

### 4. Notifications during execution

```text
execute_run_lifecycle(...)
  -> execution_notification_hooks(...)
    -> "Job started"
    -> notification runtime state initialized

Gateway tick
  -> maybe_notify_active_jobs(...)
  -> job.decide_active_job_notifications(...)
  -> heartbeat / verbose progress / long-running warning
  -> send_job_notification(...)

run finishes
  -> execution_notification_hooks(...)
    -> final status message
    -> notification runtime state cleared
```

Long-running behavior:

- jobs are not interrupted automatically
- the user receives a status warning
- the user may decide to send stop/force-stop later

### 5. Status and control messages

```text
Feishu `/job-status <job_id|run_id>`
  -> job.render_job_status_command_reply(...)
  -> render_status_text(...)
  -> reply

Feishu `/jobs`
  -> job.render_jobs_command_reply(...)
  -> render_active_runs(...)
  -> reply

Feishu `/job-stop <job_id|run_id>`
  -> job.request_job_stop(...)
  -> gateway cancel callback
  -> reply
```

## Reply-Thread Flow

Proposal messages are correlated by persisted presented message id.

That allows:

- reply `confirm`
- reply `reject`
- reply `revise <guidance>`

without repeating the proposal id in chat.

Flow:

```text
proposal reply message
  -> incoming message has reply_to
  -> job.resolve_target_proposal(store, "", reply_to)
  -> proposal recovered from stored presented_message_id
  -> command proceeds normally
```

## Why This Architecture Exists

The earlier implementation pushed too much job behavior into `gateway/server`.

The current architecture keeps one process but separates responsibilities:

- `gateway` handles transport and background task launch
- `job` handles application behavior and policy

This keeps:

- Feishu/chat support inside the main gateway service
- job semantics reusable from CLI/RPC/HTTP
- future job families implementable without adding more gateway-specific logic

## Current Remaining Boundary

The gateway is now close to the intended boundary. The remaining gateway-specific code is mostly:

- channel message creation
- channel message sending
- HTTP/RPC route plumbing
- background run spawning

That is the intended adapter surface.
