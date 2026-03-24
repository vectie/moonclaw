# Noetix E1 Integration Plan

This document defines the recommended MoonClaw architecture for integrating the
Noetix E1 humanoid robot based on the vendor SDK guide in
[E1+SDK开发指南.docx](/Users/kq/Downloads/E1+SDK开发指南.docx).

## Summary

MoonClaw should not directly control E1 by running the vendor DDS demo
executables as ordinary chat-driven shell commands.

MoonClaw should orchestrate a dedicated E1 bridge service.

The E1 bridge service should own:

- DDS client lifecycle
- mode switching
- robot state subscription
- high-level action execution
- stop / emergency semantics
- robot-local safety policy

MoonClaw should own:

- chat and Feishu interaction
- approvals
- planning and intent interpretation
- job tracking
- operator-visible progress and results

## Why This Architecture

The SDK guide makes several things clear:

- the SDK is C/S based and uses DDS with CycloneDDS
- the user-facing development board is the Jetson Orin Nano Super
- the robot motion-control board is not user-facing
- there are two control paths:
  - `highcontrol`
  - `lowcontrol`
- `lowcontrol` is a 500Hz closed-loop path for per-motor control
- emergency stop is mapped to the remote `+` button
- disconnecting the DDS client causes the robot to revert to the prior mode
- the guide explicitly warns against interacting with the motion-control board
  while the motion controller is active

These are strong signals that MoonClaw should not be the real-time controller.

## Recommended System Split

### 1. MoonClaw

MoonClaw handles:

- user command intake from Feishu/UI/chat
- intent parsing
- clarification when needed
- approval before hardware action
- task dispatch
- task supervision
- progress reporting
- history, logs, and artifacts

### 2. E1 Bridge Service

The E1 bridge service runs on the E1 Jetson board and handles:

- DDS init and config
- `publishModeData(...)`
- robot status subscription
- high-level motion commands
- robot mode tracking
- stop / safe fallback
- robot-local guardrails

This service should expose a typed API to MoonClaw instead of exposing raw DDS
or raw shell calls.

### 3. E1 Robot

The robot executes through the vendor stack:

- high-level mode control
- motion controller
- sensor and motor state publication

## Control Levels

The SDK guide exposes two very different control levels.

### `highcontrol`

Use this first.

Characteristics:

- behavior-level commands
- vendor locomotion remains in charge
- suitable for fast application development
- appropriate for orchestration from MoonClaw

Example capabilities mentioned or implied by the guide:

- walk
- run
- swing / wave
- shake
- cheer
- prepare
- teach / play recorded action

### `lowcontrol`

Do not make this the first MoonClaw integration target.

Characteristics:

- user sends per-motor `pos/vel/tau/kp/kd`
- 500Hz closed-loop control
- suitable for motion-control engineering
- should remain inside robotics specialists and robot-local code

For MoonClaw, `lowcontrol` should be treated as:

- out of scope for normal chat-triggered execution
- allowed only behind explicit engineering workflows and stronger approvals

## First Product Goal

The first target should be:

```text
Feishu/UI -> MoonClaw -> E1 bridge -> highcontrol action -> progress -> result
```

Not:

```text
Feishu/UI -> MoonClaw -> raw DDS executable -> robot
```

## Typed E1 Bridge API

Recommended API surface:

- `robot.get_capabilities`
- `robot.get_state`
- `robot.enter_mode`
- `robot.stop`
- `robot.run_action`
- `robot.walk`
- `robot.play_teach_slot`

Recommended first action set:

- `enable`
- `disable`
- `prepare`
- `walk`
- `run`
- `wave`
- `shake`
- `cheer`
- `play_teach_slot`

Example request shape:

```json
{
  "robot_id": "e1-main",
  "action": "walk",
  "params": {
    "x": 0.2,
    "yaw": 0.0,
    "duration_ms": 3000
  }
}
```

Example status shape:

```json
{
  "task_id": "robot-task-123",
  "status": "running",
  "mode": "walk",
  "summary": "Walking forward",
  "updated_at": 1710000000000
}
```

## MoonClaw Job Model

MoonClaw should represent E1 actions as specialist worker jobs.

Recommended profile families:

- `robot.e1.system_check`
- `robot.e1.highcontrol_action`
- `robot.e1.session_supervision`

Recommended execution pattern:

- analysis/controller step in MoonClaw interprets user intent
- delegate or external-worker step calls the E1 bridge
- bridge executes and streams status
- MoonClaw reports back to Feishu/UI

## Safety Model

This must be stricter than generic command approval.

Required safety categories:

- `inspect_only`
  read state, capabilities, logs
- `highcontrol_motion`
  vendor high-level robot motion
- `lowcontrol_engineering`
  500Hz joint-level control

Default policy recommendation:

- allow `inspect_only`
- require approval for `highcontrol_motion`
- disallow `lowcontrol_engineering` from chat-driven workflows unless the
  operator explicitly enters an engineering mode

## Operator UX

MoonClaw should surface:

- current robot mode
- active robot task
- stop button / cancel action
- safe summary such as:
  - `Preparing`
  - `Walking`
  - `Playing teach action`
  - `Stopped`
  - `Approval required`

It should not expose raw joint-level control details in normal chat flows.

## Bridge Implementation Guidance

The bridge should run on the Jetson board at the user-facing IP shown in the
guide:

- `192.168.55.101`

It should manage the DDS config pointing to the motion-control board:

- `192.168.55.102`

The bridge should embed or wrap the vendor examples rather than asking MoonClaw
to run `sudo ./highcontrol` directly each time.

Preferred bridge implementation options:

1. native service wrapping the SDK in C++ with HTTP/gRPC
2. local daemon supervising `highcontrol` and exposing a typed RPC layer

Avoid:

- direct chat-triggered shell execution of the DDS demo binaries
- exposing the motion-control board to MoonClaw

## First Milestone

Milestone 1 should prove:

- MoonClaw can query E1 bridge capabilities and state
- MoonClaw can ask for approval before motion
- MoonClaw can trigger a safe `highcontrol` action like `wave` or `cheer`
- MoonClaw can show progress and final result in Feishu/UI

## Non-Goals For The First Milestone

- natural-language end-to-end tasking like `pick up water and give it to me`
- perception-driven object fetching
- whole-body manipulation planning
- `lowcontrol` orchestration from MoonClaw

Those should come later, after the bridge and safety model are proven.
