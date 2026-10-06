///|
fn fixture_binding(root : String) -> Binding {
  {
    workspace_id: "selected-suite",
    book_id: "relocated-book",
    source_root: root,
    request_digest: "sha256:" + "a".repeat(64),
  }
}

///|
async fn fixture_write(root : String, path : String, content : String) -> Unit {
  let parts = path.split("/").to_array()
  let dir = parts[:parts.length() - 1].to_array().join("/")
  if !@fs.exists(root + "/" + dir) {
    @fs.mkdir(root + "/" + dir, recursive=true)
  }
  @fs.write_file(root + "/" + path, content, create_mode=CreateOrTruncate)
}

///|
async test "Book admission parity and frozen Desk import full byte identity" {
  let contract = @json.parse(
    @fs.read_file("internal/book_learning/testdata/accepted-memory-v1.json").text(),
  )
  let expected = @json.parse(
    @fs.read_file(
      "internal/book_learning/testdata/accepted-memory-v1-results.json",
    ).text(),
  )
  guard contract
    is {
      "vectors": Array(vectors),
      "desk_imported_records": Array(records),
      ..
    } else {
    fail("Invalid fixture")
  }
  let results : Array[Json] = []
  for vector in vectors {
    guard vector
      is { "content": String(content), "status": String(expected), .. } else {
      fail("Invalid vector")
    }
    let status = review_status(content)
    assert_eq(status, expected)
    results.push({ "sha256": digest(@utf8.encode(content)), "status": status })
  }
  let root = @fs.tmpdir(prefix="claw-book-learning-")
  defer @fs.rmdir(root, recursive=true)
  for record in records {
    guard record
      is {
        "path": String(path),
        "content": String(content),
        "sha256": String(sha256),
        ..
      } else {
      fail("Invalid producer record")
    }
    assert_eq(digest(@utf8.encode(content)), sha256)
    assert_eq(review_status(content), "accepted")
    fixture_write(root, path, content)
    results.push({ "sha256": sha256, "status": "accepted" })
  }
  assert_eq(Json::array(results), expected)
  fixture_write(
    root, "memory/procedures/v1..v2.json", "{\"status\":\"promoted\",\"applicability\":\"APPLY_TAIL\",\"steps\":[\"step one\"],\"verification\":\"VERIFY_TAIL\",\"counterexamples\":\"COUNTEREXAMPLE_TAIL\",\"invalidation\":\"INVALIDATION_TAIL\"}",
  )
  fixture_write(
    root, "memory/procedures/candidate.json", "{\"status\":\"candidate\",\"accepted\":true,\"note\":\"CANDIDATE_NOT_SENT\"}",
  )
  fixture_write(
    root, "memory/beliefs/nested.json", "{\"nested\":{\"status\":\"accepted\"},\"note\":\"NESTED_NOT_SENT\"}",
  )
  let snapshot = capture(fixture_binding(root), 1)
  assert_eq(snapshot.status, "ready")
  assert_eq(snapshot.records.length(), 5)
  assert_eq(snapshot.excluded_records, 2)
  assert_true(validate(snapshot, fixture_binding(root)) is Ok(_))
  for record in snapshot.records {
    assert_eq(
      @utf8.encode(record.content_utf8),
      @fs.read_file(root + "/" + record.path).binary(),
    )
  }
  let rendered = render(snapshot)
  assert_true(rendered.contains("INVALIDATION_TAIL"))
  assert_false(rendered.contains("CANDIDATE_NOT_SENT"))
  assert_false(rendered.contains("NESTED_NOT_SENT"))
  assert_true(rendered.contains("Capability lessons remain ideas"))
  assert_true(rendered.contains("Acceptance provenance"))
}

///|
async test "optional nonBook empty unsafe and corrupt inputs preserve explicit status" {
  let root = @fs.tmpdir(prefix="claw-book-learning-")
  defer @fs.rmdir(root, recursive=true)
  let binding = fixture_binding(root)
  assert_eq(capture({ ..binding, book_id: "", }, 0).status, "not_applicable")
  assert_eq(capture(binding, 0).status, "empty")
  fixture_write(
    root, "memory/procedures/invalid.md", "---\nstatus: accepted\n---\nvalid",
  )
  @fs.write_file(
    root + "/memory/procedures/invalid.md",
    Bytes::from_array([255]),
    create_mode=CreateOrTruncate,
  )
  let invalid = capture(binding, 0)
  assert_eq(invalid.status, "unavailable")
  assert_eq(invalid.reasons, ["invalid_utf8"])
  @fs.remove(root + "/memory/procedures/invalid.md")
  @fs.symlink(target="/etc/passwd", root + "/memory/procedures/escape.md")
  assert_eq(capture(binding, 0).status, "unavailable")
  @fs.remove(root + "/memory/procedures/escape.md")
  @fs.rmdir(root + "/memory/procedures")
  @fs.symlink(target="/tmp", root + "/memory/procedures")
  assert_eq(capture(binding, 0).status, "unavailable")
  @fs.remove(root + "/memory/procedures")
  let original = empty(binding, "empty", 0)
  assert_true(validate({ ..original, status: "ready", }, binding) is Err(_))
  assert_true(validate(original, { ..binding, book_id: "other", }) is Err(_))
}

///|
async test "full-record budgets include exact boundaries and never truncate clauses" {
  let root = @fs.tmpdir(prefix="claw-book-learning-")
  defer @fs.rmdir(root, recursive=true)
  let binding = fixture_binding(root)
  let prefix = "---\nstatus: accepted\n---\n"
  let full = prefix +
    "x".repeat(32768 - @utf8.encode(prefix).length() - 4) +
    "尾\n"
  assert_eq(@utf8.encode(full).length(), 32768)
  fixture_write(root, "memory/procedures/a.md", full)
  fixture_write(root, "memory/procedures/b.md", full)
  let exact = capture(binding, 0)
  assert_eq(exact.status, "ready")
  assert_eq(exact.records.length(), 2)
  assert_eq(exact.records[0].content_utf8, full)
  fixture_write(root, "memory/procedures/c.md", prefix)
  let over = capture(binding, 0)
  assert_eq(over.status, "over_budget")
  assert_eq(over.records.length(), 0)
  @fs.remove(root + "/memory/procedures/c.md")
  fixture_write(root, "memory/procedures/a.md", full + "x")
  assert_eq(capture(binding, 0).status, "over_budget")
  @fs.remove(root + "/memory/procedures/a.md")
  @fs.remove(root + "/memory/procedures/b.md")
  for index in 0..<33 {
    fixture_write(
      root,
      "memory/procedures/" + index.to_string() + ".md",
      prefix,
    )
  }
  assert_eq(capture(binding, 0).status, "over_budget")
}

///|
async test "source mutation cancellation root aliases and scan limits are explicit" {
  let root = @fs.tmpdir(prefix="claw-learning-consistency-")
  defer @fs.rmdir(root, recursive=true)
  let binding = fixture_binding(root)
  fixture_write(
    root, "memory/procedures/a.md", "---\nstatus: accepted\n---\nORIGINAL",
  )
  let changed = capture_impl(binding, 0, before_recheck=() => {
    fixture_write(
      root, "memory/procedures/a.md", "---\nstatus: accepted\n---\nCHANGED",
    )
  })
  assert_eq(changed.status, "unavailable")
  assert_eq(changed.reasons, ["source_changed_during_capture"])
  assert_eq(changed.records.length(), 0)
  assert_eq(changed.admitted_records, 1)
  let completed : Ref[Bool] = { val: false, }
  ignore(
    @async.with_timeout_opt(5, () => {
      ignore(capture_impl(binding, 0, before_recheck=() => @async.sleep(1000)))
      completed.val = true
    }),
  )
  assert_false(completed.val)
  let alias = root + "-alias"
  @fs.symlink(target=root, alias)
  assert_eq(capture(fixture_binding(alias), 0).status, "ready")
  @fs.remove(alias)
  @fs.remove(root + "/memory/procedures/a.md")
  for index in 0..<257 {
    fixture_write(
      root,
      "memory/procedures/" + index.to_string() + ".md",
      "status: candidate",
    )
  }
  let over = capture(binding, 0)
  assert_eq(over.status, "over_budget")
  assert_eq(over.observed_entries, 257)
  assert_eq(over.records.length(), 0)
}
