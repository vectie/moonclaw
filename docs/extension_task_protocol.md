# Extension Task Protocol

This document describes the generic provider-backed execution contract used by
MoonClaw runtime steps.

## Goal

MoonClaw should be able to execute domain-local work through an extension
boundary without making that domain first-class in core runtime.

Core owns:

- proposal compilation
- analysis execution
- delegated child runs
- artifacts
- lineage
- operator visibility

The provider owns:

- goal acceptance
- task decomposition
- worker context hydration
- durable result persistence

For wiki-style ingest flows, this means MoonClaw may route a controller family
into a provider-backed extension step, but it should not decide what counts as a
real source, how source pages are written, or when a domain workspace is ready
for query. Those remain provider responsibilities.

## Runtime Progression

Provider-backed execution is still expected to follow normal MoonClaw workflow
state transitions:

1. the routed provider step runs as a normal analysis step
2. if the provider result requests `needs_subplan`, MoonClaw compiles bounded
   child runs and executes them as ordinary workflow runs
3. child completion is synthesized back into the parent provider step and
   persisted through the normal provider-result path
4. child run lifecycle is mirrored onto the parent run through
   `child_run.started`, `child_run.succeeded`, and `child_run.failed` events
5. when the final assistant turn has no tool calls, the event session must stop
   cleanly so the workflow engine can record `step.succeeded`, start the next
   phase, or finish the run

This matters because provider packs can shape domain phases such as
`bootstrap_gather`, `source_materialize`, `knowledge_revise`, and
`review_finalize`, but core runtime is still responsible for actually moving the
run from one phase to the next.

MoonClaw treats the bootstrap phase names above as generic runtime phase hints,
not as first-class wiki semantics. When a provider returns those task kinds,
MoonClaw orders and bounds them as:

1. `bootstrap_gather`
2. `source_materialize`
3. `knowledge_revise`
4. `review_finalize`
5. `review`

The provider still owns the meaning of the workspace and the quality bar for
source/entity/concept/query material. MoonClaw only turns broad provider tasks
into smaller child jobs, harvests the resulting artifacts, refreshes catalog
surfaces when requested by the phase, and persists the provider result.

## Routing

Analysis or delegate steps can route into a provider through:

- `execution_mode: "provider"`
- `execution_mode: "extension"`

Each routed step must also provide:

- `execution_target`

`execution_target` is resolved from `.moonclaw/providers.json`.

## Provider Registry Shape

A provider entry should expose:

- `name`
- `title`
- `description`
- `kind`
- optional `endpoint`
- `capabilities`
- `metadata`

Recommended generic values:

- `kind: "extension"`
- or `kind: "task-provider"`

Recommended generic capabilities:

- `provider`
- `extension`
- `provider.task`
- `extension.task`

Required provider metadata:

- `command`
- `args`
- `workspace_root`

Optional provider metadata:

- `cwd`

## Command Contract

MoonClaw invokes the provider as:

```text
<command> <args...> wiki extension <subcommand> <workspace_root> <subcommand-args...>
```

Current subcommands:

- `tasks`
- `context`
- `persist`

The command prefix is provider-owned. MoonClaw only assumes that the final
subcommand contract is stable.

## Typed Payloads

### `tasks`

Input:

- `<goal>`

Output JSON:

```json
{
  "goal_id": "goal-1",
  "goal": "Update the knowledge base",
  "summary": "Task batch summary",
  "tasks": [
    {
      "id": "task-1",
      "title": "Extract durable updates",
      "kind": "wiki.update",
      "prompt": "Read the source and update the durable wiki state.",
      "priority": 90,
      "requires_review": true,
      "target_pages": ["wiki/entity.md", "wiki/index.md"]
    }
  ]
}
```

### `context`

Input:

- `<goal> --task <task-id>`

Output JSON:

```json
{
  "book_id": "book-1",
  "workspace_root": "/abs/workspace",
  "task_id": "task-1",
  "prompt": "Use the source evidence to revise the wiki carefully.",
  "policy": ["Keep raw sources immutable"],
  "routines": ["Update entity pages"],
  "skill_paths": ["skills/wiki-maintainer/SKILL.md"],
  "context_pages": ["wiki/index.md", "wiki/entity.md"],
  "active_memory": [],
  "user_memory": [],
  "working_memory": [],
  "memory_summary": "",
  "output_contract": ["Return strict JSON"]
}
```

The field names are historically wiki-shaped because the first provider lives in
that domain, but MoonClaw treats the payload as provider-owned context rather
than a first-class wiki feature.

### `persist`

Input:

- `<result-json-path>`

MoonClaw writes the analysis result to a temporary JSON file and passes the file
path to the provider.

Expected result payload shape:

```json
{
  "task_id": "task-1",
  "summary": "Updated the wiki and captured the contradiction.",
  "artifacts": ["wiki/entity.md"],
  "memory_candidates": [
    {
      "kind": "fact",
      "title": "Entity contradiction",
      "detail": "Two sources disagree on valuation.",
      "durable": true,
      "target_page": "wiki/entity.md"
    }
  ],
  "requires_review": true,
  "notify_town": false
}
```

For long prompt-derived provider task ids, MoonClaw may compact the persisted
`task_id` into a stable `provider-<phase-slug>-<hash>` form before handing the
result to `persist`. This keeps provider journals and downstream projections
readable. Short provider-owned task ids are preserved.

Provider results should report workspace-relative artifacts that actually exist.
MoonClaw filters out missing or non-workspace paths before persistence. For
bootstrap-style flows, a successful materialization result should include
durable pages such as `raw/bootstrap/*`, `wiki/sources/*`,
`wiki/entities/*`, `wiki/concepts/*`, `wiki/queries/*`, `wiki/synthesis/*`,
`wiki/index.md`, or `wiki/log.md` when those files were touched.

Provider persist response:

```json
{
  "log_path": "wiki/log.md",
  "updated_pages": ["wiki/entity.md", "wiki/index.md"],
  "review_queued": true,
  "notify_town": false,
  "evidence_id": "evidence-1"
}
```

## Runtime Behavior

When routed through a provider:

1. MoonClaw resolves `execution_target`
2. asks the provider for a task batch
3. selects the intended task
4. loads provider-owned worker context
5. runs the task through the normal analysis runtime
6. if the task is too broad, compiles bounded child runs from provider phase
   hints and gathered workspace artifacts
7. parses or synthesizes the structured result
8. persists it back through the provider
9. stores the operator-facing report and result metadata

For bootstrap-like providers, the current runtime has deterministic shapers for:

- gather lanes from source hints
- durable source-page materialization from gathered bootstrap packets
- entity/concept/synthesis revision targets from durable source pages
- final catalog/status refresh for `wiki/index.md`, `wiki/log.md`, and
  `wiki/synthesis/map.md`

These shapers are intentionally bounded. They avoid asking the model to
self-decompose one large provider task repeatedly, while still leaving the
provider responsible for workspace semantics and persistence.

## Metadata Conventions

MoonClaw currently emits both:

- generic metadata fields:
  - `extension_goal`
  - `extension_goal_id`
  - `extension_task_id`
  - `extension_task_kind`
  - `extension_priority`
  - `extension_requires_review`
  - `extension_target_pages`

## Design Rule

If a provider needs more domain semantics than this protocol gives it, extend
the provider implementation or its workspace-local pack first.

Do not hardcode domain-specific execution branches into MoonClaw core unless the
change is truly runtime-generic.
