///|
pub fn runtime_tool_contract_id() -> String {
  "mooncode-runtime-tools.v1"
}

///|
pub fn runtime_tool_contract_kind() -> String {
  "mooncode-tool-contract"
}

///|
pub fn runtime_tool_call_contract_kind() -> String {
  "mooncode-tool-call-contract"
}

///|
pub fn runtime_tool_read() -> String {
  "read"
}

///|
pub fn runtime_tool_read_skill() -> String {
  "read_skill"
}

///|
pub fn runtime_tool_edit() -> String {
  "edit"
}

///|
pub fn runtime_tool_write() -> String {
  "write"
}

///|
pub fn runtime_tool_apply_patch() -> String {
  "apply_patch"
}

///|
pub fn runtime_tool_revert_patch() -> String {
  "revert_patch"
}

///|
pub fn runtime_tool_shell() -> String {
  "shell"
}

///|
pub fn runtime_tool_moon_ide() -> String {
  "moon_ide"
}

///|
pub fn runtime_tool_moon_cmd() -> String {
  "moon_cmd"
}

///|
pub fn runtime_tool_finish() -> String {
  "finish"
}

///|
pub fn runtime_tool_spawn_workers() -> String {
  "spawn_workers"
}

///|
pub fn runtime_tool_wait_workers() -> String {
  "wait_workers"
}

///|
pub fn runtime_tool_package_app_tool() -> String {
  "package_app_tool"
}

///|
pub fn runtime_tool_glob() -> String {
  "glob"
}

///|
pub fn runtime_tool_grep() -> String {
  "grep"
}

///|
pub fn runtime_tool_todo_write() -> String {
  "todo_write"
}

///|
pub fn runtime_tool_web_fetch() -> String {
  "web_fetch"
}

///|
pub fn runtime_tool_web_search() -> String {
  "web_search"
}

///|
pub fn runtime_tool_names() -> Array[String] {
  [
    runtime_tool_shell(),
    "read_result",
    runtime_tool_read(),
    runtime_tool_read_skill(),
    "mcp_list_tools",
    "ask_user",
    "mcp_call_tool",
    runtime_tool_edit(),
    runtime_tool_write(),
    runtime_tool_moon_ide(),
    runtime_tool_moon_cmd(),
    runtime_tool_finish(),
    runtime_tool_spawn_workers(),
    runtime_tool_wait_workers(),
    runtime_tool_apply_patch(),
    runtime_tool_revert_patch(),
    runtime_tool_package_app_tool(),
    runtime_tool_glob(),
    runtime_tool_grep(),
    runtime_tool_todo_write(),
    runtime_tool_web_fetch(),
    runtime_tool_web_search(),
  ]
}

///|
pub fn runtime_tool_native_required_tools() -> Array[String] {
  [
    runtime_tool_read(),
    runtime_tool_read_skill(),
    runtime_tool_edit(),
    runtime_tool_write(),
    runtime_tool_apply_patch(),
    runtime_tool_revert_patch(),
    runtime_tool_shell(),
    runtime_tool_moon_ide(),
    runtime_tool_moon_cmd(),
    runtime_tool_finish(),
    runtime_tool_spawn_workers(),
    runtime_tool_wait_workers(),
  ]
}

///|
pub fn runtime_tool_alias_rows() -> Array[Json] {
  [
    runtime_tool_alias_row("Bash", runtime_tool_shell()),
    runtime_tool_alias_row("FileRead", runtime_tool_read()),
    runtime_tool_alias_row("Read", runtime_tool_read()),
    runtime_tool_alias_row("FileEdit", runtime_tool_edit()),
    runtime_tool_alias_row("Edit", runtime_tool_edit()),
    runtime_tool_alias_row("NotebookEdit", runtime_tool_edit()),
    runtime_tool_alias_row("FileWrite", runtime_tool_write()),
    runtime_tool_alias_row("Write", runtime_tool_write()),
    runtime_tool_alias_row("Glob", runtime_tool_glob()),
    runtime_tool_alias_row("Grep", runtime_tool_grep()),
    runtime_tool_alias_row("TodoWrite", runtime_tool_todo_write()),
    runtime_tool_alias_row("WebFetch", runtime_tool_web_fetch()),
    runtime_tool_alias_row("WebSearch", runtime_tool_web_search()),
  ]
}

///|
pub fn runtime_tool_moonclaw_mapping_rows() -> Array[Json] {
  [
    runtime_tool_mapping_row("read_file", runtime_tool_read(), "native"),
    runtime_tool_mapping_row(
      "read_multiple_files",
      runtime_tool_read(),
      "native",
    ),
    runtime_tool_mapping_row("read_resource", runtime_tool_read(), "native"),
    runtime_tool_mapping_row("write_to_file", runtime_tool_write(), "native"),
    runtime_tool_mapping_row("replace_in_file", runtime_tool_edit(), "native"),
    runtime_tool_mapping_row("patch_edit", runtime_tool_edit(), "native"),
    runtime_tool_mapping_row(
      "apply_patch",
      runtime_tool_apply_patch(),
      "native",
    ),
    runtime_tool_mapping_row("execute_command", runtime_tool_shell(), "native"),
    runtime_tool_mapping_row("list_files", runtime_tool_read(), "discovery"),
    runtime_tool_mapping_row("glob_files", runtime_tool_read(), "discovery"),
    runtime_tool_mapping_row("search_files", runtime_tool_read(), "discovery"),
    runtime_tool_mapping_row("runtime_context", runtime_tool_read(), "context"),
    runtime_tool_mapping_row("todo", runtime_tool_finish(), "planning-only"),
    runtime_tool_mapping_row("Bash", runtime_tool_shell(), "package-style"),
    runtime_tool_mapping_row("FileRead", runtime_tool_read(), "package-style"),
    runtime_tool_mapping_row("Read", runtime_tool_read(), "package-style"),
    runtime_tool_mapping_row("FileEdit", runtime_tool_edit(), "package-style"),
    runtime_tool_mapping_row("Edit", runtime_tool_edit(), "package-style"),
    runtime_tool_mapping_row(
      "NotebookEdit",
      runtime_tool_edit(),
      "package-style",
    ),
    runtime_tool_mapping_row("FileWrite", runtime_tool_write(), "package-style"),
    runtime_tool_mapping_row("Write", runtime_tool_write(), "package-style"),
    runtime_tool_mapping_row("Glob", runtime_tool_glob(), "package-style"),
    runtime_tool_mapping_row("Grep", runtime_tool_grep(), "package-style"),
    runtime_tool_mapping_row(
      "TodoWrite",
      runtime_tool_todo_write(),
      "package-style",
    ),
    runtime_tool_mapping_row(
      "WebFetch",
      runtime_tool_web_fetch(),
      "package-style",
    ),
    runtime_tool_mapping_row(
      "WebSearch",
      runtime_tool_web_search(),
      "package-style",
    ),
  ]
}

///|
pub fn runtime_tool_from_moonclaw_tool(tool_name : String) -> String {
  match tool_name {
    "read_file" | "read_multiple_files" | "read_resource" => runtime_tool_read()
    "write_to_file" => runtime_tool_write()
    "replace_in_file" | "patch_edit" => runtime_tool_edit()
    "apply_patch" => runtime_tool_apply_patch()
    "execute_command" => runtime_tool_shell()
    "list_files" | "glob_files" | "search_files" | "runtime_context" =>
      runtime_tool_read()
    "todo" => runtime_tool_finish()
    _ => runtime_tool_canonical_name(tool_name)
  }
}

///|
pub fn runtime_tool_canonical_name(tool_name : String) -> String {
  let normalized = tool_name.replace(old="-", new="_").to_lower()
  match normalized {
    "bash" => runtime_tool_shell()
    "read" | "fileread" | "file_read" => runtime_tool_read()
    "edit" | "fileedit" | "file_edit" | "notebookedit" | "notebook_edit" =>
      runtime_tool_edit()
    "write" | "filewrite" | "file_write" => runtime_tool_write()
    "glob" => runtime_tool_glob()
    "grep" => runtime_tool_grep()
    "todowrite" | "todo_write" => runtime_tool_todo_write()
    "webfetch" | "web_fetch" => runtime_tool_web_fetch()
    "websearch" | "web_search" => runtime_tool_web_search()
    _ => tool_name
  }
}

///|
pub fn runtime_tool_is_supported(tool_name : String) -> Bool {
  runtime_tool_names().contains(runtime_tool_canonical_name(tool_name))
}

///|
pub fn runtime_tool_call_contract_json() -> Json {
  {
    "kind": runtime_tool_call_contract_kind(),
    "protocol": protocol_version(),
    "contract_id": runtime_tool_contract_id(),
    "owner": "mooncode",
    "runtime_owner": "moonclaw",
    "reference": "mooncode/runtime/tool-call-contract",
    "accepted_shapes": [
      "native function tool call: {id,type,function:{name,arguments}}", "runtime event wrapper: {event:'tool_call'|'tool_started'|'tool_result',tool_call:{id,function:{name,arguments}}}",
      "flattened runtime event: {tool_call_id,tool_name,arguments}",
    ],
    "supported_tools": runtime_tool_names(),
    "accepted_aliases": runtime_tool_alias_rows(),
    "argument_rule": "function.arguments is kept as the raw JSON string and also exposed as parsed_arguments when it is valid JSON; MoonClaw owns final tool-specific validation before execution.",
    "unknown_tool_policy": "unknown tool names fail this decoder and should be emitted as tool_call_decode_error runtime events, not silently executed",
  }
}

///|
pub fn runtime_tool_contract_json() -> Json {
  {
    "kind": runtime_tool_contract_kind(),
    "protocol": protocol_version(),
    "contract_id": runtime_tool_contract_id(),
    "owner": "moonclaw",
    "supported_tools": runtime_tool_names(),
    "accepted_aliases": runtime_tool_alias_rows(),
    "moonclaw_tool_mappings": runtime_tool_moonclaw_mapping_rows(),
  }
}

///|
fn runtime_tool_alias_row(alias_name : String, canonical : String) -> Json {
  { "alias": alias_name, "canonical": canonical }
}

///|
fn runtime_tool_mapping_row(
  source : String,
  mooncode_tool : String,
  source_kind : String,
) -> Json {
  {
    "source": source,
    "mooncode_tool": mooncode_tool,
    "source_kind": source_kind,
  }
}
