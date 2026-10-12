# Review a saved run with its exported outputs

Put a run's journal and exact output revisions into one readable review. This
joins the existing saved journal and portable artifact export formats, without
starting a job or reopening its original runtime store. A reviewer can read what
was recorded, see archived and current revisions together, and open each selected
copied file or its original record from the same Markdown document.

## Use

Build `cmd/review_run` as described in BUILD.md. Select artifacts using the
existing `export_artifacts` workflow, and keep saved `events.jsonl` journals.
Run the compiled command with an explicit run ID and the export's manifest:

```sh
review_run saved/events.jsonl --artifacts review-folder/manifest.json --run run-17 > run-17.json
review_run saved/parent.jsonl saved/child.jsonl --artifacts review-folder/manifest.json --run run-17 --markdown > review-folder/run-17.md
review_run --help
```

Choose a new output filename; shell redirection can overwrite a file before
MoonClaw starts. Save Markdown beside the manifest, so its relative `files/...`
and `records/...` links resolve. Open copied content in a trusted appropriate
viewer. The document never links the original machine's absolute content path.
Run `sha256sum -c SHA256SUMS` in the export directory separately to verify the
existing packet. This review command reads only the explicit journals and
manifest. It does not read referenced content or original record files and does
not authenticate or verify their checksums, even when they are present.

## What the review contains

- Exact run and job identity, selected event/output counts and declared bytes
- Counts of events and artifacts excluded because they name other runs
- Every matching event in stored timestamp order, with input order breaking ties,
  original filename and one-based physical line number
- All matching export entries in manifest order, including archived revisions,
  logical output key, type, content type, scope, metadata, recorded status,
  creation/archive timestamps, declared byte count and SHA-256 values
- Links to the portable copied content and original record, and each entry's
  one-based position in the manifest
- Explicit notes when either journal observations or output revisions for the
  selected run were absent from the supplied selection

The JSON schema is `moonclaw.run-review.v1`. `events[].record` and
`artifacts[].entry` preserve parsed original JSON, including unknown fields.
Whitespace, duplicate JSON-key spelling, and original serialization are not
preserved. Full event `data` and unknown fields stay in JSON; Markdown presents
messages, statuses, source locations and output metadata. Every review says
`content_verification: "not_checked"`.

The host API is:

```moonbit
let entries = @job_journal.parse_journal(saved_text, source="events.jsonl")
let review = @job_journal.review_run(
  entries,
  manifest_text,
  manifest_source="review-folder/manifest.json",
  run_id="run-17",
)
let json = review.to_json()
let markdown = review.to_markdown()
```

## Matching and interpretation

Run IDs match exactly and case-sensitively. All matching events and output
records must name one consistent, nonblank job ID; disagreement is refused.
The selected run must occur in at least one input. An empty journal is allowed
for an artifact-only review. If a journal-only run has no artifacts in the
supplied export, it remains reviewable with an explicit missing-selection note.
The export itself must contain 1–32 entries, as required by its v1 producer.

Repeated journal observations are retained. Revisions are never collapsed to a
single "latest" output or joined to individual steps by guessed timing. An
artifact can be created outside the supplied event time span. No event status,
including Succeeded, means that this report knows the current run state or owner
acceptance. Unknown states remain visible. Empty selected evidence on one side
means none was supplied, not that no work or output existed.

This is a selection, not a complete run archive. Plans and authority references
are included only when they already occur in the original supplied records.
The report neither invents them nor claims to fulfill the PRD's entire evidence
export, recovery or release qualification requirements.

## Bounds and errors

The CLI accepts 1–32 distinct explicit journal filename arguments, each at most
4 Mi UTF-16 code units, and at most 10,000 total events. The artifact manifest has
the same 4 Mi-code-unit text limit and supports the producer's 1–32 artifacts,
16 MiB per declared content file and 64 MiB declared total. Files are loaded
before text limits are checked. Separate paths to the same file are not detected
as aliases; avoid supplying both.

All journal events and all manifest entries are validated, including unselected
runs. Fractional integer fields, duplicate artifact IDs, unsupported schema,
invalid declared digests, inconsistent totals, unsafe portable member paths,
malformed fields and conflicting selected run/job identity fail visibly.
Member-path validation permits only numbered safe portable filenames for links;
it does not prove the original record's path or bytes match that filename.

Errors exit 1, write stderr and produce no partial stdout. Success exits 0.
Inputs and runtime state are never changed. Use stable saved files: reading them
is not an atomic snapshot of a concurrent runtime or artifact exporter.

Nothing is uploaded, executed, retried, accepted or promoted into MoonBook.
No secrets are scrubbed. Journals, metadata, original paths and file contents may
be private; inspect the entire packet before sharing it. Checksums establish
consistency, not authorship or trustworthiness.

## Focused evidence

Six new API tests cover exact joins, revisions, partial selections, ambiguous
identity, all-entry validation, original JSON preservation and inert Markdown.
All 20 tests in `job_journal` pass with the pinned JS target. The practical native
script `scripts/test-run-review-cli.py BINARY NEW_OUTPUT_DIRECTORY` retains
synthetic journals and a real-file portable packet, checks JSON/Markdown, opens
all generated relative link targets, externally verifies checksums, confirms
unchanged inputs and tests errors. Detached manifests explicitly remain
unverified. These are local fixture observations, not live-provider execution,
whole-runtime or human usability qualification.
