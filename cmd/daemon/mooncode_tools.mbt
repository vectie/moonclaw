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
  let session_id = session_id.to_owned()
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
  if protocol != mooncode_protocol_version() {
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
    "protocol": mooncode_protocol_version(),
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
    "moon_ide" => mooncode_tool_moon_ide(book_root, arguments)
    "moon_cmd" => mooncode_tool_moon_cmd(book_root, arguments)
    "moon_check" => mooncode_tool_moon_check(book_root, arguments)
    "finish" =>
      mooncode_tool_finish_for_session(session_id, book_root, arguments)
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
    "protocol": mooncode_protocol_version(),
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
  tool == "moon_ide" ||
  tool == "moon_cmd" ||
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
  if mooncode_moonbit_manifest_write_error(relative, content, existed~)
    is Some(message) {
    return mooncode_tool_error_result("write", message~)
  }
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
      "before_fingerprint": mooncode_tool_content_fingerprint(
        before,
        exists=existed,
      ),
      "after_fingerprint": mooncode_tool_content_fingerprint(
        content,
        exists=true,
      ),
      "diff": mooncode_tool_unified_diff(relative, before, content, existed~),
    },
  )
}

///|
fn mooncode_moonbit_manifest_write_error(
  relative : String,
  content : String,
  existed~ : Bool,
) -> String? {
  let name = @pathx.basename(relative).to_owned()
  if !existed && (name == "moon.mod.json" || name == "moon.pkg.json") {
    return Some(
      "new legacy MoonBit manifest `\{relative}` is not allowed; create current `moon.mod` or `moon.pkg` syntax instead",
    )
  }
  if name == "moon.mod" || name == "moon.pkg" {
    let trimmed = content.trim()
    if trimmed.has_prefix("{") || trimmed.has_prefix("[") {
      return Some(
        "MoonBit manifest `\{relative}` must use current manifest syntax, not JSON",
      )
    }
  }
  if name == "moon.mod" &&
    (
      content.contains("supported_targets") ||
      content.contains("deps =") ||
      content.contains("import =") ||
      content.contains("[\"moonbitlang/") ||
      content.contains("moonbitlang/x =")
    ) {
    return Some(
      "MoonBit module dependencies must use current module syntax such as `import { \"moonbitlang/x@0.4.46\", }`; keep supported_targets and package imports in moon.pkg",
    )
  }
  None
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
  let relative = mooncode_json_string(path, "relative_path", default="")
  if mooncode_moonbit_manifest_write_error(relative, new_content, existed=true)
    is Some(message) {
    return mooncode_tool_error_result("edit", message~)
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
    message="replaced \{replacement_count} occurrence(s) in \{relative}",
    output="",
    metadata={
      "path": relative,
      "absolute_path": absolute,
      "replacement_count": replacement_count,
      "changed": content != new_content,
      "before_fingerprint": mooncode_tool_content_fingerprint(
        content,
        exists=true,
      ),
      "after_fingerprint": mooncode_tool_content_fingerprint(
        new_content,
        exists=true,
      ),
      "diff": mooncode_tool_unified_diff(
        relative,
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
  let before_string = mooncode_tool_patch_before(arguments)
  let after_string = mooncode_tool_patch_after(arguments)
  let diff_text = mooncode_tool_patch_diff_text(arguments)
  if diff_text != "" {
    let patch_files = mooncode_tool_patch_files_from_unified_diff(diff_text)
    if patch_files.length() > 1 {
      return mooncode_tool_apply_unified_patchset(
        tool,
        book_root,
        arguments,
        patch_files,
        diff_text,
        reverse~,
      )
    }
  }
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
  if before_string == "" && after_string == "" && diff_text != "" {
    return mooncode_tool_apply_unified_diff(
      tool,
      book_root,
      arguments,
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
    return mooncode_tool_patch_result(
      tool,
      book_root,
      arguments,
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
  mooncode_tool_patch_result(
    tool,
    book_root,
    arguments,
    message="\{tool} updated \{relative}",
    output="",
    metadata={
      "path": relative,
      "absolute_path": absolute,
      "changed": content != patched,
      "before_fingerprint": mooncode_tool_content_fingerprint(
        content,
        exists=existed,
      ),
      "after_fingerprint": mooncode_tool_content_fingerprint(
        patched,
        exists=true,
      ),
      "diff": mooncode_tool_unified_diff(relative, content, patched, existed~),
      "proof_event": mooncode_tool_patch_proof_event(tool),
    },
  )
}

///|
fn mooncode_tool_patch_path(book_root : String, arguments : Json) -> Json {
  let path = mooncode_json_string(arguments, "path", default="")
  if path != "" {
    return mooncode_resolve_book_path(
      book_root,
      mooncode_tool_patch_file_target(path),
    )
  }
  let context_path = mooncode_json_string(arguments, "context_path", default="")
  if context_path != "" {
    return mooncode_resolve_book_path(
      book_root,
      mooncode_tool_patch_file_target(context_path),
    )
  }
  let target = mooncode_json_string(arguments, "target", default="")
  if target != "" {
    return mooncode_resolve_book_path(
      book_root,
      mooncode_tool_patch_file_target(target),
    )
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
fn mooncode_tool_patch_files_from_unified_diff(diff : String) -> Array[Json] {
  let files : Array[Json] = []
  let lines : Array[String] = []
  let mut old_path = ""
  let mut new_path = ""
  let mut collecting = false
  for line_view in diff.split("\n") {
    let line = line_view.to_owned()
    if line.has_prefix("--- ") {
      mooncode_tool_patch_flush_file(files, old_path, new_path, lines)
      old_path = mooncode_tool_patch_clean_diff_path(line[4:])
      new_path = ""
      lines.push(line)
      collecting = true
    } else if collecting {
      if line.has_prefix("+++ ") && new_path == "" {
        new_path = mooncode_tool_patch_clean_diff_path(line[4:])
      }
      lines.push(line)
    }
  }
  mooncode_tool_patch_flush_file(files, old_path, new_path, lines)
  files
}

///|
fn mooncode_tool_patch_flush_file(
  files : Array[Json],
  old_path : String,
  new_path : String,
  lines : Array[String],
) -> Unit {
  if lines.length() == 0 {
    return
  }
  let path = mooncode_tool_patch_file_path(old_path, new_path)
  if path != "" {
    files.push({
      "path": path,
      "old_path": old_path,
      "new_path": new_path,
      "diff": lines.join("\n") + "\n",
    })
  }
  lines.clear()
}

///|
fn mooncode_tool_patch_file_path(
  old_path : String,
  new_path : String,
) -> String {
  if new_path != "" && new_path != "/dev/null" {
    new_path
  } else if old_path != "" && old_path != "/dev/null" {
    old_path
  } else {
    ""
  }
}

///|
fn mooncode_tool_patch_explicit_file_target(arguments : Json) -> String {
  let path = mooncode_json_string(arguments, "path", default="")
  if path != "" {
    return mooncode_tool_patch_file_target(path)
  }
  let context_path = mooncode_json_string(arguments, "context_path", default="")
  if context_path != "" {
    return mooncode_tool_patch_file_target(context_path)
  }
  let target = mooncode_json_string(arguments, "target", default="")
  if target != "" {
    return mooncode_tool_patch_file_target(target)
  }
  ""
}

///|
fn mooncode_tool_patch_file_target(target : String) -> String {
  let file = mooncode_tool_first_split_piece(target, "#hunk-")
  mooncode_tool_patch_clean_diff_path(file)
}

///|
fn mooncode_tool_patch_selected_hunk_index(arguments : Json) -> Int {
  let hunk_index = mooncode_json_int(arguments, "hunk_index", default=0)
  if hunk_index > 0 {
    return hunk_index
  }
  let selected_hunk_index = mooncode_json_int(
    arguments,
    "selected_hunk_index",
    default=0,
  )
  if selected_hunk_index > 0 {
    return selected_hunk_index
  }
  let hunk_id = mooncode_json_string(arguments, "hunk_id", default="")
  if hunk_id != "" {
    return mooncode_tool_patch_hunk_index_from_text(hunk_id)
  }
  let selected_hunk_id = mooncode_json_string(
    arguments,
    "selected_hunk_id",
    default="",
  )
  if selected_hunk_id != "" {
    return mooncode_tool_patch_hunk_index_from_text(selected_hunk_id)
  }
  let path = mooncode_json_string(arguments, "path", default="")
  if path != "" {
    let index = mooncode_tool_patch_hunk_index_from_target(path)
    if index > 0 {
      return index
    }
  }
  let context_path = mooncode_json_string(arguments, "context_path", default="")
  if context_path != "" {
    let index = mooncode_tool_patch_hunk_index_from_target(context_path)
    if index > 0 {
      return index
    }
  }
  let target = mooncode_json_string(arguments, "target", default="")
  if target != "" {
    return mooncode_tool_patch_hunk_index_from_target(target)
  }
  0
}

///|
fn mooncode_tool_patch_hunk_index_from_target(target : String) -> Int {
  let mut seen_marker = false
  for piece in target.split("#hunk-") {
    if seen_marker {
      return mooncode_tool_patch_hunk_index_from_text(piece.to_owned())
    }
    seen_marker = true
  }
  0
}

///|
fn mooncode_tool_patch_hunk_index_from_text(text : String) -> Int {
  let raw = if text.has_prefix("hunk-") {
    text[5:].to_owned()
  } else {
    mooncode_tool_first_split_piece(text, "#")
  }
  @string.parse_int(raw) catch {
    _ => 0
  }
}

///|
fn mooncode_tool_patch_hunk_target(
  relative : String,
  selected_hunk_index : Int,
) -> String {
  if selected_hunk_index > 0 {
    "\{relative}#hunk-\{selected_hunk_index}"
  } else {
    relative
  }
}

///|
async fn mooncode_tool_apply_unified_patchset(
  tool : String,
  book_root : String,
  arguments : Json,
  files : Array[Json],
  diff_text : String,
  reverse~ : Bool,
) -> Json {
  let plans : Array[Json] = []
  let file_results : Array[Json] = []
  let output_diffs : Array[String] = []
  let selected_hunk_index = mooncode_tool_patch_selected_hunk_index(arguments)
  let selected_file_target = mooncode_tool_patch_explicit_file_target(arguments)
  if selected_hunk_index > 0 && selected_file_target == "" {
    return mooncode_tool_error_result(
      tool,
      message="selected hunk patchsets require path, context_path, or target",
      metadata={
        "path": "patchset",
        "selected_hunk_index": selected_hunk_index,
        "available_file_count": files.length(),
      },
    )
  }
  let mut total_hunks = 0
  let mut changed = false
  let mut matched_selected_file = selected_hunk_index == 0
  for file in files {
    let path_text = mooncode_json_string(file, "path", default="")
    if selected_hunk_index > 0 && path_text != selected_file_target {
      continue
    }
    matched_selected_file = true
    let resolved = mooncode_resolve_book_path(book_root, path_text)
    if mooncode_json_bool(resolved, "ok", default=false) == false {
      return mooncode_tool_error_result(
        tool,
        message=mooncode_json_string(
          resolved,
          "message",
          default="invalid patchset path",
        ),
        metadata={ "path": path_text, "patch_file": file },
      )
    }
    let absolute = mooncode_json_string(resolved, "absolute_path", default="")
    let relative = mooncode_json_string(resolved, "relative_path", default="")
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
    let file_diff = mooncode_json_string(file, "diff", default="")
    let chunks = mooncode_tool_patch_chunks_from_unified_diff(file_diff)
    let available_hunk_count = chunks.length()
    if chunks.length() == 0 {
      return mooncode_tool_error_result(
        tool,
        message="unified patchset file contains no applicable hunks: \{relative}",
        metadata={ "path": relative, "absolute_path": absolute },
      )
    }
    if selected_hunk_index > available_hunk_count {
      return mooncode_tool_error_result(
        tool,
        message="selected hunk \{selected_hunk_index} is outside \{relative}'s \{available_hunk_count} hunk(s)",
        metadata={
          "path": mooncode_tool_patch_hunk_target(relative, selected_hunk_index),
          "file_path": relative,
          "absolute_path": absolute,
          "selected_hunk_index": selected_hunk_index,
          "available_hunk_count": available_hunk_count,
        },
      )
    }
    let selected_chunks : Array[Json] = []
    if selected_hunk_index > 0 {
      selected_chunks.push(chunks[selected_hunk_index - 1])
    } else {
      for chunk in chunks {
        selected_chunks.push(chunk)
      }
    }
    let proof_path = mooncode_tool_patch_hunk_target(
      relative, selected_hunk_index,
    )
    let patched_result = mooncode_tool_apply_unified_chunks_to_content(
      tool,
      proof_path,
      absolute,
      content,
      selected_chunks,
      reverse~,
    )
    if mooncode_json_bool(patched_result, "ok", default=false) == false {
      return patched_result
    }
    let patched = mooncode_json_string(
      patched_result,
      "patched",
      default=content,
    )
    let applied_count = mooncode_json_int(
      patched_result,
      "applied_hunk_count",
      default=0,
    )
    let old_path = mooncode_json_string(file, "old_path", default="")
    let new_path = mooncode_json_string(file, "new_path", default="")
    let delete_file = (new_path == "/dev/null" && !reverse) ||
      (old_path == "/dev/null" && reverse)
    let file_changed = content != patched || (delete_file && existed)
    total_hunks += applied_count
    changed = changed || file_changed
    let output_diff = mooncode_tool_unified_diff(
      relative,
      content,
      patched,
      existed~,
    )
    output_diffs.push(output_diff)
    plans.push({
      "path": relative,
      "proof_path": proof_path,
      "absolute_path": absolute,
      "patched": patched,
      "delete_file": delete_file,
    })
    file_results.push({
      "path": proof_path,
      "file_path": relative,
      "absolute_path": absolute,
      "changed": file_changed,
      "delete_file": delete_file,
      "before_fingerprint": mooncode_tool_content_fingerprint(
        content,
        exists=existed,
      ),
      "after_fingerprint": mooncode_tool_content_fingerprint(
        patched,
        exists=!delete_file,
      ),
      "applied_hunk_count": applied_count,
      "available_hunk_count": available_hunk_count,
      "selected_hunk_index": selected_hunk_index,
      "selected_hunk_id": if selected_hunk_index > 0 {
        "hunk-\{selected_hunk_index}"
      } else {
        ""
      },
      "hunk_control_scope": if selected_hunk_index > 0 {
        "selected-hunk"
      } else {
        "all-hunks"
      },
      "diff": output_diff,
    })
  }
  if selected_hunk_index > 0 && !matched_selected_file {
    return mooncode_tool_error_result(
      tool,
      message="selected patchset file not found: \{selected_file_target}",
      metadata={
        "path": selected_file_target,
        "selected_hunk_index": selected_hunk_index,
        "available_file_count": files.length(),
      },
    )
  }
  for plan in plans {
    let absolute = mooncode_json_string(plan, "absolute_path", default="")
    if mooncode_json_bool(plan, "delete_file", default=false) {
      if @fsx.exists(absolute) {
        @fsx.remove(absolute) catch {
          error =>
            return mooncode_tool_error_result(
              tool,
              message="error removing \{absolute}: \{error}",
              metadata={
                "path": mooncode_json_string(plan, "path", default=""),
                "absolute_path": absolute,
              },
            )
        }
      }
    } else {
      @fsx.make_directory(
        @pathx.dirname(absolute),
        recursive=true,
        exists_ok=true,
      )
      @fsx.write_to_file(
        absolute,
        mooncode_json_string(plan, "patched", default=""),
      ) catch {
        error =>
          return mooncode_tool_error_result(
            tool,
            message="error writing \{absolute}: \{error}",
            metadata={
              "path": mooncode_json_string(plan, "path", default=""),
              "absolute_path": absolute,
            },
          )
      }
    }
  }
  mooncode_tool_patch_result(
    tool,
    book_root,
    arguments,
    message="\{tool} applied \{total_hunks} unified diff hunk(s) across \{file_results.length()} file(s)",
    output="",
    metadata={
      "path": if selected_hunk_index > 0 && file_results.length() == 1 {
        mooncode_json_string(file_results[0], "path", default="patchset")
      } else {
        "patchset"
      },
      "changed": changed,
      "diff": output_diffs.join(""),
      "proof_event": mooncode_tool_patch_proof_event(tool),
      "applied_hunk_count": total_hunks,
      "available_hunk_count": if selected_hunk_index > 0 &&
        file_results.length() == 1 {
        mooncode_json_int(
          file_results[0],
          "available_hunk_count",
          default=total_hunks,
        )
      } else {
        total_hunks
      },
      "selected_hunk_index": selected_hunk_index,
      "selected_hunk_id": if selected_hunk_index > 0 {
        "hunk-\{selected_hunk_index}"
      } else {
        ""
      },
      "hunk_control_scope": if selected_hunk_index > 0 {
        "selected-hunk"
      } else {
        "all-hunks"
      },
      "patched_file_count": file_results.length(),
      "files": Json::array(file_results),
      "input_diff": diff_text,
    },
  )
}

///|
async fn mooncode_tool_apply_unified_diff(
  tool : String,
  book_root : String,
  arguments : Json,
  relative : String,
  absolute : String,
  content : String,
  existed~ : Bool,
  diff_text : String,
  reverse~ : Bool,
) -> Json {
  let chunks = mooncode_tool_patch_chunks_from_unified_diff(diff_text)
  let available_hunk_count = chunks.length()
  if chunks.length() == 0 {
    return mooncode_tool_error_result(
      tool,
      message="unified diff contains no applicable hunks",
      metadata={ "path": relative, "absolute_path": absolute },
    )
  }
  let selected_hunk_index = mooncode_tool_patch_selected_hunk_index(arguments)
  if selected_hunk_index > available_hunk_count {
    return mooncode_tool_error_result(
      tool,
      message="selected hunk \{selected_hunk_index} is outside \{relative}'s \{available_hunk_count} hunk(s)",
      metadata={
        "path": mooncode_tool_patch_hunk_target(relative, selected_hunk_index),
        "file_path": relative,
        "absolute_path": absolute,
        "selected_hunk_index": selected_hunk_index,
        "available_hunk_count": available_hunk_count,
      },
    )
  }
  let selected_chunks : Array[Json] = []
  if selected_hunk_index > 0 {
    selected_chunks.push(chunks[selected_hunk_index - 1])
  } else {
    for chunk in chunks {
      selected_chunks.push(chunk)
    }
  }
  let proof_path = mooncode_tool_patch_hunk_target(
    relative, selected_hunk_index,
  )
  let patched_result = mooncode_tool_apply_unified_chunks_to_content(
    tool,
    proof_path,
    absolute,
    content,
    selected_chunks,
    reverse~,
  )
  if mooncode_json_bool(patched_result, "ok", default=false) == false {
    return patched_result
  }
  let patched = mooncode_json_string(patched_result, "patched", default=content)
  let applied_count = mooncode_json_int(
    patched_result,
    "applied_hunk_count",
    default=0,
  )
  @fsx.make_directory(@pathx.dirname(absolute), recursive=true, exists_ok=true)
  @fsx.write_to_file(absolute, patched) catch {
    error =>
      return mooncode_tool_error_result(
        tool,
        message="error writing \{absolute}: \{error}",
        metadata={ "path": relative, "absolute_path": absolute },
      )
  }
  mooncode_tool_patch_result(
    tool,
    book_root,
    arguments,
    message="\{tool} applied \{applied_count} unified diff hunk(s) to \{relative}",
    output="",
    metadata={
      "path": proof_path,
      "file_path": relative,
      "absolute_path": absolute,
      "changed": content != patched,
      "before_fingerprint": mooncode_tool_content_fingerprint(
        content,
        exists=existed,
      ),
      "after_fingerprint": mooncode_tool_content_fingerprint(
        patched,
        exists=true,
      ),
      "diff": mooncode_tool_unified_diff(relative, content, patched, existed~),
      "proof_event": mooncode_tool_patch_proof_event(tool),
      "applied_hunk_count": applied_count,
      "available_hunk_count": available_hunk_count,
      "selected_hunk_index": selected_hunk_index,
      "selected_hunk_id": if selected_hunk_index > 0 {
        "hunk-\{selected_hunk_index}"
      } else {
        ""
      },
      "hunk_control_scope": if selected_hunk_index > 0 {
        "selected-hunk"
      } else {
        "all-hunks"
      },
      "input_diff": diff_text,
    },
  )
}

///|
fn mooncode_tool_apply_unified_chunks_to_content(
  tool : String,
  relative : String,
  absolute : String,
  content : String,
  chunks : Array[Json],
  reverse~ : Bool,
) -> Json {
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
  { "ok": true, "patched": patched, "applied_hunk_count": applied_count }
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
async fn mooncode_tool_patch_result(
  tool : String,
  book_root : String,
  arguments : Json,
  message~ : String,
  output~ : String,
  metadata~ : Json,
) -> Json {
  if !mooncode_tool_patch_verification_requested(arguments) {
    return mooncode_tool_ok_result(tool, message~, output~, metadata~)
  }
  let verification = mooncode_tool_run_patch_verification(book_root, arguments)
  let metadata = mooncode_json_object_with_field(
    metadata, "verification", verification,
  )
  if mooncode_json_bool(verification, "ok", default=false) {
    mooncode_tool_ok_result(tool, message~, output~, metadata~)
  } else {
    mooncode_tool_error_result(
      tool,
      message="\{message}; post-change verification failed",
      output~,
      metadata~,
    )
  }
}

///|
fn mooncode_tool_patch_verification_requested(arguments : Json) -> Bool {
  mooncode_json_bool(arguments, "verify_after", default=false) ||
  mooncode_json_bool(arguments, "run_verification", default=false) ||
  mooncode_json_string(arguments, "verification_command", default="") != "" ||
  mooncode_json_string(arguments, "test_command", default="") != "" ||
  mooncode_json_string(arguments, "moon_check_target", default="") != ""
}

///|
async fn mooncode_tool_run_patch_verification(
  book_root : String,
  arguments : Json,
) -> Json {
  let command = mooncode_tool_patch_verification_command(arguments)
  let timeout = mooncode_json_int(
    arguments,
    "verification_timeout_ms",
    default=mooncode_json_int(arguments, "timeout_ms", default=60000),
  )
  let max_output_chars = mooncode_json_int(
    arguments,
    "verification_max_output_chars",
    default=mooncode_json_int(arguments, "max_output_chars", default=12000),
  )
  if command != "" {
    let process = @spawn.spawn("sh", ["-lc", command], timeout~, cwd=book_root) catch {
      error =>
        return {
          "ok": false,
          "tool": "shell",
          "command": command,
          "message": "error running post-change verification: \{error}",
        }
    }
    return mooncode_tool_patch_verification_result(
      "shell",
      command,
      process.status,
      process.elapsed,
      process.stdout + process.stderr,
      max_output_chars,
    )
  }
  let target = mooncode_json_string(arguments, "moon_check_target", default="")
  let args : Array[StringView] = if target == "" {
    ["check"]
  } else {
    ["check", target]
  }
  let process = @spawn.spawn("moon", args, timeout~, cwd=book_root) catch {
    error =>
      return {
        "ok": false,
        "tool": "moon_check",
        "target": target,
        "command": if target == "" {
          "moon check"
        } else {
          "moon check \{target}"
        },
        "message": "error running post-change moon check: \{error}",
      }
  }
  mooncode_tool_patch_verification_result(
    "moon_check",
    if target == "" {
      "moon check"
    } else {
      "moon check \{target}"
    },
    process.status,
    process.elapsed,
    process.stdout + process.stderr,
    max_output_chars,
    target~,
  )
}

///|
fn mooncode_tool_patch_verification_command(arguments : Json) -> String {
  let verification = mooncode_json_string(
    arguments,
    "verification_command",
    default="",
  )
  if verification != "" {
    return verification
  }
  mooncode_json_string(arguments, "test_command", default="")
}

///|
fn mooncode_tool_patch_verification_result(
  tool : String,
  command : String,
  status : Int,
  elapsed_ms : Int,
  output : String,
  max_output_chars : Int,
  target? : String = "",
) -> Json {
  let capped = mooncode_cap_tool_output(output, max_output_chars)
  {
    "ok": status == 0,
    "tool": tool,
    "command": command,
    "target": target,
    "status": status,
    "elapsed_ms": elapsed_ms,
    "output": mooncode_json_string(capped, "output", default=""),
    "truncated": mooncode_json_bool(capped, "truncated", default=false),
    "message": if status == 0 {
      "post-change verification passed"
    } else {
      "post-change verification failed with status \{status}"
    },
  }
}

///|
fn mooncode_json_object_with_field(
  json : Json,
  key : String,
  value : Json,
) -> Json {
  let object : Map[String, Json] = {}
  match json {
    Object(existing) =>
      for name, field in existing.iter2() {
        object[name] = field
      }
    _ => ()
  }
  object[key] = value
  object.to_json()
}

///|
fn mooncode_tool_finish(arguments : Json) -> Json {
  let answer = mooncode_json_string(arguments, "answer", default="")
  mooncode_tool_ok_result("finish", message="finished", output=answer, metadata={
    "answer": answer,
  })
}

///|
async fn mooncode_tool_finish_for_session(
  session_id : String,
  book_root : String,
  arguments : Json,
) -> Json {
  let basic = mooncode_tool_finish(arguments)
  let goal_runtime = match arguments {
    Object(fields) => fields.get("goal_runtime")
    _ => None
  }
  guard goal_runtime is Some(decision_json) else { return basic }
  let decision = mooncode_goal_runtime_decode_decision(decision_json) catch {
    _ =>
      return mooncode_tool_error_result(
        "finish",
        message="goal_runtime must be an exact valid achieved or blocked decision",
      )
  }
  if decision is @mooncode_core.Continue(_, _, _) {
    return mooncode_tool_error_result(
      "finish",
      message="finish goal_runtime decision must be achieved or blocked",
    )
  }
  let response = mooncode_goal_runtime_api_get_internal(book_root, session_id)
  if response.status_code != 200 {
    return mooncode_tool_error_result(
      "finish",
      message="goal_runtime settlement requires an active runtime goal",
    )
  }
  guard response.body is Object(body) &&
    body["status"] is Object(status) &&
    body["genesis"] is Object(genesis) else {
    return mooncode_tool_error_result(
      "finish",
      message="goal_runtime settlement could not read runtime authority",
    )
  }
  if mooncode_json_bool(Json::object(status), "terminal", default=false) {
    return mooncode_tool_error_result(
      "finish",
      message="goal_runtime is already terminal",
    )
  }
  match decision {
    @mooncode_core.Achieved(_, evidence) => {
      let criteria = mooncode_json_array_items(
        Json::object(genesis),
        "criteria",
      )
      if evidence.length() != criteria.length() {
        return mooncode_tool_error_result(
          "finish",
          message="achieved evidence must cover every goal criterion exactly once",
        )
      }
      for criterion in criteria {
        let criterion_id = mooncode_json_string(criterion, "id", default="")
        if !evidence.any(item => item.criterion == criterion_id) {
          return mooncode_tool_error_result(
            "finish",
            message="achieved evidence must use the exact goal criterion ids",
          )
        }
      }
    }
    @mooncode_core.Blocked(_, _, _) => ()
    @mooncode_core.Continue(_, _, _) => abort("continue rejected above")
  }
  let answer = mooncode_json_string(arguments, "answer", default="")
  mooncode_tool_ok_result("finish", message="finished", output=answer, metadata={
    "answer": answer,
    "goal_runtime": decision_json,
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
        absolute[root.length() + 1:].to_owned()
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
      "output": text[:limit].to_owned(),
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
fn mooncode_tool_content_fingerprint(
  content : String,
  exists~ : Bool,
) -> String {
  if exists {
    "present:\{mooncode_runtime_turn_sha256_base64(content)}"
  } else {
    "absent"
  }
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
      lines.push(prefix + part.to_owned())
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
    "protocol": mooncode_protocol_version(),
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
  path~ : String,
  diff~ : String,
) -> String {
  match tool {
    "moon_cmd" => "test"
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
    "moon_ide" => "moon_ide.finished"
    "moon_cmd" => "moon_cmd.finished"
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
    "moon_cmd" => "tool_result"
    "moon_check" => "tool_result"
    "finish" => "finish"
    _ => "tool_result"
  }
}

///|
fn mooncode_json_int(json : Json, key : String, default~ : Int) -> Int {
  match json {
    Object(object) =>
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
    "protocol": mooncode_protocol_version(),
    "session_id": "session-demo",
    "tool": "read",
    "arguments": { "path": "README.md" },
    "packet": { "command_id": "cmd-1" },
  })
  assert_true(mooncode_json_bool(report, "ok", default=false))
  let rejected = mooncode_validate_tool_call_body("session-demo", "/tmp/book", {
    "protocol": mooncode_protocol_version(),
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
      "protocol": mooncode_protocol_version(),
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
      "protocol": mooncode_protocol_version(),
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
      "protocol": mooncode_protocol_version(),
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
      "protocol": mooncode_protocol_version(),
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
      "protocol": mooncode_protocol_version(),
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
      "protocol": mooncode_protocol_version(),
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
      "protocol": mooncode_protocol_version(),
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
async test "mooncode native patch tools runs selected unified diff hunks" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-selected-hunk-XXXXXX"),
  )
  @fsx.make_directory(
    @pathx.join(book_root, "tools"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    @pathx.join(book_root, "tools/hunks.txt"),
    "one\nalpha\n\nsecond\nbeta\n",
  )
  let diff = "--- a/tools/hunks.txt\n+++ b/tools/hunks.txt\n@@\n one\n-alpha\n+Alpha\n \n@@\n second\n-beta\n+Beta\n"
  let apply = mooncode_execute_tool_call(
    "session-selected-hunk",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-selected-hunk",
      "book_root": book_root,
      "tool": "apply_patch",
      "command_id": "cmd-apply-hunk-2",
      "arguments": { "context_path": "tools/hunks.txt#hunk-2", "diff": diff },
    },
    now=@clock.Timestamp::from_ms(54L),
  )
  let apply_result = mooncode_json_object_field_or_empty(apply, "result")
  assert_true(mooncode_json_bool(apply_result, "ok", default=false))
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "tools/hunks.txt")),
    "one\nalpha\n\nsecond\nBeta\n",
  )
  let apply_event = mooncode_json_object_field_or_empty(apply, "event")
  assert_eq(
    mooncode_json_string(apply_event, "path", default=""),
    "tools/hunks.txt#hunk-2",
  )
  let apply_metadata = mooncode_json_object_field_or_empty(
    mooncode_json_object_field_or_empty(apply_event, "tool_result"),
    "metadata",
  )
  assert_eq(
    mooncode_json_string(apply_metadata, "file_path", default=""),
    "tools/hunks.txt",
  )
  assert_eq(
    mooncode_json_string(apply_metadata, "hunk_control_scope", default=""),
    "selected-hunk",
  )
  assert_eq(
    mooncode_json_int(apply_metadata, "selected_hunk_index", default=0),
    2,
  )
  assert_eq(
    mooncode_json_int(apply_metadata, "applied_hunk_count", default=0),
    1,
  )
  assert_eq(
    mooncode_json_int(apply_metadata, "available_hunk_count", default=0),
    2,
  )
  let revert = mooncode_execute_tool_call(
    "session-selected-hunk",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-selected-hunk",
      "book_root": book_root,
      "tool": "revert_patch",
      "command_id": "cmd-revert-hunk-2",
      "arguments": { "context_path": "tools/hunks.txt#hunk-2", "diff": diff },
    },
    now=@clock.Timestamp::from_ms(55L),
  )
  let revert_result = mooncode_json_object_field_or_empty(revert, "result")
  assert_true(mooncode_json_bool(revert_result, "ok", default=false))
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "tools/hunks.txt")),
    "one\nalpha\n\nsecond\nbeta\n",
  )
  let revert_event = mooncode_json_object_field_or_empty(revert, "event")
  assert_eq(
    mooncode_json_string(revert_event, "path", default=""),
    "tools/hunks.txt#hunk-2",
  )
  assert_eq(
    mooncode_json_string(revert_event, "kind", default=""),
    "runtime.patch_reverted",
  )
}

///|
async test "mooncode native patch tools apply and revert unified patchsets" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-patchset-XXXXXX"),
  )
  @fsx.make_directory(
    @pathx.join(book_root, "tools"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(@pathx.join(book_root, "tools/one.txt"), "one\nalpha\n")
  @fsx.write_to_file(@pathx.join(book_root, "tools/two.txt"), "two\nbeta\n")
  let diff = "--- a/tools/one.txt\n+++ b/tools/one.txt\n@@\n one\n-alpha\n+Alpha\n--- a/tools/two.txt\n+++ b/tools/two.txt\n@@\n two\n-beta\n+Beta\n"
  let apply = mooncode_execute_tool_call(
    "session-patchset",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-patchset",
      "book_root": book_root,
      "tool": "apply_patch",
      "command_id": "cmd-apply-patchset",
      "arguments": {
        "path": "tools/one.txt",
        "before": "one\nalpha\n",
        "after": "one\nAlpha\n",
        "diff": diff,
      },
    },
    now=@clock.Timestamp::from_ms(50L),
  )
  let apply_result = mooncode_json_object_field_or_empty(apply, "result")
  assert_true(mooncode_json_bool(apply_result, "ok", default=false))
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "tools/one.txt")),
    "one\nAlpha\n",
  )
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "tools/two.txt")),
    "two\nBeta\n",
  )
  let apply_event = mooncode_json_object_field_or_empty(apply, "event")
  assert_eq(mooncode_json_string(apply_event, "path", default=""), "patchset")
  assert_eq(
    mooncode_json_string(apply_event, "kind", default=""),
    "runtime.patch_applied",
  )
  let apply_metadata = mooncode_json_object_field_or_empty(
    mooncode_json_object_field_or_empty(apply_event, "tool_result"),
    "metadata",
  )
  assert_eq(
    mooncode_json_int(apply_metadata, "patched_file_count", default=0),
    2,
  )
  assert_eq(
    mooncode_json_int(apply_metadata, "applied_hunk_count", default=0),
    2,
  )
  let revert = mooncode_execute_tool_call(
    "session-patchset",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-patchset",
      "book_root": book_root,
      "tool": "revert_patch",
      "command_id": "cmd-revert-patchset",
      "arguments": { "diff": diff },
    },
    now=@clock.Timestamp::from_ms(51L),
  )
  let revert_result = mooncode_json_object_field_or_empty(revert, "result")
  assert_true(mooncode_json_bool(revert_result, "ok", default=false))
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "tools/one.txt")),
    "one\nalpha\n",
  )
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "tools/two.txt")),
    "two\nbeta\n",
  )
  let revert_event = mooncode_json_object_field_or_empty(revert, "event")
  assert_eq(
    mooncode_json_string(revert_event, "kind", default=""),
    "runtime.patch_reverted",
  )
}

///|
async test "mooncode native patchsets runs selected file hunks" (t : @test.Test) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-patchset-hunk-XXXXXX"),
  )
  @fsx.make_directory(
    @pathx.join(book_root, "tools"),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(@pathx.join(book_root, "tools/one.txt"), "one\nalpha\n")
  @fsx.write_to_file(
    @pathx.join(book_root, "tools/two.txt"),
    "first\nbeta\n\nsecond\ngamma\n",
  )
  let diff = "--- a/tools/one.txt\n+++ b/tools/one.txt\n@@\n one\n-alpha\n+Alpha\n--- a/tools/two.txt\n+++ b/tools/two.txt\n@@\n first\n-beta\n+Beta\n \n@@\n second\n-gamma\n+Gamma\n"
  let apply = mooncode_execute_tool_call(
    "session-patchset-hunk",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-patchset-hunk",
      "book_root": book_root,
      "tool": "apply_patch",
      "command_id": "cmd-apply-patchset-hunk",
      "arguments": { "context_path": "tools/two.txt#hunk-2", "diff": diff },
    },
    now=@clock.Timestamp::from_ms(56L),
  )
  let apply_result = mooncode_json_object_field_or_empty(apply, "result")
  assert_true(mooncode_json_bool(apply_result, "ok", default=false))
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "tools/one.txt")),
    "one\nalpha\n",
  )
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "tools/two.txt")),
    "first\nbeta\n\nsecond\nGamma\n",
  )
  let apply_event = mooncode_json_object_field_or_empty(apply, "event")
  assert_eq(
    mooncode_json_string(apply_event, "path", default=""),
    "tools/two.txt#hunk-2",
  )
  let apply_metadata = mooncode_json_object_field_or_empty(
    mooncode_json_object_field_or_empty(apply_event, "tool_result"),
    "metadata",
  )
  assert_eq(
    mooncode_json_int(apply_metadata, "patched_file_count", default=0),
    1,
  )
  assert_eq(
    mooncode_json_int(apply_metadata, "applied_hunk_count", default=0),
    1,
  )
  assert_eq(
    mooncode_json_string(apply_metadata, "hunk_control_scope", default=""),
    "selected-hunk",
  )
}

///|
async test "mooncode native patch tools attach post-change verification" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-patch-verify-XXXXXX"),
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
    "session-patch-verify",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-patch-verify",
      "book_root": book_root,
      "tool": "apply_patch",
      "command_id": "cmd-apply-verify",
      "arguments": {
        "path": "tools/demo.txt",
        "old_string": "hello mooncode",
        "new_string": "hello MoonCode",
        "verification_command": "grep 'hello MoonCode' tools/demo.txt",
      },
    },
    now=@clock.Timestamp::from_ms(52L),
  )
  let apply_result = mooncode_json_object_field_or_empty(apply, "result")
  assert_true(mooncode_json_bool(apply_result, "ok", default=false))
  let metadata = mooncode_json_object_field_or_empty(apply_result, "metadata")
  let verification = mooncode_json_object_field_or_empty(
    metadata, "verification",
  )
  assert_true(mooncode_json_bool(verification, "ok", default=false))
  assert_eq(mooncode_json_string(verification, "tool", default=""), "shell")
  assert_eq(mooncode_json_int(verification, "status", default=-1), 0)
  assert_true(
    mooncode_json_string(verification, "output", default="").contains(
      "hello MoonCode",
    ),
  )
}

///|
async test "mooncode native patch verification failure fails the tool result" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-patch-verify-fail-XXXXXX"),
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
    "session-patch-verify-fail",
    book_root,
    {
      "protocol": mooncode_protocol_version(),
      "session_id": "session-patch-verify-fail",
      "book_root": book_root,
      "tool": "apply_patch",
      "command_id": "cmd-apply-verify-fail",
      "arguments": {
        "path": "tools/demo.txt",
        "old_string": "hello mooncode",
        "new_string": "hello MoonCode",
        "verification_command": "grep 'not present' tools/demo.txt",
      },
    },
    now=@clock.Timestamp::from_ms(53L),
  )
  let apply_result = mooncode_json_object_field_or_empty(apply, "result")
  assert_false(mooncode_json_bool(apply_result, "ok", default=true))
  assert_eq(
    @fsx.read_file(@pathx.join(book_root, "tools/demo.txt")),
    "hello MoonCode\n",
  )
  let apply_event = mooncode_json_object_field_or_empty(apply, "event")
  assert_eq(
    mooncode_json_string(apply_event, "kind", default=""),
    "runtime.patch_applied",
  )
  assert_eq(mooncode_json_string(apply_event, "status", default=""), "failed")
  let metadata = mooncode_json_object_field_or_empty(apply_result, "metadata")
  let verification = mooncode_json_object_field_or_empty(
    metadata, "verification",
  )
  assert_false(mooncode_json_bool(verification, "ok", default=true))
}
