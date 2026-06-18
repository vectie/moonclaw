///|
async test "find_repo_root" (t : @test.Test) {
  @mock.run(t, mock => {
    // Not in a git repo
    assert_true(@git.find_repo_root(mock.cwd.path()) is None)

    // Non-existent path
    assert_true(
      @git.find_repo_root(@pathx.join(mock.cwd.path(), "nope")) is None,
    )

    // In a git repo
    @git.init_(mock.cwd.path())
    assert_true(@git.find_repo_root(mock.cwd.path()) == Some(mock.cwd.path()))

    // Subdirectory in a git repo
    let sub = mock.cwd.add_directory("sub")
    assert_true(@git.find_repo_root(sub.path()) == Some(mock.cwd.path()))

    // File path in a git repo
    let file = sub.add_file("hello.txt")
    file.write_string("hello")
    assert_true(@git.find_repo_root(file.path()) == Some(sub.path()))
  })
}
