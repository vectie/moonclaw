# Noetix E1 Test Guide

This is a planning and integration-shape guide for the E1 branch.

It does not assume the full E1 bridge exists yet.

## Goal

Prove the intended MoonClaw architecture:

- MoonClaw orchestrates
- E1 bridge executes
- robot control stays out of generic chat shell execution

## 1. Install the example profile into a workspace

```bash
mkdir -p ~/.moonclaw/e1-workspace
cp /Users/kq/Workspace/moonclaw/docs/examples/neotix_e1_moonclaw.jobs.json ~/.moonclaw/e1-workspace/moonclaw.jobs.json
```

## 2. Start the gateway

```bash
moon run cmd/main -- gateway start --home ~/.moonclaw --cwd ~/.moonclaw/e1-workspace
```

## 3. Trigger a robot-style request

Use Feishu, UI chat, or the gateway chat surface:

```text
/plan-job Ask the E1 robot to wave at the operator.
```

Then confirm it:

```text
/confirm <proposal_id>
```

## 4. What this should prove today

Even before a real E1 bridge backend exists, this should prove the shape:

- the proposal family becomes `robot.e1.highcontrol_action`
- the run is controller-shaped
- lane metadata groups steps into:
  - `Control`
  - `Robot`
  - `Operator`
- the robot-facing step carries:
  - `execution_mode: "robot.e1"`
  - `execution_target: "e1-main"`

## 5. What is intentionally missing

Today this example does not imply a finished backend.

The branch still needs:

- a real E1 bridge service
- a MoonClaw backend for `execution_mode: "robot.e1"`
- motion approval policy
- stop / status integration

## 6. Why this is useful

It locks in the intended architecture:

- MoonClaw remains the orchestrator
- robot execution is a specialist backend
- the workflow shape is still profile-driven and general
