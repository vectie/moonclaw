# Role Substrate

MoonClaw now supports a reusable role substrate for planner-style and
executor-style agents.

This is intentionally generic. It does not define Mayor, Lead, or Worker
product policy. It defines the runtime envelope those roles can run inside.

## Core Types

MoonClaw job runtime now includes:

- `RoleRuntimeContract`
- `RoleHandoffPacket`

These live in:

- [/Users/kq/Workspace/moonclaw/job/role_runtime.mbt](/Users/kq/Workspace/moonclaw/job/role_runtime.mbt)

## What `RoleRuntimeContract` Controls

- `role_id`
- `planning_layer`
  - `Strategic`
  - `Domain`
  - `Execution`
- `runtime_mode`
  - `PlannerOnly`
  - `Executor`
- `tool_access`
  - `Disabled`
  - `Limited`
  - `Full`
- `memory_scope`
  - `Step`
  - `Workspace`
  - `Domain`
  - `Global`
- `allow_delegate`
- `allow_workspace_write`
- `allow_execution_tools`
- `output_contract`

## Default Runtime Envelopes

Current defaults are:

- `role: "controller"`
  - domain planner
  - planner-only
  - limited tools
  - no workspace writes
  - no execution tools
  - delegation allowed
- `role: "lead"`
  - domain planner
  - planner-only
  - limited tools
  - no workspace writes
  - no execution tools
  - delegation allowed
- `role: "mayor"`
  - strategic planner
  - planner-only
  - limited tools
  - no workspace writes
  - no execution tools
  - delegation allowed
- all other roles
  - execution layer
  - executor mode
  - full tools
  - workspace writes allowed

These are generic runtime defaults, not product policy.

## How Profiles Override The Envelope

Profiles can add:

```json
{
  "metadata": {
    "role_runtime": {
      "planning_layer": "domain",
      "runtime_mode": "planner_only",
      "tool_access": "limited",
      "memory_scope": "domain",
      "allow_delegate": true,
      "allow_workspace_write": false,
      "allow_execution_tools": false,
      "output_contract": "lead.plan.packet.v1"
    }
  }
}
```

Step metadata can also carry `role_runtime`, and step metadata overrides profile
metadata.

## Current Runtime Use

The current runtime uses the resolved role contract to:

- attach role contract metadata to `AnalysisRequest`
- constrain tool exposure before tools are added to the agent
- persist role contract metadata into analysis execution metadata

This means planner-style roles are now mechanically constrained by runtime, not
only by prompt wording.

## What MoonClaw Core Owns

MoonClaw core owns:

- role envelope types
- resolution logic
- runtime tool gating
- typed handoff packet shape

Host systems should own:

- Mayor policy
- Lead policy
- domain-specific routing
- persistence/review semantics
- scheduling heuristics

So the split remains:

- MoonClaw: role substrate
- host workspace/app: role-specific brains
