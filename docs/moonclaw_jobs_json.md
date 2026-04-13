# `moonclaw.jobs.json` Reference

This document is the canonical reference for workspace-local job profile
configuration.

MoonClaw loads job profiles only from:

- `<cwd>/moonclaw.jobs.json`

This file is intentionally separate from global runtime config in:

- `~/.moonclaw/moonclaw.json`

## Purpose

`moonclaw.jobs.json` defines workspace-local workflow policy:

- which prompts match which profile
- what family a proposal should use
- whether a proposal behaves like a normal job or a controller job
- what steps it should run
- what skills, routing hints, and board metadata each step carries

It is the main extension boundary for packs like research, wiki maintenance,
and OPC.

## Top-Level Shape

```json
{
  "jobs": {
    "profiles": {
      "profile_id": {
        "...": "..."
      }
    }
  }
}
```

## Profile Fields

Each entry under `jobs.profiles` can contain:

- `family`
  job family name stamped onto the proposal
- `role`
  usually `default` or `controller`
- `priority`
  higher priority wins when multiple profiles match
- `tags`
  optional descriptive tags
- `match`
  profile selection rules
- `steps`
  the explicit step list to use
- `metadata`
  arbitrary profile-level metadata

Example:

```json
{
  "jobs": {
    "profiles": {
      "opc_feature_sprint": {
        "family": "opc_feature_sprint",
        "role": "controller",
        "priority": 90,
        "tags": ["opc", "controller"],
        "match": {
          "any": ["feature", "sprint", "ship", "dashboard"]
        },
        "steps": [],
        "metadata": {
          "controller_policy": {
            "acceptance_source": "step_output"
          }
        }
      }
    }
  }
}
```

## Match Rules

Current match controls:

- `match.any`
  profile matches if any term appears
- `match.all`
  profile matches only if all terms appear

Terms are simple text fragments, not a full query language.

When multiple profiles match:

- higher `priority` wins

## Step Fields

Each step should include:

- `id`
- `title`
- `kind`

Current common `kind` values:

- `job.analysis`
- `job.delegate`

Optional common step fields:

- `prompt_template`
- `metadata`
- optional `metadata.role_runtime`

Example:

```json
{
  "id": "eng_plan",
  "title": "Engineering plan",
  "kind": "job.analysis",
  "metadata": {
    "preferred_skills": ["opc-eng"]
  }
}
```

## Analysis Step Metadata

`job.analysis` steps can currently carry metadata such as:

- `preferred_skills`
- `system_prompt`
- `enable_tools`
- `web_search`
- `model`
- `execution_mode`
- `execution_target`
- `board_lane`
- `board_order`
- `role_runtime`

Important current routing behavior:

- if `execution_mode: "acp"` and `execution_target` are present, the gateway can
  route that analysis step through ACP instead of the local model path
- if `execution_mode: "provider"` or `execution_mode: "extension"` and
  `execution_target` point at a registered task provider, MoonClaw can:
  - ask the provider for a task batch
  - hydrate worker context for the selected task
  - run the task through the normal analysis runtime
  - persist the structured result back through the provider

Example:

```json
{
  "id": "scope",
  "title": "Scope the feature",
  "kind": "job.analysis",
  "metadata": {
    "preferred_skills": ["opc-ceo"],
    "execution_mode": "acp",
    "execution_target": "codex-main",
    "board_lane": "CEO",
    "board_order": 0
  }
}
```

Example provider-backed routing:

```json
{
  "id": "book_update",
  "title": "Update the local knowledge base",
  "kind": "job.analysis",
  "metadata": {
    "preferred_skills": ["wiki-maintainer"],
    "execution_mode": "provider",
    "execution_target": "wiki-main",
    "board_lane": "Wiki",
    "board_order": 1
  }
}
```

The `execution_target` is resolved through `.moonclaw/providers.json`. A task
provider should expose:

- `kind: "extension"` or `kind: "task-provider"`
- `kind: "moonbook"` or `kind: "book-harness"`
- capability `provider`, `extension`, `provider.task`, or `extension.task`
- compatibility aliases `bookapi` or `moonbook.bookapi` are also accepted
- metadata fields:
  - `command`
  - `args`
  - `workspace_root`
  - optional `cwd`

Example provider manifest entry:

```json
[
  {
    "name": "wiki-main",
    "title": "Primary Wiki",
    "description": "Domain-local wiki harness",
    "kind": "extension",
    "capabilities": ["provider.task"],
    "metadata": {
      "command": "moon",
      "args": ["run", "cmd/main", "--"],
      "workspace_root": "/absolute/path/to/book-workspace"
    }
  }
]
```

### `role_runtime`

Profiles or steps can define a reusable role envelope in metadata:

```json
{
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
```

Supported values:

- `planning_layer`
  - `strategic`
  - `domain`
  - `execution`
- `runtime_mode`
  - `planner_only`
  - `executor`
- `tool_access`
  - `none`
  - `limited`
  - `full`
- `memory_scope`
  - `step`
  - `workspace`
  - `domain`
  - `global`

Step-level `metadata.role_runtime` overrides profile-level
`metadata.role_runtime`.

## Delegate Step Fields

`job.delegate` steps can currently carry:

- `child_profile`
- `execution_mode`
- `execution_target`
- `include_parent_outputs`
- `max_depth`
- `metadata`

Example:

```json
{
  "id": "review",
  "title": "Peer review",
  "kind": "job.delegate",
  "child_profile": "opc_review_worker",
  "execution_mode": "acp",
  "execution_target": "codex-review",
  "metadata": {
    "board_lane": "Review",
    "board_order": 3
  }
}
```

## Controller Metadata

Controller-shaped profiles usually use:

- `role: "controller"`

and may include:

- `metadata.controller_policy`
- `metadata.role_runtime`

The runtime keeps controller behavior generic. The profile provides the policy
shape; the runtime persists controller state, iterations, lineage, and
decisions.

## Board Metadata

The Rabbita company board prefers explicit metadata on steps:

- `board_lane`
- `board_order`

This is the current recommended way to make the board predictable. If these
fields are missing, the UI falls back to heuristics.

## Fallback Behavior

If no matching profile is found and no valid model-generated plan is available:

- the generic fallback proposal is a single minimal `execute` step

So explicit profiles are the right place for structured workflow shape.

## Recommended Layout

Typical workspace layout:

```text
workspace/
  moonclaw.jobs.json
  skills/
    my-pack/
      SKILL.md
```

For full examples, see:

- [docs/examples/research_job_moonclaw.json](/Users/kq/Workspace/moonclaw/docs/examples/research_job_moonclaw.json)
- [docs/examples/wiki_moonclaw.jobs.json](/Users/kq/Workspace/moonclaw/docs/examples/wiki_moonclaw.jobs.json)
- [docs/examples/opc_moonclaw.jobs.json](/Users/kq/Workspace/moonclaw/docs/examples/opc_moonclaw.jobs.json)
