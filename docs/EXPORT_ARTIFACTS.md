# Export a portable retained-artifact selection

Copy exact saved outputs into a local review folder, including text, JSON,
images, PDFs, empty files and arbitrary binary bytes. Select the actual artifact
IDs you want; archived revisions and outputs from different runs/jobs can be
included together. No running gateway or provider is needed.

## Command

Build `cmd/export_artifacts` with the pinned native toolchain, then use the
compiled executable:

```sh
export_artifacts /path/to/saved-store /path/to/new-review-folder revision-old revision-new figure-1
cd /path/to/new-review-folder
sha256sum -c SHA256SUMS
```

The destination parent must exist, and the destination itself must be new and
outside the source store. Existing files/directories are never merged or
replaced. Repeating into another new folder with the same unchanged selection
produces identical bytes. Selection order is preserved. Duplicate IDs are an
error. Successful export prints its manifest as JSON and exits 0; errors print
to stderr, exit 1 and produce no stdout result.

## What you get

- `files/`: exact content bytes, prefixed with a one-based selection number.
  An ASCII-safe form of the original basename is retained (up to 96 characters).
  Numbered prefixes preserve distinct outputs even when filenames collide
- `records/`: the exact original `record.json` bytes for each selection, including
  unknown future fields and original formatting
- `manifest.json`: schema `moonclaw.artifact-export.v1`, original typed artifact
  records, relative output paths, original-record and content SHA-256 values,
  byte lengths and total content bytes
- `README.txt`: plain-text index of job/run identity, logical output, revision,
  archived/active state, filenames and digests. Content is not rendered
- `SHA256SUMS`: standard checksums for all content, original records, README and
  manifest. Verify after copying the folder to another computer; MoonClaw and
  the original store are not needed for this check

Open a copied output in an appropriate trusted viewer. The original absolute
`path` inside each record is provenance, not a location to follow on the
receiving computer. The manifest's relative `content_path` identifies the copy.
Checksums establish byte consistency, not who created the evidence or whether
it is correct. This is a review copy, not a runtime store backup/restore format.
Use [portable artifact import](IMPORT_ARTIFACTS.md) to reopen it as a new
artifact-only inspection store for search, comparison and re-export.

## Host API

`@job.export_retained_artifacts(root, artifact_ids, destination)` and
`ArtifactStore::export_selected(artifact_ids, destination)` implement the same
workflow. The latter rereads durable records, rather than trusting its in-memory
index. `ArtifactExport::to_readme()` renders the plain-text index.

## Exactness and limits

The reader directly loads `artifacts/<id>/record.json`, checks its exact ID and
positive integer revision, refuses deletion markers, and reads the recorded
regular content file inside that artifact directory. Index-only legacy records
need normal runtime recovery before export. A stale or broken index is neither
consulted nor repaired. No MIME restriction, UTF-8 decode, newline normalization,
BOM removal or NUL stripping is applied to content.

At most 32 distinct artifacts, 16 MiB per content file, 64 MiB total content and
256 KiB per original record are supported. File-size bounds are checked on the
same descriptors used for reads. All inputs are loaded and rechecked before
creating the output; an invalid selection leaves no output folder. The command
buffers the bounded selection. Use saved or quiescent stores: this is not a
transactional snapshot across concurrently edited files, nor proof of historical
immutability.

A disk/write failure after output creation may leave an incomplete folder. The
manifest is written last, but an interrupted final write can also be partial.
Treat success as the command's exit 0 plus complete checksum verification.
Preserve an incomplete folder for inspection and retry to a different new path.
There is no crash-durability/fsync guarantee or automatic cleanup.

Export never runs a job, contacts a provider, changes runtime state, accepts an
output or imports it into Book. Original metadata and content may contain
private data; no redaction is applied. Review the entire folder before sharing.
This is distinct from the Book-specific completed-text outcome/interpretation
handoff and from the gateway's single-artifact download.

## Focused verification

`job/artifact_export_wbtest.mbt` exercises actual ArtifactStore-produced binary
and text outputs, cross-run revisions, archived outputs, unknown fields, empty
files, filename collisions, limits and destination/source preservation.
`scripts/test-artifact-export-cli.py` exercises the compiled command, relocated
checksum verification and detection of a changed copy. Fixtures are synthetic
and local. This does not qualify live providers, browsers, gateways, store
restoration, authenticity or human acceptance.
