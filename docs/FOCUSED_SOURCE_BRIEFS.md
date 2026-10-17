# Focused source briefs

The Work surface now offers **Choose focused source excerpts** beside the
existing procedure and output-revision controls. This is an input-authoring
journey: take selected passages from local UTF-8 text files and exact retained
outputs into a new task. The [retained-source workflow](RETAINED_SOURCE_PASSAGES.md)
adds linked-run output inspection, revision provenance and exact rereads to the
same curation controls. Whole-output rework remains in its separate panel.

## Operator journey

1. Open a Work thread and describe the task in its ordinary composer.
2. Expand **Choose focused source excerpts** and select local UTF-8 files.
   Reading uses the browser File API. Importing does not upload or send them.
3. Choose a source and inspect its numbered lines. Literal, case-insensitive
   search reports original line numbers and shows at most 100 matching lines.
   Search narrows the view, not the selected excerpt. Narrow the search to
   inspect later lines; there is no silent source truncation.
4. Specify an inclusive first/last line and why those lines matter. Add the
   excerpt. Repeat for other passages and files. Selected ranges are displayed
   in full, including lines omitted by the current search.
5. Select an excerpt to edit its range or relevance note, move it up/down, or
   remove it. Overlapping ranges from the same source are refused. Removing a
   source removes its unsent excerpts. Changes to the unsent set leave any
   already-applied composer text untouched until you preview and apply again.
6. Set the excerpt-content byte budget and choose **Preview source brief**.
   The complete proposed composer text appears, including the objective,
   ordered excerpts, relevance notes, source identity, and limits.
7. **Put previewed sources in draft** dispatches the ordinary composer input
   event. It does not send, plan, approve, or run work. Use the existing Plan,
   Preview, Promote and Confirm controls and inspect the proposed scope.
8. Reapply after editing to replace only this feature's source block, preserving
   surrounding text and other workflow packets exactly. **Remove source block
   from draft** removes that block while preserving other draft text and the
   unsent working set. The explanatory text outside the block remains.

## Exactness, limits and continuity

- Up to eight combined sources, with local files at most 256 KiB and retained
  text at most 32 KiB each; 1 MiB total imported bytes.
  Duplicate names in one picker selection, invalid UTF-8, NUL-containing binary
  data, and mismatched declared/read byte counts are rejected atomically.
- At most eight non-overlapping excerpts. The default selected-text budget is
  8192 UTF-8 bytes; allowed budgets are 1024–16384 bytes. It is not a token,
  request, price or runtime-cost budget. The JSON packet is bounded to 64 KiB
  and the combined task draft to 128 KiB. Other runtime context is unchanged.
- Line boundaries are LF, preserving CRLF, any BOM and exact UTF-8 content.
  A trailing LF does not create an extra empty line. Bare CR is content, not a
  separate line delimiter. Hashes cover exact imported full-file and excerpt
  UTF-8 bytes. Fingerprints establish byte identity, not source authenticity,
  disk freshness, factual correctness, permission, or accepted Book knowledge.
- Source names are local basenames. Absolute local paths are not requested.
  Files are frozen browser snapshots. Later disk changes are not detected;
  explicitly reimport to update. Reimporting changed bytes under the same name
  drops that source's old excerpts. Unchanged imports preserve its selections.
  The separate [reviewed source refresh](REFRESH_SOURCE_EXCERPTS.md) path can
  preserve curated notes and order while you explicitly choose exact relocated
  ranges, replacement passages or dropped excerpts in a revised same-name file.
- Every source, range, budget, search, relevance-note or composer edit
  invalidates the preview, including edit-and-restore. Changed task/gateway
  context clears unsent sources. Late reads and hashing results are generation
  guarded; Cancel, newer picks, navigation and unmount cannot overwrite a new
  draft. A file read cannot always be physically interrupted, but its result is
  discarded. Duplicate preview clicks do not create concurrent preparations.
- Unsent source bytes and selections are tab-local. To resume after
  reload/navigation, explicitly [save and reopen a source project](SOURCE_PROJECTS.md).
  No automatic persistence is added. An applied packet persists only when the ordinary task request is
  subsequently sent and retained by the existing host. This feature adds no
  local-storage database or automatic restore of imported sources.
- Excerpts remain untrusted source data, and omitted lines may be important.
  Source instructions are not authority. Nothing here changes host permissions,
  planner context inclusion, runtime enforcement, or acceptance ownership.

## Source grounding and implementation

PRD workflow **MC-W01** calls for recording objective and input references.
Requirement **MOONCLAW-B02**, Bounded plan approval, calls for inputs attached to
an approved plan. This feature supplies reviewable local inputs to that existing
boundary; it does not implement or qualify all of B02's authority enforcement.

The existing `render_cowork_workspace_panel` only offers whole managed snapshot
files through **Add to Chat**. `workspace/runtime.mbt` manages IDENTITY, AGENTS,
USER, ROUTINES and MEMORY; `/v1/workspace` is a cached gateway snapshot, not an
arbitrary local file picker. This new flow adds operator-picked local text,
line selection, relevance notes, order, byte limits and exact preview.

`bootstrap.js` mounts `source-brief-controls.js` on the existing Work anchor.
`source-brief.js` owns bounded file decoding, curation, packet validation and
byte-preserving composer replacement. The controller sets
`claw-procedure-composer` and emits the same input event handled by
`SetCoworkComposer`. Local-only selection makes no network request. Retained selection uses the
existing read-only run/artifact endpoints via `retained-sources.js`; no runtime
API, MoonBit file, provider or existing procedure/recovery/rework flow changes.

## Verification boundary

Run the new production-module/controller tests:

```sh
node --test ui/rabbita-job/source-brief.test.mjs
```

Run adjacent regressions including exact-output rework and checkpoint recovery:

```sh
node --test ui/rabbita-job/*.test.mjs
```

The DOM tests execute production mount/bind/install handlers with a lightweight
DOM harness and real File-like UTF-8 bytes/WebCrypto. They verify file import,
source search, edit/reorder/remove, exact preview/apply/remove-block, interruption,
context change, repeated actions and stale-response guards. They do not qualify
actual browser rendering, native OS picker behavior, built Rabbita bundles,
host persistence/restart, or configured model execution. Those remain separate.

## Find changed passages

Use [snapshot comparison](CHANGED_SOURCE_PASSAGES.md) to inspect exact line changes
between two imported source identities and explicitly send one side to the
ordinary excerpt editor. Selection, relevance notes, budgets and task approval
remain in this same workflow.
