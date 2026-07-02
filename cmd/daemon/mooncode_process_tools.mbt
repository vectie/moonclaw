///|
async fn mooncode_tool_shell(book_root : String, arguments : Json) -> Json {
  let cmd = mooncode_json_string(arguments, "cmd", default="")
  if cmd == "" {
    return mooncode_tool_error_result("shell", message="cmd must be non-empty")
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
  let process = @spawn.spawn("sh", ["-lc", cmd], timeout~, cwd=cwd_path) catch {
    error =>
      return mooncode_tool_error_result(
        "shell",
        message="error running shell: \{error}",
      )
  }
  let output = process.stdout + process.stderr
  let capped = mooncode_cap_tool_output(
    output,
    mooncode_json_int(arguments, "max_output_chars", default=12000),
  )
  let result = if process.status == 0 {
    mooncode_tool_ok_result(
      "shell",
      message="shell exited 0",
      output=mooncode_json_string(capped, "output", default=""),
      metadata={
        "cmd": cmd,
        "cwd": mooncode_json_string(cwd, "relative_path", default="."),
        "status": process.status,
        "elapsed_ms": process.elapsed,
        "truncated": mooncode_json_bool(capped, "truncated", default=false),
      },
    )
  } else {
    mooncode_tool_error_result(
      "shell",
      message="shell exited \{process.status}",
      output=mooncode_json_string(capped, "output", default=""),
      metadata={
        "cmd": cmd,
        "cwd": mooncode_json_string(cwd, "relative_path", default="."),
        "status": process.status,
        "elapsed_ms": process.elapsed,
        "truncated": mooncode_json_bool(capped, "truncated", default=false),
      },
    )
  }
  result
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
  if !mooncode_moon_target_supported(target) {
    return mooncode_tool_error_result(
      "moon_ide",
      message="unsupported moon_ide target: \{target}",
      metadata={ "target": target },
    )
  }
  let cwd = mooncode_tool_cwd(book_root, arguments)
  if mooncode_json_bool(cwd, "ok", default=false) == false {
    return mooncode_tool_error_result(
      "moon_ide",
      message=mooncode_json_string(cwd, "message", default="invalid cwd"),
    )
  }
  let args = mooncode_moon_ide_args(arguments, action)
  let timeout = mooncode_json_int(arguments, "timeout_ms", default=30000)
  let cwd_path = mooncode_json_string(cwd, "absolute_path", default=book_root)
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
fn mooncode_moon_ide_args(arguments : Json, action : String) -> Array[String] {
  let args : Array[String] = ["ide", mooncode_moon_ide_cli_action(action)]
  if mooncode_json_bool(arguments, "no_check", default=false) {
    args.push("--no-check")
  }
  let target = mooncode_json_string(arguments, "target", default="")
  if target != "" {
    args.push("--target")
    args.push(target)
  }
  let loc = mooncode_json_string(arguments, "loc", default="")
  if loc != "" {
    args.push("--loc")
    args.push(loc)
  }
  let operand = if action == "outline" {
    mooncode_json_string(arguments, "path", default="")
  } else {
    mooncode_json_string(arguments, "query", default="")
  }
  if operand != "" {
    args.push(operand)
  }
  args
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
  if command == "fmt" &&
    mooncode_json_string(arguments, "target", default="") != "" {
    return mooncode_tool_error_result(
      "moon_cmd",
      message="moon fmt does not accept target in moon_cmd",
    )
  }
  let target = mooncode_json_string(arguments, "target", default="")
  if !mooncode_moon_target_supported(target) {
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
  let cwd = mooncode_tool_cwd(book_root, arguments)
  if mooncode_json_bool(cwd, "ok", default=false) == false {
    return mooncode_tool_error_result(
      "moon_cmd",
      message=mooncode_json_string(cwd, "message", default="invalid cwd"),
    )
  }
  let args = mooncode_moon_cmd_args(arguments, command)
  let timeout = mooncode_json_int(arguments, "timeout_ms", default=60000)
  let cwd_path = mooncode_json_string(cwd, "absolute_path", default=book_root)
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
    "elapsed_ms": process.elapsed,
    "truncated": mooncode_json_bool(capped, "truncated", default=false),
    "test_update_kind": mooncode_json_string(
      arguments,
      "test_update_kind",
      default="",
    ),
  }
  if process.status == 0 {
    mooncode_tool_ok_result(
      "moon_cmd",
      message="moon \{command} exited 0",
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
fn mooncode_moon_cmd_args(arguments : Json, command : String) -> Array[String] {
  let args : Array[String] = [command]
  let target = mooncode_json_string(arguments, "target", default="")
  if target != "" {
    args.push("--target")
    args.push(target)
  }
  mooncode_push_json_string_field(args, arguments, "arg")
  mooncode_push_json_string_array_field(args, arguments, "args")
  mooncode_push_json_string_field(args, arguments, "path")
  mooncode_push_json_string_array_field(args, arguments, "paths")
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
fn mooncode_moon_cmd_is_test_update(arguments : Json) -> Bool {
  if mooncode_json_string(arguments, "command", default="") != "test" {
    return false
  }
  if mooncode_json_string(arguments, "arg", default="") == "--update" {
    return true
  }
  for arg in mooncode_json_array_string_items(arguments, "args") {
    if arg == "--update" {
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
  let args : Array[StringView] = if target == "" {
    ["check"]
  } else {
    ["check", target]
  }
  let command = mooncode_moon_check_command(target)
  let key = mooncode_moon_check_key(book_root)
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
  let process = @spawn.spawn("moon", args, timeout~, cwd=book_root) catch {
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
