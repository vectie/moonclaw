# Read, filter and export public feeds

`read_feed` reads JSON Feed 1/1.1, RSS 2.0 and Atom into the same article fields: ID, title, publisher date, plain-text summary and link. Use it for blog updates, science/news feeds or a small research reading list. No account, model or paid provider is required.

Have an existing feed-reader export? [Import an OPML collection](IMPORT_FEEDS.md) into the same registered-source workflow with `cmd/import_feeds`.

## Try a complete reading workflow

These synthetic samples use reserved example domains and need no network access:

```sh
# Find telescope articles, then read the next matching article.
moon run cmd/read_feed --target native -- . '{"source":"file://testdata/feeds/observatory.rss","query":"telescope","limit":1}'
moon run cmd/read_feed --target native -- . '{"source":"file://testdata/feeds/observatory.rss","query":"telescope","limit":1,"offset":1}'

# Read climate research from Atom and save a portable digest.
moon run cmd/read_feed --target native -- . '{"source":"file://testdata/feeds/research.atom","query":"climate"}' --markdown > climate-reading.md

# JSON Feed remains supported, with the same optional filter.
moon run cmd/read_feed --target native -- . '{"source":"file://testdata/feeds/observatory.json","limit":1}'
```

Replace `source` with a public HTTP(S) feed URL to fetch a real source. The format is detected from the document, not its filename or Content-Type. JSON is the default stdout format; `--markdown` exports only the selected page, including article links, dates and summaries. Errors exit unsuccessfully. Export redirects stdout to a user-selected local file; the feed tool itself only reads.

## Select a topic and explore results

- `query` is an optional case-insensitive substring in article title, returned summary, ID or URL. Leading/trailing spaces are ignored. Clear it to read all articles.
- Filtering happens before pagination, in publisher order. `total_items` counts the whole document; `matched_items` counts filtered articles, and `format` identifies `rss`, `atom` or `json-feed`.
- The default `limit` is 10, allowed 1–50. Use `next_offset` with the same source and query to read the next matching page.
- At the end of the matching items, a publisher's `next_url` is exposed for an explicit next request, including when the current document has no matches. It is never fetched automatically. RSS supports the common Atom `rel="next"` extension.
- Offsets are document-local; a refreshed feed can reorder articles. IDs normally come from JSON Feed `id`, RSS `guid`/link or Atom `id`/link. An XML item without either gets a deterministic content-hash fallback, which can change when its content changes and is not a globally unique durable identity.

## Use registered sources or jobs

Use the same JSON arguments in the existing `read_feed` analysis-job tool. It remains registered alongside `web_fetch` when web fetching is enabled. Existing read-files/read-resource permissions still control `file://` input, including registered file endpoints. No new approval layer is added.

In the existing `.moonsuite/resource-providers.json` registry, a source can point to any supported feed format:

```json
[{"name":"research","title":"Open Research Notes","kind":"atom","endpoint":"file://testdata/feeds/research.atom","capabilities":["read_feed"]}]
```

Then select `{"source":"provider://research","query":"climate"}`. File paths are relative to the selected workspace, or absolute. `read_resource` continues to read the source's metadata as before.

## Content handling and limits

RSS descriptions/content and Atom HTML/XHTML text are converted to readable plain text; publisher markup is never rendered. XML namespaces, CDATA, standard/numeric XML entities, RSS content/DC extensions and relative HTTP(S) links with `xml:base` are supported. Atom alternate links are selected instead of self links. RSS permalink GUIDs can supply a missing article link. Dates remain publisher-provided strings; Atom falls back from `published` to `updated`.

Summaries are capped at 2,000 Unicode characters, and filtering searches that returned summary. JSON Feed summaries prefer `summary`, then `content_text`; its HTML-only content still has an empty summary. Atom binary/external content is not downloaded. Optional dates/links remain absent rather than invented. The Markdown digest escapes publisher text and only emits HTTP(S) article links.

This is a UTF-8, feed-oriented reader, not a general XML/HTML validator or browser. RSS 1.0/RDF, DTDs/custom entities, non-UTF-8 XML encodings, authentication, redirects, caching, full-article extraction, date sorting and automatic archive crawling are outside scope. XML nesting is limited to 64 and documents to 4 Mi UTF-16 code units after reading. HTTP reads time out after 45 seconds, but the transport still reads one whole response before parsing, so this is intended for ordinary feeds rather than bulk downloads.

Tests cover synthetic local HTTP and offline source workflows; no live public publisher, graphical browser, Mac installation or model-driven run is claimed.

## Compare saved observations

Use [Compare two saved feed observations](COMPARE_FEEDS.md) to inspect newly listed, changed visible fields and no-longer-listed articles across two explicit local documents. The offline `cmd/compare_feeds` command exports structured JSON or an escaped Markdown digest; it never infers deletion or fetches publisher archive pages.

## Search multiple saved sources together

Use [Search a saved feed collection](READ_FEED_COLLECTION.md) to explore a topic across explicitly chosen local RSS, Atom and JSON Feed snapshots. `cmd/read_feed_collection` keeps each article's source and observation label, filters before combined pagination, and exports JSON or an escaped reading digest without fetching or updating sources.
