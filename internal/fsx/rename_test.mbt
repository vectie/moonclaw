///|
async test "rename moves a file-system entry without changing its content" {
  with_temporary_directory("moonclaw-rename-XXXXXX", root => {
    let source = @pathx.join(root, "before.txt")
    let destination = @pathx.join(root, "after.txt")
    write_to_file(source, "durable")
    rename(source, destination)
    assert_false(exists(source))
    assert_true(exists_as_file(destination))
    assert_eq(read_file(destination), "durable")
  })
}
