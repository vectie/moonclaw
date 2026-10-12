# Curate a saved reading shortlist

`cmd/feed_shortlist` turns saved RSS, Atom and JSON Feed observations into a portable reading catalog. Select articles in your own order, keep private reading notes and `unread` / `reading` / `read` state, then reopen the same article snapshots later. Source files are read only during `capture`. `show`, `catalog`, `edit` and `export` open only the saved archive.

This is an offline artifact workflow building on [saved feed collections](READ_FEED_COLLECTION.md), not a subscription manager, provider operation, new runtime authority or evidence of owner acceptance. No URLs are fetched.

## Capture, select, resume

Build the native `cmd/feed_shortlist` package with the repository's pinned toolchain, private dependencies and an explicit external build target. `BIN` below names that compiled executable. Run these examples from the repository root; they use reserved example domains and synthetic content. `jq` is convenient for selecting IDs but is not required by the MoonBit application.

```sh
"$BIN" capture testdata/feeds/shortlist/collection.json > captured.json
"$BIN" catalog captured.json
"$BIN" catalog captured.json moon
```

Capture retains every article in the supplied collection, including articles beyond the existing collection reader's 50-item page. It initially selects none. Each catalog row shows the full `entry_id`, title, source, observation label, original index, note, state and selected position (one-based, or null).

Choose exact IDs from this saved catalog. `order` is the complete selection in the desired export order; it is not a list of search offsets or publisher IDs. For the included seven-article collection, this creates a three-source list:

```sh
jq '{title:"Weekend Moon reading", order:[.entries[5].entry_id,.entries[2].entry_id,.entries[0].entry_id], annotations:[{entry_id:.entries[5].entry_id,state:"reading",note:"Compare the syndicated account with the observatory original."},{entry_id:.entries[2].entry_id,state:"read",note:"Keep the mineral results for discussion."}]}' captured.json > choices.json
"$BIN" edit captured.json choices.json > weekend.json
"$BIN" show weekend.json > reopened.json
"$BIN" export reopened.json > weekend.md
```

Change selection order by supplying a new `order` array. Deselecting an article keeps its snapshot and annotations in the archive, so selecting its ID later resumes the same notes. An empty array clears the selection. Omit `order` to keep it unchanged. Annotation entries may contain `state`, `note` or both; omitted fields are retained. An empty note clears it. Omit `title` to retain the title. `edit` returns a new archive and never mutates its input file.

Always redirect to a new filename. Shell redirection to an input filename truncates that input before the program can read it. Inspect the new archive before replacing an older one yourself; retain older revisions as needed. Commands emit no partial result on validation failure, use stderr and exit 1. They do not create files or provide a filesystem transaction; your shell or host owns saving stdout.

## What survives source changes

Each saved entry contains an immutable normalized article payload (publisher ID, title, date string, summary and URL) and explicit provenance:

- caller-supplied source identity, observation label and source title
- feed format and original zero-based article position
- SHA-256 of the supplied feed body's UTF-8 encoding
- an `article-` ID derived from the canonical saved payload and provenance

Repeated publisher IDs, repeated URLs and syndicated content across sources remain separate entries. Position is evidence within the hashed observation, never an instruction to reread the current file. Changing, reordering, relabeling or losing source files cannot remap an already saved entry. A new capture produces IDs bound to its own observation. Archive merge below joins only exact snapshot IDs; there is no automatic refresh, fuzzy matching or annotation transfer between changed observations.

## Bring another saved collection into your reading list

Capture another local manifest, or receive another saved archive. Inspect its overlap with your existing list, then combine them:

```sh
"$BIN" capture another-collection.json > incoming.json
"$BIN" inspect-merge weekend.json incoming.json > merge-preview.json
"$BIN" merge weekend.json incoming.json > combined.json
"$BIN" catalog combined.json
"$BIN" export combined.json > combined.md
```

`inspect-merge` lists newly added IDs, shared count, resulting count and every differing state/note pair with existing and incoming values. It checks the 1,000-article count, not the serialized archive size. It creates no archive. Preview contains private notes; review before sharing.

`merge` keeps the first archive's title, existing catalog order and selection order. Incoming-only entries follow in incoming catalog order; incoming selected IDs not already selected append in incoming selection order. An unselected incoming-only article stays unselected. Shared entries are identified by their entire snapshot ID, never publisher ID or URL. Exact overlap is stored once, so repeating the same successful intake is idempotent. Different observations of the same source remain separate even if their article URLs match.

Any shared ID with different state or note fails by default, including a reset to unread or an empty note. After inspecting the preview, choose `merge weekend.json incoming.json keep-existing` or `merge weekend.json incoming.json use-incoming`. The explicit policy chooses the whole state/note pair for every conflict; it does not concatenate notes or infer recency. To resolve conflicts individually, use the existing `edit` operation to align the chosen annotations in a new archive first. Selection union is independent of annotation policy; incoming deselection does not remove existing selections. Use `edit` afterward for your final selection or title.

Both inputs remain unchanged. The union must fit the existing 1,000-entry and 16-Mi-code-unit archive limits; validation failure emits no archive. Always write to a fresh output filename. Merging opens only the two archives, not original feeds, manifests or URLs. It is a local artifact operation, not synchronization or owner acceptance.

The archive stores normalized article snapshots and the source-body hash, not complete raw feed bodies or full articles. Keep original feed files separately if you need to inspect raw source bytes. Labels and dates are caller/publisher assertions, not verified capture time or freshness. The digest detects accidental snapshot edits when reopening; it is not a signature or proof of publisher authenticity. Anyone who can rewrite the archive and recompute hashes can forge one.

## Archive and edit contract

Archive JSON has `schema: "moonclaw.reading-shortlist"`, `schema_version: 1`, `title`, `entries` and `order`. Entries separate `snapshot` from reader-owned `state` and `note`. The parser validates every captured entry, including unselected ones, and verifies IDs before returning the archive. It never silently drops malformed entries. Unsupported versions, unknown fields, duplicate IDs/selections/annotations, missing IDs, bad types, invalid states and snapshot identity mismatches fail visibly. JSON duplicate object keys follow the existing JSON parser behavior.

`edit` accepts only `title`, `order` and `annotations`; annotations accept only `entry_id`, `state` and `note`. Snapshot changes cannot be requested through the edit API. All changes validate before a fresh result is returned, leaving the original value unchanged if any annotation or selection is invalid.

The JSON archive includes the whole captured catalog and notes, including unselected articles. Markdown includes only the ordered selection, its notes/read states and source-bound provenance. Review what you are sharing. Publisher fields and reader notes are escaped as text; note line breaks are collapsed for the digest but preserved exactly in JSON. Only HTTP(S) article URLs are emitted as links, with repeated Markdown destination delimiters escaped.

## Bounds and scope

- Maximum 32 sources per capture, using the existing collection manifest's local-path rules; merged archives may contain observations from more sources within the archive limits
- Manifest 1 Mi UTF-16 code units; each feed body 4 Mi; combined bodies 16 Mi
- Maximum 1,000 captured articles, including unselected entries
- Archive and changes file each 16 Mi UTF-16 code units; title 4,096; each note 16,384
- Summaries retain at most 2,000 Unicode characters, using the existing feed normalization

File size checks happen after whole-file reads, so this is not streaming or hostile-large-file ingestion. The archive size cap can be reached before per-field/count caps. Dates are retained as strings; JSON Feed HTML-only content is not extracted. There is no ranking, automatic deduplication, publisher validation, full article extraction, network request, provider call or runtime/owner-acceptance claim.

## Host API

`tools/read_feed` exposes `capture_reading_shortlist(snapshots, title?)`, `capture_reading_shortlist_file(manifest_path)`, `parse_reading_shortlist(text)` and `read_reading_shortlist(path)`. `ReadingShortlist` has private fields and methods `catalog(query?)`, `edit(changes)`, `preview_merge(incoming)`, `merge(incoming, conflict?)`, `to_archive()`, `to_json()` and `to_markdown()`. JSON and catalog methods produce independent values; ordinary edits cannot modify frozen snapshots.
