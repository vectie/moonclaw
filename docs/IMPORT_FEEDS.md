# Import an OPML reading list

Move a feed-reader subscription export into MoonClaw without copying each feed URL. `import_feeds` reads a local UTF-8 OPML 1.0, 1.1 or 2.0 document and prints a JSON resource-provider manifest. It does not fetch feeds or change the workspace registry.

```sh
moon run cmd/import_feeds --target native -- subscriptions.opml research > imported-feeds.json
```

The optional prefix defaults to `opml`; choose a distinct prefix when combining collections. Names are sequential (`research-1`, `research-2`, …) in first-occurrence document order, so reordering the input can change names. The output includes:

- `providers`: ready-to-use entries with title, description, endpoint and `read_feed` capability
- `metadata.folders`: the nested folder labels of the first occurrence
- `metadata.read_feed`: ready-to-use tool arguments such as `{"source":"provider://research-1"}`
- collection title, duplicate count, skipped leaf-outline count and unsupported-URL warnings

Review the output. For a **new workspace without a registry**, save the entire output as `.moonsuite/resource-providers.json`; the existing loader accepts the `providers` wrapper. For an existing registry, merge the new `providers` entries into its array, keeping existing entries and choosing unique names. Do not overwrite an existing registry with shell redirection. No automatic merge, persistence or background subscription is performed.

```sh
# Once installed into the chosen workspace's registry:
moon run cmd/read_feed --target native -- /path/to/workspace '{"source":"provider://research-1","query":"climate"}' --markdown > climate-reading.md

# Synthetic collection conversion, requiring no network:
moon run cmd/import_feeds --target native -- testdata/feeds/research.opml research
```

The included fixture uses reserved example domains. Its generated registry is a valid illustrative reading list, but those URLs are not live publishers. The integration test imports a collection, writes its exact manifest into a temporary workspace, reads a loopback HTTP feed through `provider://opml-1`, and exports a digest.

## Conversion rules and limits

Nested `outline` elements with `xmlUrl` become subscriptions; folders are traversed depth-first. `title` takes precedence over `text`; an unnamed feed uses its URL. Duplicate decoded, whitespace-trimmed URL strings keep the first entry and its folder path. No URL normalization, case-folding, query stripping or cross-registry deduplication is performed. The source type is not trusted to determine RSS versus Atom: `read_feed` detects actual content when explicitly called.

Only absolute lowercase `http://` or `https://` endpoints without whitespace or userinfo are imported. Relative, file and other schemes are skipped with a warning. This is basic endpoint screening, not a reachability or comprehensive URI validation check. Private/tokenized feed URLs can contain secrets in their path or query: keep your exported OPML and registry private. The converter never logs rejected URLs.

Non-feed leaf outlines are counted as skipped; folders are not. Unsupported feed outlines are skipped while their nested outlines are still visited. Unknown non-outline XML elements are ignored. The reader supports standard/numeric XML entities, comments and a UTF-8 BOM. DTDs/custom entities, non-UTF-8 input, extension namespaces, subscription state and folder editing are outside scope. XML depth is limited to 64; input parsing is limited to 4 Mi UTF-16 code units after the file has been read into memory. Malformed XML fails the command before emitting a manifest. Empty valid collections produce an empty provider array.

No model, login, paid provider or GUI is needed. Existing runtime permissions still apply when a feed is actually read. Live external publishers, browser interaction and provider-driven jobs are not qualified by the offline and loopback tests.
