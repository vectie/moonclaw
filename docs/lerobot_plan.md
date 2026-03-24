# LeRobot Integration Plan

This document describes the recommended architecture for turning MoonClaw into
an orchestration layer for embodied robotics work, using LeRobot as the
specialist execution stack.

## Goal

Enable a user flow like:

```text
@lerobot pick up water and give it to me
```

without collapsing MoonClaw into a robot runtime.

The goal is not to make MoonClaw directly own robot control internals.
The goal is to make MoonClaw orchestrate a robotics worker cleanly.

## Core Position

MoonClaw should remain:

- the chat and operator surface
- the planner
- the approval gate
- the long-running job tracker
- the multi-agent orchestrator
- the artifact and status hub

LeRobot should remain:

- the robot capability stack
- the policy execution stack
- the hardware interface layer
- the perception and retry loop owner

## Recommended Architecture

### 1. MoonClaw as orchestrator

MoonClaw handles:

- user intent from Feishu/UI/chat
- clarification and decomposition
- risk approval for hardware actions
- dispatch to specialist workers
- progress reporting
- final operator-facing results

### 2. LeRobot service as embodiment worker

LeRobot should be wrapped as a long-running worker service or agent that owns:

- robot capability discovery
- world-state access
- task execution
- recovery and retry logic
- robot-local safety checks
- device/resource ownership

This service should expose a typed task interface instead of expecting MoonClaw
to shell out blindly.

### 3. Structured bridge

The boundary should use structured task APIs such as:

- `robot.list_capabilities`
- `robot.get_state`
- `robot.run_skill`
- `robot.stop`
- `robot.get_task_status`

This is better than:

- raw shell commands
- direct prompt-only delegation
- embedding robot control policy in generic analysis steps

## Why Not Make MoonClaw the Robot Runtime

That would overfit the core runtime to one embodied domain.

Problems with that approach:

- hardware safety policy becomes entangled with generic command execution
- robot retry logic gets mixed into generic controller logic
- world state and device ownership become awkward to model as normal job steps
- testing becomes harder because robot-specific assumptions leak into core

## What Already Works

MoonClaw can already orchestrate LeRobot-adjacent batch work well:

- `lerobot-info`
- `lerobot-train`
- `lerobot-eval`
- repo-defined automation targets like the LeRobot `Makefile` E2E tests

This fits MoonClaw's current strengths:

- long-running jobs
- artifact collection
- ACP routing
- notifications
- operator UI

## What Does Not Yet Work Well

The current system is not yet enough for:

- `lerobot-teleoperate`
- `lerobot-record`
- real-time robot skill execution from chat

Those need:

- long-lived process/session supervision
- device/resource locking
- live progress streaming
- robot-local safety semantics
- structured action status instead of raw command output

## Rollout Plan

### Phase 1: Generic execution boundary

Refactor MoonClaw so external execution backends are a generic seam instead of
an ACP-only special case.

Target outcome:

- analysis and delegated worker steps can route through a generic external
  execution mode
- ACP remains the first backend
- robotics can later plug in as another backend

### Phase 2: LeRobot extension pack

Add a workspace pack for LeRobot operations:

- `lerobot_system_check`
- `lerobot_train_run`
- `lerobot_eval_run`
- `lerobot_bug_investigation`
- `lerobot_record_session`

These should live in:

- `moonclaw.jobs.json`
- `skills/lerobot-*/SKILL.md`

### Phase 3: LeRobot specialist service

Build a service or worker process around LeRobot with a task API.

Initial safe skills:

- `move_home`
- `wave`
- `look_for_object`
- `pick_object`
- `place_object`

Later composite skills:

- `fetch_object`
- `handover_to_user`

### Phase 4: MoonClaw robotics orchestration

Add MoonClaw job/controller flows that:

- parse user intent
- check whether a robotics worker can perform it
- request approval for physical motion
- dispatch the structured robot task
- stream status back to the user

### Phase 5: Live operations and safety

Add robotics-specific controls:

- explicit hardware approval mode
- stop/pause controls
- device reservation
- sim-only vs hardware mode
- emergency interruption path

## First Concrete Implementation Slice

The first code slice in MoonClaw should be generic:

- add a generic external execution routing seam in the gateway/job runtime
- keep ACP as the first implementation
- make room for a future robotics backend without changing job/profile shapes again

This keeps the system general while making robotics a natural extension.

## What Will Come Next After This Slice

After the generic execution seam exists, the next recommended implementation is:

1. a LeRobot extension pack for training/eval/system-check jobs
2. a robotics worker backend contract
3. a first safe specialist backend for non-hardware or sim-only robot tasks

## Decision Summary

Use MoonClaw to orchestrate robotics work.

Do not use MoonClaw as the robot control runtime itself.

Make robotics a specialist execution backend plus workspace-local extension pack.
