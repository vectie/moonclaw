///|
async test "enter_worktree creates a checkout and returns the handle" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    @git.init_(mock.cwd.path())
    mock.add_json_tree({ "README.md": "hello" })
    @git.commit("init", ["README.md"], cwd=mock.cwd.path())
    let tool = new(mock.cwd.path())
    let result = tool.call({ "task_key": "Review docs" })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(output.created, content="true")
    inspect(output.handle.branch_name, content="moonclaw/review-docs")
    inspect(
      @pathx.join(output.handle.path, "README.md") |> @fsx.exists(),
      content="true",
    )
    @worktree.remove_worktree(output.handle)
  })
}

///|
async test "enter_worktree reuses an existing path" (t : @test.Test) {
  @mock.run(t, mock => {
    @git.init_(mock.cwd.path())
    mock.add_json_tree({ "README.md": "hello" })
    @git.commit("init", ["README.md"], cwd=mock.cwd.path())
    let handle = @worktree.plan_worktree(mock.cwd.path(), "Review docs")
    ignore(@worktree.create_worktree(handle))
    let tool = new(mock.cwd.path())
    let result = tool.call({ "task_key": "Review docs" })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(output.created, content="false")
    inspect(output.handle.path, content=handle.path)
    @worktree.remove_worktree(handle)
  })
}
