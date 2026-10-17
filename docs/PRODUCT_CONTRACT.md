# MoonClaw product contract

Class: platform service
Maturity: advanced local alpha
Last reviewed: 2026-07-30

## Outcome

MoonClaw is MoonSuite's sole agent runtime. It turns an approved request into a
durable session or job, runs the model/tool loop, and records events, artifacts,
control decisions and memory.

## Users and jobs

- Operators run, inspect, steer, cancel and recover agent work.
- MoonDesk submits commands and renders the resulting journals.
- MoonFlow invokes MoonClaw when a declared work item requires agent execution.
- Domain packs expose tools to MoonClaw without adding another agent runtime.

## Ownership

MoonClaw owns model reasoning lifecycle, agent sessions, jobs, tool execution,
MoonCode runtime behavior, runtime memory and ACP remote-agent control.

MoonClaw does not own:

- domain ranking, media-production, robotics or accounting policy;
- durable dependency orchestration owned by MoonFlow;
- accepted book truth and Bookkeeper learning owned by MoonBook;
- provider policy and usage control owned by MoonGate;
- human acceptance or physical authority.

## Capability status

| Capability | Status |
| --- | --- |
| Native agent, job, tool and memory runtime | available |
| Durable journals, workspaces and artifact evidence | available |
| MoonCode command, control and evaluation paths | available |
| ACP remote-agent coordination | available |
| Gateway and operator surfaces | available locally |
| Versioned pack capability invocation and reconciliation | available |
| Live pack tool execution | conditional on an installed, healthy, conformant adapter |
| Autonomous product/domain policy | excluded |
| Production multi-user deployment | planned |

Conformance: **L2 usable locally** for request → reviewed plan → durable run →
outcome inspection. L3 is conditional on the receiving pack's installed,
healthy adapter and correlated reconciliation receipt.

## Authority and evidence

Every consequential operation must carry the requested authority and produce a
receipt. Unknown outcomes reconcile before retry. Workspace artifacts remain
contained under the selected product/book roots. A successful runtime turn is
execution evidence, not acceptance evidence; named review remains outside the
runtime.

Domain-specific endpoints must not be added to MoonClaw. A MoonRobo action, for
example, is invoked through a MoonRobo-owned adapter while MoonClaw remains the
generic runtime.

The executable cross-product contract is documented in
[Generic Capability Invocation](CAPABILITY_INVOCATION.md). MoonClaw accepts
only canonical `<product>/<tool>@<pack-version>` operations and versioned
schemas from MoonFlow's compiled capability catalog. It then re-verifies the
active pack and expiring health evidence before execution.

## Operation

The canonical command and daemon surfaces are documented in the root README and
`cmd/`. Deployment-specific credentials remain host secret references.
Operators must back up durable product state and book-owned accepted artifacts,
not `_build` or disposable caches.

## Verification

Use the repository's targeted tests during development and the full native
suite before release:

```sh
moon check --target native
moon test --target native
moon info
moon fmt
```

## Release gates and next milestones

- Clean-machine daemon install, update, rollback and recovery proof.
- Multi-day restart/soak evidence without journal loss or duplicate effects.
- Capability-registry conformance and live health evidence for every pack
  adapter.
- Removal of stale domain-specific documentation and endpoints.
- Clear operator backup, restore and incident-response procedures.

## Focused task inputs

The Work surface supports [focused source briefs](FOCUSED_SOURCE_BRIEFS.md):
operator-picked UTF-8 file snapshots and [exact retained-output passages](RETAINED_SOURCE_PASSAGES.md),
ordered line excerpts, producing-run/revision provenance, relevance notes,
selected-byte limits and exact preview into the existing task composer. This is
bounded input authoring for ordinary plan review. Snapshot fingerprints do not
establish disk freshness, accepted knowledge or execution authority. Other runtime
context and the existing Plan/Preview/Promote/Confirm boundary remain unchanged.

### Exact changed-passage preparation (bounded development slice)

Work operators can [compare imported text snapshots](CHANGED_SOURCE_PASSAGES.md),
inspect exact changed ranges and choose one side for the existing source-excerpt
editor. Retained sources retain producing identities and are reread before both
comparison and range selection. Local files remain frozen snapshots. No semantic
judgment, accepted knowledge, authority or runtime execution is inferred.

### Observed outputs for Book correction rehearsal (bounded development slice)

Work operators can [export observed teaching cases](OBSERVED_CASE_EXPORT.md) from
exact retained terminal-run text passages. They explicitly author useful/adverse
labels and literal checks, preview a CSV matching MoonBook's existing intake,
and download only after gateway revision revalidation. Import, comparison and
named review remain explicit in Book; runtime success does not adopt a lesson.

### Resume focused source preparation (bounded development slice)

Operators can [save and reopen source projects](SOURCE_PROJECTS.md) containing
full imported text snapshots plus curated ranges, relevance notes, order and
selected-text budget. Explicit file preview and replacement resume authoring
without changing the task draft or approvals. Reopened snapshots disclose
unverified freshness; selected retained revisions still require the existing
gateway rereads before task preview/application. This is input-authoring
continuity, not a runtime checkpoint or complete B02/B04 qualification.

### Reviewed local source refresh (bounded development slice)

Operators can [refresh a curated local snapshot](REFRESH_SOURCE_EXCERPTS.md)
using a revised same-name file. Exact line matches are candidates, never an
automatic selection: each old excerpt is explicitly relocated, replaced with
an authored range/note, or dropped. A complete preview precedes atomic unsent
working-set replacement. Kept notes/order and unrelated retained provenance
survive; task drafts change only through the existing source-brief application.
No disk freshness, semantic equivalence, permission or execution is inferred.

### Selected CSV task input (bounded development slice)

Operators can [select local CSV records and columns](SELECTED_TABLE_INPUTS.md)
by original position, including duplicate/blank headers and quoted multiline
cells. Ordered literal cells, a relevance note and exact source fingerprints
enter the ordinary task only after full preview and explicit draft application.
Omitted cells are not included. Selection grants no authority, interprets no
formula, adds no runtime API and leaves the existing plan approval boundary
and all requirement statuses unchanged.

### Keyed CSV changes as task input (bounded development slice)

Operators can [compare two local CSV snapshots](CSV_CHANGES.md) using explicit
key and column mappings, inspect added/removed/changed records, and curate exact
selected before/after cells into the ordinary task draft. Reordering alone is
unchanged; duplicate/blank keys are reported rather than guessed. This reuses the
existing plan/approval path and leaves runtime authority and PRD statuses intact.

### Nested JSON observations as task input (bounded development slice)

Operators can [choose exact JSON or JSON Lines values](SELECTED_JSON_INPUTS.md)
by original document and JSON Pointer, inspect and order complete subtrees or
scalars, then preview their selected syntax in the ordinary task draft. Large
numeric IDs and escaped strings are preserved without floating-point conversion.
Unselected fields remain omitted. This is local input curation, with unchanged
plan approval, execution authority and requirement statuses.
