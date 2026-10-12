# Compare two feedback passes on the same exported revisions

After reviewers return another pass, compare the two saved feedback collections
without manually matching every note. This extends the existing artifact review
CLI and the [collection workflow](ARTIFACT_FEEDBACK_COLLECTION.md). It compares
reviewer statements, not artifact bytes, runtime completion, or human acceptance.

## Use

With Python 3.9+ and its standard library, first create the two collections using
`collect` as documented. Both must refer to the exact same exported packet:

```sh
python3 tools/artifact_review.py collection-compare review-folder feedback.json feedback-next.json > feedback-progress.json
python3 tools/artifact_review.py collection-compare review-folder feedback.json feedback-next.json --markdown > review-folder/feedback-progress.md
```

Save to new filenames; shell redirection can truncate an input before execution.
Keep Markdown beside the packet's manifest so content/record links resolve.
Copy the packet and collections elsewhere to reopen the comparison; individual
worksheet paths and the original runtime store are unnecessary.

The report retains both collection byte digests, titles, the verified manifest
identity, every artifact's run/job/revision and copied-file references, and both
worksheet digests for every reviewer. Reviewers are matched using the collection's
trimmed, Unicode-casefolded label identity; original labels remain visible.
Reviewer order follows the before collection, with after-only labels appended.
Artifact order is the packet order. Changing only input ordering or JSON formatting
does not create note changes; changed collection/worksheet hashes still disclose
those exact-byte differences.

For each artifact/reviewer pair, `added`, `removed`, `changed` or `unchanged`
describes presence or exact state/note equality. A note edit with an unchanged
state counts as changed. Both complete notes are retained, including Unicode and
line breaks. Markdown escapes supplied text, retaining safe local copied-file
links. Aggregate counts count annotation pairs, not artifacts or resolved tasks.

A reviewer absent from one collection is not presumed to have withdrawn a note
or completed inspection. `needs-changes` becoming `inspected` is merely a reported
checklist transition. There is no automatic resolution, majority, acceptance,
authenticated identity, chronology inference, semantic comparison or transfer of
feedback to another artifact revision. Before/after are the operator's labels.
Use the original collections for independently retained evidence.

## Validation and limits

Both complete collections and every embedded worksheet are verified against the
same packet before output, including unchanged entries. Changed packet content,
a different manifest, changed embedded bytes without matching hashes or repeated
reviewer labels refuse. This uses the existing 1–32-artifact packet verifier,
1–16-reviewer bounds per collection and 16 MiB collection input/output caps.
A union of up to 32 reviewer labels is possible. The Markdown or JSON report
must fit 16 MiB and is buffered before output. Large notes can reach that cap;
no note is silently truncated. Single-reviewer and collection formats are unchanged.

Exit 0 is success, 1 validation/read failure (stderr, no successful stdout), 2
argument error. Output I/O failures can leave partial redirected files. Work from
stable files; reads are not an atomic snapshot against external concurrent edits.
The packet's optional README/checksum-list files are not checked by this reader.
Notes may contain sensitive data; nothing is scrubbed, uploaded, sent, executed
or promoted. Runtime files and input collections remain unchanged.

## Evidence and product boundary

MC-W02 and MOONCLAW-B04/B10 call for exact-revision inspection and honest evidence.
This bounded Python review-progress path adds that capability to existing exported
packets; it does not complete the whole plan/authority/journal/redaction workflow.
`python3 scripts/test-artifact-review-progress.py` exercises actual CLI collection,
comparison, Markdown and relocated reopen with preserved sources and outputs.
Run the existing review and collection tests alongside it. Set
`MOONCLAW_PROGRESS_EVIDENCE` to a fresh directory to retain test evidence there.
No native exporter, MoonBit graph, browser, provider, authentication or full-product
qualification is claimed. R50 remains the last fully verified cumulative baseline;
R51–55 are separate.
