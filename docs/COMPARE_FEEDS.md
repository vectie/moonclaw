# Compare two saved feed observations

Find what is newly listed, what changed, and what is no longer listed between two local copies of the same feed. The comparison includes old and new visible values, then lets you filter, page, and export a reading digest. It works offline with JSON Feed 1/1.1, RSS 2.0, Atom, or a mix of formats.

## Try it

From the repository root:

```sh
moon run cmd/compare_feeds --target native -- \
  https://example.test/feed \
  testdata/feeds/observations/before.rss \
  testdata/feeds/observations/after.atom

# Export the changes as an escaped Markdown digest.
moon run cmd/compare_feeds --target native -- \
  https://example.test/feed \
  testdata/feeds/observations/before.rss \
  testdata/feeds/observations/after.atom --markdown > observation-changes.md

# Read just the telescope correction, including its old and new values.
moon run cmd/compare_feeds --target native -- \
  https://example.test/feed \
  testdata/feeds/observations/before.rss \
  testdata/feeds/observations/after.atom \
  '{"query":"telescope","kind":"changed","limit":10}'
```

The synthetic examples produce one newly listed moonrise article, one changed telescope announcement, one no-longer-listed older talk, and one unchanged sky guide. Reordering the sky guide produces no change. Reserved example URLs are illustrative and are never fetched.

Usage: `compare_feeds SOURCE BEFORE_FILE AFTER_FILE [OPTIONS_JSON] [--markdown]`.

Select the earlier and later raw saved feed documents yourself. `SOURCE` is their shared logical source, preferably the original feed URL; it is used to resolve relative XML links and fallback IDs. The program reads only the two supplied local file paths. It does not verify that the documents came from the same publisher or that their order is chronological. Labels in the output preserve your exact file-path arguments; no capture time is invented. Neither saved `read_feed` result pages nor OPML collections are raw feed observations.

JSON is the default stdout format. Errors exit unsuccessfully, put diagnostics on stderr, and leave stdout empty. Save exports to new files, separate from your inputs. Filesystem reads, output redirection, and optional further sharing remain operator-selected actions.

## Choose the changes to read

- `query`: case-insensitive substring in either the old or new ID, title, visible summary, URL, or date. Surrounding query whitespace is ignored. Default: empty.
- `kind`: `all` (default), `newly_listed`, `changed`, or `no_longer_listed`.
- `limit`: integer from 1 through 50. Default: 50.
- `offset`: nonnegative integer. Default: 0. Follow `next_offset` using the same files, source and filters until it is null.

All entries in both documents participate in the comparison, including entries beyond the reader's 50-item page size. Filtering and result pagination happen afterward. New and changed entries follow the later document's order, then no-longer-listed entries follow the earlier document's order. Unchanged entries are counted, not emitted. Overall counts remain independent of your filter and selected page; `matched_changes` describes the filtered set.

JSON schema version 1 includes source, before/after labels, titles, formats, item counts and publisher next URLs; global category counts; selected changes with ID, kind, old/new articles and `changed_fields`; and filter/pagination fields. Absent old/new articles, optional article values, and exhausted `next_offset` are plain JSON nulls. Markdown includes the same scope/caveat and selected old/new visible values, escaping publisher text.

## What “changed” means

Entries match by exact parsed ID. A changed entry differs in one or more normalized reader-visible fields: `title`, `date_published`, `summary`, or `url`. `changed_fields` names those differences in that order. Dates remain publisher strings; equivalent timestamps with different formatting can differ. Format-specific normalization remains exactly the [existing feed reader's](READ_FEED.md): XML entities/HTML become plain text, whereas JSON Feed strings retain their original text.

Summaries are limited to the first 2,000 Unicode characters. A change only beyond that point is invisible. JSON Feed HTML-only content has no visible summary, so HTML-only edits are also invisible. This is a normalized visible-field comparison, not full-content detection. Feed title/format/next-URL differences appear in before/after metadata but are not article changes. No content hash, publication-date inference, URL fuzzy matching, or cross-ID merging is performed.

Duplicate parsed IDs anywhere in either document are rejected, even when hidden by filters or paging. Empty/whitespace-only IDs are also rejected. Resolve ambiguous source data before comparing. XML entries without publisher IDs/links use the reader's content-hash fallback; content edits can therefore appear as a newly listed entry plus a no-longer-listed one. Stable publisher IDs give the best results.

“No longer listed” means absent from the supplied later document, never proven deleted. Feeds often expose a rolling window. Both publisher `next_url` values are always disclosed, but no next document is fetched or compared. The result covers only your two chosen observations; it is not a publisher-wide inventory or change history.

The existing UTF-8/XML/4-Mi-UTF-16-code-unit document limits apply. Local files are read in full before this parser limit is checked. There is no polling, scheduling, feed download, registry mutation, publishing, new runtime tool, or new permission tier in this command.
