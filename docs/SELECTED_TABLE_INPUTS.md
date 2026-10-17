# Select CSV records and columns for a task

Work → **Choose CSV records and columns** turns a local spreadsheet export into
focused agent input. Choose records and columns explicitly, keep their task
order, inspect every included cell, and put the exact preview in the ordinary
task draft. This avoids pasting a whole table or treating quoted multiline cells
as unrelated text lines. No model, gateway, upload or task is started here.

For cohorts such as Status=waiting AND Owner=Alex, use the integrated
[column filters and bulk selection](FILTER_TABLE_INPUTS.md), then follow the same
column selection and task preview journey below.

## Try the complete journey

The portable [work-items.csv](examples/table-input/work-items.csv) contains three
fictional work items. It deliberately includes a multiline quoted cell, a comma,
leading-zero IDs, formula-like text and an owner column to omit.

1. Open an existing Work thread. In its ordinary composer, write “Summarize the
   selected work items in their chosen order. Do not execute any formulas.”
2. Expand **Choose CSV records and columns** and open `work-items.csv`.
   Nothing is selected by default. Check the filename, source hash and counts.
3. Search for `waiting`, choose original **Record 3**, and inspect its complete
   cells. Choose **Add inspected record**. Search for `multiline`, choose
   **Record 2**, inspect it and add it. Record numbers include the header as
   record 1; multiline data record 2 occupies physical lines 2–3.
4. Choose source **Column 3: Note**, then **Add column**. Add **Column 1: ID**.
   In **Selected columns**, choose ID and move it left. The resulting column
   order is ID, Note; the record order is 3, 2. The owner column and third data
   record will not be included. Filtering never changes this selection.
5. Explain why the selected cells matter, such as “Draft a short status summary
   for these two records. Keep their task order.” Choose an allowed byte budget.
6. Choose **Preview selected table in task**. Read the complete resulting draft,
   including existing task text and the selected table JSON. The sample selection
   matches [expected-selection.json](examples/table-input/expected-selection.json).
   Formula-like text is literal input data; it is not evaluated.
7. Choose **Put previewed table in draft**. This emits the ordinary composer
   input event. Use the existing Plan, Preview, Promote and Confirm controls to
   review scope and authorize only the work you actually want.
8. To revise it, choose a selected record and move it up/down or remove it.
   Choose a selected column and move it left/right or remove it. Edit the
   relevance note or budget, preview again and apply. Reapplying replaces only
   the table block, preserving surrounding task text and other workflow packets.
9. **Remove table block from draft** removes only that block and preserves
   other text, including its explanatory framing. Unsent table selections remain
   available. **Clear unsent table** instead clears imported bytes and selections
   without changing an already-applied task draft.

## Cell and identity semantics

- Input is UTF-8, comma-separated, with one header and at least one data record.
  LF and CRLF record separators, optional leading BOM, quoted commas, doubled
  quotes and multiline quoted cells are supported. Quoted bare CR is literal
  cell text; bare CR outside quoted cells is rejected. Whitespace after a closing
  quote, unclosed quotes and inconsistent column counts are rejected visibly.
  Semicolon/tab-separated formats are not detected or converted.
- Blank and duplicate headers are legal. Columns are identified by original
  one-based position, so “Column 2: Note” and “Column 3: Note” remain distinct.
  There is no guessed ID column, fuzzy row mapping, header deduplication or
  type conversion. Blank strings, leading zeroes, whitespace, Unicode and cell
  line endings survive exactly after CSV quote decoding.
- Source SHA-256 covers the full original file bytes, including BOM, quoting
  and final newline. The packet retains its basename, byte count and source
  dimensions, chosen original column numbers/headers, logical record numbers,
  physical line spans and decoded selected cell text. A separate selection hash
  covers the ordered selected columns/records. Hashes detect byte changes, not
  authenticity, factual correctness, permission, currency or accepted knowledge.
- The packet contains only selected headers/cells plus provenance metadata and
  the relevance note. It does not embed the complete CSV or unselected cells.
  The local record inspector does show all cells before selection; avoid
  displaying sensitive files in a shared screen. Existing task text may already
  contain other private content, and the complete draft preview shows it.
- Full CSV lexical bytes are not in the task packet, so they cannot be rebuilt
  from the selected cells. Keep the original file if later source verification
  matters. Selecting or reimporting a file reads a frozen snapshot; there is no
  disk watch, automatic refresh or live spreadsheet connection.

## Bounds and editing continuity

One file is limited to 256 KiB, 2000 data records and 128 columns. Up to 50
distinct records and 32 distinct columns may enter one packet. Selected headers
and cells have an explicit 1024–16384 UTF-8 byte budget (8192 by default);
this is not a token or cost budget. Metadata adds overhead: packet JSON is
limited to 64 KiB and the full draft to 128 KiB. The entire bounded matching
record list remains reachable; there is no hidden first-100-row cutoff.

File replacement parses and hashes completely before replacing the unsent
selection. A malformed file leaves current selections and the draft intact.
Successful replacement starts with no selected rows/columns. Importing never
changes an already-applied task. Every editor, filter, selection or composer
event invalidates its preview, including edit-and-restore. Apply consumes the
preview; repeated clicks cannot repeat it. A changed saved folder, Work thread,
gateway base or access epoch clears this unsent preparation while keeping the
main draft. Pending reads/hashes cannot win after Cancel, closing the panel,
navigation, unmount, disposal or a newer file selection.

Unsent table preparation is tab-local and is lost on reload or leaving Work.
It is separate from saved text source projects. There is no autosave, new
storage, runtime API, permission, dependency, approval or execution contract.
Already-sent ordinary requests retain their input using the existing host path.

## Grounding and verification

PRD `MC-W01` begins with recording the objective and input references.
`MOONCLAW-B02` asks for inputs attached to the approved plan. This slice supplies
focused, reviewable structured input at the existing draft/plan boundary; it
does not qualify B02's runtime authority enforcement or promote any PRD/native
inventory status. The previous focused-source flow uses LF-delimited ranges;
source projects, same-name refresh and snapshot comparison retain that model.
Review CSV export edits artifact feedback; observed-case CSV exports Book
teaching cases. Neither accepts arbitrary table records as next-task input.

Run from the source root:

    node --test ui/rabbita-job/table-input.test.mjs
    node --test ui/rabbita-job/*.test.mjs

Tests execute the actual parser, packet codec and mounted production controller
with real portable CSV bytes, WebCrypto, a lightweight DOM/File boundary and the
ordinary composer event. They cover multiline/duplicate-header semantics,
literal values, selection order/edits, budget limits, failure preservation,
context changes and interrupted/repeated actions. They do not qualify graphical
browser layout, accessibility, OS picker behavior, native host durability,
configured providers or production authority. These gates remain separate.
