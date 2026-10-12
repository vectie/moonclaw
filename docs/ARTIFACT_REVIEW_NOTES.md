# Keep reviewer notes attached to exact exported revisions

A portable artifact packet can contain an archived draft, a current revision and
binary output from the same run. Keep a separate local review worksheet so a
reviewer can return to each exact copy and record which needs further work.
This extends `export_artifacts` and `review_run` under PRD MC-W02,
MOONCLAW-B04 and B10. It does not change runtime artifact status or implement
human acceptance, which the product contract leaves outside the runtime.

When several reviewers return worksheets, use the
[feedback collection](ARTIFACT_FEEDBACK_COLLECTION.md) to save them together,
inspect every opinion for each revision, and export change-request or pending
inspection views without replacing any reviewer's notes.

For local spreadsheet or CSV editing, use the [CSV review exchange](ARTIFACT_REVIEW_CSV.md)
to preview and import selected note edits without hand-writing JSON.

## Complete local workflow

Use Python 3.9+ with its standard library. No package installation, daemon,
provider, executor configuration or original runtime store is needed. Begin
with an existing packet made by `cmd/export_artifacts`:

```sh
python3 tools/artifact_review.py create review-folder --reviewer 'Alex' > review-initial.json
```

Open the copied files with an appropriate trusted viewer. Save `changes.json`:

```json
{"annotations":[
  {"artifact_id":"revision-old","state":"inspected","note":"Kept for comparison."},
  {"artifact_id":"revision-new","state":"needs-changes","note":"The total omits the last row."}
]}
```

Apply the notes to a new worksheet and generate a readable handoff:

```sh
python3 tools/artifact_review.py annotate review-folder review-initial.json --changes changes.json > review-updated.json
python3 tools/artifact_review.py report review-folder review-updated.json --markdown > review-folder/reviewer-notes.md
python3 tools/artifact_review.py report review-folder review-updated.json > reopened-review.json
```

Use actual artifact IDs from the initial worksheet. Place Markdown beside the
packet's manifest so its copied-content and original-record links resolve.
Move or copy the packet and worksheet together and use `report` at the new
location to reverify the evidence. The original machine's absolute artifact
paths are never followed or included in the worksheet or Markdown. Original
record files themselves still contain that provenance and can be private.

Every invocation reads and verifies the supplied packet's manifest, all original
record copies and all content copies. Each original record must agree with the known typed fields of its manifest
entry; raw-only unknown fields remain covered by the original-record digest; byte count and exact SHA-256 must agree. The worksheet pins the manifest's
exact bytes and the projected artifact identities/digests. Even reformatting the
manifest requires a new worksheet. A changed or missing copied artifact refuses
rather than attaching earlier feedback to a new revision. No feedback is
transferred automatically to another packet.

## Notes and meaning

- `unreviewed`: the reviewer's local checklist has no inspection recorded
- `inspected`: the reviewer says they inspected this copy
- `needs-changes`: the reviewer recorded further work in the note

All entries start unreviewed. Changes replace state and full note for the named
IDs, preserving every other annotation. Clear a note with an empty string.
Edits return a new worksheet on stdout and do not overwrite their input.
There are no `accepted`, `approved`, execute, retry or promotion states.
`reviewer` is a self-entered label, not an authenticated or signed identity.
Anyone who can edit the local JSON can change its notes. Digests establish
consistency with supplied bytes, not authorship, safety or human acceptance.

The worksheet is `moonclaw.artifact-review-notes.v1`, with `reviewer`, `source`
and ordered `annotations`. Its source contains the exact manifest digest,
artifact/run/job IDs, output keys, revisions, producer state, safe portable
member paths, record/content digests and content byte lengths. It intentionally
does not copy arbitrary private record metadata. The Markdown summarizes note
counts, gives each revision its own section and links only the verified local
member names. Untrusted text is escaped; it is not a rich-content renderer.

## Bounds and limitations

The existing export selection bounds apply: 1–32 artifacts, at most 16 MiB per
content file and 64 MiB combined; original records at most 256 KiB. Manifest,
worksheet, edit input and rendered result are capped at 4 MiB. Reviewer labels
are at most 256 Unicode characters, notes 16,384; NUL is rejected. Original
record fields unknown to the typed producer are preserved in the copied record
and covered by its exact digest. Known fields are compared; absent/null optional
logical keys and archive timestamps normalize to null. A missing logical key
is labeled explicitly rather than guessed from a filename. Duplicate JSON keys, nonfinite JSON numbers,
unsafe/duplicate portable paths, symlink members/directories, incorrect totals,
unsupported states and unknown edit IDs refuse. Python 3.9+ is required.

Only numbered `records/N.json` and safe `files/N-name` producer paths are read.
Nothing is extracted, executed, uploaded, promoted or written to the runtime.
The tool does not verify README.txt or SHA256SUMS; use the packet's existing
`sha256sum -c SHA256SUMS` workflow for its complete packaging checks. Work from
stable saved packets: sequential reads and final manifest recheck are not an
atomic snapshot against a concurrent editor. Copies are untrusted inputs, and
viewer safety remains the chosen viewer's responsibility.

Success is exit 0. A validation/read error exits 1 with stderr and no partial
successful stdout. Argument errors exit 2. Check exit status and use new output
paths because shell redirection can truncate a file before the program starts;
output I/O failures can leave a partial file. No secrets are scrubbed from notes,
IDs or original copies. Review any proposed external sharing separately.

## Focused verification

`python3 scripts/test-artifact-review.py` exercises the full create → annotate →
Markdown → relocated reopen workflow on real synthetic export-format files.
It verifies three distinct revisions/outputs including archived and binary
content, links, note preservation, repeatability, unchanged source hashes and
visible refusal of changed or malformed evidence. All fixtures and CLI outputs
are retained in the printed evidence directory; `MOONCLAW_REVIEW_EVIDENCE` can
select a new directory. This qualifies the Python workflow, not a native export
producer rerun, browser, live runtime/provider, authenticated reviewer or whole
product release. R50 remains the last fully verified cumulative checkpoint;
R51–55 are separate.

## Continue inspection after outputs are revised

[Carry prior notes into a new revision](ARTIFACT_REVIEW_TRANSFER.md) explicitly
maps selected comments between two verified packets. It retains both revision
identities and exports a fresh ordinary worksheet with visible prior-note
provenance. Every target starts unreviewed; matching bytes or a prior inspected
state never complete the new inspection.
