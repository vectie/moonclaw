///|
async test "lock_daemon_file uses moonsuite product home" {
  @fsx.with_temporary_directory("moonclaw-daemon-home-XXXXXX", async fn(root) {
    let suite_root = @pathx.join(root, "suite")
    let home = @pathx.join(suite_root, "books/research-demo")
    @fsx.make_directory(home, recursive=true, exists_ok=true)
    let file = lock_daemon_file(home=home[:])
    guard file is Some(file) else {
      fail("expected daemon lock to be acquired")
    }
    defer file.close()
    let product_path = moonclaw_daemon_info_path(home)
    assert_true(@fsx.exists(product_path))
    assert_true(product_path.has_prefix(suite_root))
    assert_false(product_path.contains("/books/research-demo/.moonsuite"))
  })
}

///|
test "detached daemon home follows served workspace root" {
  let suite_root = "/tmp/moonclaw-suite"
  let book_root = @pathx.join(suite_root, "books/research-demo")
  assert_eq(moonclaw_daemon_home_for_serve(Some(book_root[:])), book_root)
  assert_eq(
    moonclaw_daemon_info_path(
      moonclaw_daemon_home_for_serve(Some(book_root[:])),
    ),
    @pathx.join(suite_root, ".moonsuite/products/moonclaw/daemon.json"),
  )
}
