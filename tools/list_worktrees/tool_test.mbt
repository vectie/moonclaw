///|
async test "list_worktrees returns created MoonClaw worktrees" (t : @test.Test) {
  @mock.run(t, mock => {
    let repo = mock.cwd.path()
    @git.init_(repo)
    @fsx.write_to_file(@pathx.join(repo, "README.md"), "hello")
    @git.commit("init", ["README.md"], cwd=repo)
    let handle = @worktree.plan_worktree(repo, "Inspect docs")
    ignore(@worktree.create_worktree(handle))
    let tool = new(repo)
    let result = tool.call({})
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(output.repo_root, content=repo)
    inspect(output.worktrees.length(), content="1")
    inspect(
      output.worktrees[0].path.contains(".moonclaw-worktrees"),
      content="true",
    )
    @worktree.remove_worktree(handle)
  })
}
