///|
async test "a deletion patch must account for all file content" {
  @fsx.with_temporary_directory("mooncode-delete-guard-XXXXXX", async fn(
    book_root,
  ) {
    let path = @pathx.join(book_root, "target.txt")
    @fsx.write_to_file(path, "alpha\nbeta\n")
    let partial = mooncode_tool_apply_patch(book_root, {
      "path": ".",
      "diff": "--- a/target.txt\n+++ /dev/null\n@@\n-alpha\n",
    })
    assert_false(mooncode_json_bool(partial, "ok", default=true))
    assert_true(
      mooncode_json_string(partial, "message", default="").contains(
        "refusing to delete the whole file",
      ),
    )
    assert_eq(@fsx.read_file(path), "alpha\nbeta\n")
    let complete = mooncode_tool_apply_patch(book_root, {
      "path": ".",
      "diff": "--- a/target.txt\n+++ /dev/null\n@@\n-alpha\n-beta\n",
    })
    assert_true(mooncode_json_bool(complete, "ok", default=false))
    assert_false(@fsx.exists(path))
  })
}

///|
async test "reversing a file creation cannot discard later content" {
  @fsx.with_temporary_directory("mooncode-reverse-delete-XXXXXX", async fn(
    book_root,
  ) {
    let path = @pathx.join(book_root, "target.txt")
    @fsx.write_to_file(path, "alpha\nbeta\n")
    let result = mooncode_tool_revert_patch(book_root, {
      "path": ".",
      "diff": "--- /dev/null\n+++ b/target.txt\n@@\n+alpha\n",
    })
    assert_false(mooncode_json_bool(result, "ok", default=true))
    assert_eq(@fsx.read_file(path), "alpha\nbeta\n")
  })
}
