///|
fn observation_json(
  items : Array[Json],
  next~ : String = "https://example.test/older",
) -> String {
  (
    {
      "version": "https://jsonfeed.org/version/1.1",
      "title": "Observatory",
      "items": items,
      "next_url": next,
    } : Json).stringify()
}

///|
test "comparison returns new changed absent and unchanged with exact old and new values" {
  let before = observation_json([
    {
      "id": "changed",
      "title": "Old title",
      "summary": "Old summary",
      "date_published": "old date",
      "url": "https://example.test/old",
    },
    { "id": "missing", "title": "Archive entry" },
    { "id": "same", "title": "Stable" },
  ])
  let after = observation_json([
    { "id": "new", "title": "New entry" },
    { "id": "same", "title": "Stable" },
    {
      "id": "changed",
      "title": "New title",
      "summary": "New summary",
      "url": "https://example.test/new",
    },
  ])
  let result = @read_feed.compare_feeds(
    before,
    after,
    "observatory",
    before_label="Monday",
    after_label="Tuesday",
  )
  inspect(
    [
      result.newly_listed,
      result.changed,
      result.no_longer_listed,
      result.unchanged,
    ],
    content="[1, 1, 1, 1]",
  )
  inspect(
    result.changes.map(c => c.kind),
    content="[newly_listed, changed, no_longer_listed]",
  )
  inspect(
    result.changes[1].changed_fields,
    content="[title, date_published, summary, url]",
  )
  assert_eq(result.changes[1].before.unwrap().title, "Old title")
  assert_eq(result.changes[1].after.unwrap().date_published, None)
  assert_eq(result.before.label, "Monday")
  assert_eq(result.after.label, "Tuesday")
  assert_eq(result.total_changes, 3)
  assert_eq(result.matched_changes, 3)
  assert_eq(result.next_offset, None)
  guard result.to_json()
    is {
      "schema_version": 1,
      "changes": [{ "before": Null, .. }, _, { "after": Null, .. }],
      "next_offset": Null,
      "absence_caveat": String(caveat),
      ..
    } else {
    fail("Expected plain JSON nulls and explicit absence caveat")
  }
  assert_true(caveat.contains("not deleted"))
}

///|
test "RSS Atom and JSON observations share normalized visible values despite reordered entries" {
  let rss = "<rss version='2.0'><channel><title>Old feed title</title><item><guid isPermaLink='false'>a</guid><title>A &amp; B</title><description>&lt;p&gt;Clear   skies&lt;/p&gt;</description><link>https://example.test/a</link><pubDate>2026-10-08</pubDate></item><item><guid isPermaLink='false'>b</guid><title>Second</title></item></channel></rss>"
  let atom = "<feed xmlns='http://www.w3.org/2005/Atom'><title>New feed title</title><entry><id>b</id><title>Second</title></entry><entry><id>a</id><title>A &amp; B</title><summary>Clear skies</summary><link href='a'/><published>2026-10-08</published></entry></feed>"
  let json = observation_json([
    {
      "id": "a",
      "title": "A & B",
      "summary": "Clear skies",
      "url": "https://example.test/a",
      "date_published": "2026-10-08",
    },
    { "id": "b", "title": "Second" },
  ])
  let result = @read_feed.compare_feeds(rss, atom, "https://example.test/feed")
  assert_eq(result.total_changes, 0)
  assert_eq(result.unchanged, 2)
  assert_eq(result.before.format, "rss")
  assert_eq(result.after.format, "atom")
  assert_eq(result.before.title, "Old feed title")
  assert_eq(result.after.title, "New feed title")
  let result = @read_feed.compare_feeds(atom, json, "https://example.test/feed")
  assert_eq(result.total_changes, 0)
  assert_eq(result.unchanged, 2)
  assert_eq(result.after.format, "json-feed")
}

///|
test "all supplied entries beyond fifty participate before comparison filtering and pagination" {
  let before : Array[Json] = []
  let after : Array[Json] = []
  for i in 0..<123 {
    before.push({ "id": "\{i}", "title": "Old \{i}" })
    after.push({ "id": "\{i}", "title": "New \{i}" })
  }
  let first = @read_feed.compare_feeds(
    observation_json(before),
    observation_json(after),
    "same",
  )
  assert_eq(first.changed, 123)
  assert_eq(first.changes.length(), 50)
  assert_eq(first.next_offset, Some(50))
  let second = @read_feed.compare_feeds(
    observation_json(before),
    observation_json(after),
    "same",
    offset=50,
  )
  assert_eq(second.changes[0].id, "50")
  assert_eq(second.changes.length(), 50)
  assert_eq(second.next_offset, Some(100))
  let last = @read_feed.compare_feeds(
    observation_json(before),
    observation_json(after),
    "same",
    offset=100,
  )
  assert_eq(last.changes.length(), 23)
  assert_eq(last.changes[22].id, "122")
  assert_eq(last.next_offset, None)
  let filtered = @read_feed.compare_feeds(
    observation_json(before),
    observation_json(after),
    "same",
    query="Old 122",
    limit=1,
  )
  assert_eq(filtered.changes[0].id, "122")
  assert_eq(filtered.matched_changes, 1)
  assert_eq(filtered.changed, 123)
  // Publisher paging remains visible on every comparison page, but is not read.
  assert_eq(first.before.next_url, Some("https://example.test/older"))
  assert_eq(first.after.next_url, Some("https://example.test/older"))
}

///|
test "duplicate IDs in either whole observation fail even beyond selected page or filter" {
  let duplicates : Array[Json] = []
  for i in 0..<61 {
    duplicates.push({ "id": "\{i}" })
  }
  duplicates.push({ "id": "0", "title": "Ambiguous duplicate" })
  let empty = observation_json([])
  let before = try? @read_feed.compare_feeds(
    observation_json(duplicates),
    empty,
    "same",
    query="no match",
    limit=1,
  )
  guard before is Err(Failure(message)) else {
    fail("Expected duplicate error")
  }
  assert_true(
    message.has_suffix("before observation has duplicate article ID: 0"),
  )
  let after = try? @read_feed.compare_feeds(
    empty,
    observation_json(duplicates),
    "same",
    kind="changed",
  )
  guard after is Err(Failure(message)) else { fail("Expected duplicate error") }
  assert_true(
    message.has_suffix("after observation has duplicate article ID: 0"),
  )
  assert_true(
    (try? @read_feed.compare_feeds(
      empty,
      observation_json([{ "id": " \t" }]),
      "same",
    ))
    is Err(_),
  )
  // Comparison's ambiguity rule does not silently change the existing reader.
  assert_eq(
    @read_feed.parse_feed(observation_json(duplicates), "same").total_items,
    62,
  )
  let rss = "<rss version='2.0'><channel><title>Duplicate</title><item><guid>x</guid></item><item><guid>x</guid></item></channel></rss>"
  assert_true((try? @read_feed.compare_feeds(rss, empty, "same")) is Err(_))
}

///|
test "empty observations and out of range result pages remain explicit" {
  let empty = observation_json([])
  let one = observation_json([{ "id": "one" }])
  let result = @read_feed.compare_feeds(empty, empty, "same")
  assert_eq(result.total_changes, 0)
  assert_eq(result.changes.length(), 0)
  assert_true(
    result.to_markdown().contains("No changes on this selected page."),
  )
  let result = @read_feed.compare_feeds(empty, one, "same")
  assert_eq(result.newly_listed, 1)
  assert_true(result.changes[0].before is None)
  let result = @read_feed.compare_feeds(one, empty, "same")
  assert_eq(result.no_longer_listed, 1)
  assert_true(result.changes[0].after is None)
  let result = @read_feed.compare_feeds(empty, one, "same", offset=2147483647)
  assert_eq(result.total_changes, 1)
  assert_eq(result.matched_changes, 1)
  assert_eq(result.changes.length(), 0)
  assert_eq(result.next_offset, None)
}

///|
test "case insensitive filters search both sides and kind selection follows full comparison" {
  let before = observation_json([
    {
      "id": "a",
      "title": "Retired Telescope title",
      "date_published": "2025-01-01",
    },
    { "id": "b", "title": "Telescope archive" },
  ])
  let after = observation_json([
    {
      "id": "a",
      "title": "Replacement",
      "url": "https://example.test/Telescope",
    },
    { "id": "c", "title": "Telescope addition" },
  ])
  let result = @read_feed.compare_feeds(
    before,
    after,
    "same",
    query=" TELESCOPE ",
    kind="changed",
  )
  assert_eq(result.query, "TELESCOPE")
  assert_eq(result.total_changes, 3)
  assert_eq(result.matched_changes, 1)
  assert_eq(result.changes[0].id, "a")
  assert_eq(
    @read_feed.compare_feeds(before, after, "same", query="retired").matched_changes,
    1,
  )
  assert_eq(
    @read_feed.compare_feeds(before, after, "same", query="2025-01").matched_changes,
    1,
  )
  assert_eq(
    @read_feed.compare_feeds(before, after, "same", kind="no_longer_listed").changes[0].id,
    "b",
  )
  assert_eq(
    @read_feed.compare_feeds(before, after, "same", kind="newly_listed").changes[0].id,
    "c",
  )
}

///|
test "comparison explicitly limits summaries to two thousand Unicode characters" {
  let text = String::from_array(Array::make(2000, '🌙'))
  let before = observation_json([{ "id": "a", "summary": text + "old tail" }])
  let after = observation_json([{ "id": "a", "summary": text + "new tail" }])
  let result = @read_feed.compare_feeds(before, after, "same")
  assert_eq(result.unchanged, 1)
  assert_eq(result.total_changes, 0)
  assert_true(result.to_markdown().contains("first 2000 Unicode characters"))
  assert_true(result.to_markdown().contains("no full-content comparison"))
  // HTML-only JSON Feed content is outside the existing reader's visible fields.
  assert_eq(
    @read_feed.compare_feeds(
      observation_json([{ "id": "a", "content_html": "old" }]),
      observation_json([{ "id": "a", "content_html": "new" }]),
      "same",
    ).unchanged,
    1,
  )
}

///|
test "Markdown escapes untrusted observation IDs labels titles summaries and links" {
  let result = @read_feed.compare_feeds(
    observation_json([]),
    observation_json([
      {
        "id": "[id]",
        "title": "# <script>*title*</script>",
        "summary": "line\n## [click](javascript:evil) `code`",
        "url": "javascript:<svg onload=evil>",
      },
    ]),
    "<source>",
    before_label="[old]",
    after_label="`new`",
  )
  let md = result.to_markdown()
  assert_true(md.contains("Source: \\<source\\>"))
  assert_true(md.contains("Before: \\[old\\]"))
  assert_true(md.contains("## Newly listed: \\[id\\]"))
  assert_true(md.contains("\\# \\<script\\>\\*title\\*\\</script\\>"))
  assert_true(
    md.contains("line \\#\\# \\[click\\](javascript:evil) \\`code\\`"),
  )
  assert_false(md.contains("<script>"))
  assert_false(md.contains("[click]("))
  assert_false(md.contains("\n## [click]"))
  assert_true(md.contains("URL: javascript:\\<svg onload=evil\\>"))
  assert_false(md.contains("<svg onload=evil>"))
}

///|
test "invalid observations and comparison options fail instead of producing an empty diff" {
  let empty = observation_json([])
  assert_true((try? @read_feed.compare_feeds("{}", empty, "same")) is Err(_))
  assert_true(
    (try? @read_feed.compare_feeds(empty, "<broken", "same")) is Err(_),
  )
  assert_true((try? @read_feed.compare_feeds(empty, empty, " ")) is Err(_))
  assert_true(
    (try? @read_feed.compare_feeds(empty, empty, "same", kind="deleted"))
    is Err(_),
  )
  assert_true(
    (try? @read_feed.compare_feeds(empty, empty, "same", limit=0)) is Err(_),
  )
  assert_true(
    (try? @read_feed.compare_feeds(empty, empty, "same", limit=51)) is Err(_),
  )
  assert_true(
    (try? @read_feed.compare_feeds(empty, empty, "same", offset=-1)) is Err(_),
  )
}
