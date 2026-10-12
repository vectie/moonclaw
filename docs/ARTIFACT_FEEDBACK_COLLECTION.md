# Collect several reviewers' feedback on exact output revisions

An operator can already export artifacts and attach one reviewer's notes to
their exact copies. When several reviewers return worksheets, collect those
independent statements into one saved feedback file. Open an artifact with all
its notes together, or focus on outputs with change requests, mixed checklist
states, or inspection still pending. A reviewer saying `inspected` never hides
another reviewer's `needs-changes` note.

This extends the existing [artifact review](ARTIFACT_REVIEW_NOTES.md) command,
not the runtime job/approval model. It supports the exact-revision inspection
part of PRD MC-W02, MOONCLAW-B04 and B10. It does not qualify full evidence
export/redaction, acceptance, owner recovery controls or runtime execution.

## End-to-end local workflow

Use Python 3.9+ and its standard library. Start with one existing
[portable export](EXPORT_ARTIFACTS.md) and separate worksheets created against
that exact packet. Reviewers use `create`, inspect the copied content in their
chosen trusted viewer, and save notes with `annotate`, as before:

```sh
python3 tools/artifact_review.py create review-folder --reviewer 'Alex' > alex-blank.json
python3 tools/artifact_review.py create review-folder --reviewer 'Bea' > bea-blank.json
```

After each reviewer has returned their final annotated worksheet, collect the
explicit files. These are local files: this command does not request reviews,
send messages or fetch attachments.

```sh
python3 tools/artifact_review.py collect review-folder alex-review.json bea-review.json --title 'Report feedback' > feedback.json
python3 tools/artifact_review.py collection-report review-folder feedback.json > feedback-all.json
python3 tools/artifact_review.py collection-report review-folder feedback.json --markdown > review-folder/feedback.md
python3 tools/artifact_review.py collection-report review-folder feedback.json --focus needs-changes --markdown > review-folder/change-requests.md
python3 tools/artifact_review.py collection-report review-folder feedback.json --focus mixed-states
python3 tools/artifact_review.py collection-report review-folder feedback.json --focus pending
python3 tools/artifact_review.py collection-report review-folder feedback.json --artifact revision-new
```

Use actual artifact IDs from the packet/worksheet. `--artifact` is exact and
case-sensitive; it combines with `--focus` using AND. An absent artifact ID is
an error. A valid selection with no matching rows succeeds and says so.

Save Markdown beside `manifest.json` so the copied-content and original-record
links resolve. The report never links the original machine's absolute paths.
Copy the packet and `feedback.json` to another location, then run
`collection-report` with those new paths. The original worksheet filenames and
original runtime store are not needed: the collection embeds the full exact
UTF-8 JSON text of each supplied worksheet, with its SHA-256. Byte formatting,
Unicode notes and multiline notes survive the collection/reopen roundtrip.

Commands never modify their inputs. Always redirect into new filenames: shell
redirection can truncate an input before the command runs. A failed output
write can leave a partial output file; inspect the exit status before using it.

## Reading the result

The report keeps packet artifact order and input reviewer order. Each artifact
retains its run/job identity, logical output, revision, archived/active producer
state, safe copied paths and digests. Its feedback lists every included
reviewer's label, exact worksheet digest, state and complete note. The JSON
report preserves all note text; Markdown escapes it as inert text and indents
continuation lines. It is not a rich-content renderer.

Views are derived only from the supplied worksheets:

- `needs-changes`: at least one reviewer recorded that state
- `mixed-states`: two or more different checklist states, including unreviewed
- `pending`: at least one included reviewer left the artifact unreviewed
- `all`: every artifact, including archived and binary outputs

The whole-collection summary also counts artifacts where all included reviewers
said `inspected`. Summary counts overlap and always cover the complete supplied
collection, even in a filtered report; `matched_artifacts` counts displayed rows.
Every reviewer remains visible for a displayed artifact, regardless of which
reviewer's state made it match. There is no majority vote, merged note, acceptance
decision, inferred agreement, or suppression of a minority change request.
Different notes under the same state are retained but not semantically compared.
Mixed states can mean an inspection is merely pending, rather than disagreement.

Only included reviewers are counted. An absent reviewer is not an unreviewed
reviewer, and the command knows no expected reviewer roster. `inspected` is a
self-reported checklist state, not approval or acceptance. No checklist state
changes the artifact's recorded status or the current runtime/job state.

## Updating the collection

A collection is a saved snapshot. Editing a source worksheet later has no effect
on it. To incorporate updated feedback, select one intended worksheet per
reviewer and explicitly run `collect` again to a fresh filename:

```sh
python3 tools/artifact_review.py collect review-folder alex-updated.json bea-review.json --title 'Report feedback, second pass' > feedback-next.json
```

Keep earlier collections if their history matters. Combining two worksheet
editions with the same reviewer label refuses, rather than guessing which is
newest. Labels are compared after trimming surrounding whitespace and Unicode
case-folding (`Alex` and ` aLeX ` conflict); the original display labels are
retained. Labels are self-entered, not authenticated identities. Two distinct
people with the same label need distinctly labeled source worksheets before
collection. This is explicit intake, not synchronization or review assignment.

## Validation, format and bounds

Every command reuses the existing packet verifier: the exact manifest and every
copied original record/content file are checked before feedback is returned.
Every embedded worksheet is then validated against that same source, even if
its annotations would not appear in the chosen view. Changed packet bytes,
reformatted manifests, worksheets for another packet, changed embedded text
without a matching digest, invalid review states and repeated reviewer labels
all refuse with no successful stdout. There is no automatic transfer to newer
artifact revisions or another export.

The saved format is `moonclaw.artifact-review-collection.v1`, with `title`,
`source` and ordered `reviews`. A review stores `worksheet_sha256` and
`worksheet_json`, the exact text of a `moonclaw.artifact-review-notes.v1` file.
The report format is `moonclaw.artifact-review-collection-report.v1`; it is a
projection for reading/export, not an input collection. Collection fields are
strict. The existing single-reviewer worksheet schema remains unchanged.

- 1–16 distinct reviewer worksheets; at most 4 MiB each and 8 MiB combined
- Collection input and rendered output each at most 16 MiB
- Title at most 4,096 Unicode characters; the existing label/note bounds apply
- Existing packet bounds: 1–32 artifacts, 16 MiB per content file, 64 MiB total

JSON escaping can make the serialized collection reach its output cap before
the worksheet input cap. All operations buffer bounded data. Success exits 0;
validation/read failures exit 1 with stderr and no partial successful stdout;
argument errors exit 2. Use stable saved files: this is not an atomic snapshot
against concurrent editors. The packet verifier does not check README.txt or
SHA256SUMS; use the export's checksum workflow separately when needed.

Digests detect inconsistent copies; they neither authenticate a reviewer nor
prevent someone from rewriting JSON and recomputing a digest. No signatures,
timestamps, recency choice, identity service or source authenticity is inferred.
The collection includes every supplied note, even for unreviewed outputs. There
is no automatic secret scrubber. Review proposed sharing separately; the command
itself reads only local files and emits stdout. Nothing is executed, uploaded,
accepted, promoted into MoonBook or written to runtime state.

## Focused verification

```sh
python3 scripts/test-artifact-review.py
python3 scripts/test-artifact-review-collection.py
```

The nine new real-file CLI tests exercise collection, exact source retention,
relocated reopen without source worksheet paths, all view types, exact-ID and
empty selections, readable local links, explicit recollection with new feedback,
reviewer ordering and duplicates, stale/wrong packet refusal and bounded inputs.
Every test invocation checks its input files remain unchanged. Fixtures and
stdout/stderr are retained in the printed directory; set
`MOONCLAW_COLLECTION_EVIDENCE` to a new directory to choose its location.

This verifies the Python workflow with synthetic export-format packets and
worksheets produced by the existing CLI. It does not rerun the native exporter,
compile MoonBit, launch a real browser/viewer, authenticate reviewers or qualify
the full product, provider, remote, deployment or hardware lanes. No dependency
installation or network is needed. R50 remains the last fully verified cumulative
checkpoint; R51–55 remain separate.

## Compare feedback passes

Use [feedback progress comparison](ARTIFACT_FEEDBACK_PROGRESS.md) to match reviewer
statements across two saved collections for this same exact packet. The existing
CLI's `collection-compare` returns both states/notes and roster additions/removals,
without inferring resolution or acceptance.

## Compare returns with an expected roster

[Review coverage](ARTIFACT_REVIEW_COVERAGE.md) adds an explicit saved plan of
reviewer/artifact assignments. It distinguishes missing worksheets from returned
unreviewed statements and preserves unassigned feedback. Ordinary collections
remain roster-free; use a plan only when you intend to track expected returns.
