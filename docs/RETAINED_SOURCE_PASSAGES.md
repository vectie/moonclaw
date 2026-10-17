# Build next-task evidence from retained outputs

In **Work → Choose focused source excerpts**, an operator can bring selected
passages from the linked terminal run into a new ordinary task, alongside local
UTF-8 sources. The existing exact-output revision panel still supports whole
output rework; this flow supports a different job: curate several useful pieces
of evidence from one or more retained outputs without download/reupload.

## Connected workflow

1. Write the next objective in the ordinary Work composer.
2. Choose **Load linked run outputs**. The existing linked run must be Succeeded,
   Failed or Cancelled. Its identity, job and actual terminal status are shown.
3. Choose a retained textual output and **Inspect and add retained source**.
   The R581 exact reader verifies inventory identity, revision, content type and
   the host-owned SHA-256 against the complete retained UTF-8 content. Synthetic,
   binary, oversized, NUL-containing and malformed text cannot become sources.
4. Inspect numbered lines or use literal search. Select inclusive line ranges,
   supply relevance notes, and repeat with several passages or outputs. Local
   file snapshots can be added through the existing picker. Same-named local
   and retained sources stay separate; source selectors identify their origin.
5. Edit, reorder and remove passages within the shared selected-text byte budget.
   Selections display their exact text, producing run/job, revision and digest.
6. **Preview source brief** rereads the linked run and every selected retained
   source, once per source. Any changed identity, revision, digest, logical key,
   content type or terminal status refuses preview and keeps the draft.
7. Review the whole proposed composer text. **Put previewed sources in draft**
   performs those exact reads again, then applies precisely the previewed text
   using the ordinary composer input event. It does not dispatch a plan or job.
   Use the existing Plan, Preview, Promote and Confirm controls to approve work.
8. Reload and inspect changed revisions explicitly. Reimporting a changed
   revision removes only that source's stale excerpts, even if its bytes stayed
   identical. Reapplying replaces only the focused-source block; removing it
   preserves surrounding task restrictions and other workflow packets.

## Exactness and authority

- The existing R581 `readRun`, `textArtifacts` and `readSource` are reused.
  The only network requests are read-only, no-store GETs to the already-existing
  `/v1/jobs/runs/{id}` and `/v1/artifacts/{id}` endpoints. IDs are URL encoded;
  redirects are refused. No endpoint, upload, model/provider call or effect was
  added. Source text is rendered as text, never HTML.
- Retained full text is limited to 32 KiB by the exact reader. Local text keeps
  its 256 KiB/file limit. The combined working set is at most eight sources and
  1 MiB. Up to eight non-overlapping excerpts share the 1024–16384-byte selected
  text budget (8192 default). JSON is limited to 64 KiB; the composed draft to
  128 KiB. These are UTF-8 byte bounds, not token, price or runtime context bounds.
- A retained excerpt carries run, job, artifact, version, content type, logical
  key, original terminal status, full-source digest/byte/line counts, exact line
  range and excerpt digest. Failed/cancelled outputs retain their labels; none
  of this establishes correctness, accepted knowledge or execution authority.
- Local-only packets remain `moonclaw.focused-sources.v1`. Packets containing
  retained sources use `moonclaw.focused-sources.v2`, with retained-only or mixed
  origin and per-source provenance. The existing source-block delimiters remain
  stable so reapplication can replace old local packets. Legacy v1 packets
  without explicit source keys remain readable. Mixed packets cannot claim v1.
- Rereads establish exactness at preparation/application time; they are not a
  lease or a promise about future changes after the packet enters the draft.
  Already-applied text remains an explicitly identified historical snapshot.
- Any task/folder/run/gateway/access change clears unsent sources. Range, note,
  search, selection, budget or composer edits invalidate the preview. Pending
  requests use AbortController and generation guards; late results after Cancel,
  closing the source panel,
  navigation, newer imports, or A→B→A changes cannot overwrite current work.
  Repeated clicks share a single pending operation. A failed read preserves the
  composer and curated working set; removing retained excerpts allows local-only
  preparation to continue without a gateway.
- Unsent sources are tab-local. Explicitly [save and reopen a source project](SOURCE_PROJECTS.md)
  to resume their curation after reload/navigation; reopened retained claims
  still require exact gateway rereads. Applied evidence persists only through
  the existing ordinary sent request, with no new automatic store.

## PRD and evidence boundary

This implements the input/reference authoring slice of **MC-W01 / MOONCLAW-B02**
and the exact producing-revision inspection/continuity slice of **MC-W02 /
MOONCLAW-B04**. It does not newly qualify runtime approval enforcement, durable
execution, checkpoint persistence/recovery, live provider execution or acceptance.

The connection is source-grounded in `main/cowork_surface.mbt` and its existing
`SetCoworkComposer` input handler, the R581 exact reader, and
`gateway/server/handler.mbt: handle_get_artifact` (host-owned revision source).
No MoonBit source or interface was changed.

Run `node --test ui/rabbita-job/retained-sources.test.mjs
ui/rabbita-job/source-brief.test.mjs` for production-module/controller tests, or
`node --test ui/rabbita-job/*.test.mjs` for adjacent regressions. Tests cover the
complete mixed-source journey and stale identity/bytes, same-name collisions,
version-only changes, limits, provenance, read failures, cancellation, repeated
interaction, changing context and draft protection. The lightweight DOM harness
uses real WebCrypto and File-like UTF-8 bytes; it does not establish graphical
browser rendering/accessibility, native host restart, built production bundles,
configured provider execution, end-user speed or result quality.
