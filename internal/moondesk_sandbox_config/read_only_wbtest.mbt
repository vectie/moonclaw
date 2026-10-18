///|
async test "read-only config preserves private modes and content and refuses insecure files without chmod" {
  let root = @fs.realpath(@fs.tmpdir(prefix="readonly-config-"))
  defer @fs.remove(root)
  @fs.chmod(root, 0o700)
  let path = root + "/config.json"
  let value : Config = {
    protocol_version: 1,
    instance_id: "a".repeat(32),
    auth_token: "b".repeat(64),
    workspace_id: "book",
    workspace_root: root,
    trusted_book_roots: None,
  }
  @fs.write_file(
    path,
    value.to_json().stringify(),
    create_mode=CreateNew,
    permission=0o600,
  )
  defer @fs.remove(path)
  let before = @fs.read_file(path).binary()
  assert_eq(load_from_path(path, root, read_only=true), value)
  assert_true(check_private_control_path(root, true))
  assert_true(check_private_control_path(path, false))
  assert_eq(@fs.read_file(path).binary(), before)
  @fs.chmod(path, 0o644)
  assert_true(
    (Ok(load_from_path(path, root, read_only=true)) catch {
      error => Err(error)
    })
    is Err(_),
  )
  assert_false(check_private_control_path(path, false))
  assert_eq(@fs.read_file(path).binary(), before)
  @fs.chmod(path, 0o600)
  @fs.chmod(root, 0o755)
  assert_true(
    (Ok(load_from_path(path, root, read_only=true)) catch {
      error => Err(error)
    })
    is Err(_),
  )
  assert_false(check_private_control_path(root, true))
  assert_eq(@fs.read_file(path).binary(), before)
}
