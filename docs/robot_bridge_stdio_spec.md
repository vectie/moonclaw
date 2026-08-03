# Robot Bridge Stdio Spec

This document defines the minimal stdin/stdout bridge protocol for MoonClaw to
talk to a custom DDS robot bridge.

MoonClaw already supports this style through `execution_mode: "robot.dds"`.

## Why Stdio First

The SDK in `/Users/kq/Workspace/sdk` currently provides demo executables and C++
control loops, not a stable external task API.

A stdio bridge is the smallest useful adapter:

- MoonClaw launches one command
- sends one JSON request on stdin
- reads one JSON response on stdout
- treats the bridge as the specialist worker

This is enough to:

- validate the MoonClaw integration boundary
- test job routing and approvals
- keep DDS and board logic outside MoonClaw

## Request Shape

MoonClaw sends JSON like:

```json
{
  "kind": "job.analysis",
  "job_id": "job.robot",
  "run_id": "run.robot",
  "step_id": "dispatch_robot_action",
  "prompt": "Ask the robot to wave at the operator.",
  "system_prompt": "Use the robot bridge.",
  "model_name": "default",
  "cwd": "/path/to/workspace",
  "home": "/path/to/home",
  "execution_mode": "robot.dds",
  "execution_target": "robot-main",
  "preferred_skills": [],
  "enable_tools": false,
  "web_search": false,
  "metadata": {
    "robot_action": "wave",
    "robot_params": {
      "arm": "right"
    },
    "robot_safety_class": "high_level_motion"
  }
}
```

The `metadata` object is the stable contract for structured robot dispatch.

Recommended fields:

- `robot_action`
- `robot_params`
- `robot_safety_class`

## Response Shape

The bridge should return JSON like:

```json
{
  "status": "completed",
  "content": "Robot waved at the operator.",
  "metadata": {
    "action": "wave",
    "robot_id": "robot-main"
  }
}
```

## Failure Shape

Return:

```json
{
  "status": "failed",
  "error": "Bridge could not connect to DDS domain 17"
}
```

MoonClaw treats a nonzero exit code or a JSON `status: "failed"` as a failed
step.

## Recommended Bridge Responsibilities

The board-side bridge should:

- parse the MoonClaw JSON request
- prefer explicit `metadata.robot_action` over prompt inference
- initialize DDS and board transport
- execute a high-level task
- return a concise result

The bridge should not:

- expose raw joint commands to MoonClaw
- expect the LLM to drive timing-sensitive loops
- rely on terminal-interactive flows

## Suggested Action Vocabulary

Start with:

- `wave`
- `walk`
- `turn`
- `go_home`
- `stop`

Later add:

- `look_for_object`
- `pick_object`
- `handover_object`

## Suggested Next Adapter For `../sdk`

For the SDK in `/Users/kq/Workspace/sdk`, the next real adapter should be a new
C++ or Python bridge executable that:

1. accepts stdin JSON
2. maps actions onto SDK high-level commands
3. initializes DDS with the correct config
4. returns stdout JSON

Do not point MoonClaw straight at `highcontrol` until such an adapter exists.
