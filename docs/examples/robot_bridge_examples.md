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
- the starter bridge defaults to `MOONCLAW_ROBOT_DRY_RUN=true`
- keep `MOONCLAW_ROBOT_ALLOW_MOTION=false` until you intentionally enable hardware motion
- use `ROBOT_ALLOWED_ACTIONS` to narrow what a target may do
- hook commands can be pointed at one example script:
  - [robot_hook_example.py](/Users/kq/Workspace/moonclaw/scripts/robot_hook_example.py)

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

## Example Safety Gate

The starter bridge now enforces a simple robot-side policy:

- `MOONCLAW_ROBOT_DRY_RUN=true`
  motion actions are accepted but treated as dry-run
- `MOONCLAW_ROBOT_DRY_RUN=false` and `MOONCLAW_ROBOT_ALLOW_MOTION=false`
  high-level motion actions fail fast
- `ROBOT_ALLOWED_ACTIONS`
  constrains which actions the target may execute at all

Example safe target env:

```json
{
  "MOONCLAW_ROBOT_BACKEND": "custom",
  "MOONCLAW_ROBOT_DRY_RUN": "false",
  "MOONCLAW_ROBOT_ALLOW_MOTION": "false",
  "ROBOT_ALLOWED_ACTIONS": "inspect,stop"
}
```

Example motion-enabled target env:

```json
{
  "MOONCLAW_ROBOT_BACKEND": "custom",
  "MOONCLAW_ROBOT_DRY_RUN": "false",
  "MOONCLAW_ROBOT_ALLOW_MOTION": "true",
  "ROBOT_ALLOWED_ACTIONS": "inspect,stand,wave,walk,turn,go_home,stop"
}
```

## Example Hook Wiring

The starter bridge can now call your board and DDS runtime through command
hooks.

These env vars are supported:

- `ROBOT_BOARD_CONNECT_COMMAND`
- `ROBOT_BOARD_SAFE_MODE_COMMAND`
- `ROBOT_DDS_CONNECT_COMMAND`
- `ROBOT_DDS_PUBLISH_COMMAND`
- `ROBOT_DDS_WAIT_COMMAND`

For a working local example, point them all at:

- [robot_hook_example.py](/Users/kq/Workspace/moonclaw/scripts/robot_hook_example.py)

That script reads JSON from stdin and returns simple JSON results, so you can
exercise the full bridge path before wiring your real board runtime.

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
