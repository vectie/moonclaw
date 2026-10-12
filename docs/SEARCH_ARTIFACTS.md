# Find saved outputs and export the exact matches

Use `search_artifacts` to find retained output revisions without remembering
artifact IDs or starting the gateway. Search a saved store by literal text,
inspect line excerpts and producing job/run identity, then collect matching
outputs into a portable folder using the existing artifact-export format.
This workflow is entirely local and does not execute jobs or contact providers.

## Find, inspect, collect

Build `cmd/search_artifacts` with the pinned native environment in BUILD.md.
Run its compiled executable:

```sh
search_artifacts /path/to/store --job release-job --text 'release ready' --format text
search_artifacts /path/to/store --job release-job --text 'release ready' --export /path/to/new-review-folder
cd /path/to/new-review-folder
sha256sum -c SHA256SUMS
```

The first command shows exact artifact IDs, revisions, active/archived state,
job/run/type, byte length, SHA-256 and up to three line excerpts per output.
The second searches again and exports its own observed matches, rechecking their
original-record and content digests before creating the destination. A change
between the separate commands can change the second command's selection; save
its JSON output if you need to retain the search context alongside the export.
The destination parent must exist. The destination must be new and outside the
source store, as for the existing `export_artifacts` command.

To select only some results, use their exact IDs with `export_artifacts` or
`compare_artifacts`. Search is the discovery step; existing exact-ID workflows
remain available. Inspect original content in a trusted viewer before sharing.

## Filters and formats

- `--job ID`, `--run ID`, `--type TYPE`, `--key LOGICAL_KEY` and `--scope SCOPE`
  are exact, case-sensitive metadata filters. All supplied filters must match
- `--status active|archived|all` defaults to `all`. Archived revisions are
  intentionally discoverable. Artifact state does not imply run completion or
  human acceptance
- `--text LITERAL` searches UTF-8 text and JSON bodies. It is case-sensitive,
  with no regex, stemming or whitespace normalization. The literal must contain
  1–128 UTF-16 code units and cannot contain a newline or carriage return
- Without `--text`, catalog any retained MIME type, including empty/binary
  outputs. Every result still identifies the actual content bytes by digest
- `--limit 1..32` controls displayed matches, default 32. Search continues to
  count eligible matches and sets `truncated` if any are omitted. Results are
  sorted by artifact ID, independent of directory enumeration order
- `--format json|text` defaults to JSON. JSON contains `search` and nullable
  `export` members. The search schema is `moonclaw.artifact-search.v1`. Text
  quotes all untrusted strings, making terminal control/newline characters
  visible rather than interpreting them
- `--export NEW_DIRECTORY` exports the complete observed selection. Empty,
  truncated or damaged/incomplete searches cannot be exported this way. Narrow
  the query, inspect the issues, or choose exact IDs with `export_artifacts`

Text matches count matching lines rather than occurrences. Line numbers are
one-based and split on LF (including CRLF files). Each match retains the first
three matching lines, with up to 240 Unicode characters of context around the
first occurrence on that line, plus ellipses for clipped edges. Exact bytes,
including newline style, are preserved by export. Snippets are only previews.

A search with zero matches exits 0. A search with `issues` also exits 0 and
reports partial coverage explicitly; callers must inspect `issues` and
`truncated`, not only the exit code. Invalid options, inaccessible store roots,
hard scan bounds, or unsuccessful export exit 1 with stderr and no stdout
result. A failed export can retain an incomplete destination if writing had
already begun, as documented in [EXPORT_ARTIFACTS.md](EXPORT_ARTIFACTS.md).

## Host API

`@job.search_retained_artifacts(root, query~, text~, limit~)` accepts the existing
`ArtifactQuery`. Omitted text means catalog. `ArtifactSearch::to_text()` renders
human-readable inspection output. `ArtifactSearch::export_selected(destination)`
exports that exact observed selection and refuses changed records/content before
creating output. It reuses the existing portable format rather than introducing
a second artifact archive schema.

## Saved-store behavior and limits

Search reads `artifacts/<id>/record.json` directly. It neither loads nor repairs
`index/artifacts.json`; a missing or malformed index does not hide durable
records. Deletion markers exclude artifacts. Legacy index-only records require
normal runtime recovery to become searchable. A root without an artifacts
directory is an empty catalog. Non-directory entries, malformed/incomplete
records, missing content and invalid UTF-8 text are reported as issues.
Non-text MIME types are counted separately as `excluded_nontext` during text
search, not marked damaged. Metadata records are validated before filters, so
a malformed unrelated record can still make coverage incomplete.

This bounded scanner supports at most 2,048 artifact-directory entries, 256 KiB
per record, 16 MiB per content file and 64 MiB content in a successful scan
after metadata and MIME filtering. The total is checked after each bounded file
read, so a rejected scan can read one additional file of up to 16 MiB. Exceeding the directory or total-scan bound aborts rather
than presenting a partial count. Oversized individual content is reported as
an issue. Up to 32 matches can be returned/exported. Narrow metadata filters to
reduce content scanning. There is no recursive arbitrary filesystem crawl,
full-text index, OCR, semantic search or binary body search.

Use saved or quiescent stores. Digests bind the bytes observed by this command;
this is not a transactional snapshot against concurrent modifications and does
not establish historical immutability or authenticity. It does not redact
content or metadata. Saved content remains runtime evidence, without automatic
acceptance or MoonBook promotion.

## Verification

`job/artifact_search_wbtest.mbt` tests real ArtifactStore-produced revisions,
filters, exact content hashes, archived output, Unicode snippets, invalid UTF-8,
partial checkpoints, source/index preservation, truncated selection and changed
content/metadata before export. Existing artifact-export tests cover the shared
export implementation. `scripts/test-artifact-search-cli.py` exercises compiled
CLI search, catalog, text output, exact portable export and checksum verification,
partial inputs, limits and invalid options with retained synthetic fixtures.
No provider, gateway, installation or full-suite qualification is claimed.
