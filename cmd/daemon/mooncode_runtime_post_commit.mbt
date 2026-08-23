///|
async fn mooncode_runtime_post_commit_snapshot(book_root : String) -> Json {
  let head = mooncode_runtime_turn_git(
    book_root,
    @trusted_host_process.Head,
    timeout_ms=10000,
    max_output_chars=4000,
  )
  let tree = mooncode_runtime_turn_git(
    book_root,
    @trusted_host_process.HeadTree,
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
    @trusted_host_process.StatusProductPorcelain,
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
    !mooncode_shell_has_git_commit(
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
    true.to_json(),
  )
  metadata = mooncode_json_object_with_field(
    metadata,
    "post_commit_capture_valid",
    mooncode_json_bool(snapshot, "valid", default=false).to_json(),
  )
  metadata = mooncode_json_object_with_field(
    metadata,
    "commit_sha",
    commit_sha.to_json(),
  )
  metadata = mooncode_json_object_with_field(
    metadata,
    "commit_tree",
    mooncode_json_string(snapshot, "commit_tree", default="").to_json(),
  )
  metadata = mooncode_json_object_with_field(
    metadata,
    "changed_paths",
    Json::array(changed_paths.map(path => path.to_json())),
  )
  mooncode_json_object_with_field(result, "metadata", metadata)
}

///|
fn mooncode_runtime_post_commit_boundary(results : Array[Json]) -> Json {
  let mut boundary = Json::object({})
  for execution in results {
    let direct_result = mooncode_json_object_field_or_empty(execution, "result")
    let event_result = mooncode_json_object_field_or_empty(
      execution, "tool_result",
    )
    let result = if mooncode_json_string(direct_result, "tool", default="") !=
      "" {
      direct_result
    } else {
      event_result
    }
    let metadata = mooncode_json_object_field_or_empty(result, "metadata")
    if mooncode_json_bool(metadata, "post_commit_boundary", default=false) {
      boundary = {
        "commit_sha": mooncode_json_string(metadata, "commit_sha", default=""),
        "commit_tree": mooncode_json_string(metadata, "commit_tree", default=""),
        "capture_valid": mooncode_json_bool(
          metadata,
          "post_commit_capture_valid",
          default=false,
        ),
      }
    }
    let commit_result = mooncode_json_object_field_or_empty(
      execution, "commit_result",
    )
    if mooncode_json_bool(commit_result, "commit_created", default=false) &&
      mooncode_json_string(commit_result, "event", default="") ==
      "commit_created" {
      let commit_sha = mooncode_json_string(
        commit_result,
        "commit_sha",
        default="",
      )
      let commit_tree = mooncode_json_string(
        commit_result,
        "commit_tree",
        default="",
      )
      boundary = {
        "commit_sha": commit_sha,
        "commit_tree": commit_tree,
        "capture_valid": mooncode_json_bool(
          commit_result,
          "accepted",
          default=false,
        ) &&
        commit_sha != "" &&
        commit_tree != "",
      }
    }
  }
  boundary
}

///|
fn mooncode_runtime_post_commit_tool_mutates(tool_call : Json) -> Bool {
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  match tool {
    "write" | "edit" | "apply_patch" | "revert_patch" => true
    "shell" =>
      mooncode_shell_has_workspace_mutation(
        mooncode_json_string(arguments, "cmd", default=""),
      )
    "moon_cmd" =>
      mooncode_json_string(arguments, "command", default="") == "fmt" ||
      mooncode_json_string(arguments, "command", default="") == "info" ||
      mooncode_moon_cmd_is_test_update(arguments)
    _ => false
  }
}

///|
async fn mooncode_runtime_post_commit_guard(
  book_root : String,
  tool_call : Json,
  results : Array[Json],
) -> Json {
  let boundary = mooncode_runtime_post_commit_boundary(results)
  let commit_sha = mooncode_json_string(boundary, "commit_sha", default="")
  if commit_sha == "" &&
    !mooncode_json_bool(boundary, "capture_valid", default=false) {
    return {
      "active": false,
      "allowed": true,
      "commit_sha": "",
      "commit_tree": "",
      "reason": "",
    }
  }
  let commit_tree = mooncode_json_string(boundary, "commit_tree", default="")
  if !mooncode_json_bool(boundary, "capture_valid", default=false) ||
    commit_sha == "" ||
    commit_tree == "" {
    return {
      "active": true,
      "allowed": false,
      "commit_sha": commit_sha,
      "commit_tree": commit_tree,
      "reason": "post-commit verification is sealed because the created commit identity could not be captured",
    }
  }
  if mooncode_runtime_post_commit_tool_mutates(tool_call) {
    return {
      "active": true,
      "allowed": false,
      "commit_sha": commit_sha,
      "commit_tree": commit_tree,
      "reason": "post-commit mutation rejected: this command is sealed at commit \{commit_sha}; submit a later explicit user command to start another mutation cycle",
    }
  }
  let current = mooncode_runtime_post_commit_snapshot(book_root)
  let exact = mooncode_json_bool(current, "valid", default=false) &&
    mooncode_json_string(current, "commit_sha", default="") == commit_sha &&
    mooncode_json_string(current, "commit_tree", default="") == commit_tree &&
    mooncode_json_bool(current, "clean", default=false)
  {
    "active": true,
    "allowed": exact,
    "commit_sha": commit_sha,
    "commit_tree": commit_tree,
    "reason": if exact {
      ""
    } else {
      "post-commit verification rejected because repository HEAD/tree or product worktree no longer matches sealed commit \{commit_sha}"
    },
  }
}

///|
fn mooncode_runtime_post_commit_rejected_execution(
  session_id : String,
  book_root : String,
  command_id : String,
  tool_call : Json,
  verdict : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  let result = mooncode_tool_error_result(
    tool,
    message=mooncode_json_string(
      verdict,
      "reason",
      default="post-commit tool execution rejected",
    ),
    metadata={
      "post_commit_sealed": true,
      "commit_sha": mooncode_json_string(verdict, "commit_sha", default=""),
      "commit_tree": mooncode_json_string(verdict, "commit_tree", default=""),
    },
  )
  {
    "accepted": false,
    "kind": "mooncode-tool-execution",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "tool": tool,
    "arguments": arguments,
    "result": result,
    "event": mooncode_tool_result_event(
      session_id,
      book_root,
      command_id,
      tool,
      result,
      now~,
    ),
  }
}
