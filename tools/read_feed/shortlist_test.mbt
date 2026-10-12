///|
fn shortlist_ids(saved : @read_feed.ReadingShortlist) -> Array[String] raise {
  guard saved.to_json() is { "entries": Array(entries), .. } else {
    fail("Missing entries")
  }
  entries.map(entry => {
    guard entry is { "entry_id": String(id), .. } else { fail("Missing ID") }
    id
  })
}

///|
fn shortlist_error(action : () -> Unit raise) -> Unit raise {
  try action() catch {
    _ => ()
  } noraise {
    _ => fail("Expected failure")
  }
}

///|
test "shortlist captures all pages and keeps duplicate publisher IDs and cross-source URLs" {
  let many : Array[Json] = []
  for index in 0..<53 {
    many.push({
      "id": "repeated",
      "title": "Article \{index}",
      "url": "https://example.test/shared",
    })
  }
  let saved = @read_feed.capture_reading_shortlist([
    snapshot("one", collection_json(many)),
    snapshot(
      "two",
      collection_json([
        {
          "id": "repeated",
          "title": "Article 0",
          "url": "https://example.test/shared",
        },
      ]),
    ),
  ])
  let ids = shortlist_ids(saved)
  assert_eq(ids.length(), 54)
  assert_true(ids[0] != ids[1])
  assert_true(ids[0] != ids[53])
  let selected = saved.edit({ "order": [ids[53], ids[52], ids[0]] })
  guard selected.catalog() is { "selected": 3, "total_captured": 54, .. } else {
    fail("Wrong catalog count")
  }
  guard selected.to_json() is { "order": Array(order), .. } else {
    fail("Missing selection")
  }
  assert_eq(order, [ids[53].to_json(), ids[52].to_json(), ids[0].to_json()])
  assert_true(selected.to_markdown().contains("## 2. Article 52"))
}

///|
test "shortlist notes status order and deselection survive exact archive roundtrip" {
  let saved = @read_feed.capture_reading_shortlist(
    [
      snapshot(
        "one",
        collection_json([
          { "id": "same", "title": "First" },
          { "id": "same", "title": "Second" },
        ]),
      ),
    ],
    title="Weekend",
  )
  let ids = shortlist_ids(saved)
  let edited = saved.edit({
    "title": "Weekend reading",
    "order": [ids[1], ids[0]],
    "annotations": [
      {
        "entry_id": ids[1],
        "state": "reading",
        "note": "Compare with earlier results 月",
      },
      { "entry_id": ids[0], "state": "read" },
    ],
  })
  let reopened = @read_feed.parse_reading_shortlist(edited.to_archive())
  assert_eq(reopened.to_archive(), edited.to_archive())
  assert_eq(reopened.to_markdown(), edited.to_markdown())
  assert_true(reopened.to_markdown().contains("## 1. Second"))
  assert_true(reopened.to_markdown().contains("Reading state: reading"))
  assert_true(
    reopened.to_markdown().contains("Compare with earlier results 月"),
  )
  let hidden = reopened.edit({ "order": [] })
  assert_true(hidden.to_markdown().contains("No articles selected."))
  let restored = hidden.edit({ "order": [ids[1]] })
  assert_true(
    restored.to_markdown().contains("Compare with earlier results 月"),
  )
  assert_true(saved.to_markdown().contains("No articles selected."))
  guard saved.to_json()
    is { "entries": [{ "state": "unread", "note": "", .. }, _], .. } else {
    fail("Edit mutated original")
  }
}

///|
test "shortlist identity binds exact observation and normalized article provenance" {
  let body = collection_json([{ "id": "one", "title": "Original" }])
  let first = @read_feed.capture_reading_shortlist([snapshot("source", body)])
  let same = @read_feed.capture_reading_shortlist([snapshot("source", body)])
  let whitespace_changed = @read_feed.capture_reading_shortlist([
    snapshot("source", body + " "),
  ])
  let content_changed = @read_feed.capture_reading_shortlist([
    snapshot(
      "source",
      collection_json([{ "id": "one", "title": "Replacement" }]),
    ),
  ])
  assert_eq(shortlist_ids(first), shortlist_ids(same))
  assert_true(shortlist_ids(first)[0] != shortlist_ids(whitespace_changed)[0])
  assert_true(shortlist_ids(first)[0] != shortlist_ids(content_changed)[0])
  let json = first.to_json()
  guard json
    is {
      "entries": [{ "snapshot": { "article": Object(article), .. }, .. }],
      ..
    } else {
    fail("Missing snapshot")
  }
  article["title"] = "Tampered"
  shortlist_error(() => {
    ignore(@read_feed.parse_reading_shortlist(json.stringify()))
  })
  assert_true(first.to_archive().contains("Original"))
  assert_false(first.to_archive().contains("Tampered"))
}

///|
test "shortlist edits reject malformed references atomically" {
  let saved = @read_feed.capture_reading_shortlist([
    snapshot("source", collection_json([{ "id": "one" }])),
  ])
  let id = shortlist_ids(saved)[0]
  let before = saved.to_archive()
  let bad : Array[Json] = [
    [],
    { "unknown": true },
    { "title": 1 },
    { "order": null },
    { "order": [1] },
    { "order": [id, id] },
    { "order": ["missing"] },
    { "annotations": "no" },
    { "annotations": [{ "entry_id": id, "state": "done" }] },
    { "annotations": [{ "entry_id": id, "note": 1 }] },
    {
      "annotations": [
        { "entry_id": id, "note": "first" },
        { "entry_id": id, "note": "second" },
      ],
    },
    { "annotations": [{ "entry_id": "missing", "state": "read" }] },
    { "annotations": [{ "entry_id": id, "snapshot": {} }] },
    {
      "title": "changed",
      "order": [id],
      "annotations": [
        { "entry_id": id, "note": "valid" },
        { "entry_id": "missing", "note": "invalid" },
      ],
    },
    { "annotations": [{ "entry_id": id, "note": "x".repeat(16385) }] },
    { "title": "x".repeat(4097) },
  ]
  for changes in bad {
    shortlist_error(() => ignore(saved.edit(changes)))
    assert_eq(saved.to_archive(), before)
  }
}

///|
test "shortlist archive rejects malformed versions duplicate entries invalid state and references" {
  let saved = @read_feed.capture_reading_shortlist([
    snapshot("source", collection_json([{ "id": "one" }])),
  ])
  let id = shortlist_ids(saved)[0]
  for
    (key, value) in [
      ("schema", "other".to_json()),
      ("schema_version", (2).to_json()),
      ("schema_version", 1.5.to_json()),
      ("title", Json::null()),
      ("order", ["missing"].to_json()),
      ("order", [id, id].to_json()),
      ("entries", Json::null()),
      ("unexpected", true.to_json()),
    ] {
    guard saved.to_json() is Object(fields) else { fail("Missing root") }
    fields[key] = value
    shortlist_error(() => {
      ignore(
        @read_feed.parse_reading_shortlist(Json::object(fields).stringify()),
      )
    })
  }
  let json = saved.to_json()
  guard json is { "entries": Array(entries), .. } else {
    fail("Missing entries")
  }
  entries.push(entries[0])
  shortlist_error(() => {
    ignore(@read_feed.parse_reading_shortlist(json.stringify()))
  })
  let bad_state = saved.to_json()
  guard bad_state is { "entries": [Object(entry)], .. } else {
    fail("Missing entry")
  }
  entry["state"] = "accepted"
  shortlist_error(() => {
    ignore(@read_feed.parse_reading_shortlist(bad_state.stringify()))
  })
  shortlist_error(() => ignore(@read_feed.parse_reading_shortlist("not json")))
  shortlist_error(() => ignore(@read_feed.parse_reading_shortlist("{}")))
}

///|
test "shortlist Markdown escapes publisher fields reader notes and repeated URL delimiters" {
  let saved = @read_feed.capture_reading_shortlist(
    [
      snapshot(
        "source <x>",
        collection_json([
          {
            "id": "[id]",
            "title": "**Title**",
            "url": "https://example.test/a b c/<one>/<two>\r\n\\\t",
            "summary": "<script>alert(1)</script>",
          },
          { "id": "unsafe", "url": "javascript:alert(1)" },
        ]),
      ),
    ],
    title="# Reader",
  )
  let ids = shortlist_ids(saved)
  let edited = saved.edit({
    "order": ids,
    "annotations": [
      {
        "entry_id": ids[0],
        "note": "[click](javascript:alert(1))\n<script>test</script> **note**",
      },
    ],
  })
  let markdown = edited.to_markdown()
  assert_true(markdown.contains("# \\# Reader"))
  assert_true(markdown.contains("\\*\\*Title\\*\\*"))
  assert_true(markdown.contains("\\[click\\]"))
  assert_false(markdown.contains("<script>"))
  assert_false(markdown.contains("[Read article](<javascript:"))
  assert_true(markdown.contains("a%20b%20c/%3Cone%3E/%3Ctwo%3E%0D%0A%5C%09"))
  assert_true(markdown.contains("not verified capture times"))
  assert_true(markdown.contains("not full articles"))
}

///|
test "shortlist Unicode normalization cap and empty catalog are explicit" {
  let saved = @read_feed.capture_reading_shortlist([
    snapshot(
      "source",
      collection_json([{ "id": "one", "summary": "月🌙".repeat(1100) }]),
    ),
  ])
  guard saved.to_json()
    is {
      "entries": [
        {
          "snapshot": { "article": { "summary": String(summary), .. }, .. },
          ..
        },
      ],
      ..
    } else {
    fail("Missing summary")
  }
  assert_eq(summary.to_array().length(), 2000)
  assert_eq(
    @read_feed.parse_reading_shortlist(saved.to_archive()).to_archive(),
    saved.to_archive(),
  )
  let empty = @read_feed.capture_reading_shortlist([])
  assert_eq(shortlist_ids(empty), [])
  assert_true(empty.to_markdown().contains("No articles selected"))
  assert_eq(
    empty.edit({ "order": [], "annotations": [] }).to_archive(),
    empty.to_archive(),
  )
}

///|
test "shortlist capture validates every feed and enforces catalog bound" {
  let valid = snapshot("valid", collection_json([{ "id": "one" }]))
  shortlist_error(() => {
    ignore(@read_feed.capture_reading_shortlist([valid, valid]))
  })
  shortlist_error(() => {
    ignore(
      @read_feed.capture_reading_shortlist([valid, snapshot("broken", "broken")]),
    )
  })
  let many : Array[Json] = []
  for index in 0..<1001 {
    many.push({ "id": "\{index}" })
  }
  shortlist_error(() => {
    ignore(
      @read_feed.capture_reading_shortlist([
        snapshot("many", collection_json(many)),
      ]),
    )
  })
  shortlist_error(() => {
    ignore(@read_feed.capture_reading_shortlist([], title="x".repeat(4097)))
  })
}

///|
async test "shortlist real file reopen survives source changes and lost manifest" {
  @fsx.with_temporary_directory("moonclaw-shortlist-XXXXXX", async fn(dir) {
    let body = collection_json([
      { "id": "same", "title": "Original first" },
      { "id": "same", "title": "Original second" },
    ])
    @fsx.write_to_file(dir + "/feed.json", body)
    @fsx.write_to_file(
      dir + "/manifest.json",
      (
        {
          "sources": [
            {
              "source": "https://example.test/feed",
              "path": "feed.json",
              "label": "Earlier save",
            },
          ],
        } : Json).stringify(),
    )
    let saved = @read_feed.capture_reading_shortlist_file(
      dir + "/manifest.json",
    )
    let ids = shortlist_ids(saved)
    let selected = saved.edit({
      "order": [ids[1]],
      "annotations": [
        { "entry_id": ids[1], "state": "read", "note": "Retain original" },
      ],
    })
    @fsx.write_to_file(dir + "/shortlist.json", selected.to_archive())
    @fsx.write_to_file(
      dir + "/feed.json",
      collection_json([{ "id": "same", "title": "Replacement at index zero" }]),
    )
    @fsx.write_to_file(dir + "/manifest.json", "manifest is no longer usable")
    let reopened = @read_feed.read_reading_shortlist(dir + "/shortlist.json")
    assert_eq(reopened.to_archive(), selected.to_archive())
    assert_eq(reopened.to_markdown(), selected.to_markdown())
    assert_true(reopened.to_markdown().contains("Original second"))
    assert_false(reopened.to_markdown().contains("Replacement"))
    guard reopened.catalog(query="Retain") is { "articles": [_], .. } else {
      fail("Note search failed")
    }
  })
}

///|
test "shortlist standalone summaries remain text instead of Markdown blocks" {
  for
    (raw, escaped) in [
      ("---", "\\-\\-\\-"),
      ("- content", "\\- content"),
      ("+ content", "\\+ content"),
      ("1. content", "1\\. content"),
      ("1) content", "1\\) content"),
      ("===", "\\=\\=\\="),
      ("> quote", "\\> quote"),
      ("~~strike~~", "\\~\\~strike\\~\\~"),
    ] {
    let saved = @read_feed.capture_reading_shortlist([
      snapshot("source", collection_json([{ "id": "one", "summary": raw }])),
    ])
    let id = shortlist_ids(saved)[0]
    let selected = saved.edit({
      "order": [id],
      "annotations": [{ "entry_id": id, "note": raw }],
    })
    let markdown = selected.to_markdown()
    assert_true(markdown.contains("\n\n" + escaped + "\n\n"))
    assert_true(markdown.contains("Reader note: " + escaped + "\n\n"))
    assert_false(markdown.contains("\n\n" + raw + "\n\n"))
    guard selected.to_json()
      is {
        "entries": [
          {
            "snapshot": { "article": { "summary": String(summary), .. }, .. },
            "note": String(note),
            ..
          },
        ],
        ..
      } else {
      fail("Missing retained text")
    }
    assert_eq(summary, raw)
    assert_eq(note, raw)
  }
}
