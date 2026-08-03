# Custom Board DDS Robot Integration Plan

This document defines the recommended MoonClaw architecture for integrating a
custom humanoid or mobile robot where you own:

- the controller board
- the board transport
- the DDS layer
- the high-level task runtime

The previous Noetix E1 SDK direction is now treated as one possible bridge
backend shape, not the primary architecture.

## Summary

MoonClaw should not directly control your robot by issuing low-level board or
DDS commands as ordinary chat-driven shell commands.

MoonClaw should orchestrate a dedicated robot bridge service.

The robot bridge service should own:

- DDS client lifecycle
- board transport session management
- robot state subscription
- high-level task execution
- stop / emergency semantics
- robot-local safety policy

MoonClaw should own:

- chat and Feishu interaction
- approvals
- planning and intent interpretation
- job tracking
- operator-visible progress and results

## Why This Architecture

Even when the board and DDS are your own, the system boundary should stay the
same:

- MoonClaw is not a real-time controller
- timing-sensitive loops belong on the robot-side stack
- low-level control should not be directly driven by an LLM conversation
- MoonClaw should supervise typed tasks, not stream raw joint commands

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

### 2. Robot Bridge Service

The robot bridge service runs on your onboard computer or companion computer and
handles:

- DDS init and config
- board protocol init
- robot status subscription
- high-level motion commands
- robot mode tracking
- stop / safe fallback
- robot-local guardrails

This service should expose a typed API to MoonClaw instead of exposing raw DDS,
raw sockets, or raw shell calls.

### 3. Your Robot

The robot executes through your own control stack:

- high-level mode control
- motion controller
- sensor and motor state publication

## Control Levels

Your stack should expose two very different control levels.

### High-level task control

Use this first.

Characteristics:

- behavior-level commands
- robot-local controller remains in charge
- suitable for fast application development
- appropriate for orchestration from MoonClaw

Recommended first capabilities:

- `enable`
- `disable`
- `stand`
- `walk`
- `turn`
- `go_home`
- `wave`
- `stop`

### Low-level control

Do not make this the first MoonClaw integration target.

Characteristics:

- joint-level or board-level control
- timing-sensitive closed-loop control
- suitable for motion-control engineering
- should remain inside robotics specialists and robot-local code

For MoonClaw, low-level control should be treated as:

- out of scope for normal chat-triggered execution
- allowed only behind explicit engineering workflows and stronger approvals

## First Product Goal

The first target should be:

```text
Feishu/UI -> MoonClaw -> robot bridge -> high-level action -> progress -> result
```

Not:

```text
Feishu/UI -> MoonClaw -> raw DDS command -> robot
```

## Typed Robot Bridge API

Recommended API surface:

- `robot.get_capabilities`
- `robot.get_state`
- `robot.enter_mode`
- `robot.stop`
- `robot.run_action`
- `robot.walk`
- `robot.turn`
- `robot.go_home`

Recommended first action set:

- `enable`
- `disable`
- `walk`
- `turn`
- `wave`
- `go_home`
- `stop`

Example request shape:

```json
{
  "robot_id": "robot-main",
  "action": "walk",
  "params": {
    "x": 0.2,
    "yaw": 0.0,
    "duration_ms": 3000
  }
}
```

MoonClaw should pass this through profile step metadata rather than relying on
natural-language prompt inference alone.

Recommended dispatch metadata keys:

- `robot_action`
- `robot_params`
- `robot_safety_class`

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

## DDS Design Guidance

Design your DDS surface so MoonClaw only touches high-level tasks.

Recommended DDS topics/services:

- low-level:
  - `robot/joint_command`
  - `robot/joint_state`
  - `robot/base_cmd`
  - `robot/mode_cmd`
  - `robot/fault_state`
- high-level:
  - `robot/task_request`
  - `robot/task_status`
  - `robot/action_feedback`

MoonClaw should integrate through the high-level side only.

## MoonClaw Job Model

MoonClaw should represent robot actions as specialist worker jobs.

Recommended profile families:

- `robot.dds.system_check`
- `robot.dds.action`
- `robot.dds.session_supervision`

Recommended execution pattern:

- analysis/controller step in MoonClaw interprets user intent
- dispatch step includes explicit `robot_action` metadata when possible
- delegate or external-worker step calls the robot bridge
- bridge executes and streams status
- MoonClaw reports back to Feishu/UI

## Safety Model

This must be stricter than generic command approval.

Required safety categories:

- `inspect_only`
  read state, capabilities, logs
- `high_level_motion`
  robot motion through the bridge
- `low_level_engineering`
  board-level or joint-level control

Default policy recommendation:

- allow `inspect_only`
- require approval for `high_level_motion`
- disallow `low_level_engineering` from chat-driven workflows unless the
  operator explicitly enters an engineering mode

## Operator UX

MoonClaw should surface:

- current robot mode
- active robot task
- stop button / cancel action
- safe summaries such as:
  - `Planning`
  - `Walking`
  - `Turning`
  - `Going home`
  - `Stopped`
  - `Approval required`

It should not expose low-level control details in normal chat flows.

## Bridge Implementation Guidance

The bridge should:

- own the board transport
- own DDS init and teardown
- own heartbeat and stop logic
- translate MoonClaw JSON requests into DDS requests
- translate DDS status into concise MoonClaw status updates

MoonClaw should not run your DDS binaries directly each time.

Preferred bridge implementation options:

- a local CLI bridge process first
- later an HTTP or daemon-based bridge for live supervision

## What The SDK In `../sdk` Changes

The SDK found in `/Users/kq/Workspace/sdk` confirms an important integration
detail:

- `build_release.sh` builds demo executables like `highcontrol`
- `highcontroller.cpp` and `lowcontroller.cpp` are example controller loops
- the demos do not expose a stable stdin/stdout task API
- `highcontroller.cpp` sets `CYCLONEDDS_URI` internally from `config/dds.xml`
- `highcontroller.cpp` publishes control actions like:
  - `WALK`
  - `SWING`
  - `SHAKE`
  - `CHEER`
  - `PLAYTEACH`
  - `RUN`

That means the right path is:

- do not shell-wrap `highcontrol` directly from MoonClaw
- build a small board-side adapter around the SDK
- let that adapter implement a stable MoonClaw bridge protocol

In other words, the SDK is useful as a control library/example base, not as the
final MoonClaw worker protocol.

## What MoonClaw Already Supports

The current `neotix` branch now supports:

- `execution_mode: "robot.dds"`
- `execution_target: "<target-id>"`
- bridge command resolution from `moonclaw.json`
- JSON stdin/stdout bridge requests for `job.analysis`
- compatibility alias `execution_mode: "robot.e1"` for the earlier branch work

## First Milestone

First milestone:

1. build a CLI bridge around your board + DDS runtime
2. support `wave`, `walk`, `turn`, `go_home`, and `stop`
3. route one MoonClaw job step through that bridge
4. return structured success/failure and a short summary

Only after that should you add:

- long-running live supervision
- richer robot state streaming
- manipulation tasks like pickup or handover
