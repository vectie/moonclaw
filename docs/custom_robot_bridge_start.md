# Custom Robot Bridge Start Guide

This is the fastest path to connect MoonClaw to your own board + DDS stack.

## What MoonClaw Already Supports

MoonClaw now supports:

- `execution_mode: "robot.dds"`
- `execution_target: "<target-id>"`
- bridge targets configured in `moonclaw.json`
- one-shot JSON stdin/stdout bridge execution

That means you do not need to teach MoonClaw DDS directly.

You only need to provide a bridge program.

## Starter Bridge

Use:

- [scripts/robot_dds_bridge.py](/Users/kq/Workspace/moonclaw/scripts/robot_dds_bridge.py)
- [docs/examples/robot_dds_moonclaw.json](/Users/kq/Workspace/moonclaw/docs/examples/robot_dds_moonclaw.json)
- [docs/examples/robot_bridge_examples.md](/Users/kq/Workspace/moonclaw/docs/examples/robot_bridge_examples.md)

It already:

- reads the MoonClaw JSON request
- prefers explicit robot metadata and falls back to prompt inference
- loads bridge config from env
- returns a valid JSON response
- runs in stub mode by default
- defaults to `MOONCLAW_ROBOT_DRY_RUN=true`

The most important metadata keys are:

- `robot_action`
- `robot_params`
- `robot_safety_class`

The most important target env controls are:

- `MOONCLAW_ROBOT_DRY_RUN`
- `MOONCLAW_ROBOT_ALLOW_MOTION`
- `ROBOT_ALLOWED_ACTIONS`

## How To Test Immediately

Add this to your `moonclaw.json`:

```json
{
  "robots": {
    "targets": {
      "robot-main": {
        "command": "python3",
        "args": ["/Users/kq/Workspace/moonclaw/scripts/robot_dds_bridge.py"]
      }
    }
  }
}
```

Then trigger a job that uses:

- `execution_mode: "robot.dds"`
- `execution_target: "robot-main"`

## How To Replace The Stub

Open:

- [scripts/robot_dds_bridge.py](/Users/kq/Workspace/moonclaw/scripts/robot_dds_bridge.py)

Replace or extend:

- `DDSRuntime`
- `BoardTransport`
- `CustomDDSBackend.execute(...)`

The bridge now already supports command hooks, so you do not have to edit the
Python code first if your board runtime is exposed through small helper
commands.

Supported env hook points:

- `ROBOT_BOARD_CONNECT_COMMAND`
- `ROBOT_BOARD_SAFE_MODE_COMMAND`
- `ROBOT_DDS_CONNECT_COMMAND`
- `ROBOT_DDS_PUBLISH_COMMAND`
- `ROBOT_DDS_WAIT_COMMAND`

See:

- [scripts/robot_hook_example.py](/Users/kq/Workspace/moonclaw/scripts/robot_hook_example.py)

Recommended structure:

1. parse request
2. map explicit `robot_action` metadata to an action
3. only fall back to prompt inference when metadata is absent
4. initialize board transport
5. initialize DDS/domain participant
6. validate robot safe mode
7. publish a high-level task request
8. wait for success/failure
9. return concise JSON

## Recommended First Actions

Implement these first:

- `wave`
- `stand`
- `walk`
- `turn`
- `go_home`
- `stop`

Do not start with pickup/manipulation.

## How To Switch From Stub To Your Real Backend

The starter script supports:

- stub backend by default
- custom backend when:

```bash
MOONCLAW_ROBOT_BACKEND=custom
```

So your target config can later become:

```json
{
  "robots": {
    "targets": {
      "robot-main": {
        "command": "python3",
        "args": ["/Users/kq/Workspace/moonclaw/scripts/robot_dds_bridge.py"],
        "env": {
          "MOONCLAW_ROBOT_BACKEND": "custom",
          "MOONCLAW_ROBOT_DRY_RUN": "true",
          "ROBOT_DDS_DOMAIN": "17",
          "ROBOT_DDS_TASK_TOPIC": "robot/task_request",
          "ROBOT_DDS_STATUS_TOPIC": "robot/task_status",
          "ROBOT_BOARD_URI": "board://main-controller"
        }
      }
    }
  }
}
```

Start with `MOONCLAW_ROBOT_DRY_RUN=true`.

When your board and DDS runtime are ready, remove that flag.

For real hardware, keep:

- `MOONCLAW_ROBOT_ALLOW_MOTION=false`

until you intentionally want that target to move.

## Recommended Profile Metadata

In `moonclaw.jobs.json`, prefer explicit dispatch metadata like:

```json
{
  "execution_mode": "robot.dds",
  "execution_target": "robot-main",
  "robot_action": "wave",
  "robot_params": {
    "arm": "right"
  },
  "robot_safety_class": "high_level_motion"
}
```

That is much more stable than expecting the bridge to infer the intended action
from natural language every time.

## Where The SDK In `../sdk` Fits

If you want to borrow from the Noetix SDK in
[/Users/kq/Workspace/sdk](/Users/kq/Workspace/sdk):

- treat it as a reference for a board-side adapter
- do not point MoonClaw directly at `highcontrol`
- instead, adapt the SDK inside `CustomDDSBackend` or a separate bridge process

That keeps MoonClaw general and your board runtime replaceable.
