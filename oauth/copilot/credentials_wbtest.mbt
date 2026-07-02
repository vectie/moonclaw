///|
async test "copilot credentials persist under MoonClaw product home" {
  let temp_home = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-copilot-test-XXXXXX"),
  )
  save_credentials_for_workspace_root(
    {
      github_token: "github-token",
      copilot_token: "copilot-token",
      copilot_token_expires_at: 999999L,
    },
    root=temp_home,
  )
  let path = @moonsuite.product_artifact_for_workspace_root(
    temp_home, "moonclaw", "credentials/copilot-credentials.json",
  )
  assert_true(@fsx.exists_as_file(path))
  let credentials = load_credentials_for_workspace_root(root=temp_home)
  assert_eq(credentials.github_token, "github-token")
  assert_eq(credentials.copilot_token, "copilot-token")
}

///|
async test "copilot credentials can persist under explicit MoonSuite root" {
  @fsx.with_temporary_directory("moonclaw-copilot-explicit-root-XXXXXX", dir => {
    let os_home = @pathx.join(dir, "os-home")
    let suite_root = @pathx.join(dir, "suite")
    let book_root = @pathx.join(suite_root, "books/research-demo")
    @fsx.make_directory(os_home, recursive=true, exists_ok=true)
    @fsx.make_directory(book_root, recursive=true, exists_ok=true)
    save_credentials_for_workspace_root(
      {
        github_token: "suite-github",
        copilot_token: "suite-copilot",
        copilot_token_expires_at: 999999L,
      },
      root=book_root,
    )
    let suite_path = @moonsuite.product_artifact_for_workspace_root(
      book_root, "moonclaw", "credentials/copilot-credentials.json",
    )
    let home_path = @moonsuite.product_artifact(
      os_home, "moonclaw", "credentials/copilot-credentials.json",
    )
    assert_true(@fsx.exists_as_file(suite_path))
    assert_false(@fsx.exists_as_file(home_path))
    let credentials = load_credentials_for_workspace_root(root=book_root)
    assert_eq(credentials.github_token, "suite-github")
    assert_eq(credentials.copilot_token, "suite-copilot")
    delete_credentials_for_workspace_root(root=book_root)
    assert_false(@fsx.exists_as_file(suite_path))
  })
}
