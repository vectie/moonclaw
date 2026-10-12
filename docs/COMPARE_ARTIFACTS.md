# Compare retained text-artifact revisions

Review what changed between two exact saved outputs without running their jobs
again. This advances the revision-inspection part of MOONCLAW-B04 and MC-W02.
Existing retained downloads open individual artifacts; this adds a line-level
comparison of two checkpoints, including revisions produced by different runs.

## Local command

After building `cmd/compare_artifacts` for native, run the compiled executable:

```sh
compare_artifacts /path/to/saved-store revision-old revision-new
compare_artifacts /path/to/saved-store revision-old revision-new --markdown
```

The default JSON has schema `moonclaw.artifact-comparison.v1`. Each side contains
the actual retained `ArtifactRecord`, SHA-256 of the loaded content, and byte
length. The comparison includes every line, its original one-based position,
`equal`, `delete`, or `insert`, and its exact ending. Markdown gives the two
identities, runs, versions, digests, counts and only the changed lines. Content
is escaped as inert text, with LF, CRLF and missing-final-newline labels.
Identical text returns explicit zero added/removed counts. Exit status is 0 for
a completed comparison, even when differences exist; invalid/unavailable inputs
return 1 with a diagnostic on stderr and no result on stdout.

The supplied identifiers select `artifacts/<id>/record.json` directly, not a
logical-key "latest" lookup. Both sides must have the same job ID, artifact type
and logical key, matching the existing artifact version series. They may belong
to different runs, may be archived, and may be compared in either direction.
The same ID on both sides is also supported. Missing/malformed checkpoints,
deletion markers, unavailable content and mismatched identities fail visibly.
An index-only legacy artifact needs its normal runtime checkpoint recovery
before using this command; this reader does not repair stores or use stale index
fallbacks. A broken index does not prevent comparing valid durable records.

## Host APIs

- `@job.compare_retained_artifacts(root, left_id, right_id)` reads saved records
- `ArtifactStore::compare_text(left_id, right_id)` uses that store's root but
  still rereads exact durable checkpoints, avoiding stale in-memory metadata
- `@artifact_diff.compare_text(left, right)` is the reusable pure line comparer

The comparer uses a minimal insert/delete longest-common-subsequence alignment;
equal-score choices delete first, making repeated-line alignment deterministic.
Line strings are interned before the bounded alignment matrix is calculated.

## Exactness and limits

- Retained content must be `text/*`, `application/json` or a `+json` media type,
  strict UTF-8, and contain no NUL. Binary and malformed encoding are refused
- Each content file is limited to 1 MiB before allocation, each record to 256 KiB,
  and each decoded text to 2,000 lines. No partial or truncated diff is returned
- The pure String API also limits each input to 1 Mi UTF-16 code units
- LF and CRLF are distinguished. Bare CR remains literal text. A final newline,
  whitespace, Unicode normalization and a UTF-8 BOM are not silently normalized
- Empty text has zero lines; a newline alone has one empty terminated line
- File size is checked on the descriptor used to read it. Metadata/deletion
  changes during loading are checked again. Content must reside in its recorded
  artifact directory. No artifact paths are executed or linked in Markdown
- Use a coherent saved store or quiescent artifacts. Current storage permits
  mutable artifacts and out-of-band file changes; comparison is not an atomic
  two-file snapshot or proof that bytes were immutable since their creation.
  Digests identify exactly the bytes observed in this comparison

The command is local/read-only: it does not call `SystemStore.load`, repair an
index, alter records, rerun work, contact providers, accept an output, or promote
knowledge. JSON includes original metadata and all text; Markdown includes
changed text. Neither is a secret-redaction format. Review before sharing and
redirect output only to a fresh file, never an input or retained artifact.

## Focused tests

Use the round BUILD guide's exact toolchain, dependency graph, external target,
native lock and disk-reserve checks. Tests cover exact producer records, stale
and broken indexes, cross-run lineage, reverse/identical comparisons, missing and
malformed inputs, archived JSON, byte/line limits, binary/encoding rejection,
Unicode, ending-only edits, repeated-line ties and exhaustive small-input
reconstruction. This is bounded local revision review, not full runtime release
qualification, browser UI, tamper-proof storage or owner acceptance.
