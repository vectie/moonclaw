///|
async test "copilot credentials persist under MoonClaw product home" {
  let original_home = @os.getenv("HOME") catch { _ => None }
  let temp_home = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-copilot-test-XXXXXX"),
  )
  @os.setenv("HOME", temp_home)
  defer (match original_home {
    Some(home) => ignore(@os.setenv("HOME", home) catch { _ => () })
    None => ignore(@os.unsetenv("HOME") catch { _ => () })
  })
  save_credentials({
    github_token: "github-token",
    copilot_token: "copilot-token",
    copilot_token_expires_at: 999999L,
  })
  let path = @moonsuite.product_artifact(
    temp_home, "moonclaw", "credentials/copilot-credentials.json",
  )
  assert_true(@fsx.exists_as_file(path))
  let credentials = load_credentials()
  assert_eq(credentials.github_token, "github-token")
  assert_eq(credentials.copilot_token, "copilot-token")
}
