# Reopen a portable artifact export for inspection

Copy a MoonClaw artifact export to this computer, import it into a new local
inspection folder, then use the existing search, comparison and export tools.
The original runtime store and original absolute content paths are not needed.
This completes the portable review loop without restarting any producing job.

## Export, transfer, import, inspect

Build `cmd/import_artifacts` and the existing artifact commands with the pinned
native toolchain. Use their compiled executables:

```sh
export_artifacts /path/to/saved-store /path/to/portable old-revision new-revision figure
# Copy the portable folder to the reviewing computer using your chosen method.
import_artifacts /path/to/received-folder /path/to/new-inspection-store
search_artifacts /path/to/new-inspection-store --format text
search_artifacts /path/to/new-inspection-store --text 'ready' --format json
compare_artifacts /path/to/new-inspection-store old-revision new-revision --markdown
search_artifacts /path/to/new-inspection-store --text 'ready' --export /path/to/selected
```

An inspection folder is artifact-only. It contains no restored jobs, plans,
execution authority, journals, memories or acceptance state. Do not use it as a
runtime backup or merge it into an active runtime store. Active/Archived are
original artifact states, not execution or human review outcomes.

## Identity and useful output

- IDs, revisions, producing jobs/runs, scopes, metadata, timestamps and original
  Active/Archived states remain unchanged. Binary, empty and UTF-8 content bytes
  are copied exactly, including BOMs and newline styles
- `artifacts/<id>/content.bin` holds each local content copy. Its MIME type stays
  in the record. `artifacts/<id>/record.json` preserves all original JSON fields,
  including unknown fields, changing only `path` to the local copy. Its formatting
  and record checksum therefore change
- `provenance/records/<n>.json` retains each exact original record, including its
  original path and formatting. Those original paths are never opened by import
- `provenance/manifest.json` retains the exact source manifest
- `import.json` reports schema `moonclaw.artifact-import.v1`, source manifest
  digest, relocated records/digests, original record paths/digests, content
  digests/lengths and total content bytes. The command also prints this JSON
- `README.txt` explains the inspection boundary. Existing saved-store tools read
  durable records directly; no index, running gateway or provider is required

Re-export preserves IDs, revisions and content bytes but exports the relocated
inspection records. Its record digests and paths therefore differ from the
first packet. Keep the original packet or the inspection store's provenance
folder when original-record provenance must travel with your review. Neither
import nor re-export implies authenticity, output acceptance or Book promotion.

## Input format, conflicts and limits

Input must be an existing `moonclaw.artifact-export.v1` directory produced by
`export_artifacts` or search's `--export`: `manifest.json`, numbered
`records/<n>.json`, and `files/<n>-<safe-original-basename>`. Import validates
manifest metadata against each original record, record/content SHA-256 digests,
exact integer revision/length fields and aggregate length. It reads only the
manifest and its listed members, never original absolute record paths. Members
that resolve outside the packet are refused. Extra files are not imported.

The manifest is the checksum reference. Import does not authenticate it or use
`SHA256SUMS` as an independent trust root. You can additionally run
`sha256sum -c SHA256SUMS` inside the received packet to check the original full
review folder, including README and manifest. Modified data and matching
modified checksums cannot establish the producer's authenticity.

A destination's parent must already exist. The destination must be new and
outside the packet. Existing destinations, duplicate IDs (even with identical
content), malformed metadata, missing members and mismatched bytes are refused.
Nothing is merged, overwritten, assigned a fresh ID or silently renumbered.
Repeat into another new folder when you intentionally want another review copy.

Limits: 1–32 entries, a 16 MiB manifest, 256 KiB per original record, 16 MiB per
content file, and 64 MiB total content. Relocated records must still fit the
256 KiB saved-store inspection limit. The bounded selection is buffered and
validated before output creation. Use saved, quiescent packets; this is an
observed copy, not a live filesystem transaction. All original fields and
content are retained without redaction; review before sharing.

Success prints the import receipt and exits 0. Invalid inputs/options or write
failures print an error to stderr, leave stdout empty, and exit 1. `import.json`
is written last. A write interruption may leave an incomplete directory or a
partial receipt; success requires exit 0, not simply presence of that filename.
There is no fsync guarantee or automatic cleanup. Keep an incomplete folder for
inspection and retry into a different new path.

## Host API and verification

`@job.import_artifact_export(packet, destination)` provides the same workflow
and returns `ArtifactImport`. Public export types now support FromJson for
portable manifest readers. Parsing alone does not perform import validation.

`job/artifact_import_wbtest.mbt` exercises actual ArtifactStore-produced revisions,
archived state, exact lineage, search, comparison, re-export and artifact-only
recovery. `scripts/test-artifact-import-cli.py` drives compiled commands through
export, relocation with unavailable original paths, import, inspect/search,
comparison and re-export. It also checks unknown-field preservation, binary and
empty data, source preservation, conflicts and invalid packets. These are local
synthetic tests; live providers, remote control, installation and full-suite
qualification are outside this workflow.
