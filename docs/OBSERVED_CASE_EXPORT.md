# Teach from observed outputs

A useful agent makes its work available for later correction. The Work surface
now turns operator-selected retained output into MoonBook's existing observed
teaching-case CSV. This is separate from the existing full Book outcome package:
case CSV prepares concrete task/output examples and literal checks for the
contrasting revision rehearsal, rather than a product-outcome assessment.

## Connected workflow

1. Open a Work thread with a linked terminal run and expand **Teach from observed
   outputs**. **Load linked case outputs**, select a retained UTF-8 output, then
   **Inspect case source**. The gateway-owned run, artifact revision and content
   digest are checked using the existing retained-output primitives.
2. Inspect the entire output. Choose an inclusive first/last line range and
   **Preview exact source lines** if only a relevant passage fits the case.
   Newlines, quoted text, numeric strings and Unicode remain exact. There is no
   silent truncation or semantic selection.
3. Explicitly choose **Useful example** or **Adverse example**, enter a case name,
   copy the actual observed task input, and author the literal required/forbidden
   fragments. Revised output is optional until a fresh candidate is available.
   A successful, failed or cancelled run does not choose the observed label.
4. **Add inspected case**. Inspect the queued row, add further distinct task
   inputs or remove a row. The set contains 1–6 cases.
5. **Preview MoonBook case CSV**, inspect the exact seven fields, then
   **Download inspected case CSV**. Download rereads the terminal run and every
   selected artifact through the existing gateway. Changed status, identity,
   version or bytes blocks download with the prior case set intact.
6. Open the downloaded file as text. In MoonBook, open an existing lesson
   correction → contrasting revision rehearsal → **Import a CSV teaching-case
   set**. Paste the CSV, preview it and explicitly import the exact preview.
   Book requires both useful/adverse coverage and revised outputs before its
   ordinary comparison/staging/review workflow can finish. This panel never
   submits, accepts or adopts a lesson.

The CSV retains source run status, run ID, artifact ID, revision, exact line range
and the full source SHA-256 in each case name. Book treats those as operator case
text, not verified lineage. The original field is the exact chosen passage; the
full source remains owned by MoonClaw. A runtime success does not establish
correctness, capability adoption, customer acceptance or new authority.

## Limits and recovery

The importer contract is exactly:
`kind,name,input,original,revised,required,forbidden`.
CSV quotes are doubled, every data field is quoted, row separators are CRLF and
embedded LF/CRLF text is preserved. No field is interpreted as a formula. Open
as text for Book import: formula-looking evidence is deliberately not rewritten
or neutralized for use in spreadsheet applications.

- Existing retained-source limit: 32 KiB UTF-8 per inspected artifact.
- Case name: up to 80 characters before lineage and 256 total; long identities
  that cannot fit are explicitly rejected, never shortened.
- Input, selected original passage and revised output: up to 8,192 UTF-16 code
  units each. Name, input and original must be nonblank. Revised may be empty.
- Required/forbidden fields: up to 5,140 characters; 1–20 literal fragments in
  total, each at most 256 characters, no blank lines, edge whitespace or
  duplicates. Contradictory required/forbidden fragments are rejected.
- CSV: 1–6 rows and at most 128 KiB UTF-8. Bare CR, binary controls, unpaired
  surrogates and duplicate trimmed task inputs are rejected. Nothing is truncated.
- Form edits, source selection, cancellation and case removal invalidate stale
  asynchronous work. Download/inspect are single-flight. Cancel keeps current
  fields and queued cases; Clear removes only this local set.
- Work thread, run, folder, gateway or access changes clear the old set.
  Collapsing the panel keeps the page-local draft. Reload discards unexported
  cases. An old detached remove control cannot delete a replacement case.
- Download means a browser download was requested, not that disk persistence was
  verified. A browser failure does not report success. Review private source
  text before sharing the downloaded file elsewhere.

## Qualification

The feature is a bounded MOONCLAW-B10 inspection/evidence-export slice and reuses
MOONCLAW-B04 artifact lineage. It does not change their authored requirement
statuses or qualify complete PRD acceptance. No server mutations, provider work,
new tokens, Book adoption, native install or deployment are performed.

Run the existing aggregate `bash scripts/test-source-comparison.sh`. Its glob
includes `observed-cases.test.mjs`, which executes production export functions
and mounted DOM controls, covering valid/invalid cases, exact lexical export,
queued preview, repeated clicks, cancellation, stale reads, changed ownership,
version/content drift and unchanged ordinary task composition. The optional
`MOONCLAW_CASE_FIXTURE` output captures the exact production CSV for a MoonBook
import replay. Minimal DOM tests do not qualify actual browser downloads,
layout/accessibility, compiled/native runtime or live providers; those release
gates remain unrun and unqualified.
