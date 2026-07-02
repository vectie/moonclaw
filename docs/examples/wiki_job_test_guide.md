# Wiki Maintainer Job Test Guide

This is a concrete way to test MoonClaw as the workflow/runtime layer for a
persistent markdown wiki workspace.

## 1. Install the example pack into a wiki workspace

Copy the example job profile into the workspace you want to run:

```bash
mkdir -p ~/.moonsuite/products/moonclaw/wiki-workspace
cp /Users/kq/Workspace/moonclaw/docs/examples/wiki_moonclaw.jobs.json ~/.moonsuite/products/moonclaw/wiki-workspace/moonclaw.jobs.json
```

This keeps wiki-maintainer behavior workspace-local. It does not change global
runtime config in `~/.moonsuite/products/moonclaw/moonclaw.json`.

If the workspace also contains:

- `raw/`
- `wiki/`
- `wiki/index.md`
- `wiki/log.md`

then MoonClaw can operate on it as a maintained wiki layer.

## 2. Start the gateway against that workspace

```bash
moon run cmd/main -- gateway start --home ~ --cwd ~/.moonsuite/products/moonclaw/wiki-workspace
```

## 3. Trigger the three core wiki workflows

### Ingest-style flow

Send:

```text
/plan-job Ingest this source into the wiki: read raw/land-report.md, revise the relevant wiki pages, update index and log, and summarize what changed.
```

Then confirm it:

```text
/confirm <proposal_id>
```

### Query-style flow

Send:

```text
/plan-job Answer this from the wiki: what changed in the land acquisition compensation assumptions, and save a durable query note if the answer is worth keeping?
```

### Lint-style flow

Send:

```text
/plan-job Lint the wiki for orphan pages, stale claims, weak cross-links, and missing concept pages, then repair the highest-value issues.
```

## 4. What success looks like

You should see:

- ingest requests match `wiki_ingest_controller`
- query requests match `wiki_query_controller`
- lint requests match `wiki_lint_controller`
- controller-shaped runs instead of a generic single-step fallback
- delegated worker steps use:
  - `wiki_revision_worker`
  - `wiki_review_worker`
- the run workspace appears under `.moonsuite/products/moonclaw/jobs/<run-id>`
- the resulting reports explain:
  - which wiki pages changed
  - what claims were strengthened or challenged
  - what remained uncertain

## 5. What this proves

This demonstrates the intended MoonClaw side of the wiki pattern:

- MoonClaw stays generic
- wiki workflow policy comes from `moonclaw.jobs.json`
- step shape, controller behavior, and worker roles are pack-defined
- controller bookkeeping, delegation, artifacts, workspaces, and UI reuse the
  core runtime

## 6. What this does not prove yet

This pack does not by itself guarantee:

- deep claim/supersession modeling
- domain-tuned source schemas
- automatic review/approval flows for every wiki edit
- a wiki-specific frontend

Those belong to the surrounding wiki product/workspace layer.
