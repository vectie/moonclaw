///|
fn mooncode_task_scope_paths(body : Json) -> Array[String] {
  let contract = mooncode_json_object_field_or_empty(body, "task_contract")
  let paths : Array[String] = []
  for raw in mooncode_json_array_string_items(contract, "scope") {
    let trimmed = raw.trim().to_owned()
    if trimmed == "" || @pathx.is_absolute(trimmed) || trimmed.contains("../") {
      continue
    }
    let normalized = @pathx.normalize(trimmed)
    if normalized != "" && !paths.contains(normalized) {
      paths.push(normalized)
    }
  }
  paths
}

///|
fn mooncode_task_scope_declared(body : Json) -> Bool {
  let contract = mooncode_json_object_field_or_empty(body, "task_contract")
  mooncode_json_array_items(contract, "scope").length() > 0
}

///|
fn mooncode_task_scope_contains(scopes : Array[String], path : String) -> Bool {
  let normalized = @pathx.normalize(path)
  for scope in scopes {
    if scope == "." || normalized == scope || normalized.has_prefix(scope + "/") {
      return true
    }
  }
  false
}

///|
fn mooncode_task_scope_direct_mutation_paths(
  tool : String,
  arguments : Json,
) -> Array[String] {
  if tool == "write" || tool == "edit" {
    let path = mooncode_json_string(arguments, "path", default="")
    return if path == "" { [] } else { [path] }
  }
  if tool != "apply_patch" && tool != "revert_patch" {
    return []
  }
  let diff = mooncode_tool_patch_diff_text(arguments)
  if diff != "" {
    let paths = mooncode_tool_patch_files_from_unified_diff(diff).map(file => {
      mooncode_json_string(file, "path", default="")
    })
    if !paths.is_empty() {
      return paths
    }
  }
  for key in ["path", "context_path", "target"] {
    let path = mooncode_json_string(arguments, key, default="")
    if path != "" {
      return [mooncode_tool_patch_file_target(path)]
    }
  }
  []
}

///|
fn mooncode_task_scope_preflight_error(
  body : Json,
  tool : String,
  arguments : Json,
) -> String? {
  let scopes = mooncode_task_scope_paths(body)
  if !mooncode_task_scope_declared(body) {
    return None
  }
  if scopes.is_empty() {
    return Some(
      "MoonCode task scope is present but contains no valid relative book paths",
    )
  }
  if tool == "shell" &&
    !scopes.contains(".") &&
    mooncode_shell_has_git_workspace_mutation(
      mooncode_json_string(arguments, "cmd", default=""),
    ) {
    return Some(
      "MoonCode rejects Git workspace mutations from a narrowly scoped shell call; author files with write, edit, or apply_patch and let the parent session integrate them",
    )
  }
  for path in mooncode_task_scope_direct_mutation_paths(tool, arguments) {
    if path == "" || !mooncode_task_scope_contains(scopes, path) {
      return Some(
        "MoonCode task scope rejects mutation of `\{path}`; allowed roots: \{scopes.join(", ")}",
      )
    }
  }
  None
}

///|
fn mooncode_task_scope_needs_snapshot(tool : String) -> Bool {
  tool == "shell" || tool == "moon_cmd"
}

///|
async fn mooncode_task_scope_snapshot(
  book_root : String,
  body : Json,
  tool : String,
) -> MoonCodeFmtSnapshot? {
  if !mooncode_task_scope_declared(body) ||
    !mooncode_task_scope_needs_snapshot(tool) {
    return None
  }
  Some(mooncode_moon_fmt_snapshot(book_root))
}

///|
async fn mooncode_task_scope_finish(
  book_root : String,
  body : Json,
  tool : String,
  raw_result : Json,
  before : MoonCodeFmtSnapshot?,
) -> Json {
  guard before is Some(before) else { return raw_result }
  let scopes = mooncode_task_scope_paths(body)
  if before.error != "" {
    return mooncode_tool_error_result(
      tool,
      message="MoonCode could not enforce task scope before executing `\{tool}`: \{before.error}",
      metadata={
        "allowed_scope": Json::array(scopes.map(path => path.to_json())),
      },
    )
  }
  let outcome = mooncode_moon_fmt_verify_and_restore(
    book_root, book_root, scopes, before,
  )
  if outcome.snapshot_error != "" {
    return mooncode_tool_error_result(
      tool,
      message="MoonCode could not verify task scope after executing `\{tool}`: \{outcome.snapshot_error}",
      metadata={
        "task_scope": outcome.to_json(),
        "original_result": raw_result,
      },
    )
  }
  if outcome.out_of_scope_paths.is_empty() {
    return raw_result
  }
  mooncode_tool_error_result(
    tool,
    message=if outcome.retained_paths.is_empty() {
      "MoonCode restored changes outside the task scope and rejected the tool result"
    } else {
      "MoonCode detected changes outside the task scope and could not fully restore them"
    },
    metadata={ "task_scope": outcome.to_json(), "original_result": raw_result },
  )
}
