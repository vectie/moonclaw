///|
async fn mooncode_tool_shell(book_root : String, arguments : Json) -> Json {
  let cmd = mooncode_json_string(arguments, "cmd", default="")
  if cmd == "" {
    return mooncode_tool_error_result("shell", message="cmd must be non-empty")
  }
  if mooncode_shell_has_git_commit(cmd) &&
    !mooncode_shell_git_commit_is_terminal(cmd) {
    return mooncode_tool_error_result(
      "shell",
      message="git commit must be the terminal command in a shell tool call so the runtime can seal the exact committed state",
    )
  }
  if mooncode_shell_has_file_output_redirection(cmd) {
    return mooncode_tool_error_result(
      "shell",
      message="shell output redirection cannot author MoonBook files; use write, edit, or apply_patch",
    )
  }
  if mooncode_shell_has_in_place_authoring(cmd) {
    return mooncode_tool_error_result(
      "shell",
      message="shell in-place editing cannot author MoonBook files; use write, edit, or apply_patch",
    )
  }
  match mooncode_shell_boundary_error(book_root, cmd) {
    Some(message) => return mooncode_tool_error_result("shell", message~)
    None => ()
  }
  let cwd = mooncode_tool_cwd(book_root, arguments)
  if mooncode_json_bool(cwd, "ok", default=false) == false {
    return mooncode_tool_error_result(
      "shell",
      message=mooncode_json_string(cwd, "message", default="invalid cwd"),
    )
  }
  let cwd_path = mooncode_json_string(cwd, "absolute_path", default=book_root)
  let timeout = mooncode_json_int(arguments, "timeout_ms", default=30000)
  let max_output_chars = mooncode_json_int(
    arguments,
    "max_output_chars",
    default=12000,
  )
  let shell_wrapper =
    #|child_pid=""
    #|terminate_tree() {
    #|  for descendant_pid in $(pgrep -P "$1" 2>/dev/null || true); do
    #|    terminate_tree "$descendant_pid"
    #|  done
    #|  kill -TERM "$1" 2>/dev/null || true
    #|}
    #|cancel_tree() {
    #|  if [ -n "$child_pid" ]; then
    #|    terminate_tree "$child_pid"
    #|    wait "$child_pid" 2>/dev/null || true
    #|  fi
    #|  exit 124
    #|}
    #|trap cancel_tree TERM INT
    #|sh -lc "$1" &
    #|child_pid=$!
    #|wait "$child_pid"
    #|
  let process = @spawn.spawn(
    "sh",
    ["-c", shell_wrapper, "mooncode-shell", cmd],
    timeout~,
    cwd=cwd_path,
  ) catch {
    @spawn.TimedOut(timeout~, stdout~, stderr~) => {
      let capped = mooncode_cap_tool_output(stdout + stderr, max_output_chars)
      return mooncode_tool_error_result(
        "shell",
        message="shell timed out after \{timeout}ms",
        output=mooncode_json_string(capped, "output", default=""),
        metadata={
          "cmd": cmd,
          "cwd": mooncode_json_string(cwd, "relative_path", default="."),
          "timeout_ms": timeout,
          "truncated": mooncode_json_bool(capped, "truncated", default=false),
        },
      )
    }
    error =>
      return mooncode_tool_error_result(
        "shell",
        message="error running shell: \{error}",
      )
  }
  let output = process.stdout + process.stderr
  let capped = mooncode_cap_tool_output(output, max_output_chars)
  let truncated = mooncode_json_bool(capped, "truncated", default=false)
  let file_observation = if process.status == 0 {
    mooncode_shell_file_observation(
      book_root,
      cwd_path,
      cmd,
      mooncode_json_string(capped, "output", default=""),
      truncated,
    )
  } else {
    {}
  }
  let pipeline_exit_ambiguous = mooncode_shell_pipeline_exit_ambiguous(cmd)
  let metadata : Json = {
    "cmd": cmd,
    "cwd": mooncode_json_string(cwd, "relative_path", default="."),
    "status": process.status,
    "elapsed_ms": process.elapsed,
    "truncated": truncated,
    "pipeline_exit_ambiguous": pipeline_exit_ambiguous,
    "file_observation": file_observation,
  }
  let result = if pipeline_exit_ambiguous {
    mooncode_tool_error_result(
      "shell",
      message="shell pipeline exit is ambiguous because pipefail was not enabled",
      output=mooncode_json_string(capped, "output", default=""),
      metadata~,
    )
  } else if process.status == 0 {
    mooncode_tool_ok_result(
      "shell",
      message="shell exited 0",
      output=mooncode_json_string(capped, "output", default=""),
      metadata~,
    )
  } else {
    mooncode_tool_error_result(
      "shell",
      message="shell exited \{process.status}",
      output=mooncode_json_string(capped, "output", default=""),
      metadata~,
    )
  }
  result
}

///|
fn mooncode_shell_boundary_error(book_root : String, cmd : String) -> String? {
  // The shell inherits a cwd inside the book, but an absolute path in the
  // command can otherwise bypass the executable-document boundary. Toolchain
  // programs may load their own installation implicitly; the planner must not
  // address SDK, home, temp, or parent paths directly.
  let normalized_root = @pathx.normalize(book_root)
  if cmd.contains("../") ||
    cmd.contains("$HOME") ||
    cmd.contains("${HOME}") ||
    cmd.contains("~/") ||
    cmd.contains("/.moon/") ||
    cmd.contains("/etc/") ||
    cmd.contains("/tmp/") ||
    cmd.contains("/private/") ||
    (cmd.contains("/Users/") && !cmd.contains(normalized_root)) ||
    cmd.contains("/home/") {
    Some(
      "shell command references a path outside the selected MoonBook; use relative book paths or MoonCode's semantic MoonBit tools",
    )
  } else {
    None
  }
}

///|
async fn mooncode_moon_module_cwd_for_path(
  book_root : String,
  path : String,
) -> Json {
  if path == "" {
    return mooncode_tool_cwd(book_root, {})
  }
  let resolved = mooncode_resolve_book_path(book_root, path)
  if !mooncode_json_bool(resolved, "ok", default=false) {
    return resolved
  }
  let absolute = mooncode_json_string(resolved, "absolute_path", default="")
  let name = @pathx.basename(absolute).to_owned()
  let mut candidate = if name.contains(".") {
    @pathx.dirname(absolute).to_owned()
  } else {
    absolute
  }
  let root = @pathx.normalize(book_root)
  for ;; {
    if @fsx.exists(@pathx.join(candidate, "moon.mod")) ||
      @fsx.exists(@pathx.join(candidate, "moon.mod.json")) ||
      @fsx.exists(@pathx.join(candidate, "moon.work")) {
      return mooncode_resolve_book_path(book_root, candidate)
    }
    if candidate == root {
      break
    }
    let parent = @pathx.dirname(candidate).to_owned()
    if parent == candidate || (parent != root && !parent.has_prefix(root + "/")) {
      break
    }
    candidate = parent
  }
  mooncode_tool_cwd(book_root, {})
}

///|
async fn mooncode_moon_ide_cwd(book_root : String, arguments : Json) -> Json {
  if mooncode_json_string(arguments, "cwd", default="") != "" {
    return mooncode_tool_cwd(book_root, arguments)
  }
  let path = mooncode_json_string(arguments, "path", default="")
  mooncode_moon_module_cwd_for_path(book_root, path)
}

///|
async fn mooncode_tool_moon_ide(book_root : String, arguments : Json) -> Json {
  let action = mooncode_json_string(arguments, "action", default="")
  if !mooncode_moon_ide_action_supported(action) {
    return mooncode_tool_error_result(
      "moon_ide",
      message="unsupported moon_ide action: \{action}",
      metadata={ "action": action },
    )
  }
  let argument_error = mooncode_moon_ide_argument_error(arguments, action)
  if argument_error != "" {
    return mooncode_tool_error_result("moon_ide", message=argument_error)
  }
  let target = mooncode_json_string(arguments, "target", default="")
  if target != "all" && !mooncode_moon_target_supported(target) {
    return mooncode_tool_error_result(
      "moon_ide",
      message="unsupported moon_ide target: \{target}",
      metadata={ "target": target },
    )
  }
  let outline_path = mooncode_json_string(arguments, "path", default="")
  if action == "outline" {
    let resolved_path = mooncode_resolve_book_path(book_root, outline_path)
    if !mooncode_json_bool(resolved_path, "ok", default=false) {
      return mooncode_tool_error_result(
        "moon_ide",
        message=mooncode_json_string(
          resolved_path,
          "message",
          default="invalid outline path",
        ),
      )
    }
  }
  let cwd = mooncode_moon_ide_cwd(book_root, arguments)
  if mooncode_json_bool(cwd, "ok", default=false) == false {
    return mooncode_tool_error_result(
      "moon_ide",
      message=mooncode_json_string(cwd, "message", default="invalid cwd"),
    )
  }
  let cwd_path = mooncode_json_string(cwd, "absolute_path", default=book_root)
  let args = mooncode_moon_ide_args(arguments, action, book_root, cwd_path)
  let timeout = mooncode_json_int(arguments, "timeout_ms", default=30000)
  let process = @spawn.spawn(
    "moon",
    args.map(fn(arg) { arg }),
    timeout~,
    cwd=cwd_path,
  ) catch {
    error =>
      return mooncode_tool_error_result(
        "moon_ide",
        message="error running moon ide: \{error}",
      )
  }
  let capped = mooncode_cap_tool_output(
    process.stdout + process.stderr,
    mooncode_json_int(arguments, "max_output_chars", default=12000),
  )
  let metadata : Json = {
    "action": action,
    "cwd": mooncode_json_string(cwd, "relative_path", default="."),
    "command": "moon \{args.join(" ")}",
    "status": process.status,
    "elapsed_ms": process.elapsed,
    "truncated": mooncode_json_bool(capped, "truncated", default=false),
  }
  if process.status == 0 {
    mooncode_tool_ok_result(
      "moon_ide",
      message="moon ide \{action} exited 0",
      output=mooncode_json_string(capped, "output", default=""),
      metadata~,
    )
  } else {
    mooncode_tool_error_result(
      "moon_ide",
      message="moon ide \{action} exited \{process.status}",
      output=mooncode_json_string(capped, "output", default=""),
      metadata~,
    )
  }
}

///|
fn mooncode_moon_ide_action_supported(action : String) -> Bool {
  action == "doc" ||
  action == "outline" ||
  action == "peek_def" ||
  action == "hover" ||
  action == "find_references"
}

///|
fn mooncode_moon_ide_argument_error(
  arguments : Json,
  action : String,
) -> String {
  let query = mooncode_json_string(arguments, "query", default="")
  let path = mooncode_json_string(arguments, "path", default="")
  let loc = mooncode_json_string(arguments, "loc", default="")
  match action {
    "outline" => if path == "" { "moon_ide outline requires path" } else { "" }
    "hover" =>
      if query == "" {
        "moon_ide hover requires query"
      } else if loc == "" {
        "moon_ide hover requires loc"
      } else {
        ""
      }
    "doc" | "peek_def" | "find_references" =>
      if query == "" {
        "moon_ide \{action} requires query"
      } else {
        ""
      }
    _ => ""
  }
}

///|
fn mooncode_moon_ide_args(
  arguments : Json,
  action : String,
  book_root : String,
  cwd_path : String,
) -> Array[String] {
  let args : Array[String] = ["ide", mooncode_moon_ide_cli_action(action)]
  if mooncode_json_bool(arguments, "no_check", default=false) {
    args.push("--no-check")
  }
  let target = mooncode_json_string(arguments, "target", default="")
  // `moon check` accepts `all`; `moon ide` requires one concrete target.
  // Omitting `all` lets the nested module choose its preferred/default target.
  if target != "" && target != "all" {
    args.push("--target")
    args.push(target)
  }
  let loc = mooncode_moon_ide_loc(arguments, book_root, cwd_path)
  if loc != "" {
    args.push("--loc")
    args.push(loc)
  }
  let operand = if action == "outline" {
    let path = mooncode_json_string(arguments, "path", default="")
    let resolved = mooncode_resolve_book_path(book_root, path)
    let absolute = mooncode_json_string(resolved, "absolute_path", default=path)
    @pathx.relative(cwd_path, absolute) catch {
      _ => path
    }
  } else {
    mooncode_json_string(arguments, "query", default="")
  }
  if operand != "" {
    args.push(operand)
  }
  args
}

///|
/// The model schema carries `path` and `loc` separately, while `moon ide`
/// requires `--loc path:line:column`. Preserve already-qualified locations and
/// combine a numeric `line:column` with the resolved book-local path.
fn mooncode_moon_ide_loc(
  arguments : Json,
  book_root : String,
  cwd_path : String,
) -> String {
  let loc = mooncode_json_string(arguments, "loc", default="")
  let path = mooncode_json_string(arguments, "path", default="")
  let parts = loc.split(":").to_array()
  if loc == "" || path == "" || parts.length() != 2 {
    return loc
  }
  let line_column_only = try {
    ignore(@string.parse_int(parts[0]))
    ignore(@string.parse_int(parts[1]))
    true
  } catch {
    _ => false
  }
  if !line_column_only {
    return loc
  }
  let resolved = mooncode_resolve_book_path(book_root, path)
  let absolute = mooncode_json_string(resolved, "absolute_path", default=path)
  let relative = @pathx.relative(cwd_path, absolute) catch { _ => path }
  relative + ":" + loc
}

///|
fn mooncode_moon_ide_cli_action(action : String) -> String {
  match action {
    "peek_def" => "peek-def"
    "find_references" => "find-references"
    other => other
  }
}

///|
async fn mooncode_tool_moon_cmd(book_root : String, arguments : Json) -> Json {
  let command = mooncode_json_string(arguments, "command", default="")
  if !mooncode_moon_cmd_supported(command) {
    return mooncode_tool_error_result(
      "moon_cmd",
      message="unsupported moon_cmd command: \{command}",
      metadata={ "command": command },
    )
  }
  let target = mooncode_json_string(arguments, "target", default="")
  if command != "fmt" && !mooncode_moon_target_supported(target) {
    return mooncode_tool_error_result(
      "moon_cmd",
      message="unsupported moon_cmd target: \{target}",
      metadata={ "target": target },
    )
  }
  if command != "run" &&
    mooncode_json_array_string_items(arguments, "program_args").length() > 0 {
    return mooncode_tool_error_result(
      "moon_cmd",
      message="moon_cmd program_args are only valid for moon run",
    )
  }
  let expected_exit_code = mooncode_json_int(
    arguments,
    "expected_exit_code",
    default=0,
  )
  if expected_exit_code < 0 || expected_exit_code > 255 {
    return mooncode_tool_error_result(
      "moon_cmd",
      message="moon_cmd expected_exit_code must be between 0 and 255",
    )
  }
  if mooncode_moon_cmd_is_test_update(arguments) &&
    (
      mooncode_json_string(arguments, "test_update_kind", default="") == "" ||
      mooncode_json_string(arguments, "test_update_reason", default="") == ""
    ) {
    return mooncode_tool_error_result(
      "moon_cmd",
      message="moon test --update requires test_update_kind and test_update_reason",
    )
  }
  let command_args = mooncode_moon_cmd_command_args(arguments)
  if command == "fmt" && mooncode_moon_fmt_has_malformed_selector(command_args) {
    return mooncode_tool_error_result(
      "moon_cmd",
      message="moon fmt selector options require a non-option value",
    )
  }
  let selector = mooncode_moon_cmd_primary_path(arguments)
  let explicit_cwd = mooncode_json_string(arguments, "cwd", default="") != ""
  let cwd = if explicit_cwd {
    mooncode_tool_cwd(book_root, arguments)
  } else {
    mooncode_moon_module_cwd_for_path(book_root, selector)
  }
  if mooncode_json_bool(cwd, "ok", default=false) == false {
    return mooncode_tool_error_result(
      "moon_cmd",
      message=mooncode_json_string(cwd, "message", default="invalid cwd"),
    )
  }
  let cwd_path = mooncode_json_string(cwd, "absolute_path", default=book_root)
  let selector_root = if explicit_cwd { cwd_path } else { book_root }
  let module_cwd = mooncode_moon_module_cwd_for_path(book_root, cwd_path)
  let module_root = mooncode_json_string(
    module_cwd,
    "absolute_path",
    default=cwd_path,
  )
  for path in mooncode_moon_cmd_paths(arguments) {
    let resolved = mooncode_resolve_book_path(selector_root, path)
    if !mooncode_json_bool(resolved, "ok", default=false) {
      return mooncode_tool_error_result(
        "moon_cmd",
        message=mooncode_json_string(
          resolved,
          "message",
          default="invalid moon_cmd path",
        ),
      )
    }
    let absolute_path = mooncode_json_string(
      resolved,
      "absolute_path",
      default="",
    )
    let path_module = mooncode_moon_module_cwd_for_path(
      book_root, absolute_path,
    )
    if mooncode_json_string(path_module, "absolute_path", default=book_root) !=
      module_root {
      return mooncode_tool_error_result(
        "moon_cmd",
        message="moon_cmd paths must belong to one Moon module",
      )
    }
  }
  let explicit_paths = mooncode_moon_cmd_paths(arguments)
  let fmt_scope_before = if command == "fmt" && explicit_paths.length() > 0 {
    mooncode_moon_fmt_snapshot(book_root)
  } else {
    MoonCodeFmtSnapshot::{ error: "", states: {} }
  }
  if fmt_scope_before.error != "" {
    return mooncode_tool_error_result(
      "moon_cmd",
      message="moon fmt with explicit paths requires a verified Git worktree snapshot before execution: \{fmt_scope_before.error}",
      metadata={
        "command": command,
        "requested_paths": explicit_paths,
        "scope_verification": "failed-before-execution",
      },
    )
  }
  let args = mooncode_moon_cmd_args(
    arguments,
    command,
    selector_root~,
    cwd_path~,
  )
  let timeout = mooncode_json_int(arguments, "timeout_ms", default=60000)
  let process = @spawn.spawn(
    "moon",
    args.map(fn(arg) { arg }),
    timeout~,
    cwd=cwd_path,
  ) catch {
    error =>
      return mooncode_tool_error_result(
        "moon_cmd",
        message="error running moon command: \{error}",
      )
  }
  let capped = mooncode_cap_tool_output(
    process.stdout + process.stderr,
    mooncode_json_int(arguments, "max_output_chars", default=12000),
  )
  let metadata : Json = {
    "command": "moon \{args.join(" ")}",
    "moon_command": command,
    "cwd": mooncode_json_string(cwd, "relative_path", default="."),
    "status": process.status,
    "expected_exit_code": expected_exit_code,
    "elapsed_ms": process.elapsed,
    "truncated": mooncode_json_bool(capped, "truncated", default=false),
    "test_update_kind": mooncode_json_string(
      arguments,
      "test_update_kind",
      default="",
    ),
  }
  if command == "fmt" && explicit_paths.length() > 0 {
    let scope = mooncode_moon_fmt_verify_and_restore(
      book_root, selector_root, explicit_paths, fmt_scope_before,
    )
    guard metadata is Object(fields) else {
      return mooncode_tool_error_result(
        "moon_cmd",
        message="moon fmt scope verification could not attach evidence",
      )
    }
    fields["formatter_scope"] = scope.to_json()
    if scope.snapshot_error != "" {
      return mooncode_tool_error_result(
        "moon_cmd",
        message="moon fmt scope verification failed after execution: \{scope.snapshot_error}; inspect the working tree before any commit",
        output=mooncode_json_string(capped, "output", default=""),
        metadata~,
      )
    }
    if scope.out_of_scope_paths.length() > 0 {
      if scope.retained_paths.length() > 0 {
        return mooncode_tool_error_result(
          "moon_cmd",
          message="moon fmt changed paths outside its explicit scope and could not restore and verify: \{scope.retained_paths.join(", ")}. Stop before committing and inspect the working tree; do not widen formatter scope to resolve this containment failure.",
          output=mooncode_json_string(capped, "output", default=""),
          metadata~,
        )
      }
      if mooncode_moon_cmd_exit_expected(arguments, process.status) {
        return mooncode_tool_ok_result(
          "moon_cmd",
          message="moon fmt formatted the requested paths: \{scope.requested_paths.join(", ")}. Out-of-scope formatter changes were restored and verified: \{scope.restored_paths.join(", ")}. Continue with the task; do not widen formatter scope unless a restored path is independently task-owned.",
          output=mooncode_json_string(capped, "output", default=""),
          metadata~,
        )
      }
    }
  }
  if mooncode_moon_cmd_exit_expected(arguments, process.status) {
    mooncode_tool_ok_result(
      "moon_cmd",
      message="moon \{command} exited expected status \{expected_exit_code}",
      output=mooncode_json_string(capped, "output", default=""),
      metadata~,
    )
  } else {
    mooncode_tool_error_result(
      "moon_cmd",
      message="moon \{command} exited \{process.status}",
      output=mooncode_json_string(capped, "output", default=""),
      metadata~,
    )
  }
}

///|
fn mooncode_moon_cmd_exit_expected(arguments : Json, status : Int) -> Bool {
  status == mooncode_json_int(arguments, "expected_exit_code", default=0)
}

///|
fn mooncode_moon_cmd_supported(command : String) -> Bool {
  command == "check" ||
  command == "test" ||
  command == "run" ||
  command == "info" ||
  command == "fmt" ||
  command == "build"
}

///|
fn mooncode_moon_target_supported(target : String) -> Bool {
  target == "" ||
  target == "wasm" ||
  target == "wasm-gc" ||
  target == "js" ||
  target == "native" ||
  target == "llvm" ||
  target == "all"
}

///|
fn mooncode_moon_cmd_args(
  arguments : Json,
  command : String,
  selector_root~ : String,
  cwd_path~ : String,
) -> Array[String] {
  let args : Array[String] = [command]
  let target = mooncode_json_string(arguments, "target", default="")
  if command != "fmt" && target != "" {
    args.push("--target")
    args.push(target)
  }
  let command_args = mooncode_moon_cmd_command_args(arguments)
  if command == "fmt" {
    for value in mooncode_moon_fmt_normalized_args(command_args) {
      args.push(value)
    }
  } else {
    for value in command_args {
      args.push(value)
    }
  }
  for path in mooncode_moon_cmd_paths(arguments) {
    args.push(
      mooncode_moon_cmd_path_relative_to_cwd(path, selector_root, cwd_path),
    )
  }
  let program_args = mooncode_json_array_string_items(arguments, "program_args")
  if program_args.length() > 0 {
    args.push("--")
    for arg in program_args {
      args.push(arg)
    }
  }
  args
}

///|
fn mooncode_moon_cmd_command_args(arguments : Json) -> Array[String] {
  let values : Array[String] = []
  mooncode_push_json_string_field(values, arguments, "arg")
  mooncode_push_json_string_array_field(values, arguments, "args")
  values
}

///|
fn mooncode_moon_cmd_paths(arguments : Json) -> Array[String] {
  let paths : Array[String] = []
  mooncode_push_json_string_field(paths, arguments, "path")
  mooncode_push_json_string_array_field(paths, arguments, "paths")
  paths
}

///|
fn mooncode_moon_cmd_primary_path(arguments : Json) -> String {
  let paths = mooncode_moon_cmd_paths(arguments)
  if paths.length() == 0 {
    ""
  } else {
    paths[0]
  }
}

///|
/// `moon fmt` accepts paths but has neither backend nor package selectors.
/// Planner calls occasionally copy selectors from check/test/info. Remove only
/// those command-incompatible selectors and preserve formatter options.
fn mooncode_moon_fmt_normalized_args(values : Array[String]) -> Array[String] {
  let normalized : Array[String] = []
  let mut skip_selector_value = false
  for value in values {
    if skip_selector_value {
      skip_selector_value = false
    } else if value == "--target" || value == "--package" || value == "-p" {
      skip_selector_value = true
    } else if value.has_prefix("--target=") || value.has_prefix("--package=") {
      ()
    } else {
      normalized.push(value)
    }
  }
  normalized
}

///|
fn mooncode_moon_fmt_has_malformed_selector(values : Array[String]) -> Bool {
  for index, value in values {
    if value == "--target" || value == "--package" || value == "-p" {
      if index + 1 >= values.length() || values[index + 1].has_prefix("-") {
        return true
      }
    }
  }
  false
}

///|
fn mooncode_moon_cmd_path_relative_to_cwd(
  path : String,
  selector_root : String,
  cwd_path : String,
) -> String {
  let resolved = mooncode_resolve_book_path(selector_root, path)
  if !mooncode_json_bool(resolved, "ok", default=false) {
    return path
  }
  let absolute = mooncode_json_string(resolved, "absolute_path", default=path)
  @pathx.relative(cwd_path, absolute) catch {
    _ => path
  }
}

///|
fn mooncode_moon_cmd_is_test_update(arguments : Json) -> Bool {
  if mooncode_json_string(arguments, "command", default="") != "test" {
    return false
  }
  let arg = mooncode_json_string(arguments, "arg", default="")
  if arg == "--update" || arg == "-u" {
    return true
  }
  for arg in mooncode_json_array_string_items(arguments, "args") {
    if arg == "--update" || arg == "-u" {
      return true
    }
  }
  false
}

///|
fn mooncode_push_json_string_field(
  args : Array[String],
  json : Json,
  key : String,
) -> Unit {
  let value = mooncode_json_string(json, key, default="")
  if value != "" {
    args.push(value)
  }
}

///|
fn mooncode_push_json_string_array_field(
  args : Array[String],
  json : Json,
  key : String,
) -> Unit {
  for value in mooncode_json_array_string_items(json, key) {
    args.push(value)
  }
}

///|
fn mooncode_json_array_string_items(json : Json, key : String) -> Array[String] {
  let values : Array[String] = []
  for item in mooncode_json_array_items(json, key) {
    match item {
      String(value) => values.push(value)
      _ => ()
    }
  }
  values
}

///|
async fn mooncode_tool_moon_check(book_root : String, arguments : Json) -> Json {
  let target = mooncode_json_string(arguments, "target", default="")
  if !mooncode_moon_target_supported(target) {
    return mooncode_tool_error_result(
      "moon_check",
      message="unsupported moon_check target: \{target}",
      metadata={ "target": target },
    )
  }
  let cwd = mooncode_tool_cwd(book_root, arguments)
  if !mooncode_json_bool(cwd, "ok", default=false) {
    return mooncode_tool_error_result(
      "moon_check",
      message=mooncode_json_string(cwd, "message", default="invalid cwd"),
    )
  }
  let args = mooncode_moon_check_args(target)
  let cwd_path = mooncode_json_string(cwd, "absolute_path", default=book_root)
  let cwd_relative = mooncode_json_string(cwd, "relative_path", default=".")
  let command = mooncode_moon_check_command(target) + " (cwd=\{cwd_relative})"
  let key = mooncode_moon_check_key(cwd_path)
  let previous = mooncode_moon_check_read_state(book_root)
  let previous_command = mooncode_json_string(previous, "command", default="")
  let previous_status = mooncode_json_string(previous, "status", default="")
  let previous_seq = mooncode_json_int(previous, "seq", default=0)
  let restart_count = mooncode_json_int(previous, "restart_count", default=0)
  let watcher = if previous_status == "" {
    "started"
  } else if previous_status == "running" && previous_command == command {
    "reused"
  } else if previous_status == "running" {
    "replaced"
  } else {
    "restarted"
  }
  let restart_count = if watcher == "restarted" || watcher == "replaced" {
    restart_count + 1
  } else {
    restart_count
  }
  let timeout = mooncode_json_int(arguments, "timeout_ms", default=60000)
  let process = @spawn.spawn(
    "moon",
    args.map(fn(arg) { arg }),
    timeout~,
    cwd=cwd_path,
  ) catch {
    error =>
      return mooncode_tool_error_result(
        "moon_check",
        message="error running moon check: \{error}",
      )
  }
  let output = process.stdout + process.stderr
  let capped = mooncode_cap_tool_output(
    output,
    mooncode_json_int(arguments, "max_output_chars", default=12000),
  )
  let seq = previous_seq + 1
  let state = mooncode_moon_check_state(
    book_root,
    command,
    target,
    key,
    watcher,
    seq,
    restart_count,
    process.status,
    process.elapsed,
    mooncode_json_string(capped, "output", default=""),
    mooncode_json_bool(capped, "truncated", default=false),
    mooncode_json_int(capped, "max_output_chars", default=12000),
  )
  mooncode_moon_check_write_state(book_root, state)
  if process.status == 0 {
    mooncode_tool_ok_result(
      "moon_check",
      message=mooncode_moon_check_message("moon check passed", state),
      output=mooncode_json_string(capped, "output", default=""),
      metadata=state,
    )
  } else {
    mooncode_tool_error_result(
      "moon_check",
      message=mooncode_moon_check_message(
        "moon check failed with status \{process.status}",
        state,
      ),
      output=mooncode_json_string(capped, "output", default=""),
      metadata=state,
    )
  }
}

///|
fn mooncode_moon_check_args(target : String) -> Array[String] {
  if target == "" {
    ["check"]
  } else {
    ["check", "--target", target]
  }
}

///|
fn mooncode_moon_check_key(book_root : String) -> String {
  "moon-check:" + @pathx.normalize(book_root)
}

///|
fn mooncode_moon_check_command(target : String) -> String {
  if target == "" {
    "moon check --watch --diagnostic-limit 10"
  } else {
    "moon check --watch --diagnostic-limit 10 \{target}"
  }
}

///|
fn mooncode_moon_check_state_path(book_root : String) -> String {
  @moonsuite.product_artifact_for_workspace_root(
    book_root, "moonclaw", "mooncode/watchers/moon-check.json",
  )
}

///|
async fn mooncode_moon_check_read_state(book_root : String) -> Json {
  let path = mooncode_moon_check_state_path(book_root)
  if !@fsx.exists(path) {
    return Json::object({})
  }
  @json.parse(@fsx.read_file(path)) catch {
    _ => Json::object({})
  }
}

///|
async fn mooncode_moon_check_write_state(
  book_root : String,
  state : Json,
) -> Unit {
  let path = mooncode_moon_check_state_path(book_root)
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  @fsx.write_to_file(path, state.stringify(indent=2))
}

///|
fn mooncode_moon_check_state(
  book_root : String,
  command : String,
  target : String,
  key : String,
  watcher : String,
  seq : Int,
  restart_count : Int,
  exit_code : Int,
  elapsed_ms : Int,
  output : String,
  truncated : Bool,
  max_output_chars : Int,
) -> Json {
  let status = if exit_code == 0 { "running" } else { "stopped" }
  {
    "kind": "mooncode-moon-check-watcher",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "book_root": @pathx.normalize(book_root),
    "target": target,
    "key": key,
    "id": mooncode_moon_check_id(key),
    "command": command,
    "watcher": watcher,
    "status": status,
    "seq": seq,
    "exit_status": exit_code,
    "exit_code": exit_code,
    "elapsed_ms": elapsed_ms,
    "restart_count": restart_count,
    "restart_limit": 3,
    "truncated": truncated,
    "max_output_chars": max_output_chars,
    "output": output,
    "state_path": mooncode_moon_check_state_path(book_root),
  }
}

///|
fn mooncode_moon_check_id(key : String) -> String {
  let mut hash = 5381
  for ch in key {
    hash = hash * 33 + ch.to_int()
  }
  "moon-check-\{hash}"
}

///|
fn mooncode_moon_check_message(prefix : String, state : Json) -> String {
  let watcher = mooncode_json_string(state, "watcher", default="started")
  let status = mooncode_json_string(state, "status", default="stopped")
  let seq = mooncode_json_int(state, "seq", default=0)
  "\{prefix}; watcher=\{watcher}; status=\{status}; seq=\{seq}"
}
