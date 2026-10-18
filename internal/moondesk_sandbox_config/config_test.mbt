///|
async test "public trusted Book policy grants only an explicitly listed canonical root" {
  let root = @fs.realpath(@fs.tmpdir(prefix="public-trusted-book-"))
  let denied : @moondesk_sandbox_config.Config = {
    protocol_version: 1,
    instance_id: "a".repeat(32),
    auth_token: "b".repeat(64),
    workspace_id: "fixture",
    workspace_root: root,
    trusted_book_roots: None,
  }
  assert_false(denied.allows_book_root(root))
  let trusted = { ..denied, trusted_book_roots: Some([root]), }
  assert_true(trusted.allows_book_root(root))
}
