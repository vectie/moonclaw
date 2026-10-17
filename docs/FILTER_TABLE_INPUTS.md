# Filter CSV task inputs by column

MoonClaw is the shared agent runtime. Its Work table chooser now lets an operator
prepare a specific cohort of records without selecting each row separately.
This extends the existing selected-table input path; the normal Plan, Preview,
Promote and Confirm controls still own execution.

## Worked journey

1. Write a task in the ordinary Work composer. Expand **Choose CSV records and
   columns** and open [work-items.csv](examples/table-filter/work-items.csv).
2. Choose **Column 2: Status**, **Equals**, and type `waiting`. Choose **Add
   column filter (AND)**. Add **Column 3: Owner Equals Alex** the same way.
3. The result is two of four data records: original records 2 and 5. Inspect
   **matching_records**, including their complete literal cells and physical line
   locations. Record 3 contains the word waiting in its note but has status ready;
   record 4 belongs to Sam. Neither qualifies.
4. Choose **Add all matching records in source order** once. Choose the ID and
   Note columns using the existing column selector. Set a relevance note and
   byte budget, preview the complete task, then put it in the ordinary draft.
   Only the selected columns enter that packet; the filter values and omitted
   Owner column do not become a new task input block.
5. Continue through the ordinary planning and authorization controls when ready.
   No task, provider call, upload, or source change occurs during filtering.

## Editing and semantics

- Up to eight filters combine with AND. The existing any-cell search also must
  match. Equals and Contains are case-sensitive literal comparisons with no
  trimming, numeric/date conversion or regular expressions. Is empty means zero
  characters; a space is not empty. Its value field is ignored. Empty Contains
  matches every cell. Any-cell search retains its existing case-insensitive rule.
- Column positions identify duplicate or blank headers. Original logical record
  numbers and physical line spans remain unchanged, including multiline cells.
- Active filters are listed. Remove one or clear all and inspect the new matches.
  Filter changes never add/remove selected records. Unsent filters are lost on
  reload, changing Work context, or importing a replacement CSV successfully.
- Bulk addition preserves existing selection order, skips already selected IDs,
  and appends new matches in source order. If the combined selection would exceed
  the existing 50-record limit, it rejects the whole addition without truncation.
  Narrow filters or remove selected records before retrying. Zero matches adds
  nothing. The selected cell byte budget is still enforced at task preview.
- Selecting an already selected record for inspection clears search and filters
  so that the selected original record remains reachable in the inspector.
- Editing filters invalidates an unapplied task preview. Previously applied
  task text remains a frozen snapshot until explicitly previewed and applied
  again. Filters themselves neither certify completeness nor infer relevance.

## Efficiency and verification

For N matching records, the bulk action replaces N individual Add record actions
with one after cohort preparation. This is a deterministic interaction reduction;
it does not establish model quality, token savings, or autonomous performance.

The production controller test opens the worked fixture, adds both predicates,
inspects matches, bulk-selects, chooses columns, previews, applies and reads back
the exact selected-table packet. Focused tests cover original IDs, AND/search
composition, multiline text, leading-zero strings, duplicate headers, empty vs
space, ordered deduplication, atomic selection-limit failure, editing and context
reset. Tests use the existing minimal DOM fixture, not a graphical browser.

Run `node --test ui/rabbita-job/table-input.test.mjs` from the source root.
No MoonBit source or generated interface changes are required. Assembled dist,
browser layout/accessibility, native product compilation, live gateway/provider
execution and full release gates remain unrun for this change.
