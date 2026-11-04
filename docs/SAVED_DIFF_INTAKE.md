# Plan from selected Git diff hunks

MoonClaw turns an operator's request into reviewed agent work. This Work-composer
input lets you bring the relevant parts of a saved Git diff into that request
without opening a repository or copying full before/after file snapshots.

1. In Work, write the overall objective in the main task composer.
2. Open **Choose focused source excerpts → Plan from a saved Git diff**.
3. Open your UTF-8 `.patch` or `.diff` file, or try
   `docs/examples/saved-diff-demo.patch` (fictional example).
4. Choose a changed file, then a hunk. The inspector shows its exact file header,
   hunk header, unchanged context, additions, deletions and newline markers.
5. Use **Keep this hunk** for each relevant hunk. Switch files to keep more.
   **Remove this hunk from selection** undoes a choice. Nothing is selected by
   default. The selection preview follows original patch order, regardless of
   the order you picked hunks. Binary and metadata-only files are listed with
   an explanation and no selectable text hunks.
6. Write the request for those changes and expected checks. Click **Add selected
   diff to source brief**. This stages one excerpt with exact selected patch
   bytes plus the original patch's name and SHA-256 in its relevance note.
7. Inspect **Preview source brief**, then **Put previewed sources in draft**.
   The normal **Plan → Preview → Promote → Confirm** workflow remains in charge.

Changing hunk picks does not silently update a staged excerpt: click **Add
selected diff to source brief** again to replace the same patch's staged
selection. To remove all staged diff material, use the existing excerpt/source
removal controls. Source brief preview/apply controls then update the draft.
Other source excerpts stay available alongside the selected diff. A rejected
oversized selection leaves the prior working set unchanged.

## Boundaries and useful limits

- This is input preparation only. It neither applies a patch nor reads/writes a
  repository, starts a plan, calls a provider or grants runtime authority.
- Files use the existing 256 KiB UTF-8 text import limit. Selected content uses
  the existing 8 KiB default / 16 KiB maximum byte budget. Raise the budget or
  select fewer hunks if needed. Request/checks plus provenance share the existing
  1,000-byte relevance-note limit.
- Normal `diff --git` unified text hunks are supported, including new/deleted
  files, rename headers with content changes, CRLF and no-final-newline markers.
  Combined merge diffs, binary payloads and metadata-only changes are not
  selectable. Truncated hunk counts are reported rather than filled in.
- File labels are literal Git header text, including Git-quoted paths. No path
  is resolved or opened. Selected excerpts are partial review material, not an
  assertion that they form a complete or applicable patch.
- Save the original patch yourself if you need all omitted changes. The existing
  source-project download saves the staged selected snapshot; it does not save
  the un-staged navigator state or omitted original hunks. Changing Work thread
  clears the diff navigator. Reload loses unsaved preparation.

## Verification

From the repository root, run:

    node --test ui/rabbita-job/saved-diff.test.mjs ui/rabbita-job/source-brief.test.mjs ui/rabbita-job/source-project.test.mjs ui/rabbita-job/source-refresh.test.mjs ui/rabbita-job/source-comparison.test.mjs

70 tests pass on Node v24.19.0. Seven focused tests cover parser selection and
byte preservation, ordinary malformed input, mounted file/hunk selection,
request/check staging, preview/apply/input events, restaging, budget rollback,
thread change and production Plan wiring. The DOM tests use the repository's
lightweight fake-DOM pattern, not a browser visual test. Plan wiring is inspected
in production MoonBit source; a compiled browser/real gateway/provider roundtrip
was not run. No MoonBit source or dependency changed. This source delivery does
not establish those runtime/release gates.
