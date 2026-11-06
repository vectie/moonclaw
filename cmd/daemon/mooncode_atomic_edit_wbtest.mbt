///|
async test "mooncode edit applies ordered replacements with one atomic write" {
  @fsx.with_temporary_directory("mooncode-atomic-edit-XXXXXX", async fn(root) {
    let path = @pathx.join(root, "sample.txt")
    @fsx.write_to_file(path, "alpha beta gamma")
    let result = mooncode_tool_edit(root, {
      "path": "sample.txt",
      "old_string": "",
      "new_string": "",
      "replace_all": false,
      "edits": [
        { "old_string": "alpha", "new_string": "one" },
        { "old_string": "one beta", "new_string": "two" },
      ],
    })
    assert_true(mooncode_json_bool(result, "ok", default=false))
    assert_eq(@fsx.read_file(path), "two gamma")
    let metadata = mooncode_json_object_field_or_empty(result, "metadata")
    assert_eq(mooncode_json_int(metadata, "edit_count", default=0), 2)
    assert_eq(mooncode_json_int(metadata, "replacement_count", default=0), 2)
    assert_true(mooncode_json_bool(metadata, "atomic", default=false))
    let ambiguous = mooncode_tool_edit(root, {
      "path": "sample.txt",
      "old_string": "two",
      "new_string": "single",
      "edits": [{ "old_string": "two", "new_string": "batch" }],
    })
    assert_false(mooncode_json_bool(ambiguous, "ok", default=true))
    assert_eq(@fsx.read_file(path), "two gamma")
  })
}

///|
async test "mooncode edit leaves the file unchanged when a later edit fails" {
  @fsx.with_temporary_directory("mooncode-atomic-edit-fail-XXXXXX", async fn(
    root,
  ) {
    let path = @pathx.join(root, "sample.txt")
    let original = "alpha beta gamma"
    @fsx.write_to_file(path, original)
    let result = mooncode_tool_edit(root, {
      "path": "sample.txt",
      "edits": [
        { "old_string": "alpha", "new_string": "one" },
        { "old_string": "missing", "new_string": "never" },
      ],
    })
    assert_false(mooncode_json_bool(result, "ok", default=true))
    assert_eq(@fsx.read_file(path), original)
    let metadata = mooncode_json_object_field_or_empty(result, "metadata")
    assert_eq(mooncode_json_int(metadata, "edit_index", default=-1), 1)
    assert_true(mooncode_json_bool(metadata, "atomic", default=false))
  })
}

///|
async test "mooncode edit preserves the legacy single replacement contract" {
  @fsx.with_temporary_directory("mooncode-legacy-edit-XXXXXX", async fn(root) {
    let path = @pathx.join(root, "sample.txt")
    @fsx.write_to_file(path, "alpha alpha")
    let result = mooncode_tool_edit(root, {
      "path": "sample.txt",
      "old_string": "alpha",
      "new_string": "beta",
      "replace_all": true,
      "edits": [],
    })
    assert_true(mooncode_json_bool(result, "ok", default=false))
    assert_eq(@fsx.read_file(path), "beta beta")
    let metadata = mooncode_json_object_field_or_empty(result, "metadata")
    assert_eq(mooncode_json_int(metadata, "edit_count", default=0), 1)
    assert_eq(mooncode_json_int(metadata, "replacement_count", default=0), 2)
  })
}
