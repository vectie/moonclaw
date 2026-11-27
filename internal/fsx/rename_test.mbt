///|
async test "rename moves a file-system entry without changing its content" {
  @fsx.with_temporary_directory("moonclaw-rename-XXXXXX", root => {
    let source = @pathx.join(root, "before.txt")
    let destination = @pathx.join(root, "after.txt")
    @fsx.write_to_file(source, "durable")
    @fsx.rename(source, destination)
    assert_false(@fsx.exists(source))
    assert_true(@fsx.exists_as_file(destination))
    assert_eq(@fsx.read_file(destination), "durable")
  })
}
