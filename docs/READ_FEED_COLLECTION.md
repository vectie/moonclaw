# Search a saved feed collection

To select, reorder, annotate and reopen a durable list from these same local observations, use the separate [reading shortlist workflow](READING_SHORTLIST.md).

`cmd/read_feed_collection` searches local RSS 2.0, Atom and JSON Feed 1/1.1 snapshots together. It produces one paginated reading list with the exact source and supplied observation label on every article. Use this to explore a topic across saved research feeds and export a portable digest without manually querying each feed.

## A complete offline example

The repository includes three small synthetic observations on reserved example domains. No URL is fetched:

```sh
moon run cmd/read_feed_collection --target native -- testdata/feeds/collection/collection.json '{"query":"moon","limit":2}'
moon run cmd/read_feed_collection --target native -- testdata/feeds/collection/collection.json '{"query":"moon","limit":2,"offset":2}'
moon run cmd/read_feed_collection --target native -- testdata/feeds/collection/collection.json '{"query":"moon"}' --markdown > moon-reading.md
```

The first page contains an observatory event and a laboratory article. The second contains a checklist and an archived observing plan. Three articles happen to share publisher ID `shared-1`; all three remain present under their different source identities.

## Supply a collection

Create a local JSON manifest:

```json
{
  "title": "Saved research",
  "sources": [
    {
      "source": "https://publisher.example/feed",
      "label": "Saved 9 October, morning",
      "path": "snapshots/publisher.xml"
    },
    {
      "source": "https://notes.example/feed.json",
      "path": "/absolute/path/notes.json"
    }
  ]
}
```

- `sources` is required and may be empty. Each entry needs a nonblank unique `source` identity and a local `path`.
- Paths are resolved beside the manifest, independently of the command's working directory. Absolute paths are allowed. URI paths, including `file://` and HTTP(S), are rejected; supply an ordinary filesystem path.
- `source` is a caller-supplied logical identity. For XML snapshots, use the original HTTP(S) feed URL when relative article links need a base. The source is never fetched or checked for reachability.
- `label` defaults to `source`; `title` defaults to `Feed collection`. Labels are descriptions supplied by the caller, not verified capture timestamps.
- This is a separate local-snapshot manifest, not an OPML subscription list or resource-provider registry. No registry is installed or edited. Choose files that you are authorized to read and share.

## Explore and export

The optional JSON options are `query`, `source`, `limit` and `offset`. Unknown fields and wrong types are errors.

- `query` is a trimmed case-insensitive substring in article title, normalized summary, publisher ID, URL or publisher date. Source titles and labels are not searched.
- `source` selects one exact supplied source identity. Omit it or use `""` for every source. An unknown identity is an error.
- Filtering happens before pagination. `limit` defaults to 50 and allows 1–50. `offset` is a nonnegative integer; use `next_offset` with the same unchanged manifest, source files and filters.
- Order is manifest order, then each publisher's document order. Dates remain strings. There is no date sorting or deduplication; syndicated URLs and repeated publisher IDs are retained.
- Every article includes `source`, `source_title`, observation `label`, zero-based original `article_index` and the normalized `article` object. The source plus index identifies a position in that supplied document, not a durable identity after edits.
- `total_items` counts every supplied document. `matched_items` and each source's matching count reflect both filters, before pagination. Metadata for all sources remains visible, including those excluded by the source filter.
- Each source's publisher `next_url` is shown on every collection page, but never fetched. A snapshot can be incomplete or stale. No snapshot freshness or completeness is inferred.

JSON is the default stdout format with schema version 1 and ordinary JSON nulls. `--markdown` exports the selected page, escaping caller/publisher text, preserving article provenance and emitting only HTTP(S) article links. Redirection writes to the local file you choose. The command itself reads only and prints no partial JSON/digest if any input fails; errors go to stderr with exit status 1.

## Host API

The `tools/read_feed` package exposes:

- `collect_feeds(Array[FeedSnapshot], title?, query?, source?, limit?, offset?)` for in-memory observations
- `read_feed_collection(manifest_path, query?, source?, limit?, offset?)` for a local manifest and files
- `FeedCollectionPage::to_json()` and `FeedCollectionPage::to_markdown()` for selected-page output

`FeedSnapshot` has public `source`, `label` and `body` fields. The pure API never opens files or fetches URLs. Both entry points validate the whole collection even when a filter or page selects only part of it. A malformed source causes a visible error rather than a silently incomplete result.

## Limits

At most 32 sources, 1 Mi UTF-16 code units of manifest text, 4 Mi per feed document and 16 Mi across feed bodies. Bounds are checked after each whole local file has been read; this is not a streaming or hostile-large-file ingestion interface. JSON duplicate object keys follow the existing JSON parser behavior; source identity strings themselves must be unique. XML and content normalization have the same [single-feed reader limits](READ_FEED.md#content-handling-and-limits), including 2,000-Unicode-character summaries and no HTML-only JSON Feed content extraction.

No network fetching, automatic refresh, caching, authentication, provider dispatch, tool registration, feed subscription state, full article extraction or persistence is added. This command is a bounded local exploration/export workflow, not runtime evidence of job completion or owner acceptance. Verification uses synthetic local fixtures and the existing focused native feed package tests, not a live publisher, remote agent, graphical UI or full runtime suite.
