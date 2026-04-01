///|
async test "plan_worktree derives repo-root-based handle" (t : @test.Test) {
  @mock.run(t, mock => {
    @git.init_(mock.cwd.path())
    let handle = plan_worktree(mock.cwd.path(), "Review Attachment Flow")
    inspect(handle.repo_root, content=mock.cwd.path())
    inspect(handle.branch_name, content="moonclaw/review-attachment-flow")
    inspect(handle.path.contains(".moonclaw-worktrees"), content="true")
  })
}

///|
async test "create_worktree creates isolated checkout" (t : @test.Test) {
  @mock.run(t, mock => {
    @git.init_(mock.cwd.path())
    mock.add_json_tree({ "file.txt": "Hello, MoonClaw!" })
    @git.commit("Initial commit", ["file.txt"], cwd=mock.cwd.path())
    let handle = plan_worktree(mock.cwd.path(), "Review Attachment Flow")
    let created = create_worktree(handle)
    mock.group.add_defer(() => remove_worktree(created))
    inspect(
      @pathx.join(created.path, "file.txt") |> @fsx.read_file(),
      content="Hello, MoonClaw!",
    )
  })
}

///|
async test "with_worktree removes worktree after callback" (t : @test.Test) {
  @mock.run(t, mock => {
    @git.init_(mock.cwd.path())
    mock.add_json_tree({ "file.txt": "Hello, MoonClaw!" })
    @git.commit("Initial commit", ["file.txt"], cwd=mock.cwd.path())
    let handle = with_worktree(mock.cwd.path(), "Temporary Branch", handle => {
      inspect(
        @pathx.join(handle.path, "file.txt") |> @fsx.read_file(),
        content="Hello, MoonClaw!",
      )
      handle
    })
    let removed_path = handle.path
    inspect(@fsx.exists(removed_path), content="false")
  })
}
