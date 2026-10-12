# Edit exact-revision reviewer notes through CSV

Reviewers can now edit the existing artifact worksheet in a local CSV editor or
spreadsheet instead of hand-writing JSON. Export rows, edit `state` and `note`,
preview the changes, and import them into a new ordinary worksheet. That result
works with the existing reports, feedback collection and assignment coverage.
This advances PRD MC-W02 and MOONCLAW-B04/B10's exact-revision inspection;
it does not confer acceptance or execution authority.

## Review, edit and reopen

Python 3.9+ and its standard library are sufficient. Start with an existing
[portable artifact packet](EXPORT_ARTIFACTS.md) and keep the original base
worksheet unchanged:

```sh
python3 tools/artifact_review.py create review-folder --reviewer 'Alex' > base-review.json
python3 tools/artifact_review.py export-csv review-folder base-review.json > review-edit.csv
# Open the copied artifacts in a trusted viewer. Edit the CSV locally.
python3 tools/artifact_review.py import-csv review-folder base-review.json review-edit.csv --preview > proposed-edits.json
python3 tools/artifact_review.py import-csv review-folder base-review.json review-edit.csv > updated-review.json
python3 tools/artifact_review.py report review-folder updated-review.json --markdown > review-folder/reviewer-notes.md
python3 tools/artifact_review.py collect review-folder updated-review.json > feedback.json
```

`--preview` verifies everything and lists full before/after annotations with
exact artifact identities, source/worksheet/CSV digests and selected, changed,
unchanged-selected and omitted counts. Read it before importing. Preview is
optional and does not reserve a snapshot: keep the CSV unchanged between preview
and import. Every import reads and validates the current input bytes again.
Use `updated-review.json` as the base of the next export/edit cycle.

Choose UTF-8, comma separator and double-quote delimiter in your editor's import
dialog. Import **all columns as text**, disable formula evaluation, and retain
embedded line breaks. Save back to UTF-8 CSV, not XLSX. IDs such as `00123` must
stay text. CSV output has quoted fields, CRLF record separators and no BOM;
input also accepts a UTF-8 BOM and reordered columns. Sorting rows is fine.
A spreadsheet may normalize line breaks, strip apostrophes, shorten cells or
coerce identifiers. These applications are not qualified here; retain the
original CSV and inspect the complete preview for any unwanted changes.

## Which cells to edit

- `state`: exactly `unreviewed`, `inspected`, or `needs-changes`
- `note`: complete replacement text, including Unicode, commas, quotes and
  multiple lines. An empty cell clears this row's note.
- All other reference cells must remain unchanged: schema, manifest/worksheet
  digests, reviewer label, artifact/run/job IDs, revision, copied content path
  and content digest. They bind the row to the exact original review.
- `text_prefixed_columns` records the formula-mitigation prefixes described
  below. Adjust it only when deliberately changing an encoded note.

To export only selected artifacts, repeat exact IDs:

```sh
python3 tools/artifact_review.py export-csv review-folder base-review.json --artifact draft-2 --artifact image > selected-edit.csv
```

You can also delete unneeded data rows before importing. Omitted rows retain
their complete existing annotations, and the resulting worksheet keeps original
packet order. At least one row must remain. Duplicate IDs, unknown IDs, missing
columns and malformed rows refuse rather than guessing. Deleting a row never
clears its note or removes the artifact. Review states remain self-reported
checklist observations; `inspected` is not approval.

## Literal text and reversible prefixes

As in the [journal CSV export](JOURNAL_CSV.md), text beginning with `=`, `+`, `-`,
`@`, an apostrophe, tab, CR, LF or BOM after ordinary spaces receives one leading
apostrophe on export. `text_prefixed_columns` lists those column names separated
by semicolons. Import removes exactly one apostrophe from each listed cell.
It never evaluates formulas or strips unlisted apostrophes.

For example, the note `=1+2` exports as `'=1+2`, with `note` listed in
`text_prefixed_columns`. An original `'note` exports as `''note`.

When editing a prefixed note, either retain its one protective leading
apostrophe or remove `note` from the semicolon list and enter the literal new
text. To clear such a note, empty its cell and remove `note` from the list.
Never remove other column names. A listed cell missing its leading apostrophe
refuses with guidance; the importer does not guess what a spreadsheet changed.
New unlisted notes import literally; any later CSV export adds protective
prefixes when needed. This mitigation is not a universal spreadsheet safety
guarantee. Use a trusted editor with formula evaluation disabled.

## Exact source binding and limits

Every command reverifies the packet's manifest and all copied original records
and content, even when only one row is selected. CSV rows pin the exact bytes
of the base worksheet as well as the packet. A later note edit or even JSON
reformatting makes that base different: use the saved original base or export
again. Do not manually repair hashes to bypass a mismatch. There is no merge,
latest-version inference or transfer to different artifact revisions. Use
[explicit note carry-forward](ARTIFACT_REVIEW_TRANSFER.md) for a new packet.

Move the packet, unchanged base and CSV together to reopen on another machine;
original absolute runtime paths are not followed or included in this CSV.
Digests detect inconsistency, not authorship or authorization. A self-entered
reviewer label is not an authenticated identity. Notes and identifiers may
contain private information; no automatic redaction or external sharing occurs.

The exchange is `moonclaw.artifact-review-csv.v1`. Import returns the unchanged
`moonclaw.artifact-review-notes.v1` format; preview uses
`moonclaw.artifact-review-csv-preview.v1`. Input CSV, worksheet and each output
are capped at 4 MiB. Existing bounds apply: 1–32 artifacts, notes up to 16,384
Unicode characters, 16 MiB per content file and 64 MiB total. Overlong notes
refuse rather than truncate. Work from stable files; sequential verification is
not atomic against concurrent edits. Existing packet verification does not
check README.txt or SHA256SUMS; use the packet checksum workflow separately.

Commands write only stdout and never change inputs or runtime state. Redirect
into new filenames: the shell can truncate files before Python runs. Check exit
status before using an output; output I/O failure may leave a partial file.
Success exits 0, validation/read failure 1 with no successful stdout, argument
failure 2.

## Focused verification

```sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-artifact-review-csv.py
```

Ten real-file CLI journeys cover multiline/no-op roundtrip, literal prefixes,
preview/apply followed by collection and coverage, subsets and row/column
reordering, BOM, cleared/omitted notes, relocated reopening, stale bases,
packet drift, changed reference fields, and actionable edit refusals. Every
invocation checks that existing inputs remain byte-for-byte unchanged. Fixtures
and CLI stdout/stderr remain in the printed evidence directory; set
`MOONCLAW_REVIEW_CSV_EVIDENCE` to a fresh directory to choose its location.
The existing 41 review/collection/progress/coverage/transfer tests are also
regressed. Synthetic export-format packets qualify only the Python workflow.
No native export producer, MoonBit compiler, spreadsheet UI, browser, live
runtime/provider or whole-product release was run. R50 remains the last fully
verified cumulative checkpoint; R51–55 are separate.
