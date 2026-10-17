# MoonClaw Rabbita Operator UI

MoonBit web application for requesting, reviewing, running and inspecting
governed MoonClaw work. MoonClaw remains the sole agent runtime.

## Run

```bash
cd ui/rabbita-job
moon check main
moon info main
npm i
npm run dev
```

By default the app talks to the origin that served the published UI. This
keeps an isolated gateway such as `http://127.0.0.1:4317/ui` bound to its
actual runtime instead of assuming port `18123`.

A trusted host may supply an absolute HTTP(S) base before the Rabbita bundle
loads through `globalThis.__MOONCLAW_GATEWAY_BASE__`,
`globalThis.__MOONCLAW_RUNTIME_BASE__`,
`globalThis.__MOONCLAW_RUNTIME_CONFIG__.gatewayBase`, or a
`<meta name="moonclaw-gateway-base" content="...">` element. For local
development, `?moonclaw_gateway_base=http://127.0.0.1:18123` (or
`?gateway_base=...`) is accepted only for the same browser host or between
loopback aliases. Overrides reject non-HTTP schemes, embedded credentials,
query strings, fragments, and HTTPS-to-HTTP downgrade.

## Serve Through Gateway

Build the app bundle:

```bash
./scripts/build-rabbita-ui.sh
```

Equivalent manual steps:

```bash
cd ui/rabbita-job
npm install
npm run build
```

Then start the gateway and open:

```bash
moon -C /Users/kq/Workspace/moonclaw run cmd/main -- gateway start --home /path/to/MoonSuiteRoot --cwd /Users/kq/Workspace/moonclaw
```

```text
http://localhost:18123/ui
```

The gateway serves the built bundle from `ui/rabbita-job/dist`. It first checks
the gateway `--cwd`, then falls back to the MoonClaw repo's own
`ui/rabbita-job/dist` when the gateway is serving another workspace. It also
serves the bundle's root-level `/assets/...` files so the built app can load
correctly from `/ui`. If the bundle has not been built yet, `/ui` returns a
small HTML page explaining how to build it.

Be careful with `--cwd`: it is the gateway's default writable workspace. If
you start the gateway with `--cwd /Users/kq/Workspace/moonclaw`, agent actions
and generated files may be written into that repo. Use a separate workspace if
you want the UI and gateway to operate without mutating the source tree:

```bash
mkdir -p /path/to/MoonSuiteRoot/.moonsuite/products/moonclaw/workspace
moon -C /Users/kq/Workspace/moonclaw run cmd/main -- gateway start --home /path/to/MoonSuiteRoot --cwd /path/to/MoonSuiteRoot/.moonsuite/products/moonclaw/workspace
```

Important: `ui/rabbita-job` is its own MoonBit module. If you run
`moon run cmd/main -- ...` from inside this directory, Moon will fail because
`cmd/main` only exists in the top-level MoonClaw repo. Run gateway commands
from the repo root, or use `moon -C /path/to/moonclaw run cmd/main -- ...`.

Current surfaces:

- Work [nested JSON input selection](../../docs/SELECTED_JSON_INPUTS.md): inspect,
  order and preview exact paths from local JSON/JSON Lines exports in a task draft.

- Work source-project save/reopen: [resume exact source curation](../../docs/SOURCE_PROJECTS.md)
  through a previewed local JSON file, then edit and prepare an ordinary task.
- `Home`: one state-derived next action plus Ask → Plan → Review → Run →
  Inspect progress
- `Work`: request threads, transcript, attachments and reviewed-plan actions
- `Runs`: durable job list, expansion and evidence inspection
- `Remote`: ACP target/session/run inspection
- local job expansion viewer
- full-screen run canvas toggle
- ACP remote-agent viewer
- mixed overview linking local and remote activity
- final run report/result cards
- aggregated starter-doc input card
- linked proposal/run cards inside Cowork
- right-side Cowork context tabs for preview, workspace, artifacts, and run state
- full-screen artifact editor surface
- artifact, workspace, memory, and ACP stdio inspection
- managed polling refresh for active runs and ACP state
- export surfaces for:
  - ACP run transcripts
  - ACP session transcripts
  - ACP session timeline transcripts
  - focused mixed-lineage transcripts
  - combined case exports bundling local run, focused lineage, and linked ACP session timelines

Current limitation:

- local jobs and ACP both use live event streams, but snapshots still refresh periodically for reconciliation

Current workflow notes:

- `Work` is the ordinary conversation-first surface: create a thread, describe
  an outcome, enter plan mode, preview/promote, confirm linked proposals, and
  resume waiting runs without leaving the UI
- runtime connection data and advanced attachment controls use progressive
  disclosure so the first viewport stays task-focused
- blocked states name the retained work and a safe retry or inspection action
- final run `report.md` and `result.json` are surfaced as synthetic artifact cards when they exist only as workspace files
- starter attachment digest/text/summary/manifest artifacts are grouped into one `Starter Docs` card in the main artifact-facing surfaces
- after frontend changes, rebuild with `./scripts/build-rabbita-ui.sh`

The release journey and negative/recovery cases are recorded in
`docs/qualification/UI_TO_UI_USE_CASES.md`.

## Use what worked

The existing Work screen includes an explicit accepted-procedure browser and
expected-versus-delivered comparison. Select a saved work folder that is the Book
root, open **Use what worked**, inspect/select a method, then use the ordinary
Plan → Preview → Promote → Confirm path. See
[`docs/USE_WHAT_WORKED.md`](../../docs/USE_WHAT_WORKED.md) for exact data boundaries,
recovery behavior, authentication and verification limits. Selection alone never
starts execution. Source/controller tests: `node --test procedures.test.mjs`.

## Continue blocked work

The Work screen's linked run now has a checkpoint-scoped missing-input recovery
panel. Inspect completed work and retained artifacts, reopen a saved answer,
then explicitly continue the same blocked step. Newer checkpoints and uncertain
submissions require reconciliation rather than a blind replacement run. See
[`BLOCKED_WORK_RECOVERY.md`](../../docs/BLOCKED_WORK_RECOVERY.md) for the connected
contract and qualification limits. Run `bash scripts/test-blocked-recovery.sh`.

## Focused source inputs

In Work, **Choose focused source excerpts** imports operator-selected local UTF-8
text or loads exact text outputs from the linked terminal run. It lets you curate numbered line ranges with relevance notes and a byte budget,
and previews the exact text before adding it to the ordinary task draft. No file
is sent until the normal task controls are used. See
[Focused source briefs](../../docs/FOCUSED_SOURCE_BRIEFS.md) for limits,
reimport behavior and verification boundaries.

Retained passages share that same working set and are reread before preview and
apply. See [Retained source passages](../../docs/RETAINED_SOURCE_PASSAGES.md) for
run/job/artifact/version/digest provenance, read-only endpoints and limits.

The focused-source panel includes a bounded exact-line comparison of two imported
snapshots. Choose a changed passage and explicitly inspect either side in the
existing excerpt editor before adding, previewing or applying it. See
[Changed source passages](../../docs/CHANGED_SOURCE_PASSAGES.md) for limits,
identity semantics and interruption behavior.

### Observed teaching-case export

Work → **Teach from observed outputs** connects exact retained run text to the
existing MoonBook CSV rehearsal intake. Load, inspect source lines, explicitly
label the observation and literal checks, queue cases, preview CSV, then download
with source revalidation. See [OBSERVED_CASE_EXPORT.md](../../docs/OBSERVED_CASE_EXPORT.md).
The ordinary plan/composer and Book review authority remain unchanged.

### Reviewed local source refresh

The existing Work source panel now supports a revised same-name local file
without discarding the operator's curation. Review each old excerpt, choose an
exact relocated range or manually replace/drop it, preview the full proposed
project, then atomically replace only unsent source preparation. Notes and task
order survive for retained excerpts. Use ordinary source-brief preview/apply to
update a draft, and save a source project to keep the new revision.

See [the operator guide](../../docs/REFRESH_SOURCE_EXCERPTS.md). Production modules
are `source-refresh.js` and `source-refresh-controls.js`, mounted by the existing
`source-brief-controls.js`. No new runtime API, MoonBit interface or dependency
is introduced. Run `node --test source-refresh.test.mjs` from this directory.

### Selected CSV task input

Work → **Choose CSV records and columns** imports a local CSV, inspects logical
records including quoted multiline cells, and selects rows/columns in task
order. Original positions disambiguate blank/duplicate headers. Preview the
complete draft, apply only the selected literal cells, revise/reapply or remove
the table block. No request, model, formula or upload runs in this authoring flow.

See [the operator guide and portable example](../../docs/SELECTED_TABLE_INPUTS.md).
`table-input.js` owns the parser, selection and packet; `table-input-controls.js`
mounts through `bootstrap.js` at the existing Work anchor. Run
`node --test table-input.test.mjs`. Unsent preparation is tab-local; no source
project or runtime interface changes are introduced.

### Explicit JSON snapshot changes

The Work composer also mounts **Compare explicitly chosen JSON locations** via
`json-changes-controls.js`. Choose both local snapshots, formats, document numbers
and pointers; inspect each exact typed/token pair and select only useful changes.
Absent and null remain distinct. No array or JSONL entity identity is inferred.
Preview and apply only prepare the ordinary draft; they do not call a provider.
See the [worked JSONL example](../../docs/examples/json-changes/README.md).
Run `node --test ui/rabbita-job/json-changes.test.mjs` from the repository root.
