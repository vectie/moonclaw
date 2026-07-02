///|
async test "load_credentials prefers newer codex cli auth" {
  let temp_home = @pathx.join(
    @os.tmpdir(),
    "moonclaw-codex-test-\{generate_state()}",
  )
  let codex_auth_path = @pathx.join(temp_home, ".codex/auth.json")
  @fsx.make_directory(temp_home, recursive=true, exists_ok=true)
  let moonclaw_dir = @moonsuite.product_artifact_for_workspace_root(
    temp_home, "moonclaw", "credentials",
  )
  @fsx.make_directory(moonclaw_dir, recursive=true, exists_ok=true)
  @fsx.make_directory(
    @pathx.dirname(codex_auth_path),
    recursive=true,
    exists_ok=true,
  )
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
  @async.sleep(2500)
  @fsx.write_to_file(codex_auth_path, fresh_codex.stringify())
  let creds = load_credentials_for_workspace_root(root=temp_home)
  assert_eq(creds.idToken, "codex-id")
  assert_eq(creds.accessToken, "codex-access")
  assert_eq(creds.refreshToken, "codex-refresh")
  assert_eq(creds.accountId, "codex-account")
}

///|
async test "codex credentials can persist under explicit MoonSuite root" {
  @fsx.with_temporary_directory("moonclaw-codex-explicit-root-XXXXXX", dir => {
    let os_home = @pathx.join(dir, "os-home")
    let suite_root = @pathx.join(dir, "suite")
    let book_root = @pathx.join(suite_root, "books/research-demo")
    @fsx.make_directory(os_home, recursive=true, exists_ok=true)
    @fsx.make_directory(book_root, recursive=true, exists_ok=true)
    save_credentials_for_workspace_root(
      {
        idToken: "suite-id",
        accessToken: "suite-access",
        refreshToken: "suite-refresh",
        accountId: "suite-account",
      },
      root=book_root,
    )
    let suite_path = @moonsuite.product_artifact_for_workspace_root(
      book_root, "moonclaw", "credentials/codex-credentials.json",
    )
    let home_path = @moonsuite.product_artifact(
      os_home, "moonclaw", "credentials/codex-credentials.json",
    )
    assert_true(@fsx.exists_as_file(suite_path))
    assert_false(@fsx.exists_as_file(home_path))
    let creds = load_credentials_for_workspace_root(root=book_root)
    assert_eq(creds.idToken, "suite-id")
    assert_eq(creds.accountId, "suite-account")
    delete_credentials_for_workspace_root(root=book_root)
    assert_false(@fsx.exists_as_file(suite_path))
  })
}
