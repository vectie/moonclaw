# Refresh a local source without rebuilding its curated excerpts

Work's **Choose focused source excerpts → Refresh a local source and review its
excerpts** connects saved source preparation to revised local files. It finds
exact old passages at their new line numbers, lets you choose among duplicates,
and lets you explicitly replace or drop changed passages. Kept excerpts retain
their relevance notes and position among excerpts from other sources.

This is input authoring for **MC-W01 / MOONCLAW-B02** and exact snapshot
inspection adjacent to **MC-W02 / MOONCLAW-B04**. No requirement status, runtime
authority, checkpoint recovery, output acceptance or release gate is promoted.

## Try a complete revision journey

1. Open a Work thread and describe the next task in its ordinary composer.
2. In **Save or reopen source preparation**, open
   [`examples/source-refresh/before.json`](examples/source-refresh/before.json)
   and explicitly replace the working set. It selects two passages from a
   fictional `research-note.txt` snapshot. Save your existing work first.
3. Keep that local source selected in **Imported source**. Expand **Refresh a
   local source and review its excerpts** and choose the supplied revised
   [`research-note.txt`](examples/source-refresh/research-note.txt). Use this
   picker, rather than the ordinary import picker: ordinary same-name import
   still drops excerpts when source bytes change.
4. Inspect both full SHA-256 identities and **Inspect every revised line**.
   Every revised line is quoted, exposing whitespace, CRLF and final-newline
   distinctions. The old source and task draft are still untouched.
5. The first old excerpt has no exact match. Enter revised first/last line **3**,
   relevance **Describe the revised retry behavior.**, then **Use revised line
   range**. This is an explicit authored replacement; no fuzzy match was chosen.
6. Choose the second old excerpt. Its exact passage is now at line **4**.
   Choose that range, inspect the surrounding revised text, and **Keep chosen
   exact match**. Its existing relevance note is retained.
7. **Preview refreshed working set** shows the complete proposed project with
   final excerpt order and every source byte. Review the recorded choices and
   this preview, then **Replace source with previewed refresh**. This replaces
   only unsent source preparation. Any existing source block in the task draft
   still contains its previously applied snapshot.
8. Use ordinary **Preview source brief → Put previewed sources in draft** to
   deliberately update that task's inputs. Then save/download a new source
   project if wanted. The result matches
   [`after.json`](examples/source-refresh/after.json); reopen it to continue.
   [`decisions.json`](examples/source-refresh/decisions.json) records the example
   choices for reproducible tests, not an automatically imported instruction file.
9. Use the ordinary Plan, Preview, Promote and Confirm flow if you subsequently
   authorize work. Refreshing sources never plans, sends, approves or runs it.

## Resolve duplicates, deletions and changed meaning

Every old excerpt from the selected local source requires an explicit decision.
Even one exact match is not automatically chosen. Multiple matches remain
separate ranges; old offsets, nearby text and matching names do not choose one.
Exact selected bytes can have a different meaning in new surrounding context.
Review the whole revised snapshot before retaining them.

For a changed passage, choose new inclusive line numbers, write/revise its note,
then **Use revised line range**. The range can also be an exact match if you want
to change its note. **Drop this excerpt** deliberately omits it from the new
selection. You can revisit and replace any recorded decision before previewing.
Editing a range/note field does not record it until its button is clicked; the
decision list shows the choices that will be used.

Unrelated excerpts and sources retain their order, notes and provenance. Drops
close their position; no new unrelated excerpt is inserted. A source without
excerpts can also be refreshed after preview. Identical replacement bytes still
require explicit review of any old excerpts. Refresh the same source again after
saving/reopening; each refresh starts from the currently curated revision.

## Boundaries and interruption behavior

- Refresh is for one local file with exactly the selected local source's name.
  It is not file rename, folder synchronization or a disk freshness check.
  Retained artifacts use their existing exact gateway inspector. A local and a
  retained source with the same displayed name keep separate identities.
- Source limits stay at eight sources, 256 KiB per local file and 1 MiB combined.
  Refresh additionally bounds each old/new snapshot to 2,000 LF-delimited lines.
  Oversized inputs fail without truncation; use ordinary import/manual excerpts.
- Exact matching compares complete lines including endings using a linear KMP
  search per excerpt. BOM, Unicode, CRLF, bare CR, whitespace and final-newline
  distinctions are preserved. All candidates within the bound are offered.
  This is literal relocation, not semantic diff, fuzzy anchoring or a merge.
- Existing eight-excerpt, non-overlap, note, byte-budget and project validation
  runs on the complete proposed result before replacement. Unresolved decisions,
  invalid ranges, overlap or budget overflow leave current preparation intact.
- A new revised-file pick, ordinary source/editor/composer action, project
  save/open, Cancel, either panel closing, disposal or changed thread/folder/
  gateway access invalidates staged refreshes. Late file reads cannot overwrite
  a newer selection. A prepared replacement is consumed once and must still
  match the exact source working set used for preparation.
- No automatic storage or upload is added. Closing/refreshing the tab loses
  unsaved preparation. Explicitly save the old project before replacement if
  you need both revisions. Saved JSON includes full source text and private
  notes, even omitted/unselected text; inspect it before saving or sharing.
- Local digests identify bytes, not authenticity, correctness or permission.
  Historical/failed/cancelled retained origins are preserved and their selected
  revisions still require the normal gateway rereads before task preview/apply.
  Refresh adds no new endpoint, credentials or runtime execution path.

## Verification

From the patched source root:

    node --test ui/rabbita-job/source-refresh.test.mjs
    node --test ui/rabbita-job/*.test.mjs

Tests exercise production codec/controller modules and the mounted Work source
panel through File-like reads, WebCrypto and the ordinary composer input event.
The portable files above are opened by their real paths in the demonstration
test. A separate connected test cold-reopens a project, revises mixed excerpts,
applies the task, saves/reopens and refreshes a second time. Local refresh makes
no gateway request. Retained-source tests verify that ordinary gateway checking
still blocks an altered revision after refresh.

These are minimal-DOM source-level tests. Actual browser rendering,
accessibility, OS file dialogs, the built Vite bundle, native host/provider
execution and broad release qualification remain separate unrun gates.
