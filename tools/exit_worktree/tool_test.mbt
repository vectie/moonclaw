///|
async test "exit_worktree removes a created checkout" (t : @test.Test) {
  @mock.run(t, mock => {
    @git.init_(mock.cwd.path())
    mock.add_json_tree({ "README.md": "hello" })
    @git.commit("init", ["README.md"], cwd=mock.cwd.path())
    let handle = @worktree.plan_worktree(mock.cwd.path(), "Cleanup docs")
    ignore(@worktree.create_worktree(handle))
    let tool = new(mock.cwd.path())
    let result = tool.call({ "path": handle.path })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(output.removed, content="true")
    inspect(@fsx.exists(handle.path), content="false")
  })
}
