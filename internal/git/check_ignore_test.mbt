///|
async test "check-ignore" (t : @test.Test) {
  @mock.run(t, mock => {
    @git.init_(mock.cwd.path())
    mock.add_json_tree({
      ".gitignore": "ignored.txt\n",
      "ignored.txt": "This file is ignored.",
      "not_ignored.txt": "This file is not ignored.",
    })
    let ignored_files = @git.check_ignore(
      ["ignored.txt", "not_ignored.txt"],
      cwd=mock.cwd.path(),
    )
    json_inspect(ignored_files, content=["ignored.txt"])
  })
}

///|
async test "check-ignore preserves absolute input paths" (t : @test.Test) {
  @mock.run(t, mock => {
    @git.init_(mock.cwd.path())
    mock.add_json_tree({
      ".gitignore": "ignored.txt\n",
      "ignored.txt": "ignored",
      "not_ignored.txt": "visible",
    })
    let ignored_path = @pathx.join(mock.cwd.path(), "ignored.txt")
    let visible_path = @pathx.join(mock.cwd.path(), "not_ignored.txt")
    json_inspect(
      @git.check_ignore([ignored_path, visible_path], cwd=mock.cwd.path()),
      content=[ignored_path],
    )
    assert_false(@git.is_ignored(visible_path, cwd=mock.cwd.path()))
  })
}

///|
async test "check-ignore accepts an empty path list" (t : @test.Test) {
  @mock.run(t, mock => {
    json_inspect(@git.check_ignore([], cwd=mock.cwd.path()), content=[])
  })
}
