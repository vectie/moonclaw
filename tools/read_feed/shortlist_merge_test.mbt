///|
fn merge_fixture(
  source : String,
  title : String,
) -> @read_feed.ReadingShortlist raise {
  @read_feed.capture_reading_shortlist([
    snapshot(
      source,
      collection_json([
        { "id": "shared", "title": title, "url": "https://example.test/shared" },
      ]),
    ),
  ])
}

///|
test "merge adds captured articles keeps annotations and unions selections in reader order" {
  let left = merge_fixture("left", "First")
  let right = merge_fixture("right", "Second")
  let a = shortlist_ids(left)[0]
  let b = shortlist_ids(right)[0]
  let left = left.edit({
    "title": "My reading",
    "order": [a],
    "annotations": [{ "entry_id": a, "note": "Keep 月", "state": "read" }],
  })
  let right = right.edit({
    "title": "Imported",
    "order": [b],
    "annotations": [{ "entry_id": b, "note": "New", "state": "reading" }],
  })
  let merged = left.merge(right)
  assert_eq(shortlist_ids(merged), [a, b])
  guard merged.to_json()
    is {
      "title": "My reading",
      "order": Array(order),
      "entries": [
        { "note": "Keep 月", "state": "read", .. },
        { "note": "New", "state": "reading", .. },
      ],
      ..
    } else {
    fail("Lost reader edits")
  }
  assert_eq(order, [a.to_json(), b.to_json()])
  assert_true(merged.to_markdown().contains("## 2. Second"))
  assert_eq(
    @read_feed.parse_reading_shortlist(merged.to_archive()).to_archive(),
    merged.to_archive(),
  )
  assert_eq(merged.merge(right).to_archive(), merged.to_archive())
  assert_eq(shortlist_ids(left), [a])
  guard left.preview_merge(right)
    is { "shared_count": 0, "merged_count": 2, "annotation_conflicts": [], .. } else {
    fail("Wrong preview")
  }
}

///|
test "merge exact overlap appends selected existing entries without duplicates" {
  let saved = @read_feed.capture_reading_shortlist([
    snapshot(
      "one",
      collection_json([{ "id": "a" }, { "id": "b" }, { "id": "c" }]),
    ),
  ])
  let ids = shortlist_ids(saved)
  let left = saved.edit({ "order": [ids[1]] })
  let right = saved.edit({ "order": [ids[2], ids[1], ids[0]] })
  let merged = left.merge(right)
  assert_eq(shortlist_ids(merged), ids)
  guard merged.to_json() is { "order": Array(order), .. } else {
    fail("Missing order")
  }
  assert_eq(order, [ids[1].to_json(), ids[2].to_json(), ids[0].to_json()])
  assert_eq(saved.merge(saved).to_archive(), saved.to_archive())
}

///|
test "merge preview and explicit conflict choices preserve both originals" {
  let saved = merge_fixture("one", "Title")
  let id = shortlist_ids(saved)[0]
  let left = saved.edit({
    "annotations": [{ "entry_id": id, "state": "read", "note": "Keep this" }],
  })
  let before = left.to_archive()
  guard left.preview_merge(saved)
    is {
      "shared_count": 1,
      "added_ids": [],
      "annotation_conflicts": [
        {
          "existing": { "state": "read", "note": "Keep this" },
          "incoming": { "state": "unread", "note": "" },
          ..
        },
      ],
      ..
    } else {
    fail("Conflict not inspectable")
  }
  shortlist_error(() => ignore(left.merge(saved)))
  assert_eq(left.merge(saved, conflict="keep-existing").to_archive(), before)
  assert_eq(
    left.merge(saved, conflict="use-incoming").to_archive(),
    saved.to_archive(),
  )
  shortlist_error(() => ignore(left.merge(saved, conflict="latest")))
  assert_eq(left.to_archive(), before)
  let note_only = saved.edit({
    "annotations": [{ "entry_id": id, "note": "note" }],
  })
  shortlist_error(() => ignore(saved.merge(note_only)))
  let state_only = saved.edit({
    "annotations": [{ "entry_id": id, "state": "reading" }],
  })
  shortlist_error(() => ignore(saved.merge(state_only)))
}

///|
test "merge keeps changed observations separate rather than transferring old notes" {
  let old = merge_fixture("same source", "Original")
  let fresh = merge_fixture("same source", "Revised")
  let id = shortlist_ids(old)[0]
  let old = old.edit({
    "order": [id],
    "annotations": [{ "entry_id": id, "note": "Original only" }],
  })
  let merged = old.merge(fresh)
  assert_eq(shortlist_ids(merged).length(), 2)
  guard merged.to_json()
    is {
      "entries": [
        { "note": "Original only", .. },
        { "state": "unread", "note": "", .. },
      ],
      "order": [_],
      ..
    } else {
    fail("Observation was remapped")
  }
  guard old.preview_merge(fresh)
    is { "shared_count": 0, "annotation_conflicts": [], .. } else {
    fail("False identity match")
  }
}

///|
test "merge rejects oversized union atomically but counts identical entries once" {
  let rows : Array[Json] = []
  for n in 0..<1000 {
    rows.push({ "id": "\{n}" })
  }
  let full = @read_feed.capture_reading_shortlist([
    snapshot("many", collection_json(rows)),
  ])
  let one = merge_fixture("other", "Extra")
  let before = full.to_archive()
  shortlist_error(() => ignore(full.merge(one)))
  assert_eq(full.to_archive(), before)
  assert_eq(full.merge(full).to_archive(), before)
  guard full.preview_merge(one)
    is { "merged_count": 1001, "within_article_limit": false, .. } else {
    fail("Limit preview incorrect")
  }
  let empty = @read_feed.capture_reading_shortlist([])
  assert_eq(full.merge(empty).to_archive(), before)
  assert_eq(shortlist_ids(empty.merge(one)), shortlist_ids(one))
}
