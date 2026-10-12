# Discover feed subscriptions from a saved publisher page

A publisher page often advertises RSS, Atom or JSON Feed without showing a visible subscription button. `discover_feeds` extracts those candidates from a local UTF-8 HTML file, resolves their addresses against the original page URL, and prints a reviewable resource-provider manifest. You do not need an OPML export or a hand-copied feed address.

From the MoonClaw repository root, first select the pinned toolchain, private process paths and an external build target. All Moon recipes below use this environment, the frozen graph and the shared native lock:

```sh
export MOON_HOME=/workspace/scratch/665adc5202cf/.moonsuite-background/recovery-20261008/tooling/moon
export PATH=$MOON_HOME/bin:/usr/local/bin:/usr/bin:/bin
export ROUND_DIR="$(cd .. && pwd)"
export MOON_TARGET_DIR="$ROUND_DIR/build"
export NATIVE_LOCK=/workspace/scratch/665adc5202cf/.moonsuite-background/recovery-20261008/native-build.lock
export HOME="$ROUND_DIR/evidence/home" MOON_DEP_CACHE=off MOON_BUILD_CACHE=off
export XDG_CACHE_HOME="$ROUND_DIR/evidence/xdg-cache" XDG_CONFIG_HOME="$ROUND_DIR/evidence/xdg-config"
export XDG_DATA_HOME="$ROUND_DIR/evidence/xdg-data" XDG_STATE_HOME="$ROUND_DIR/evidence/xdg-state"
export XDG_RUNTIME_DIR="$ROUND_DIR/evidence/xdg-runtime"
mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
```

```sh
flock "$NATIVE_LOCK" moon run cmd/discover_feeds --frozen --target native --strip -j 1 --target-dir "$MOON_TARGET_DIR" -- saved-page.html https://publisher.example/news/ research > discovered-feeds.json
```

The command never fetches the page or any candidate, never executes scripts, and never modifies a workspace registry. Supply the original page URL explicitly: the saved local filename cannot establish the publisher's URL. Use the URL after any redirects that occurred when saving the page. Errors exit 1 with a diagnostic on stderr and no manifest on stdout.

The output contains:

- `page_url`: the supplied page URL, with its fragment removed
- `base_url`: the effective first base address; this JSON key is omitted if the first base is unsupported (the host API returns `None`)
- `providers`: entries compatible with the existing resource-provider registry, including endpoint, title, declared MIME type, source-page reference and ready-to-use `read_feed` arguments
- `duplicate_links`, `rejected_links`, and warnings for unsupported candidate URLs

Names default to `html-1`, `html-2`, and so on in first-candidate document order. The optional prefix accepts 1–64 ASCII letters, digits, underscores or hyphens. The first of multiple links resolving to the exact same URL wins, including its title. Fragments are removed before deduplication. Reordering input may change provider names.

## Continue into the existing reading workflow

Review the candidates and warnings. A MIME type is a publisher assertion, not proof of the fetched content, reachability or ownership. The registry loader accepts the `providers` wrapper. For a new workspace with no registry, the reviewed output may be saved as `.moonsuite/resource-providers.json`. For an existing registry, merge chosen entries into its providers array and choose unique names. Do not overwrite an existing registry or an input file with shell redirection.

Then explicitly request a source through the existing reader:

```sh
flock "$NATIVE_LOCK" moon run cmd/read_feed --frozen --target native --strip -j 1 --target-dir "$MOON_TARGET_DIR" -- /path/to/workspace '{"source":"provider://research-1","query":"climate"}' --markdown > climate.md
```

Discovery creates no permission or subscription. Existing runtime resource permissions apply when a source is subsequently read. Its format is detected from the fetched content. Private or tokenized URLs can carry secrets in the page URL, accepted endpoint paths or queries; inspect output before sharing. Rejected URLs are omitted from warnings.

## Supported saved HTML

The bounded scanner recognizes case-insensitive `link` tags whose whitespace-separated `rel` contains `alternate` and whose MIME type is `application/rss+xml`, `application/atom+xml` or `application/feed+json`. MIME parameters are permitted. RSS and Atom's generic XML MIME types, JSON Feed's generic `application/json`, anchor links, JavaScript-generated links and HTTP Link headers are deliberately not guessed.

Single-quoted, double-quoted and unquoted attributes are supported. The first duplicate attribute wins. `amp`, `lt`, `gt`, `quot`, `apos`, `nbsp` and semicolon-terminated numeric references are decoded. Unknown named references remain literal, so URLs using other HTML named entities may need manual correction. Comments, declarations, script/style/title/textarea/noscript contents and nested template contents do not contribute candidates. The scan stops at the first explicit closing `head` or opening `body` outside templates. Head fragments are supported, but omitted-tag browser DOM inference is not implemented. Malformed relevant markup, unclosed raw-text sections or comments fail before any manifest is printed.

The first `base href` applies to all candidates, including earlier links. Later base tags are ignored. Relative base addresses resolve against the supplied page URL. If the first base is unsupported, relative candidates are rejected visibly while independently absolute HTTP(S) candidates remain usable.

Absolute, protocol-relative, root-relative, directory-relative, parent-relative and query-only references are supported. Literal dot segments are removed and HTTP(S) scheme case is normalized. Fragments are removed; queries, host case, percent escapes and repeated path slashes are preserved. Empty/fragment-only candidate hrefs, non-HTTP(S) schemes, userinfo, whitespace, controls, backslashes, quotes and angle brackets are rejected. This conservative resolver is not a complete browser/WHATWG URL parser or reachability validator; percent-encoded dot segments, IDNA and default-port equivalence are not normalized. It does not block private or loopback hosts, because discovery performs no network access.

Input is limited to 4 Mi UTF-16 code units after a whole-file read. URL references and resolved URLs are limited to 8,192 UTF-16 code units, including the supplied page URL and base href. At most 256 matching candidate links are allowed, including duplicates and rejected URLs; excess candidates fail rather than silently truncate. A valid page with no candidates returns an empty provider array. There is no crawling, authentication, automatic registration, archive merge, background refresh, execution-completion claim or owner acceptance.

## Synthetic verification

`testdata/feeds/discovery-publisher.html` produces three sources, one duplicate and one rejected file URL:

```sh
flock "$NATIVE_LOCK" moon run cmd/discover_feeds --frozen --target native --strip -j 1 --target-dir "$MOON_TARGET_DIR" -- testdata/feeds/discovery-publisher.html https://observatory.example.test/about.html observatory
```

The focused native tests cover mixed formats, first-base behavior, exact resolved duplicates, comments and inert content, Unicode, entities, relative forms, rejected URLs, malformed/empty/bounded input, and an explicit loopback feed read through the generated registry. The loopback integration uses a temporary synthetic workspace. No live publisher, provider, credential or production workspace is exercised.
