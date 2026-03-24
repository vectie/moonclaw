# Custom DDS Robot Test Guide

This is a planning and integration-shape guide for a custom board + DDS robot.

It does not assume the full robot bridge exists yet.

## Goal

Prove the intended MoonClaw architecture:

- MoonClaw orchestrates
- robot bridge executes
- robot control stays out of generic chat shell execution

## 1. Install the example profile into a workspace

```bash
mkdir -p ~/.moonclaw/robot-workspace
cp /Users/kq/Workspace/moonclaw/docs/examples/neotix_e1_moonclaw.jobs.json ~/.moonclaw/robot-workspace/moonclaw.jobs.json
cp /Users/kq/Workspace/moonclaw/docs/examples/robot_dds_moonclaw.json ~/.moonclaw/moonclaw.json
```

## 2. Start the gateway

```bash
moon run cmd/main -- gateway start --home ~/.moonclaw --cwd ~/.moonclaw/robot-workspace
```

## 2.5. Optional: configure a local stub bridge

To test the runtime end to end before your real DDS bridge exists, use:

- [robot_dds_moonclaw.json](/Users/kq/Workspace/moonclaw/docs/examples/robot_dds_moonclaw.json)

This lets MoonClaw execute `robot.dds` steps immediately using the default
starter bridge config.

## 3. Trigger a robot-style request

Use Feishu, UI chat, or the gateway chat surface:

```text
/plan-job Ask the robot to wave at the operator.
```

Then confirm it:

```text
/confirm <proposal_id>
```

## 4. What this should prove today

Even before a real robot bridge backend exists, this should prove the shape:

- the proposal family becomes `robot.dds.action`
- the run is controller-shaped
- lane metadata groups steps into:
  - `Control`
  - `Robot`
  - `Operator`
- the robot-facing step carries:
  - `execution_mode: "robot.dds"`
  - `execution_target: "robot-main"`
  - explicit metadata like:
    - `robot_action`
    - `robot_params`
    - `robot_safety_class`

## 5. What is intentionally missing

Today this example does not imply a finished backend.

The branch still needs:

- a real DDS robot bridge service
- a board-side DDS runtime
- motion approval policy
- stop / status integration

## 6. Why this is useful

It locks in the intended architecture:

- MoonClaw remains the orchestrator
- robot execution is a specialist backend
- the workflow shape is still profile-driven and general
