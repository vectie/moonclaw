///|
fn collection_json(items : Array[Json]) -> String {
  (
    {
      "version": "https://jsonfeed.org/version/1.1",
      "title": "JSON source",
      "items": items,
    } : Json).stringify()
}

///|
fn snapshot(source : String, body : String) -> @read_feed.FeedSnapshot {
  { source, body, label: "saved " + source, }
}

///|
fn expect_collection_error(
  action : () -> @read_feed.FeedCollectionPage raise,
) -> Unit raise {
  try action() catch {
    _ => ()
  } noraise {
    _ => fail("Expected the invalid collection to fail")
  }
}

///|
test "collection searches RSS Atom and JSON together with source provenance" {
  let rss = "<rss version='2.0'><channel><title>Observatory</title><item><guid isPermaLink='false'>shared</guid><title>Telescope night</title></item><item><guid isPermaLink='false'>other</guid><title>Weather</title></item></channel></rss>"
  let atom = "<feed xmlns='http://www.w3.org/2005/Atom'><title>Research</title><link rel='next' href='older'/><entry><id>shared</id><title>A discovery</title><summary>Telescope findings</summary><link href='article'/></entry></feed>"
  let json = collection_json([
    {
      "id": "shared",
      "title": "Announcement",
      "url": "https://example.test/telescope",
    },
  ])
  let result = @read_feed.collect_feeds(
    [
      snapshot("https://one.example.test/feed", rss),
      snapshot("https://two.example.test/feed", atom),
      snapshot("https://three.example.test/feed", json),
    ],
    query=" TELESCOPE ",
    limit=2,
  )
  assert_eq(result.total_items, 4)
  assert_eq(result.matched_items, 3)
  assert_eq(result.query, "TELESCOPE")
  assert_eq(result.articles.length(), 2)
  assert_eq(result.next_offset, Some(2))
  assert_eq(result.articles[0].source_title, "Observatory")
  assert_eq(
    result.articles[1].article.url,
    Some("https://two.example.test/article"),
  )
  assert_eq(result.articles[1].source, "https://two.example.test/feed")
  assert_eq(result.articles[1].article.id, "shared")
  assert_eq(result.articles[1].label, "saved https://two.example.test/feed")
  assert_eq(result.sources[0].total_items, 2)
  assert_eq(result.sources[0].matched_items, 1)
  assert_eq(result.sources[0].format, "rss")
  assert_eq(result.sources[1].format, "atom")
  assert_eq(result.sources[2].format, "json-feed")
  assert_eq(result.sources[1].next_url, Some("https://two.example.test/older"))
  guard result.to_json()
    is {
      "schema_version": 1,
      "sources": [{ "next_url": Null, .. }, _, _],
      "articles": [{ "article": { "date_published": Null, .. }, .. }, _],
      ..
    } else {
    fail("Expected plain JSON nulls and nested article provenance")
  }
}

///|
test "collection paging covers every entry and preserves repeated IDs and URLs" {
  let entries : Array[@read_feed.FeedSnapshot] = []
  for source in 0..<3 {
    let items : Array[Json] = []
    for index in 0..<41 {
      items.push({
        "id": "repeated",
        "title": "\{source}:\{index}",
        "url": "https://example.test/syndicated",
      })
    }
    entries.push(snapshot("source-\{source}", collection_json(items)))
  }
  let first = @read_feed.collect_feeds(entries)
  let second = @read_feed.collect_feeds(entries, offset=50)
  let third = @read_feed.collect_feeds(entries, offset=100)
  assert_eq(first.total_items, 123)
  assert_eq(first.articles.length(), 50)
  assert_eq(second.articles.length(), 50)
  assert_eq(third.articles.length(), 23)
  assert_eq(first.next_offset, Some(50))
  assert_eq(second.next_offset, Some(100))
  assert_eq(third.next_offset, None)
  assert_eq(second.articles[0].source, "source-1")
  assert_eq(second.articles[0].article_index, 9)
  assert_eq(third.articles[22].article.title, "2:40")
  let selected = @read_feed.collect_feeds(entries, query="2:40", limit=1)
  assert_eq(selected.total_items, 123)
  assert_eq(selected.matched_items, 1)
  assert_eq(selected.articles[0].article_index, 40)
}

///|
test "collection source selection and field search happen before paging" {
  let inputs = [
    snapshot(
      "first",
      collection_json([
        {
          "id": "one",
          "title": "A",
          "date_published": "2026-10-09",
          "summary": "sky",
        },
        { "id": "sky-id", "title": "B" },
      ]),
    ),
    snapshot("second", collection_json([{ "id": "three", "title": "sky" }])),
  ]
  let result = @read_feed.collect_feeds(
    inputs,
    query="sKy",
    source="first",
    limit=1,
    offset=1,
  )
  assert_eq(result.total_items, 3)
  assert_eq(result.matched_items, 2)
  assert_eq(result.sources[1].matched_items, 0)
  assert_eq(result.sources[1].total_items, 1)
  assert_eq(result.articles[0].article.id, "sky-id")
  assert_eq(result.articles[0].article_index, 1)
  assert_eq(result.next_offset, None)
  assert_eq(@read_feed.collect_feeds(inputs, query="2026-10").matched_items, 1)
  assert_eq(
    @read_feed.collect_feeds(inputs, query="JSON source").matched_items,
    0,
  )
  expect_collection_error(() => @read_feed.collect_feeds(inputs, source="First"))
}

///|
test "empty and exhausted collection pages retain complete source metadata" {
  let empty = @read_feed.collect_feeds([])
  assert_eq(empty.total_items, 0)
  assert_eq(empty.matched_items, 0)
  assert_eq(empty.next_offset, None)
  assert_true(
    empty.to_markdown().contains("No articles on this selected page."),
  )
  let inputs = [
    snapshot("empty", collection_json([])),
    snapshot("full", collection_json([{ "id": "a" }])),
  ]
  let missing = @read_feed.collect_feeds(inputs, query="absent")
  let exhausted = @read_feed.collect_feeds(inputs, offset=2147483647)
  assert_eq(missing.total_items, 1)
  assert_eq(missing.sources.length(), 2)
  assert_eq(missing.matched_items, 0)
  assert_eq(exhausted.articles.length(), 0)
  assert_eq(exhausted.next_offset, None)
  guard missing.to_json() is { "next_offset": Null, .. } else {
    fail("Expected null offset")
  }
}

///|
test "invalid or ambiguous sources fail even when outside the selected page or source" {
  let valid = snapshot("valid", collection_json([{ "id": "one" }]))
  expect_collection_error(() => @read_feed.collect_feeds([valid], limit=0))
  expect_collection_error(() => @read_feed.collect_feeds([valid], limit=51))
  expect_collection_error(() => @read_feed.collect_feeds([valid], offset=-1))
  expect_collection_error(() => @read_feed.collect_feeds([valid, valid]))
  expect_collection_error(() => {
    @read_feed.collect_feeds([snapshot(" \t", collection_json([]))])
  })
  try
    @read_feed.collect_feeds(
      [valid, snapshot("broken", "<broken")],
      source="valid",
      limit=1,
    )
  catch {
    Failure(message) =>
      assert_true(message.contains("Could not parse source broken"))
    error => fail("Unexpected parse error: \{error}")
  } noraise {
    _ => fail("Expected parse failure")
  }
  let many : Array[@read_feed.FeedSnapshot] = []
  for i in 0..<33 {
    many.push(snapshot("source-\{i}", collection_json([])))
  }
  expect_collection_error(() => @read_feed.collect_feeds(many))
}

///|
test "collection keeps the reader summary cap and escapes publisher and caller text" {
  let long = String::from_array(Array::make(2000, '🌙'))
  let inputs = [
    snapshot(
      "<source>",
      collection_json([
        {
          "id": "[id]",
          "title": "# *title*",
          "summary": "<script>text</script>",
          "url": "javascript:evil",
        },
        {
          "id": "long",
          "summary": long + "hidden tail",
          "url": "https://example.test/<a b>",
        },
      ]),
    ),
  ]
  let result = @read_feed.collect_feeds(inputs, title="[collection]")
  assert_eq(result.articles[1].article.summary, long)
  assert_eq(
    @read_feed.collect_feeds(inputs, query="hidden tail").matched_items,
    0,
  )
  let markdown = result.to_markdown()
  assert_true(markdown.contains("# \\[collection\\]"))
  assert_true(markdown.contains("## \\# \\*title\\*"))
  assert_true(markdown.contains("publisher ID: \\[id\\]"))
  assert_true(markdown.contains("\\<script\\>text\\</script\\>"))
  assert_false(markdown.contains("<script>"))
  assert_false(markdown.contains("javascript:evil"))
  assert_true(
    markdown.contains("[Read article](<https://example.test/%3Ca%20b%3E>)"),
  )
  assert_true(markdown.contains("No fetching, date sorting or deduplication"))
}

///|
test "collection digest escapes every repeated Markdown URL delimiter" {
  let url = "https://example.test/a b c/<one>/<two>\r\n\r\n"
  let result = @read_feed.collect_feeds([
    snapshot("example", collection_json([{ "id": "repeated", "url": url }])),
  ])
  let markdown = result.to_markdown()
  assert_true(
    markdown.contains(
      "[Read article](<https://example.test/a%20b%20c/%3Cone%3E/%3Ctwo%3E%0D%0A%0D%0A>)",
    ),
  )
  assert_false(markdown.contains("<one>"))
  assert_false(markdown.contains("<two>"))
  assert_false(markdown.contains("\r"))
  assert_eq(result.articles[0].article.url, Some(url))
}

///|
async test "local manifest resolves paths beside itself and exports a complete offline journey" {
  @fsx.with_temporary_directory("moonclaw-collection-XXXXXX", async fn(dir) {
    @fsx.make_directory(dir + "/nested")
    @fsx.write_to_file(
      dir + "/nested/one.json",
      collection_json([{ "id": "one", "title": "Moon research" }]),
    )
    @fsx.write_to_file(
      dir + "/two.atom",
      "<feed xmlns='http://www.w3.org/2005/Atom'><title>Lab</title><entry><id>two</id><title>Moon sample</title><link href='article'/></entry></feed>",
    )
    @fsx.write_to_file(
      dir + "/collection.json",
      (
        {
          "title": "Saved research",
          "sources": [
            {
              "source": "one",
              "path": "nested/one.json",
              "label": "First save",
            },
            {
              "source": "https://lab.example.test/feed",
              "path": dir + "/two.atom",
            },
          ],
        } : Json).stringify(),
    )
    let first = @read_feed.read_feed_collection(
      dir + "/collection.json",
      query="moon",
      limit=1,
    )
    let second = @read_feed.read_feed_collection(
      dir + "/collection.json",
      query="moon",
      limit=1,
      offset=1,
    )
    assert_eq(first.title, "Saved research")
    assert_eq(first.articles[0].label, "First save")
    assert_eq(first.next_offset, Some(1))
    assert_eq(second.articles[0].label, "https://lab.example.test/feed")
    assert_eq(
      second.articles[0].article.url,
      Some("https://lab.example.test/article"),
    )
    assert_eq(second.next_offset, None)
    assert_true(second.to_markdown().contains("Moon sample"))
    @fsx.write_to_file(dir + "/empty.json", "{\"sources\":[]}")
    assert_eq(
      @read_feed.read_feed_collection(dir + "/empty.json").title,
      "Feed collection",
    )
  })
}

///|
async test "manifest rejects invalid shapes options missing files and network paths" {
  @fsx.with_temporary_directory("moonclaw-collection-invalid-XXXXXX", async fn(
    dir,
  ) {
    let manifests : Array[Json] = [
      [],
      {},
      { "sources": "no" },
      { "sources": [], "typo": true },
      { "sources": [], "title": 1 },
      { "sources": [null] },
      { "sources": [{ "path": "missing" }] },
      { "sources": [{ "source": "a", "path": 1 }] },
      { "sources": [{ "source": "a", "path": "" }] },
      { "sources": [{ "source": "a", "path": "missing" }] },
      { "sources": [{ "source": "a", "path": "https://example.test/feed" }] },
      { "sources": [{ "source": "a", "path": "file://feed" }] },
      { "sources": [{ "source": "a", "path": "feed", "typo": true }] },
      { "sources": [{ "source": "a", "path": "feed", "label": null }] },
    ]
    for index, manifest in manifests {
      let path = dir + "/\{index}.json"
      @fsx.write_to_file(path, manifest.stringify())
      try @read_feed.read_feed_collection(path) catch {
        _ => ()
      } noraise {
        _ => fail("Expected invalid manifest \{index} to fail")
      }
    }
  })
}
