///|
async test "suite session listing selects direct visible MoonBook roots" {
  @fsx.with_temporary_directory("mooncode-suite-list-XXXXXX", async fn(suite) {
    let books = @pathx.join(suite, "books")
    @fsx.make_directory(@pathx.join(books, "book-a"), recursive=true)
    @fsx.make_directory(@pathx.join(books, ".hidden"), recursive=true)
    @fsx.make_directory(@pathx.join(books, "book-b"), recursive=true)
    let roots = mooncode_suite_book_roots(suite)
    assert_eq(roots.length(), 2)
    assert_true(roots.contains(@pathx.join(books, "book-a")))
    assert_true(roots.contains(@pathx.join(books, "book-b")))
  })
}

///|
async test "suite listing keeps a child MoonBook session in its own book" {
  @fsx.with_temporary_directory("mooncode-suite-bound-list-XXXXXX", async fn(
    suite,
  ) {
    let book_a = @pathx.join(suite, "books/book-a")
    let book_b = @pathx.join(suite, "books/book-b")
    @fsx.make_directory(book_a, recursive=true)
    @fsx.make_directory(book_b, recursive=true)
    let session_id = "scheduled-book-a"
    let path = mooncode_session_snapshot_path(book_a, session_id)
    @fsx.make_directory(@pathx.dirname(path), recursive=true)
    @fsx.write_to_file(
      path,
      (
        {
          "contract_id": @mooncode_core.session_snapshot_contract_id(),
          "session_id": session_id,
          "book_root": book_a,
          "journal_sequence": "0",
        } : Json).stringify(),
    )
    assert_eq(
      mooncode_durable_session_listing_records(suite, include_log_counts=false).length(),
      0,
    )
    assert_eq(
      mooncode_durable_session_listing_records(book_a, include_log_counts=false).length(),
      1,
    )
    assert_eq(
      mooncode_durable_session_listing_records(book_b, include_log_counts=false).length(),
      0,
    )
  })
}

///|
test "a shared suite store does not make sibling sessions interchangeable" {
  let suite = "/tmp/mooncode-suite-identity"
  let book_a = suite + "/books/book-a"
  let book_b = suite + "/books/book-b"
  assert_true(mooncode_sessions_root(book_a) == mooncode_sessions_root(book_b))
  assert_false(mooncode_listing_root_matches(suite, book_a))
  assert_false(mooncode_listing_root_matches(book_b, book_a))
  assert_true(mooncode_listing_root_matches(book_a, book_a))
}
