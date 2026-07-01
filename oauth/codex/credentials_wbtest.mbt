///|
async test "load_credentials prefers newer codex cli auth" {
  let original_home = @os.getenv("HOME") catch { _ => None }
  let temp_home = @pathx.join(
    @os.tmpdir(),
    "moonclaw-codex-test-\{generate_state()}",
  )
  @fsx.make_directory(temp_home, recursive=true, exists_ok=true)
  @os.setenv("HOME", temp_home)
  defer (match original_home {
    Some(home) => ignore(@os.setenv("HOME", home) catch { _ => () })
    None => ignore(@os.unsetenv("HOME") catch { _ => () })
  })
  let moonclaw_dir = @moonsuite.product_artifact(
    temp_home, "moonclaw", "credentials",
  )
  let codex_dir = @pathx.join(temp_home, ".codex")
  @fsx.make_directory(moonclaw_dir, recursive=true, exists_ok=true)
  @fsx.make_directory(codex_dir, recursive=true, exists_ok=true)
  let stale_local : Json = {
    "idToken": "local-id",
    "accessToken": "local-access",
    "refreshToken": "local-refresh",
    "accountId": "local-account",
  }
  let fresh_codex : Json = {
    "auth_mode": "chatgpt",
    "tokens": {
      "id_token": "codex-id",
      "access_token": "codex-access",
      "refresh_token": "codex-refresh",
      "account_id": "codex-account",
    },
  }
  @fsx.write_to_file(
    @pathx.join(moonclaw_dir, "codex-credentials.json"),
    stale_local.stringify(),
  )
  @async.sleep(1100)
  @fsx.write_to_file(
    @pathx.join(codex_dir, "auth.json"),
    fresh_codex.stringify(),
  )
  let creds = load_credentials()
  assert_eq(creds.idToken, "codex-id")
  assert_eq(creds.accessToken, "codex-access")
  assert_eq(creds.refreshToken, "codex-refresh")
  assert_eq(creds.accountId, "codex-account")
  assert_eq(@fsx.exists(@pathx.join(temp_home, ".moonclaw")), false)
}
