///|
test "MoonDesk sandbox config control root is outside workspaces" {
  assert_eq(
    control_root_from_environment("/private/app-data", "/Users/demo"),
    "/private/app-data/control/execution-sandbox",
  )
  assert_eq(
    control_root_from_environment("", "/Users/demo"),
    "/Users/demo/Library/Application Support/app.vectie.moondesk/control/execution-sandbox",
  )
}

///|
async test "trusted Book roots are optional deny-by-default exact canonical grants" {
  let root = @fs.realpath(@fs.tmpdir(prefix="trusted-books-"))
  @fs.mkdir(root + "/book")
  @fs.mkdir(root + "/book/child")
  let legacy : Json = {
    "protocol_version": 1,
    "instance_id": "a".repeat(32),
    "auth_token": "b".repeat(64),
    "workspace_id": "fixture",
    "workspace_root": root,
  }
  let old : Config = @json.from_json(legacy)
  assert_eq(old.trusted_book_roots, None)
  assert_false(old.allows_book_root(root))
  let configured = { ..old, trusted_book_roots: Some([root + "/book"]), }
  assert_true(configured.allows_book_root(root + "/book"))
  assert_false(configured.allows_book_root(root + "/book/child"))
  assert_false(configured.allows_book_root(root))
  assert_true(
    ({ ..old, trusted_book_roots: Some([root]), } : Config).allows_book_root(
      root,
    ),
  )
}

///|
async test "malformed duplicate outside and symlink trust grants fail closed" {
  let root = @fs.realpath(@fs.tmpdir(prefix="invalid-trusted-books-"))
  let outside = @fs.realpath(@fs.tmpdir(prefix="outside-trusted-books-"))
  @fs.mkdir(root + "/book")
  @fs.symlink(root + "/alias", target=root + "/book")
  let base : Config = {
    protocol_version: 1,
    instance_id: "a".repeat(32),
    auth_token: "b".repeat(64),
    workspace_id: "fixture",
    workspace_root: root,
    trusted_book_roots: None,
  }
  for
    roots in [
      [root + "/book", root + "/book"],
      [root + "/alias"],
      [outside],
      [root + "/book/.."],
      ["relative"],
      [""],
    ] {
    let config = { ..base, trusted_book_roots: Some(roots), }
    assert_false(valid_trusted_book_roots(config))
    assert_false(config.allows_book_root(root + "/book"))
  }
  let malformed : Json = {
    "protocol_version": 1,
    "instance_id": "a".repeat(32),
    "auth_token": "b".repeat(64),
    "workspace_id": "fixture",
    "workspace_root": root,
    "trusted_book_roots": "trust-all",
  }
  let result : Result[Config, @json.JsonDecodeError] = try
    @json.from_json(malformed)
  catch {
    error => Err(error)
  } noraise {
    config => Ok(config)
  }
  assert_true(result is Err(_))
}
