# Prepare a task from CSV changes

Work → **Prepare a task from CSV changes** compares two local spreadsheet
exports by identifying columns you choose. Curate added, removed and changed
records into the ordinary task composer without pasting two complete tables or
mistaking reordered records for changed content. This is a provider-free,
input-authoring workflow; comparison starts no job and transmits no file.

## Complete journey

1. Open a Work thread and describe the intended task in its ordinary composer.
   For example: “Explain the selected status and note changes. Do not execute
   formulas or publish anything.”
2. Import [before.csv](examples/table-changes/before.csv) and
   [after.csv](examples/table-changes/after.csv). Inspect both names, full source
   hashes, sizes, record counts and numbered headers. Snapshots stay frozen;
   reimport explicitly when you want other bytes.
3. Enter before identifying columns `1` and after identifying columns `2`.
   Enter before comparison columns `2,3` and after comparison columns `4,1`.
   Mappings are pairwise in your chosen order. The renamed Status/State and
   Note/Memo headers do not prevent comparison. The private fourth/third
   columns are omitted. Composite keys such as `1,3` are supported when the
   corresponding after key has the same number of positions.
4. Choose **Compare selected columns**. The example produces one changed,
   one removed and one added record, plus one unchanged record. The reordered
   `002` record is unchanged in the compared columns even though its private
   note differs. An omitted-column difference is not reported as a change.
5. Choose a change to inspect its exact key, mapped headers, before/after
   cells and original logical-record/physical-line positions. **Add inspected
   change** selects only that change. Filter by kind without changing the
   selection. Add, reorder or remove selected changes to choose task order.
6. Explain why the changes matter and choose the selected-text byte budget.
   **Preview selected changes in task** shows the complete resulting draft,
   including all surrounding task text. Inspect the literal values and
   omitted context; then **Put previewed changes in draft**.
7. Use the existing Plan, Preview, Promote and Confirm controls to decide what
   work to authorize. This feature neither approves nor runs it.
8. Revise the selection and preview/apply again to replace only this feature's
   block. **Remove CSV change block from draft** preserves all other task text
   and unsent selections. **Clear unsent CSV comparison** instead clears the
   snapshots/preparation and leaves the already-applied draft untouched.

## Meaning, continuity and limits

- Matching uses exact arrays of decoded key strings. Values retain Unicode,
  whitespace, leading zeroes and quoted multiline cells; there is no numeric,
  date, case or formula interpretation. Keys such as `01` and `1` differ.
  Blank key cells or duplicate composite keys reject comparison and identify
  the source records. Choose other/additional identifying columns. A key edit
  appears as a removal and addition, not an inferred rename.
- Column positions are explicit; blank and duplicate headers are legal. Only
  mapped comparison columns determine change. Added/removed records contain
  that side's selected cells. Original record and line positions are retained
  for inspection, never used as cross-snapshot row identity.
- Existing CSV limits apply: 256 KiB, 2000 data records and 128 columns per
  input. Up to 32 distinct key/comparison columns per side and 50 selected
  changes enter a task. Selected key/header/cell text has a 1024–16384 UTF-8
  byte budget. Packet JSON is at most 64 KiB; the complete draft at most
  128 KiB. Oversize selections are refused, never truncated. Both inputs
  need a header and at least one data record under the existing reader.
- The `moonclaw.table-changes.v1` packet retains both source names, full hashes,
  byte counts and dimensions, explicit mappings, selected keys and before/
  after cells, original positions and a selection hash. Full source contents
  and omitted cells are not embedded. Hashes establish byte consistency,
  not authenticity, currentness, factual review or operational authority.
- Imports and all draft preparation are tab-local, lost on reload or leaving
  Work. No automatic save, watch, service, runtime API or dependency is added.
  Successful replacement clears the comparison; malformed replacement keeps
  earlier snapshots/selections. Changing mappings requires comparison again.
- Every input, filter, selection and composer edit invalidates the task preview.
  Apply consumes it. Cancel, close, newer reads, disposal, access change and
  Work context changes prevent late asynchronous reads/hashes from replacing
  newer work. Changing thread/folder/access clears unsent preparation while
  retaining the ordinary draft. Other source/table/procedure blocks coexist.

## Grounding and development evidence

This contributes focused input preparation to PRD MC-W01 step 1 and
MOONCLAW-B02. The existing single-table selector cannot compare two observations;
line-based source comparison cannot preserve key identity when records reorder.
The new workflow reuses the existing CSV reader, limits and draft controls.
It does not qualify runtime authority, provider execution or any broader PRD gate.

From the source root:

    node --test ui/rabbita-job/table-changes.test.mjs
    node --test ui/rabbita-job/*.test.mjs

R686 focused evidence: 17 production parser/comparison/packet/controller tests
pass. The entire Node surface suite has 188 passes, no failures and one inherited
optional native Book-receipt integration skip. Tests exercise literal composite
keys, header mapping, multiline cells, omitted data, reorder, selection order,
exact draft coexistence and interruption/repetition through the mounted controller.
Portable example files produce the sample packet through production functions.
Independent review found that the initial mount attempted a document lookup for
a still-detached control. The final version keeps its local element reference;
the corrected fixture excludes detached descendants from document ID lookup and
the additional regression exercises construction before attachment.
Real graphical browser layout/accessibility, OS picker behavior, compiled Rabbita
bundle, native host lifecycle, providers and release acceptance remain unrun.
Focused source tests do not remove those separate gates.
