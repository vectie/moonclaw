# Multi-Agent Collaboration in MoonClaw Gateway

This document describes what is implemented today in `gateway/server`, and what the current boundaries are.

## Implemented Building Blocks

### 1. Mailboxes

Files:

- `gateway/server/mailbox.mbt`
- `gateway/server/message.mbt`
- `gateway/server/message_handler.mbt`

Implemented behavior:

- create mailbox per `agent_id`
- send directed message to one mailbox
- broadcast message to all mailboxes except the sender
- poll one pending message non-blockingly

This is the current communication substrate between agents.

### 2. Coordination Tasks

Files:

- `gateway/server/coordination.mbt`
- `gateway/server/coordinator.mbt`
- `gateway/server/coordination_handler.mbt`
- `gateway/server/orchestration_runner.mbt`

Implemented behavior:

- create a parent coordination task with multiple subtasks
- start the coordination asynchronously
- run each pending subtask via `execute_agent(...)`
- collect subtask results into `results`
- finalize parent coordination as `Completed` or `Failed`

### 3. Pipelines

Files:

- `gateway/server/pipeline.mbt`
- `gateway/server/pipeline_manager.mbt`
- `gateway/server/pipeline_handler.mbt`
- `gateway/server/orchestration_runner.mbt`

Implemented behavior:

- create named sequential stages
- start pipeline asynchronously
- mark the first stage `Running`
- substitute `${stage}.output` placeholders from prior results
- execute each stage via `execute_agent(...)`
- auto-advance to the next stage
- fail the pipeline on stage failure

## Data Flow

## Mailbox message flow

```text
client / orchestrator
  -> POST /v1/mailbox
    -> mailbox_manager.create(agent_id)

sender
  -> POST /v1/agent/message
    -> Gateway::handle_agent_message
      -> build AgentMessage
      -> mailbox_manager.deliver_sync

receiver
  -> GET /v1/agent/{agent_id}/messages
    -> mailbox.try_get()
```

Notes:

- the mailbox is process-local only
- there is no persistence, ack, retry, or replay
- `GET /messages` returns at most one message per call today

## Coordination execution flow

```text
POST /v1/coordination
  -> create CoordinationTask
  -> subtasks start as Pending

POST /v1/coordination/{id}/start
  -> Coordinator::start_task
  -> parent status becomes Running
  -> spawn_bg(no_wait=true, run_coordination)

Gateway::run_coordination
  -> get_pending_subtasks
  -> per subtask:
     -> verify task is still runnable
     -> update_subtask_status(..., Running)
     -> execute_agent(...)
     -> if still runnable:
        -> update_subtask_status(..., Completed/Failed)

Coordinator::update_subtask_status
  -> update one subtask
  -> refresh result map
  -> if all subtasks done:
     -> finalize parent as Completed or Failed
```

### Coordination status semantics

`CoordinationStatus` values:

- `Pending`
- `Running`
- `Completed`
- `Failed`
- `Cancelled`

Current rules:

- `pending_count()` counts only `Pending`
- starting may return `429 coordination_limit_reached`
- invalid subtask update returns `404 subtask_not_found`
- late background completions do not overwrite a cancelled/stale task

## Pipeline execution flow

```text
POST /v1/pipeline
  -> create Pipeline
  -> all stages start as Pending

POST /v1/pipeline/{id}/start
  -> PipelineManager::start_pipeline
  -> stage 0 becomes Running
  -> spawn_bg(no_wait=true, run_pipeline)

Gateway::run_pipeline
  -> fetch current stage
  -> verify pipeline is still runnable
  -> resolve_input(prev_results)
  -> build AgentParams
  -> execute_agent(...)
  -> if success and still current:
       advance_stage(...)
     else if failure and still current:
       fail_stage(...)
```

### Pipeline status semantics

`PipelineStatus` values:

- `Pending`
- `Running`
- `Completed`
- `Failed`
- `Cancelled`

Current rules:

- `Pipeline::start()` marks current stage `Running`
- `advance_stage()` completes the current stage and starts the next stage
- last successful stage completes the pipeline
- invalid manual `advance` / `fail` returns `409 invalid_stage_transition`
- late background completions do not overwrite cancelled/stale pipeline state

## API Reference

### Mailboxes

```text
POST   /v1/mailbox
DELETE /v1/mailbox/{mailbox_id}
GET    /v1/mailboxes
POST   /v1/agent/message
GET    /v1/agent/{agent_id}/messages
```

### Coordination

```text
POST /v1/coordination
GET  /v1/coordination
GET  /v1/coordination/{id}
POST /v1/coordination/{id}/start
POST /v1/coordination/{id}/cancel
POST /v1/coordination/{id}/subtask/{task_id}
GET  /v1/coordination/{id}/results
```

### Pipeline

```text
POST /v1/pipeline
GET  /v1/pipeline
GET  /v1/pipeline/{id}
POST /v1/pipeline/{id}/start
POST /v1/pipeline/{id}/cancel
POST /v1/pipeline/{id}/advance
POST /v1/pipeline/{id}/fail
GET  /v1/pipeline/{id}/next
```

## Call Chain Details

### Shared execution primitive

Both coordination subtasks and pipeline stages converge on the same internal path:

```text
orchestrator
  -> Gateway::execute_agent(run_id, AgentParams)
    -> SessionManager::get_or_create
    -> @model.load(...)
    -> @agent.new(...)
    -> attach event listener
    -> agent.start()
    -> produce Json result payload
```

That means:

- all orchestration uses the same model loading rules as direct gateway agent runs
- all orchestration stores the same result shape with `content` and `conversation_id`
- orchestration is not a separate runtime; it is a thin scheduler around normal agent execution

## Tested Behavior

Whitebox tests in `gateway/server/orchestration_wbtest.mbt` currently cover:

- coordination completion after all subtasks succeed
- coordination failure after one subtask fails
- pipeline template substitution
- pipeline stage advancement and final completion

## Current Gaps

Not implemented yet:

- durable mailbox storage
- blocking mailbox wait / streaming mailbox API
- parent/child agent identity graph
- priority queues
- partial retry policy for failed subtasks/stages
- external scheduler / lane system
- rich orchestration event stream beyond the existing gateway agent events
