///|
async fn Daemon::mooncode_tool_execute(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
  let body : Json = reader.read() catch {
    _ =>
      raise json_error(400, "Bad Request", {
        "error": {
          "code": -1,
          "message": "Invalid JSON body for MoonCode tool execution",
        },
      })
  }
  let session_id = session_id.to_string()
  let requested_book_root = mooncode_request_book_root(r)
  let book_root = if requested_book_root == "" {
    mooncode_json_string(body, "book_root", default="")
  } else {
    requested_book_root
  }
  let report = mooncode_validate_tool_call_body(session_id, book_root, body)
  if !mooncode_json_bool(report, "ok", default=false) {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": mooncode_json_string(
          report,
          "message",
          default="Invalid MoonCode tool execution payload",
        ),
        "metadata": report,
      },
    })
  }
  let execution = mooncode_execute_tool_call(
    session_id,
    book_root,
    body,
    now=self.clock.now(),
  )
  let event = mooncode_json_object_field_or_empty(execution, "event")
  let binding = self.mooncode_binding_for_session(session_id)
  if binding.book_root == "" {
    binding.book_root = book_root
  }
  binding.command_count += 1
  binding.last_command_id = mooncode_json_string(
    execution,
    "command_id",
    default="",
  )
  binding.last_updated = self.clock.now()
  binding.events.put(event)
  self.mooncode_persist_event(binding, event)
  self.mooncode_persist_session(binding)
  w.header().set("Content-Type", "application/json")
  w.write_header(202, reason="Accepted")
  w.write(execution.stringify(indent=2))
}

///|
fn mooncode_validate_tool_call_body(
  session_id : String,
  book_root : String,
  body : Json,
) -> Json {
  let protocol = mooncode_json_string(body, "protocol", default="")
  let body_session = mooncode_json_string(body, "session_id", default="")
  let command_id = mooncode_tool_command_id(body)
  let tool = mooncode_tool_name(body)
  let missing : Array[Json] = []
  if protocol != "mooncode.v1" {
    missing.push("protocol".to_json())
  }
  if body_session != session_id {
    missing.push("session_id".to_json())
  }
  if book_root == "" {
    missing.push("book_root".to_json())
  }
  if command_id == "" {
    missing.push("command_id".to_json())
  }
  if !mooncode_tool_supported(tool) {
    missing.push("tool".to_json())
  }
  {
    "ok": missing.length() == 0,
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "tool": tool,
    "missing": Json::array(missing),
    "message": if missing.length() == 0 {
      "MoonCode tool execution payload is valid"
    } else {
      "MoonCode tool execution payload is missing required fields: \{missing.map(item => item.stringify()).join(", ")}"
    },
  }
}

///|
async fn mooncode_execute_tool_call(
  session_id : String,
  book_root : String,
  body : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let tool = mooncode_tool_name(body)
  let command_id = mooncode_tool_command_id(body)
  let arguments = mooncode_json_object_field_or_empty(body, "arguments")
  let result = match tool {
    "read" => mooncode_tool_read(book_root, arguments)
    "write" => mooncode_tool_write(book_root, arguments)
    "edit" => mooncode_tool_edit(book_root, arguments)
    "shell" => mooncode_tool_shell(book_root, arguments)
    "moon_check" => mooncode_tool_moon_check(book_root, arguments)
    "finish" => mooncode_tool_finish(arguments)
    _ =>
      mooncode_tool_error_result(
        tool,
        message="unsupported MoonCode tool `\{tool}`",
      )
  }
  let event = mooncode_tool_result_event(
    session_id,
    book_root,
    command_id,
    tool,
    result,
    now~,
  )
  {
    "accepted": !mooncode_json_bool(result, "is_error", default=false),
    "kind": "mooncode-tool-execution",
    "protocol": "mooncode.v1",
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "tool": tool,
    "arguments": arguments,
    "result": result,
    "event": event,
  }
}

///|
fn mooncode_tool_supported(tool : String) -> Bool {
  tool == "read" ||
  tool == "edit" ||
  tool == "write" ||
  tool == "shell" ||
  tool == "moon_check" ||
  tool == "finish"
}

///|
fn mooncode_tool_name(body : Json) -> String {
  let tool = mooncode_json_string(body, "tool", default="")
  if tool != "" {
    return tool
  }
  let name = mooncode_json_string(body, "name", default="")
  if name != "" {
    return name
  }
  let call = mooncode_json_object_field_or_empty(body, "tool_call")
  mooncode_json_string(call, "name", default="")
}

///|
fn mooncode_tool_command_id(body : Json) -> String {
  let command_id = mooncode_json_string(body, "command_id", default="")
  if command_id != "" {
    return command_id
  }
  let packet = mooncode_json_object_field_or_empty(body, "command_packet")
  let packet_id = mooncode_json_string(packet, "command_id", default="")
  if packet_id != "" {
    return packet_id
  }
  let packet = mooncode_json_object_field_or_empty(body, "packet")
  mooncode_json_string(packet, "command_id", default="")
}

///|
async fn mooncode_tool_read(book_root : String, arguments : Json) -> Json {
  let path = mooncode_tool_path(book_root, arguments)
  if mooncode_json_bool(path, "ok", default=false) == false {
    return mooncode_tool_error_result(
      "read",
      message=mooncode_json_string(path, "message", default="invalid path"),
    )
  }
  let absolute = mooncode_json_string(path, "absolute_path", default="")
  let content = @fsx.read_file(absolute) catch {
    error =>
      return mooncode_tool_error_result(
        "read",
        message="error reading \{absolute}: \{error}",
      )
  }
  let capped = mooncode_cap_tool_output(
    content,
    mooncode_json_int(arguments, "max_output_chars", default=12000),
  )
  mooncode_tool_ok_result(
    "read",
    message="read \{mooncode_json_string(path, "relative_path", default="")}",
    output=mooncode_json_string(capped, "output", default=""),
    metadata={
      "path": mooncode_json_string(path, "relative_path", default=""),
      "absolute_path": absolute,
      "char_count": content.length(),
      "truncated": mooncode_json_bool(capped, "truncated", default=false),
    },
  )
}

///|
async fn mooncode_tool_write(book_root : String, arguments : Json) -> Json {
  let path = mooncode_tool_path(book_root, arguments)
  if mooncode_json_bool(path, "ok", default=false) == false {
    return mooncode_tool_error_result(
      "write",
      message=mooncode_json_string(path, "message", default="invalid path"),
    )
  }
  let absolute = mooncode_json_string(path, "absolute_path", default="")
  let relative = mooncode_json_string(path, "relative_path", default="")
  let content = mooncode_json_string(arguments, "content", default="")
  let existed = @fsx.exists(absolute)
  let before = if existed {
    @fsx.read_file(absolute) catch {
      _ => ""
    }
  } else {
    ""
  }
  @fsx.make_directory(@pathx.dirname(absolute), recursive=true, exists_ok=true)
  @fsx.write_to_file(absolute, content) catch {
    error =>
      return mooncode_tool_error_result(
        "write",
        message="error writing \{absolute}: \{error}",
      )
  }
  mooncode_tool_ok_result(
    "write",
    message="wrote \{content.length()} chars to \{relative}",
    output="",
    metadata={
      "path": relative,
      "absolute_path": absolute,
      "char_count": content.length(),
      "changed": before != content,
      "diff": mooncode_tool_unified_diff(relative, before, content, existed~),
    },
  )
}

///|
async fn mooncode_tool_edit(book_root : String, arguments : Json) -> Json {
  let path = mooncode_tool_path(book_root, arguments)
  if mooncode_json_bool(path, "ok", default=false) == false {
    return mooncode_tool_error_result(
      "edit",
      message=mooncode_json_string(path, "message", default="invalid path"),
    )
  }
  let absolute = mooncode_json_string(path, "absolute_path", default="")
  let old_string = mooncode_json_string(arguments, "old_string", default="")
  let new_string = mooncode_json_string(arguments, "new_string", default="")
  let replace_all = mooncode_json_bool(arguments, "replace_all", default=false)
  if old_string == "" {
    return mooncode_tool_error_result(
      "edit",
      message="old_string must be non-empty",
    )
  }
  if old_string == new_string {
    return mooncode_tool_error_result(
      "edit",
      message="old_string and new_string are identical",
    )
  }
  let content = @fsx.read_file(absolute) catch {
    error =>
      return mooncode_tool_error_result(
        "edit",
        message="error reading \{absolute}: \{error}",
      )
  }
  let occurrences = content.split(old_string).count() - 1
  if occurrences == 0 {
    return mooncode_tool_error_result("edit", message="old_string not found")
  }
  if occurrences > 1 && !replace_all {
    return mooncode_tool_error_result(
      "edit",
      message="old_string matched \{occurrences} times; set replace_all=true to replace all occurrences",
    )
  }
  let replacement_count = if replace_all { occurrences } else { 1 }
  let new_content = if replace_all {
    content
    .split(old_string)
    .map(part => part.to_owned())
    .collect()
    .join(new_string)
  } else {
    content.replace(old=old_string, new=new_string)
  }
  @fsx.write_to_file(absolute, new_content) catch {
    error =>
      return mooncode_tool_error_result(
        "edit",
        message="error writing \{absolute}: \{error}",
      )
  }
  mooncode_tool_ok_result(
    "edit",
    message="replaced \{replacement_count} occurrence(s) in \{mooncode_json_string(path, "relative_path", default="")}",
    output="",
    metadata={
      "path": mooncode_json_string(path, "relative_path", default=""),
      "absolute_path": absolute,
      "replacement_count": replacement_count,
      "changed": content != new_content,
      "diff": mooncode_tool_unified_diff(
        mooncode_json_string(path, "relative_path", default=""),
        content,
        new_content,
        existed=true,
      ),
    },
  )
}

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
async fn mooncode_tool_moon_check(book_root : String, arguments : Json) -> Json {
  let target = mooncode_json_string(arguments, "target", default="")
  let args : Array[StringView] = if target == "" {
    ["check"]
  } else {
    ["check", target]
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
  if process.status == 0 {
    mooncode_tool_ok_result(
      "moon_check",
      message="moon check passed",
      output=mooncode_json_string(capped, "output", default=""),
      metadata={
        "target": target,
        "status": process.status,
        "elapsed_ms": process.elapsed,
        "truncated": mooncode_json_bool(capped, "truncated", default=false),
      },
    )
  } else {
    mooncode_tool_error_result(
      "moon_check",
      message="moon check failed with status \{process.status}",
      output=mooncode_json_string(capped, "output", default=""),
      metadata={
        "target": target,
        "status": process.status,
        "elapsed_ms": process.elapsed,
        "truncated": mooncode_json_bool(capped, "truncated", default=false),
      },
    )
  }
}

///|
fn mooncode_tool_finish(arguments : Json) -> Json {
  let answer = mooncode_json_string(arguments, "answer", default="")
  mooncode_tool_ok_result("finish", message="finished", output=answer, metadata={
    "answer": answer,
  })
}

///|
fn mooncode_tool_path(book_root : String, arguments : Json) -> Json {
  let relative = mooncode_json_string(arguments, "path", default="")
  if relative == "" {
    return { "ok": false, "message": "path must be non-empty" }
  }
  mooncode_resolve_book_path(book_root, relative)
}

///|
fn mooncode_tool_cwd(book_root : String, arguments : Json) -> Json {
  let cwd = mooncode_json_string(arguments, "cwd", default="")
  if cwd == "" {
    return {
      "ok": true,
      "relative_path": ".",
      "absolute_path": @pathx.normalize(book_root),
    }
  }
  mooncode_resolve_book_path(book_root, cwd)
}

///|
fn mooncode_resolve_book_path(book_root : String, path : String) -> Json {
  let root = @pathx.normalize(book_root)
  let absolute = if @pathx.is_absolute(path) {
    @pathx.normalize(path)
  } else {
    @pathx.join(root, path)
  }
  if absolute != root && !absolute.has_prefix(root + "/") {
    {
      "ok": false,
      "message": "path escapes MoonBook root: \{path}",
      "book_root": root,
      "absolute_path": absolute,
    }
  } else {
    {
      "ok": true,
      "book_root": root,
      "relative_path": if absolute == root {
        "."
      } else {
        absolute[root.length() + 1:].to_string()
      },
      "absolute_path": absolute,
    }
  }
}

///|
fn mooncode_cap_tool_output(text : String, limit : Int) -> Json {
  let limit = if limit <= 0 {
    12000
  } else if limit > 50000 {
    50000
  } else {
    limit
  }
  if text.length() > limit {
    {
      "output": text[:limit].to_string(),
      "truncated": true,
      "max_output_chars": limit,
      "char_count": text.length(),
    }
  } else {
    {
      "output": text,
      "truncated": false,
      "max_output_chars": limit,
      "char_count": text.length(),
    }
  }
}

///|
fn mooncode_tool_unified_diff(
  path : String,
  before : String,
  after : String,
  existed~ : Bool,
) -> String {
  if before == after {
    return ""
  }
  let from_path = if existed { "a/\{path}" } else { "/dev/null" }
  let to_path = "b/\{path}"
  let lines : Array[String] = ["--- \{from_path}", "+++ \{to_path}", "@@"]
  for line in mooncode_tool_diff_side("-", before) {
    lines.push(line)
  }
  for line in mooncode_tool_diff_side("+", after) {
    lines.push(line)
  }
  lines.join("\n") + "\n"
}

///|
fn mooncode_tool_diff_side(prefix : String, text : String) -> Array[String] {
  if text == "" {
    return []
  }
  let lines : Array[String] = []
  let mut count = 0
  for part in text.split("\n") {
    if count < 80 {
      lines.push(prefix + part.to_string())
    }
    count += 1
  }
  if count > 80 {
    lines.push(prefix + "... diff truncated after 80 lines")
  }
  lines
}

///|
fn mooncode_tool_ok_result(
  tool : String,
  message~ : String,
  output~ : String,
  metadata~ : Json,
) -> Json {
  {
    "tool": tool,
    "ok": true,
    "is_error": false,
    "message": message,
    "output": output,
    "metadata": metadata,
  }
}

///|
fn mooncode_tool_error_result(
  tool : String,
  message~ : String,
  output? : String = "",
  metadata? : Json = {},
) -> Json {
  {
    "tool": tool,
    "ok": false,
    "is_error": true,
    "message": message,
    "output": output,
    "metadata": metadata,
  }
}

///|
fn mooncode_tool_result_event(
  session_id : String,
  book_root : String,
  command_id : String,
  tool : String,
  result : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let ok = mooncode_json_bool(result, "ok", default=false)
  let metadata = mooncode_json_object_field_or_empty(result, "metadata")
  let path = mooncode_json_string(metadata, "path", default="")
  let diff = mooncode_json_string(metadata, "diff", default="")
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-tool-\{tool}-\{now}",
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "lane": mooncode_tool_event_lane(tool, path~, diff~),
    "kind": mooncode_tool_event_kind(tool),
    "title": "MoonCode tool `\{tool}` \{if ok { "completed" } else { "failed" }}",
    "status": if ok {
      "done"
    } else {
      "failed"
    },
    "detail": mooncode_json_string(result, "message", default=""),
    "path": path,
    "diff": diff,
    "tool": tool,
    "tool_result": result,
    "created_at": now,
    "source": "moonclaw-native-tool-exec",
  }
}

///|
fn mooncode_tool_event_lane(
  tool : String,
  path? : String = "",
  diff? : String = "",
) -> String {
  match tool {
    "moon_check" => "test"
    "finish" => "review"
    "write" | "edit" => "diff"
    _ if diff != "" || path != "" => "diff"
    _ => "tool"
  }
}

///|
fn mooncode_tool_event_kind(tool : String) -> String {
  match tool {
    "moon_check" => "moon_check.finished"
    "finish" => "finish"
    _ => "tool_result"
  }
}

///|
fn mooncode_json_int(json : Json, key : String, default~ : Int) -> Int {
  match json {
    Json::Object(object) =>
      match object.get(key) {
        Some(value) => @json.from_json(value) catch { _ => default }
        None => default
      }
    _ => default
  }
}

///|
test "mooncode tool validation requires supported tool and command id" {
  let report = mooncode_validate_tool_call_body("session-demo", "/tmp/book", {
    "protocol": "mooncode.v1",
    "session_id": "session-demo",
    "tool": "read",
    "arguments": { "path": "README.md" },
    "packet": { "command_id": "cmd-1" },
  })
  assert_true(mooncode_json_bool(report, "ok", default=false))
  let rejected = mooncode_validate_tool_call_body("session-demo", "/tmp/book", {
    "protocol": "mooncode.v1",
    "session_id": "session-demo",
    "tool": "delete_everything",
  })
  assert_false(mooncode_json_bool(rejected, "ok", default=true))
  assert_true(rejected.stringify().contains("tool"))
  assert_true(rejected.stringify().contains("command_id"))
}

///|
test "mooncode tool paths stay under book root" {
  let ok = mooncode_resolve_book_path("/tmp/book", "wiki/index.md")
  assert_true(mooncode_json_bool(ok, "ok", default=false))
  assert_eq(
    mooncode_json_string(ok, "absolute_path", default=""),
    "/tmp/book/wiki/index.md",
  )
  let escaped = mooncode_resolve_book_path("/tmp/book", "../outside.md")
  assert_false(mooncode_json_bool(escaped, "ok", default=true))
}

///|
async test "mooncode native tool execution writes edits and reads book files" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-tools-XXXXXX"),
  )
  let write = mooncode_execute_tool_call(
    "session-tools",
    book_root,
    {
      "protocol": "mooncode.v1",
      "session_id": "session-tools",
      "book_root": book_root,
      "tool": "write",
      "command_id": "cmd-write",
      "arguments": { "path": "tools/demo.txt", "content": "hello mooncode" },
    },
    now=@clock.Timestamp::from_ms(42L),
  )
  assert_true(
    mooncode_json_bool(
      mooncode_json_object_field_or_empty(write, "result"),
      "ok",
      default=false,
    ),
  )
  let edit = mooncode_execute_tool_call(
    "session-tools",
    book_root,
    {
      "protocol": "mooncode.v1",
      "session_id": "session-tools",
      "book_root": book_root,
      "tool": "edit",
      "command_id": "cmd-edit",
      "arguments": {
        "path": "tools/demo.txt",
        "old_string": "mooncode",
        "new_string": "MoonCode",
      },
    },
    now=@clock.Timestamp::from_ms(43L),
  )
  assert_true(
    mooncode_json_bool(
      mooncode_json_object_field_or_empty(edit, "result"),
      "ok",
      default=false,
    ),
  )
  let read = mooncode_execute_tool_call(
    "session-tools",
    book_root,
    {
      "protocol": "mooncode.v1",
      "session_id": "session-tools",
      "book_root": book_root,
      "tool": "read",
      "command_id": "cmd-read",
      "arguments": { "path": "tools/demo.txt" },
    },
    now=@clock.Timestamp::from_ms(44L),
  )
  let result = mooncode_json_object_field_or_empty(read, "result")
  assert_eq(
    mooncode_json_string(result, "output", default=""),
    "hello MoonCode",
  )
  let event = mooncode_json_object_field_or_empty(read, "event")
  assert_eq(mooncode_json_string(event, "kind", default=""), "tool_result")
  let write_event = mooncode_json_object_field_or_empty(write, "event")
  assert_eq(mooncode_json_string(write_event, "lane", default=""), "diff")
  assert_eq(
    mooncode_json_string(write_event, "path", default=""),
    "tools/demo.txt",
  )
  assert_true(
    mooncode_json_string(write_event, "diff", default="").contains(
      "+++ b/tools/demo.txt",
    ),
  )
  let edit_event = mooncode_json_object_field_or_empty(edit, "event")
  assert_eq(mooncode_json_string(edit_event, "lane", default=""), "diff")
  assert_true(
    mooncode_json_string(edit_event, "diff", default="").contains(
      "-hello mooncode",
    ),
  )
}

///|
async test "mooncode native shell tool runs inside book root" (t : @test.Test) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-shell-XXXXXX"),
  )
  let execution = mooncode_execute_tool_call(
    "session-shell",
    book_root,
    {
      "protocol": "mooncode.v1",
      "session_id": "session-shell",
      "book_root": book_root,
      "tool": "shell",
      "command_id": "cmd-shell",
      "arguments": { "cmd": "pwd", "timeout_ms": 5000 },
    },
    now=@clock.Timestamp::from_ms(45L),
  )
  let result = mooncode_json_object_field_or_empty(execution, "result")
  assert_true(mooncode_json_bool(result, "ok", default=false))
  assert_true(
    mooncode_json_string(result, "output", default="").contains(book_root),
  )
}
