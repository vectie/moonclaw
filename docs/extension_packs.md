# Extension Packs

This document describes how MoonClaw should stay general while supporting
opinionated verticals like research, wiki maintenance, and one-person-company
workflows.

## Core Rule

MoonClaw core owns mechanics.

Extension packs own policy.

AI owns reasoning inside the chosen policy.

That means:

- core runtime
  - jobs
  - controller bookkeeping
  - step execution
  - artifacts
  - memory
  - approvals
  - ACP
  - operator UI
- extension pack
  - profile matching
  - role vocabulary
  - step prompts
  - preferred skills
  - domain artifact conventions
  - decision policy metadata

## What An Extension Pack Is

An extension pack is a workspace-local combination of:

- `moonclaw.jobs.json`
- `skills/<name>/SKILL.md`
- optional domain docs, templates, and example outputs

This keeps domain behavior close to the workspace that wants it, instead of
baking it into the runtime.

## Research vs Wiki vs OPC

These are different workflow shapes built on the same core.

Research usually wants:

- compact analysis flow
- optional controller
- grounded source collection
- ranking, evaluation, and reporting

Wiki maintenance usually wants:

- controller-guided ingest, query, and lint flows
- direct markdown revision workers
- durable updates to `index.md` and `log.md`
- strong cross-reference and consistency review
- preservation of immutable raw sources

OPC usually wants:

- a controller
- multiple delegated worker steps
- role-specific skills like CEO, eng, review, QA, ship
- a sprint-shaped flow

The shared substrate is:

- `job.analysis`
- `job.delegate`
- `job.controller`
- run lineage
- artifacts
- memory
- notifications
- ACP

The differing layer is:

- profile shape
- skill pack
- domain prompts
- evaluator semantics

For wiki maintenance specifically, a separate host workspace can own the wiki
product shape while MoonClaw owns the runtime:

- host workspace
  - `raw/`
  - `wiki/`
  - `index.md`
  - `log.md`
  - rendering/building/serving
- MoonClaw pack/runtime
  - ingest/query/lint workflow policy
  - controller and worker roles
  - editing/review execution
  - artifacts, lineage, UI, and operator control

## What Must Stay Out Of Core

To preserve generality, core should not hardcode:

- research-only families
- OPC-only families
- fixed step counts by domain
- domain-specific branching rules
- domain-specific evaluator meaning
- domain-specific artifact taxonomies

Those belong in extension packs.

## Generic Core Hooks That Packs Reuse

Current hooks that make this work:

- profile loading from `<cwd>/moonclaw.jobs.json`
- profile matching with `match.any`, `match.all`, and `priority`
- role runtime envelopes via `metadata.role_runtime`
- proposal steps carrying:
  - `kind`
  - `metadata`
  - optional `child_profile` for delegated workers
  - optional `execution_mode` / `execution_target` routing hints
  - delegate controls like `include_parent_outputs` and `max_depth`
- analysis step compilation using metadata for:
  - `preferred_skills`
  - `system_prompt`
  - `enable_tools`
  - `web_search`
  - `role_runtime`
  - `model`
  - `board_lane`
  - `board_order`
- delegate step compilation using typed child-job config
- delegate step compilation can also preserve board metadata for UI grouping
- delegate steps optionally forcing a named child profile without changing core runtime semantics
- delegate steps optionally carrying execution routing intent that later executors can honor
- the gateway can honor ACP routing hints for simple delegated child analysis jobs
- analysis steps can also carry ACP routing intent
- controller policy metadata on the profile

MoonClaw now also provides a reusable role substrate:

- `RoleRuntimeContract`
- `RoleHandoffPacket`
- runtime tool gating for planner-only roles

So host systems can embed MoonClaw as different planner or executor roles
without copying runtime logic.

## Recommended Pack Structure

Example research pack:

```text
workspace/
  moonclaw.jobs.json
  skills/
    arxiv-research/
      SKILL.md
```

Example OPC pack:

```text
workspace/
  moonclaw.jobs.json
  skills/
    opc-ceo/
      SKILL.md
    opc-eng/
      SKILL.md
    opc-review/
      SKILL.md
    opc-qa/
      SKILL.md
    opc-ship/
      SKILL.md
```

Example wiki-maintainer pack:

```text
workspace/
  moonclaw.jobs.json
  raw/
  wiki/
    index.md
    log.md
  skills/
    wiki-maintainer/
      SKILL.md
    wiki-review/
      SKILL.md
```

Example controller lane metadata inside `moonclaw.jobs.json`:

```json
{
  "id": "qa",
  "title": "QA worker",
  "kind": "job.delegate",
  "metadata": {
    "board_lane": "QA",
    "board_order": 4
  }
}
```

This lets the company board remain profile-driven instead of hardcoding lane
names in core.

## Practical Rule Of Thumb

If a new use case can be expressed as:

- a profile
- a skill pack
- maybe a new tool

then it should remain outside core.

If you need to change:

- how runs execute
- how controller lineage is persisted
- how artifacts are stored
- how approvals work

then it belongs in core.

See also:

- [docs/wiki_maintainer_pack.md](/Users/kq/Workspace/moonclaw/docs/wiki_maintainer_pack.md)
- [docs/examples/wiki_moonclaw.jobs.json](/Users/kq/Workspace/moonclaw/docs/examples/wiki_moonclaw.jobs.json)
- [docs/role_substrate.md](/Users/kq/Workspace/moonclaw/docs/role_substrate.md)
