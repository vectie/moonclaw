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
    "apply_patch" => mooncode_tool_apply_patch(book_root, arguments)
    "revert_patch" => mooncode_tool_revert_patch(book_root, arguments)
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
  tool == "apply_patch" ||
  tool == "revert_patch" ||
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
async fn mooncode_tool_apply_patch(
  book_root : String,
  arguments : Json,
) -> Json {
  mooncode_tool_patch_replace(
    "apply_patch",
    book_root,
    arguments,
    reverse=false,
  )
}

///|
async fn mooncode_tool_revert_patch(
  book_root : String,
  arguments : Json,
) -> Json {
  mooncode_tool_patch_replace(
    "revert_patch",
    book_root,
    arguments,
    reverse=true,
  )
}

///|
async fn mooncode_tool_patch_replace(
  tool : String,
  book_root : String,
  arguments : Json,
  reverse~ : Bool,
) -> Json {
  let path = mooncode_tool_patch_path(book_root, arguments)
  if mooncode_json_bool(path, "ok", default=false) == false {
    return mooncode_tool_error_result(
      tool,
      message=mooncode_json_string(path, "message", default="invalid path"),
    )
  }
  let absolute = mooncode_json_string(path, "absolute_path", default="")
  let relative = mooncode_json_string(path, "relative_path", default="")
  let existed = @fsx.exists(absolute)
  let content = if existed {
    @fsx.read_file(absolute) catch {
      error =>
        return mooncode_tool_error_result(
          tool,
          message="error reading \{absolute}: \{error}",
          metadata={ "path": relative, "absolute_path": absolute },
        )
    }
  } else {
    ""
  }
  let before_string = mooncode_tool_patch_before(arguments)
  let after_string = mooncode_tool_patch_after(arguments)
  let diff_text = mooncode_tool_patch_diff_text(arguments)
  if before_string == "" && after_string == "" && diff_text != "" {
    return mooncode_tool_apply_unified_diff(
      tool,
      relative,
      absolute,
      content,
      existed~,
      diff_text,
      reverse~,
    )
  }
  let old_string = if reverse { after_string } else { before_string }
  let new_string = if reverse { before_string } else { after_string }
  if old_string == new_string {
    return mooncode_tool_error_result(
      tool,
      message="patch before/after content must differ",
      metadata={ "path": relative, "absolute_path": absolute },
    )
  }
  if content == new_string {
    return mooncode_tool_ok_result(
      tool,
      message="\{tool} already reflected in \{relative}",
      output="",
      metadata={
        "path": relative,
        "absolute_path": absolute,
        "changed": false,
        "diff": "",
        "proof_event": mooncode_tool_patch_proof_event(tool),
      },
    )
  }
  let patched = if old_string == "" {
    if existed && content != "" {
      return mooncode_tool_error_result(
        tool,
        message="empty patch before-content can only create or replace an empty file",
        metadata={ "path": relative, "absolute_path": absolute },
      )
    }
    new_string
  } else {
    let occurrences = content.split(old_string).count() - 1
    if occurrences == 0 {
      return mooncode_tool_error_result(
        tool,
        message="patch before-content not found in \{relative}",
        metadata={ "path": relative, "absolute_path": absolute },
      )
    }
    let replace_all = mooncode_json_bool(
      arguments,
      "replace_all",
      default=false,
    )
    if occurrences > 1 && !replace_all {
      return mooncode_tool_error_result(
        tool,
        message="patch before-content matched \{occurrences} times; set replace_all=true to replace all occurrences",
        metadata={ "path": relative, "absolute_path": absolute },
      )
    }
    if replace_all {
      content
      .split(old_string)
      .map(part => part.to_owned())
      .collect()
      .join(new_string)
    } else {
      content.replace(old=old_string, new=new_string)
    }
  }
  @fsx.make_directory(@pathx.dirname(absolute), recursive=true, exists_ok=true)
  @fsx.write_to_file(absolute, patched) catch {
    error =>
      return mooncode_tool_error_result(
        tool,
        message="error writing \{absolute}: \{error}",
        metadata={ "path": relative, "absolute_path": absolute },
      )
  }
  mooncode_tool_ok_result(
    tool,
    message="\{tool} updated \{relative}",
    output="",
    metadata={
      "path": relative,
      "absolute_path": absolute,
      "changed": content != patched,
      "diff": mooncode_tool_unified_diff(relative, content, patched, existed~),
      "proof_event": mooncode_tool_patch_proof_event(tool),
    },
  )
}

///|
fn mooncode_tool_patch_path(book_root : String, arguments : Json) -> Json {
  let path = mooncode_json_string(arguments, "path", default="")
  if path != "" {
    return mooncode_resolve_book_path(book_root, path)
  }
  let context_path = mooncode_json_string(arguments, "context_path", default="")
  if context_path != "" {
    return mooncode_resolve_book_path(book_root, context_path)
  }
  let target = mooncode_json_string(arguments, "target", default="")
  if target != "" {
    return mooncode_resolve_book_path(book_root, target)
  }
  let diff_path = mooncode_tool_patch_path_from_diff(
    mooncode_tool_patch_diff_text(arguments),
  )
  if diff_path != "" {
    return mooncode_resolve_book_path(book_root, diff_path)
  }
  {
    "ok": false,
    "message": "patch path, context_path, target, or diff path is required",
    "book_root": @pathx.normalize(book_root),
  }
}

///|
fn mooncode_tool_patch_before(arguments : Json) -> String {
  let old_string = mooncode_json_string(arguments, "old_string", default="")
  if old_string != "" {
    return old_string
  }
  let before = mooncode_json_string(arguments, "before", default="")
  if before != "" {
    return before
  }
  mooncode_json_string(arguments, "from", default="")
}

///|
fn mooncode_tool_patch_after(arguments : Json) -> String {
  let new_string = mooncode_json_string(arguments, "new_string", default="")
  if new_string != "" {
    return new_string
  }
  let after = mooncode_json_string(arguments, "after", default="")
  if after != "" {
    return after
  }
  mooncode_json_string(arguments, "content", default="")
}

///|
fn mooncode_tool_patch_diff_text(arguments : Json) -> String {
  let diff = mooncode_json_string(arguments, "diff", default="")
  if diff != "" {
    return diff
  }
  let patch = mooncode_json_string(arguments, "patch", default="")
  if patch != "" {
    return patch
  }
  mooncode_json_string(arguments, "unified_diff", default="")
}

///|
fn mooncode_tool_patch_path_from_diff(diff : String) -> String {
  for line in diff.split("\n") {
    let text = line.to_owned()
    if text.has_prefix("+++ ") {
      let path = mooncode_tool_patch_clean_diff_path(text[4:])
      if path != "" && path != "/dev/null" {
        return path
      }
    }
  }
  for line in diff.split("\n") {
    let text = line.to_owned()
    if text.has_prefix("--- ") {
      let path = mooncode_tool_patch_clean_diff_path(text[4:])
      if path != "" && path != "/dev/null" {
        return path
      }
    }
  }
  ""
}

///|
fn mooncode_tool_patch_clean_diff_path(raw : StringView) -> String {
  let trimmed = raw.trim().to_owned()
  let first = mooncode_tool_first_split_piece(trimmed, "\t")
  let without_timestamp = mooncode_tool_first_split_piece(first, " ")
  if without_timestamp.has_prefix("a/") || without_timestamp.has_prefix("b/") {
    without_timestamp[2:].to_owned()
  } else {
    without_timestamp
  }
}

///|
fn mooncode_tool_first_split_piece(text : String, separator : String) -> String {
  for piece in text.split(separator) {
    return piece.to_owned()
  }
  text
}

///|
async fn mooncode_tool_apply_unified_diff(
  tool : String,
  relative : String,
  absolute : String,
  content : String,
  existed~ : Bool,
  diff_text : String,
  reverse~ : Bool,
) -> Json {
  let chunks = mooncode_tool_patch_chunks_from_unified_diff(diff_text)
  if chunks.length() == 0 {
    return mooncode_tool_error_result(
      tool,
      message="unified diff contains no applicable hunks",
      metadata={ "path": relative, "absolute_path": absolute },
    )
  }
  let mut patched = content
  let mut applied_count = 0
  for chunk in chunks {
    let forward_old = mooncode_json_string(chunk, "old_text", default="")
    let forward_new = mooncode_json_string(chunk, "new_text", default="")
    let old_text = if reverse { forward_new } else { forward_old }
    let new_text = if reverse { forward_old } else { forward_new }
    if old_text == new_text {
      continue
    }
    if old_text == "" {
      if patched != "" {
        return mooncode_tool_error_result(
          tool,
          message="creation hunk can only apply to an empty or missing file",
          metadata={ "path": relative, "absolute_path": absolute },
        )
      }
      patched = new_text
      applied_count += 1
    } else {
      let occurrences = patched.split(old_text).count() - 1
      if occurrences == 0 {
        return mooncode_tool_error_result(
          tool,
          message="unified diff hunk did not match \{relative}",
          metadata={
            "path": relative,
            "absolute_path": absolute,
            "hunk": chunk,
          },
        )
      }
      if occurrences > 1 {
        return mooncode_tool_error_result(
          tool,
          message="unified diff hunk matched \{occurrences} times in \{relative}; refusing ambiguous patch",
          metadata={
            "path": relative,
            "absolute_path": absolute,
            "hunk": chunk,
          },
        )
      }
      patched = patched.replace(old=old_text, new=new_text)
      applied_count += 1
    }
  }
  @fsx.make_directory(@pathx.dirname(absolute), recursive=true, exists_ok=true)
  @fsx.write_to_file(absolute, patched) catch {
    error =>
      return mooncode_tool_error_result(
        tool,
        message="error writing \{absolute}: \{error}",
        metadata={ "path": relative, "absolute_path": absolute },
      )
  }
  mooncode_tool_ok_result(
    tool,
    message="\{tool} applied \{applied_count} unified diff hunk(s) to \{relative}",
    output="",
    metadata={
      "path": relative,
      "absolute_path": absolute,
      "changed": content != patched,
      "diff": mooncode_tool_unified_diff(relative, content, patched, existed~),
      "proof_event": mooncode_tool_patch_proof_event(tool),
      "applied_hunk_count": applied_count,
      "input_diff": diff_text,
    },
  )
}

///|
fn mooncode_tool_patch_chunks_from_unified_diff(diff : String) -> Array[Json] {
  let chunks : Array[Json] = []
  let old_lines : Array[String] = []
  let new_lines : Array[String] = []
  let mut in_hunk = false
  for line_view in diff.split("\n") {
    let line = line_view.to_owned()
    if line.has_prefix("@@") {
      mooncode_tool_patch_flush_chunk(chunks, old_lines, new_lines)
      in_hunk = true
      continue
    }
    if !in_hunk {
      continue
    }
    if line.has_prefix("\\ No newline") {
      continue
    } else if line.has_prefix("-") && !line.has_prefix("---") {
      old_lines.push(line[1:].to_owned())
    } else if line.has_prefix("+") && !line.has_prefix("+++") {
      new_lines.push(line[1:].to_owned())
    } else if line.has_prefix(" ") {
      let context = line[1:].to_owned()
      old_lines.push(context)
      new_lines.push(context)
    }
  }
  mooncode_tool_patch_flush_chunk(chunks, old_lines, new_lines)
  chunks
}

///|
fn mooncode_tool_patch_flush_chunk(
  chunks : Array[Json],
  old_lines : Array[String],
  new_lines : Array[String],
) -> Unit {
  if old_lines.length() == 0 && new_lines.length() == 0 {
    return
  }
  chunks.push({
    "old_text": mooncode_tool_patch_join_hunk_lines(old_lines),
    "new_text": mooncode_tool_patch_join_hunk_lines(new_lines),
    "old_line_count": old_lines.length(),
    "new_line_count": new_lines.length(),
  })
  old_lines.clear()
  new_lines.clear()
}

///|
fn mooncode_tool_patch_join_hunk_lines(lines : Array[String]) -> String {
  if lines.length() == 0 {
    ""
  } else {
    lines.join("\n") + "\n"
  }
}

///|
fn mooncode_tool_patch_proof_event(tool : String) -> String {
  if tool == "revert_patch" {
    "patch_reverted"
  } else {
    "patch_applied"
  }
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
    "event": mooncode_tool_event_name(tool),
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
    "apply_patch" | "revert_patch" => "review"
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
    "apply_patch" => "runtime.patch_applied"
    "revert_patch" => "runtime.patch_reverted"
    _ => "tool_result"
  }
}

///|
fn mooncode_tool_event_name(tool : String) -> String {
  match tool {
    "apply_patch" => "patch_applied"
    "revert_patch" => "patch_reverted"
    "moon_check" => "tool_result"
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
async test "mooncode native patch tools apply and revert reviewed replacements" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-patch-tools-XXXXXX"),
  )
  @fsx.make_directory(
    @pathx.join(book_root, "tools"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    @pathx.join(book_root, "tools/demo.txt"),
    "hello mooncode\n",
  )
  let apply = mooncode_execute_tool_call(
    "session-patch",
    book_root,
    {
      "protocol": "mooncode.v1",
      "session_id": "session-patch",
      "book_root": book_root,
      "tool": "apply_patch",
      "command_id": "cmd-apply",
      "arguments": {
        "path": "tools/demo.txt",
        "old_string": "hello mooncode",
        "new_string": "hello MoonCode",
      },
    },
    now=@clock.Timestamp::from_ms(46L),
  )
  let apply_result = mooncode_json_object_field_or_empty(apply, "result")
  assert_true(mooncode_json_bool(apply_result, "ok", default=false))
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "tools/demo.txt")),
    "hello MoonCode\n",
  )
  let apply_event = mooncode_json_object_field_or_empty(apply, "event")
  assert_eq(
    mooncode_json_string(apply_event, "kind", default=""),
    "runtime.patch_applied",
  )
  assert_eq(
    mooncode_json_string(apply_event, "event", default=""),
    "patch_applied",
  )
  assert_eq(mooncode_json_string(apply_event, "lane", default=""), "review")
  assert_true(
    mooncode_json_string(apply_event, "diff", default="").contains(
      "+hello MoonCode",
    ),
  )
  let revert = mooncode_execute_tool_call(
    "session-patch",
    book_root,
    {
      "protocol": "mooncode.v1",
      "session_id": "session-patch",
      "book_root": book_root,
      "tool": "revert_patch",
      "command_id": "cmd-revert",
      "arguments": {
        "path": "tools/demo.txt",
        "old_string": "hello mooncode",
        "new_string": "hello MoonCode",
      },
    },
    now=@clock.Timestamp::from_ms(47L),
  )
  let revert_result = mooncode_json_object_field_or_empty(revert, "result")
  assert_true(mooncode_json_bool(revert_result, "ok", default=false))
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "tools/demo.txt")),
    "hello mooncode\n",
  )
  let revert_event = mooncode_json_object_field_or_empty(revert, "event")
  assert_eq(
    mooncode_json_string(revert_event, "kind", default=""),
    "runtime.patch_reverted",
  )
  assert_eq(
    mooncode_json_string(revert_event, "event", default=""),
    "patch_reverted",
  )
}

///|
async test "mooncode native patch tools apply and revert unified diffs" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-unified-patch-XXXXXX"),
  )
  @fsx.make_directory(
    @pathx.join(book_root, "tools"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    @pathx.join(book_root, "tools/diff.txt"),
    "alpha\nbeta\ngamma\n",
  )
  let diff = "--- a/tools/diff.txt\n+++ b/tools/diff.txt\n@@\n alpha\n-beta\n+Beta\n gamma\n"
  let apply = mooncode_execute_tool_call(
    "session-unified-patch",
    book_root,
    {
      "protocol": "mooncode.v1",
      "session_id": "session-unified-patch",
      "book_root": book_root,
      "tool": "apply_patch",
      "command_id": "cmd-apply-unified",
      "arguments": { "diff": diff },
    },
    now=@clock.Timestamp::from_ms(48L),
  )
  let apply_result = mooncode_json_object_field_or_empty(apply, "result")
  assert_true(mooncode_json_bool(apply_result, "ok", default=false))
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "tools/diff.txt")),
    "alpha\nBeta\ngamma\n",
  )
  let apply_event = mooncode_json_object_field_or_empty(apply, "event")
  assert_eq(
    mooncode_json_string(apply_event, "path", default=""),
    "tools/diff.txt",
  )
  assert_eq(
    mooncode_json_string(apply_event, "kind", default=""),
    "runtime.patch_applied",
  )
  let apply_metadata = mooncode_json_object_field_or_empty(
    mooncode_json_object_field_or_empty(apply_event, "tool_result"),
    "metadata",
  )
  assert_eq(
    mooncode_json_int(apply_metadata, "applied_hunk_count", default=0),
    1,
  )
  let revert = mooncode_execute_tool_call(
    "session-unified-patch",
    book_root,
    {
      "protocol": "mooncode.v1",
      "session_id": "session-unified-patch",
      "book_root": book_root,
      "tool": "revert_patch",
      "command_id": "cmd-revert-unified",
      "arguments": { "diff": diff },
    },
    now=@clock.Timestamp::from_ms(49L),
  )
  let revert_result = mooncode_json_object_field_or_empty(revert, "result")
  assert_true(mooncode_json_bool(revert_result, "ok", default=false))
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "tools/diff.txt")),
    "alpha\nbeta\ngamma\n",
  )
  let revert_event = mooncode_json_object_field_or_empty(revert, "event")
  assert_eq(
    mooncode_json_string(revert_event, "kind", default=""),
    "runtime.patch_reverted",
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
