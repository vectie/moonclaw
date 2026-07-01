///|
async test "lock_daemon_file uses moonsuite product home" {
  @fsx.with_temporary_directory("moonclaw-daemon-home-XXXXXX", async fn(home) {
    let file = lock_daemon_file(home~)
    guard file is Some(file) else {
      fail("expected daemon lock to be acquired")
    }
    defer file.close()
    let product_path = moonclaw_daemon_info_path(home)
    let legacy_path = home
      |> @pathx.join(".moonclaw")
      |> @pathx.join("daemon.json")
    assert_true(@fsx.exists(product_path))
    assert_false(@fsx.exists(legacy_path))
  })
}
