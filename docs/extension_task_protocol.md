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
4. when the final assistant turn has no tool calls, the event session must stop
   cleanly so the workflow engine can record `step.succeeded`, start the next
   phase, or finish the run

This matters because provider packs can shape domain phases such as
`bootstrap_gather`, `source_materialize`, `knowledge_revise`, and
`review_finalize`, but core runtime is still responsible for actually moving the
run from one phase to the next.

## Routing

Analysis or delegate steps can route into a provider through:

- `execution_mode: "provider"`
- `execution_mode: "extension"`

Compatibility aliases currently still accepted:

- `execution_mode: "bookapi"`
- `execution_mode: "moonbook.bookapi"`

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

Compatibility values still accepted:

- `kind: "moonbook"`
- `kind: "book-harness"`
- `capabilities: ["bookapi"]`
- `capabilities: ["moonbook.bookapi"]`

Required provider metadata:

- `command`
- `args`
- `workspace_root`

Optional provider metadata:

- `cwd`

## Command Contract

MoonClaw invokes the provider as:

```text
<command> <args...> wiki book <subcommand> <workspace_root> <subcommand-args...>
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
6. parses the structured result
7. persists it back through the provider
8. stores the operator-facing report and result metadata

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
- compatibility metadata fields:
  - `bookapi_goal`
  - `bookapi_goal_id`
  - `bookapi_task_id`
  - `bookapi_task_kind`
  - `bookapi_priority`
  - `bookapi_requires_review`
  - `bookapi_target_pages`

New configs should prefer the `extension_*` names.

## Design Rule

If a provider needs more domain semantics than this protocol gives it, extend
the provider implementation or its workspace-local pack first.

Do not hardcode domain-specific execution branches into MoonClaw core unless the
change is truly runtime-generic.
