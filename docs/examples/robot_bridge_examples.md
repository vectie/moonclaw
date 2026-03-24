# Robot Bridge Examples

These examples show the current structured contract for a custom board + DDS
robot bridge.

## Example `moonclaw.json`

Use:

- [robot_dds_moonclaw.json](/Users/kq/Workspace/moonclaw/docs/examples/robot_dds_moonclaw.json)

Key points:

- target id: `robot-main`
- execution mode: `robot.dds`
- bridge command: `scripts/robot_dds_bridge.py`
- default to `MOONCLAW_ROBOT_DRY_RUN=true` first

## Example `moonclaw.jobs.json`

Use:

- [neotix_e1_moonclaw.jobs.json](/Users/kq/Workspace/moonclaw/docs/examples/neotix_e1_moonclaw.jobs.json)

Even though the filename still mentions `e1`, the content now represents the
generic custom-board DDS pattern.

## Example Bridge Request

MoonClaw sends one JSON request on stdin:

```json
{
  "kind": "job.analysis",
  "job_id": "job.robot",
  "run_id": "run.robot",
  "step_id": "dispatch_robot_action",
  "prompt": "Ask the robot to wave.",
  "execution_mode": "robot.dds",
  "execution_target": "robot-main",
  "metadata": {
    "robot_action": "wave",
    "robot_params": {
      "arm": "right"
    },
    "robot_safety_class": "high_level_motion"
  }
}
```

## Example Bridge Response

Your bridge should return JSON like:

```json
{
  "status": "completed",
  "content": "Robot waved at the operator.",
  "metadata": {
    "task_id": "task-123",
    "action": "wave",
    "params": {
      "arm": "right"
    },
    "safety_class": "high_level_motion",
    "robot_id": "robot-main",
    "summary": "Waving at the operator."
  }
}
```

## Example Actions

The starter bridge currently recognizes and validates:

- `inspect`
- `stand`
- `wave`
- `walk`
- `turn`
- `go_home`
- `stop`

## Example Feishu Prompts

Good first prompts:

- `@robot wave`
- `@robot stand`
- `@robot walk forward a little`
- `@robot turn left`
- `@robot go home`
- `@robot stop`

Better than prompt-only routing:

- use profile metadata to force the exact robot action
- let the prompt remain user-facing and natural
