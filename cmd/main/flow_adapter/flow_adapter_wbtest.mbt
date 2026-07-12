///|
test "flow adapter parses repeated options and rejects path escape" {
  let args = [
    "--model", "codex/test", "--artifact", "books/a.json", "--artifact", "books/b.json",
  ]
  assert_true(option(args, "--model") == Some("codex/test"))
  assert_true(
    repeated_option(args, "--artifact") == ["books/a.json", "books/b.json"],
  )
  assert_true(safe_ref("books/a.json"))
  assert_false(safe_ref("../escape"))
  assert_false(safe_ref("/absolute"))
}
