# Save and resume focused source preparation

Work's **Choose focused source excerpts → Save or reopen source preparation**
preserves an unfinished research/input-curation session in a local JSON file.
It saves the imported snapshots, selected line ranges, relevance notes, their
order and the selected-text byte budget. You can reopen them after a reload,
revise the selections and prepare the next ordinary task without finding and
selecting every passage again.

## Try the connected journey

1. Open a Work thread. Write a task such as “Compare the retry note with the
   stop condition. Explain the discrepancy; do not execute anything.”
2. In **Choose focused source excerpts**, import local UTF-8 notes or use the
   existing **Load linked run outputs** and exact retained-output inspector.
   Select passages, explain why each matters, and put them in task order.
3. Expand **Save or reopen source preparation**. Choose **Preview source project
   for saving**. Review the counts and open **Inspect complete project JSON**.
   The file includes every imported source in full, including unselected sources
   and lines omitted from the eventual task. Review private text before saving
   or sharing. The feature does not redact source text.
4. Choose **Download previewed source project** and check the browser's downloads
   before leaving. The filename is `moonclaw-source-project.json`. This requests
   a local file; the UI cannot prove the browser saved it. Save another revision
   explicitly after editing if you want to keep those changes.
5. After reloading, return to Work and choose that file using **Open a saved
   source project**. A preview shows all stored source bytes and selections plus
   how many current unsent sources/excerpts would be replaced. Nothing is merged
   or replaced yet. Save any current work first, then reopen the desired file.
6. Choose **Replace working set with opened project**. The existing task composer
   is untouched. Restored sources are marked **reopened** and their inspection
   view says **reopened saved snapshot; freshness unverified**. The first source
   is selected, and the saved byte budget and excerpt order are restored.
7. Select an excerpt to edit its range or note, move it up/down, or remove it.
   Ordinary source search and changed-passage comparison remain available.
   Choose **Preview source brief**, inspect exactly what enters this task, then
   **Put previewed sources in draft**. Only selected lines enter that brief.
8. Continue through the existing Plan, Preview, Promote and Confirm controls
   when you decide to authorize execution. Saving, reopening and applying a
   source brief do not run a model, approve a plan, or accept output.

For a provider-free starting point, open
[`examples/source-project-demo.json`](examples/source-project-demo.json).
It contains one three-line fictional research note and two ordered excerpts.
Move the stop-condition excerpt first, edit its relevance note, preview/apply
the brief, then save the revised project and reopen it. The production test
loads this same fixture and verifies the resumed packet.

## What the file means

- This is `moonclaw.source-project.v1`, an input-authoring file, not a runtime
  checkpoint. It does not contain the composer objective, thread/folder binding,
  gateway URL, access token, approval or execution state. Those are selected and
  reviewed in the current Work context. No browser storage or automatic save
  is added.
- It stores up to eight sources, 256 KiB per local snapshot, 32 KiB per retained
  snapshot, and 1 MiB of combined source content. Up to eight non-overlapping
  excerpts retain a 1024–16384-byte selected-text budget. You can save a working
  set before selecting its first excerpt. A set over its current excerpt budget
  must be narrowed or given a valid larger budget before it can be saved.
- JSON is capped at 8 MiB before a file is read or parsed, allowing the original
  1 MiB source content to expand through JSON escaping. File bytes, source byte
  counts, SHA-256 fingerprints, UTF-8, origins, retained provenance, source keys,
  range bounds, overlaps and budget are checked before replacement. Failure
  preserves the old working set and composer; there is no partial import.
- BOM, CRLF/LF, Unicode and final-newline distinctions in source content survive
  saving and reopening. SHA-256 checks byte consistency, not authenticity.
  Someone who edits both the text and its hash can author a different local
  snapshot; it remains untrusted data and confers no authority.
- Reopened local snapshots are historical copies, never live disk reads.
  Explicitly reimport a local file to get its current bytes. The existing import
  rules drop only stale excerpts when the same named source's bytes change.
  To carry curated notes/order into a revised file, use the explicit
  [local source refresh](REFRESH_SOURCE_EXCERPTS.md) journey instead: review exact
  relocated passages, author replacements or drop obsolete excerpts, preview
  the complete result, then replace unsent source preparation.
- Retained source claims keep exact run/job/artifact/version, digest, logical
  key, content type and original terminal state. A project containing retained
  sources can be restored only in a Work thread linked to that run. Reopening
  itself can work without the gateway, but comparison and the existing source
  brief preview/apply paths reread their selected retained revisions. Changed,
  missing, nonterminal or inaccessible revisions block task preparation. Remove
  an unavailable retained source if you want to continue with only local ones.
- A new file selection, editor/composer edit, cancellation, panel close,
  navigation, access/context change or disposal invalidates prepared saves and
  imports. Late reads cannot replace newer work. Download and replacement each
  consume their preview, so a repeated click cannot silently repeat them.

## Grounding and verification

PRD **MC-W01 / MOONCLAW-B02** asks for reviewable objectives and inputs. This
adds authoring continuity for those inputs. **MC-W02 / MOONCLAW-B04** supplies
the exact retained-source lineage being carried, without qualifying durable
execution/checkpoint recovery. Native inventory statuses remain B02
`unverified` and B04 `partial`.

Before this slice, `FOCUSED_SOURCE_BRIEFS.md` and
`RETAINED_SOURCE_PASSAGES.md` explicitly described unsent sources as tab-only,
lost on reload. `SourceBrief` supported import, curation and brief generation,
but no persisted authoring project. R627's observed-case CSV targets MoonBook
teaching cases and cannot restore this working set.

From the MoonClaw source root:

    node --test ui/rabbita-job/source-project.test.mjs
    node --test ui/rabbita-job/*.test.mjs

Tests execute the production codec and mounted controller, File-like UTF-8
reads, WebCrypto, a Blob/download-boundary harness, and the existing composer
input event. The round-trip disposes the first controller, reopens into a new
surface, edits/reorders, and produces the exact ordinary task packet. Retained
checks use supplied read-only gateway responses. Actual browser layout,
accessibility, OS file picker/download dialogs, production Rabbita bundle
builds, native host restart and configured-provider execution remain unrun.
The existing optional native Book receipt integration is still skipped when
its environment is absent. No broad release gate or requirement is promoted.
