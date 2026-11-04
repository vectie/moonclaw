///|
async fn mooncode_runtime_post_commit_snapshot(book_root : String) -> Json {
  let head = mooncode_runtime_turn_git(
    book_root,
    Head,
    timeout_ms=10000,
    max_output_chars=4000,
  )
  let tree = mooncode_runtime_turn_git(
    book_root,
    HeadTree,
    timeout_ms=10000,
    max_output_chars=4000,
  )
  let commit_sha = mooncode_json_string(head, "output", default="")
    .trim()
    .to_owned()
  let commit_tree = mooncode_json_string(tree, "output", default="")
    .trim()
    .to_owned()
  let status = mooncode_runtime_turn_git(
    book_root,
    StatusProductPorcelain,
    timeout_ms=10000,
    max_output_chars=MOONCODE_DEFAULT_TOOL_OUTPUT_CHARS,
  )
  let status_output = mooncode_json_string(status, "output", default="")
  let clean = mooncode_json_bool(status, "ok", default=false) &&
    status_output.trim().is_empty()
  {
    "valid": mooncode_json_bool(head, "ok", default=false) &&
    mooncode_json_bool(tree, "ok", default=false) &&
    commit_sha != "" &&
    commit_tree != "" &&
    clean,
    "commit_sha": commit_sha,
    "commit_tree": commit_tree,
    "clean": clean,
    "status": status_output,
  }
}

///|
async fn mooncode_runtime_post_commit_capture(
  book_root : String,
  tool : String,
  arguments : Json,
  result : Json,
) -> Json {
  if tool != "shell" ||
    mooncode_json_bool(result, "is_error", default=true) ||
    !@mooncode_tools.shell_has_git_commit(
      mooncode_json_string(arguments, "cmd", default=""),
    ) {
    return result
  }
  let snapshot = mooncode_runtime_post_commit_snapshot(book_root)
  let commit_sha = mooncode_json_string(snapshot, "commit_sha", default="")
  let changed_paths = if commit_sha == "" {
    []
  } else {
    mooncode_runtime_commit_changed_paths(book_root, commit_sha)
  }
  let mut metadata = mooncode_json_object_field_or_empty(result, "metadata")
  metadata = mooncode_json_object_with_field(
    metadata,
    "post_commit_boundary",
    Json(true),
  )
  metadata = mooncode_json_object_with_field(
    metadata,
    "post_commit_capture_valid",
    Json(mooncode_json_bool(snapshot, "valid", default=false)),
  )
  metadata = mooncode_json_object_with_field(
    metadata,
    "commit_sha",
    Json(commit_sha),
  )
  metadata = mooncode_json_object_with_field(
    metadata,
    "commit_tree",
    Json(mooncode_json_string(snapshot, "commit_tree", default="")),
  )
  metadata = mooncode_json_object_with_field(
    metadata,
    "changed_paths",
    Json::array(changed_paths.map(path => Json(path))),
  )
  mooncode_json_object_with_field(result, "metadata", metadata)
}
