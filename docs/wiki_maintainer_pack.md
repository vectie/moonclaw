# Wiki Maintainer Pack

This document describes the MoonClaw side of running a persistent markdown wiki
workspace.

## Goal

MoonClaw should not hardcode a wiki product into core.

Instead, MoonClaw should provide a reusable runtime for:

- inspecting source material
- planning durable wiki updates
- editing markdown pages
- reviewing cross-page consistency
- recording artifacts, lineage, and controller decisions

The wiki-specific behavior should come from a workspace-local extension pack.

This is designed to sit cleanly beside a separate wiki product/workspace layer.
A wiki host workspace can own:

- `raw/`
- `wiki/`
- `wiki/index.md`
- `wiki/log.md`
- rendering/building/serving

while MoonClaw owns the workflow/runtime behavior operating inside that
workspace.

## Recommended Pack Shape

```text
workspace/
  moonclaw.jobs.json
  raw/
  wiki/
    index.md
    log.md
    entities/
    concepts/
    synthesis/
    queries/
    sources/
  skills/
    wiki-maintainer/
      SKILL.md
    wiki-review/
      SKILL.md
```

The current example job pack is:

- [docs/examples/wiki_moonclaw.jobs.json](/Users/kq/Workspace/moonclaw/docs/examples/wiki_moonclaw.jobs.json)

Current runtime support also detects wiki-shaped workspaces automatically and
surfaces compact wiki structure plus `wiki/index.md` / `wiki/log.md` excerpts
in prompt context.

## Core Workflow Families

Recommended controller profiles:

- `wiki_ingest_controller`
  - routes first through a provider-backed ingest extension
  - lets the workspace pack decide source discovery and durable page creation
  - then continues with generic controller/review/runtime behavior as needed

- `wiki_query_controller`
  - reads `wiki/index.md` first
  - locates relevant wiki pages
  - synthesizes an answer with citations to page paths
  - optionally files a durable query note back into `wiki/queries/`

- `wiki_lint_controller`
  - audits wiki health
  - proposes repair work
  - optionally applies repairs
  - finalizes with a health report

Recommended worker profiles:

- `wiki_revision_worker`
  - edits wiki markdown directly
  - updates `wiki/index.md` and `wiki/log.md` when the wiki changes
  - preserves `raw/` as immutable source material

- `wiki_review_worker`
  - reviews wiki changes
  - checks consistency, stale wording, link integrity, and unsupported synthesis

## What Belongs In MoonClaw

MoonClaw owns:

- profile matching
- controller bookkeeping
- step execution
- child delegation
- workspaces and artifacts
- resume and operator control
- Cowork and Jobs UI

This is the part that turns a wiki pack into an actual workflow system instead
of a prompt convention.

## What Stays Outside MoonClaw

MoonClaw should not hardcode:

- wiki directory taxonomy
- page templates
- claim semantics for one domain
- source import rules
- renderer or book-server behavior

Those belong in the workspace pack and the surrounding wiki toolchain.

## Practical Rule

If the change is about:

- how a wiki request matches a workflow
- how many steps it runs
- which worker roles exist
- what prompts and skills each step uses

put it in `moonclaw.jobs.json`.

If the change is about:

- what counts as a substantive source
- how `raw/` maps into durable pages
- how `wiki/index.md` or `wiki/log.md` are updated
- when the workspace is ready for query

put it in the workspace extension/provider, not MoonClaw core.

If the change is about:

- how runs persist
- how delegated workers execute
- how artifacts are stored
- how UI links to workspaces and runs

it belongs in MoonClaw core.
