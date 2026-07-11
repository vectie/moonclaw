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
pub fn runtime_tool_moon_check() -> String {
  "moon_check"
}

///|
pub fn runtime_tool_finish() -> String {
  "finish"
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
pub fn runtime_tool_eval_harness() -> String {
  "eval_harness"
}

///|
pub fn runtime_tool_names() -> Array[String] {
  [
    runtime_tool_shell(),
    runtime_tool_read(),
    runtime_tool_edit(),
    runtime_tool_write(),
    runtime_tool_moon_ide(),
    runtime_tool_moon_cmd(),
    runtime_tool_moon_check(),
    runtime_tool_finish(),
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
pub fn runtime_tool_capability_names() -> Array[String] {
  let tools = runtime_tool_names()
  tools.push(runtime_tool_eval_harness())
  tools
}

///|
pub fn runtime_tool_native_required_tools() -> Array[String] {
  [
    runtime_tool_read(),
    runtime_tool_edit(),
    runtime_tool_write(),
    runtime_tool_apply_patch(),
    runtime_tool_revert_patch(),
    runtime_tool_shell(),
    runtime_tool_moon_ide(),
    runtime_tool_moon_cmd(),
    runtime_tool_moon_check(),
    runtime_tool_finish(),
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
    "fileread" | "file_read" => runtime_tool_read()
    "fileedit" | "file_edit" | "notebookedit" | "notebook_edit" =>
      runtime_tool_edit()
    "filewrite" | "file_write" => runtime_tool_write()
    "todowrite" | "todo_write" => runtime_tool_todo_write()
    "webfetch" | "web_fetch" => runtime_tool_web_fetch()
    "websearch" | "web_search" => runtime_tool_web_search()
    _ => tool_name
  }
}

///|
pub fn runtime_tool_is_supported(tool_name : String) -> Bool {
  runtime_tool_names().contains(tool_name)
}

///|
pub fn runtime_tool_mutates_files(tool_name : String) -> Bool {
  tool_name == runtime_tool_edit() ||
  tool_name == runtime_tool_write() ||
  tool_name == runtime_tool_moon_cmd() ||
  tool_name == runtime_tool_apply_patch() ||
  tool_name == runtime_tool_revert_patch() ||
  tool_name == runtime_tool_package_app_tool()
}

///|
pub fn runtime_tool_requires_review(tool_name : String) -> Bool {
  runtime_tool_mutates_files(tool_name) ||
  tool_name == runtime_tool_shell() ||
  tool_name == runtime_tool_finish()
}

///|
pub fn runtime_tool_requires_authorization_snapshot(tool_name : String) -> Bool {
  tool_name == runtime_tool_edit() ||
  tool_name == runtime_tool_write() ||
  tool_name == runtime_tool_shell() ||
  tool_name == runtime_tool_moon_check() ||
  tool_name == runtime_tool_apply_patch() ||
  tool_name == runtime_tool_revert_patch() ||
  tool_name == runtime_tool_package_app_tool()
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
    "version": 1,
    "owner": "moonclaw",
    "execution_owner": "moonclaw",
    "approval_owner": "moondesk",
    "artifact_owner": "moonbook",
    "supported_tools": runtime_tool_names(),
    "accepted_aliases": runtime_tool_alias_rows(),
    "moonclaw_tool_mappings": runtime_tool_moonclaw_mapping_rows(),
    "tools": runtime_tool_contract_entries(),
    "constraints": {
      "workspace_scope": "All paths are selected-MoonBook relative and must resolve inside the book root.",
      "path_rule": "MoonClaw validates paths before reading, writing, editing, packaging, or running tools.",
      "diff_rule": "Every mutating tool emits durable file_change and diff events before MoonDesk can render accept/reject/package controls.",
      "test_rule": "run_tests and package actions are not complete until test_result or package artifact evidence is appended.",
      "approval_rule": "MoonDesk records operator approval intent; MoonClaw enforces policy for shell, write/edit, and package execution.",
      "extraction_rule": "The schema is data-only and can move into a shared MoonCode protocol package without depending on host UI types.",
    },
  }
}

///|
pub fn runtime_tool_contract_tool_ids(contract : Json) -> Array[String] {
  let ids : Array[String] = []
  match contract {
    { "tools": Array(tools), .. } =>
      for tool in tools {
        match tool {
          { "id": String(id), .. } => ids.push(id)
          _ => ()
        }
      }
    _ => ()
  }
  ids
}

///|
pub fn runtime_tool_capability_specs() -> Array[Json] {
  [
    runtime_tool_capability_spec(
      id=runtime_tool_read(),
      owner="moonclaw",
      lane=event_lane_tool(),
      approval="auto",
      purpose="Read bounded files inside the selected MoonBook context.",
      outputs=[runtime_event_tool_result()],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_edit(),
      owner="moonclaw",
      lane=event_lane_diff(),
      approval="review",
      purpose="Apply focused edits that remain inside the selected MoonBook workspace.",
      outputs=[runtime_event_file_change(), runtime_event_diff()],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_write(),
      owner="moonclaw",
      lane=event_lane_diff(),
      approval="review",
      purpose="Create generated source files, scripts, tools, miniapps, or app-tool assets.",
      outputs=[runtime_event_file_change(), runtime_event_diff()],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_shell(),
      owner="moonclaw",
      lane=event_lane_tool(),
      approval="policy",
      purpose="Run bounded build, inspect, and packaging commands under the book workspace.",
      outputs=["terminal", runtime_event_tool_result()],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_moon_ide(),
      owner="moonclaw",
      lane=event_lane_tool(),
      approval="auto",
      purpose="Run read-only MoonBit semantic navigation before editing generated book code.",
      outputs=[runtime_event_tool_result(), runtime_event_runtime_update()],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_glob(),
      owner="moonclaw",
      lane=event_lane_tool(),
      approval="auto",
      purpose="Discover workspace files using a read-only glob pattern.",
      outputs=[runtime_event_tool_result(), runtime_event_runtime_update()],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_grep(),
      owner="moonclaw",
      lane=event_lane_tool(),
      approval="auto",
      purpose="Search workspace text using a read-only pattern.",
      outputs=[runtime_event_tool_result(), runtime_event_runtime_update()],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_todo_write(),
      owner="moonclaw",
      lane=event_lane_runtime(),
      approval="auto",
      purpose="Publish assistant plan updates as inline progress.",
      outputs=[runtime_event_runtime_update(), runtime_event_tool_result()],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_web_fetch(),
      owner="moonclaw",
      lane=event_lane_tool(),
      approval="auto",
      purpose="Read a web page as context when web search is enabled for the turn.",
      outputs=[runtime_event_tool_result(), runtime_event_runtime_update()],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_web_search(),
      owner="moonclaw",
      lane=event_lane_tool(),
      approval="auto",
      purpose="Search the web as read-only context when web search is enabled for the turn.",
      outputs=[runtime_event_tool_result(), runtime_event_runtime_update()],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_moon_cmd(),
      owner="moonclaw",
      lane=event_lane_test(),
      approval="policy",
      purpose="Run structured MoonBit check, test, build, run, info, or fmt commands with bounded output and mutation-aware proof.",
      outputs=[
        runtime_event_test_result(),
        runtime_event_tool_result(),
        runtime_event_runtime_update(),
        runtime_event_diff(),
      ],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_moon_check(),
      owner="moonclaw",
      lane=event_lane_test(),
      approval="auto",
      purpose="Run MoonBit checks, tests, builds, and package validation for generated code.",
      outputs=[runtime_event_test_result()],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_apply_patch(),
      owner="moonclaw",
      lane=event_lane_diff(),
      approval="review",
      purpose="Apply reviewed unified patches inside the selected MoonBook workspace.",
      outputs=[
        runtime_event_file_change(),
        runtime_event_diff(),
        runtime_event_patch_applied(),
      ],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_revert_patch(),
      owner="moonclaw",
      lane=event_lane_diff(),
      approval="review",
      purpose="Reverse reviewed or previously applied patches inside the selected MoonBook workspace.",
      outputs=[
        runtime_event_file_change(),
        runtime_event_diff(),
        runtime_event_patch_reverted(),
      ],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_package_app_tool(),
      owner="moonbook",
      lane=event_lane_artifact(),
      approval="review",
      purpose="Package accepted executable output as a MoonBook tool, miniapp, generated site, or app-tool bundle.",
      outputs=[runtime_event_artifact(), "review"],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_eval_harness(),
      owner="moonclaw",
      lane=event_lane_test(),
      approval="auto",
      purpose="Run MoonCode tool_harness and file_edit evals, then publish native eval proof for this MoonCode session.",
      outputs=[runtime_event_test_result(), "eval_report.manifest"],
    ),
    runtime_tool_capability_spec(
      id=runtime_tool_finish(),
      owner="moonclaw",
      lane=event_lane_review(),
      approval="operator",
      purpose="Summarize final changes, tests, residual risks, and accept/reject/package readiness.",
      outputs=["review"],
    ),
  ]
}

///|
fn runtime_tool_contract_entries() -> Array[Json] {
  [
    runtime_tool_contract_entry(
      id=runtime_tool_read(),
      lane=event_lane_tool(),
      approval="auto",
      mutates_files=false,
      requires_review=false,
      input_fields=[
        runtime_tool_field(
          "path",
          "string",
          required=true,
          "Book-relative file path to read.",
        ),
        runtime_tool_field(
          "max_bytes",
          "integer",
          required=false,
          "Optional byte cap for bounded reads.",
        ),
      ],
      output_events=[runtime_event_tool_result()],
      safety_policy="Only read files inside the selected MoonBook workspace; never traverse outside the book root.",
    ),
    runtime_tool_contract_entry(
      id=runtime_tool_edit(),
      lane=event_lane_diff(),
      approval="review",
      mutates_files=true,
      requires_review=true,
      input_fields=[
        runtime_tool_field(
          "path",
          "string",
          required=true,
          "Book-relative file path to edit.",
        ),
        runtime_tool_field(
          "old",
          "string",
          required=true,
          "Exact text to replace.",
        ),
        runtime_tool_field("new", "string", required=true, "Replacement text."),
      ],
      output_events=[
        runtime_event_file_change(),
        runtime_event_diff(),
        runtime_event_tool_result(),
      ],
      safety_policy="Emit a diff event for every edit and keep operator review state separate from execution.",
    ),
    runtime_tool_contract_entry(
      id=runtime_tool_write(),
      lane=event_lane_diff(),
      approval="review",
      mutates_files=true,
      requires_review=true,
      input_fields=[
        runtime_tool_field(
          "path",
          "string",
          required=true,
          "Book-relative file path to create or replace.",
        ),
        runtime_tool_field(
          "content",
          "string",
          required=true,
          "Complete UTF-8 file content.",
        ),
      ],
      output_events=[
        runtime_event_file_change(),
        runtime_event_diff(),
        runtime_event_tool_result(),
      ],
      safety_policy="Write only within allowed executable MoonBook roots such as tools, apps, portable/app-tool, site/generated, or reviewed wiki paths.",
    ),
    runtime_tool_contract_entry(
      id=runtime_tool_apply_patch(),
      lane=event_lane_diff(),
      approval="review",
      mutates_files=true,
      requires_review=true,
      input_fields=[
        runtime_tool_field(
          "patch",
          "string",
          required=true,
          "Unified patch text to apply inside the selected MoonBook.",
        ),
        runtime_tool_field(
          "paths",
          "array<string>",
          required=false,
          "Expected book-relative changed paths.",
        ),
      ],
      output_events=[
        runtime_event_file_change(),
        runtime_event_diff(),
        runtime_event_patch_applied(),
        runtime_event_tool_result(),
      ],
      safety_policy="Apply only reviewed patches under the selected MoonBook and emit patch_applied runtime proof.",
    ),
    runtime_tool_contract_entry(
      id=runtime_tool_revert_patch(),
      lane=event_lane_diff(),
      approval="review",
      mutates_files=true,
      requires_review=true,
      input_fields=[
        runtime_tool_field(
          "patch",
          "string",
          required=true,
          "Unified patch text to reverse inside the selected MoonBook.",
        ),
        runtime_tool_field(
          "paths",
          "array<string>",
          required=false,
          "Expected book-relative reverted paths.",
        ),
        runtime_tool_field(
          "receipt_id",
          "string",
          required=false,
          "Optional applied-patch receipt being reverted.",
        ),
      ],
      output_events=[
        runtime_event_file_change(),
        runtime_event_diff(),
        runtime_event_patch_reverted(),
        runtime_event_tool_result(),
      ],
      safety_policy="Revert only reviewed or previously applied patches under the selected MoonBook and emit patch_reverted runtime proof.",
    ),
    runtime_tool_contract_entry(
      id=runtime_tool_shell(),
      lane=event_lane_tool(),
      approval="policy",
      mutates_files=false,
      requires_review=true,
      input_fields=[
        runtime_tool_field(
          "cmd",
          "array<string>",
          required=true,
          "Argument-vector command, not a raw shell string.",
        ),
        runtime_tool_field(
          "cwd",
          "string",
          required=false,
          "Book-relative working directory.",
        ),
        runtime_tool_field(
          "timeout_ms",
          "integer",
          required=false,
          "Bounded execution timeout.",
        ),
      ],
      output_events=[
        runtime_event_tool_result(),
        runtime_event_runtime_update(),
      ],
      safety_policy="Run bounded commands under the selected book root; destructive or networked commands require explicit policy approval.",
    ),
    runtime_tool_contract_entry(
      id=runtime_tool_moon_ide(),
      lane=event_lane_tool(),
      approval="auto",
      mutates_files=false,
      requires_review=false,
      input_fields=[
        runtime_tool_field(
          "action",
          "string",
          required=true,
          "Read-only MoonBit IDE action: doc, outline, peek_def, hover, or find_references.",
        ),
        runtime_tool_field(
          "query",
          "string",
          required=false,
          "Symbol or text query for doc, peek_def, hover, and find_references.",
        ),
        runtime_tool_field(
          "path",
          "string",
          required=false,
          "Book-relative package or file path for outline.",
        ),
        runtime_tool_field(
          "loc",
          "string",
          required=false,
          "Optional location as path:line:column for semantic navigation.",
        ),
        runtime_tool_field(
          "target",
          "string",
          required=false,
          "Optional MoonBit backend target.",
        ),
      ],
      output_events=[
        runtime_event_tool_result(),
        runtime_event_runtime_update(),
      ],
      safety_policy="Run read-only moon ide commands under the selected MoonBook root before broad file reads or edits.",
    ),
    runtime_tool_contract_entry(
      id=runtime_tool_glob(),
      lane=event_lane_tool(),
      approval="auto",
      mutates_files=false,
      requires_review=false,
      input_fields=[
        runtime_tool_field(
          "pattern",
          "string",
          required=true,
          "Glob pattern to discover workspace files.",
        ),
        runtime_tool_field(
          "path",
          "string",
          required=false,
          "Optional book-relative directory to search.",
        ),
      ],
      output_events=[
        runtime_event_tool_result(),
        runtime_event_runtime_update(),
      ],
      safety_policy="Read-only file discovery inside the selected MoonBook workspace.",
    ),
    runtime_tool_contract_entry(
      id=runtime_tool_grep(),
      lane=event_lane_tool(),
      approval="auto",
      mutates_files=false,
      requires_review=false,
      input_fields=[
        runtime_tool_field(
          "pattern",
          "string",
          required=true,
          "Regular expression pattern to search for.",
        ),
        runtime_tool_field(
          "path",
          "string",
          required=false,
          "Optional book-relative file or directory to search.",
        ),
        runtime_tool_field(
          "glob",
          "string",
          required=false,
          "Optional glob filter for matching files.",
        ),
      ],
      output_events=[
        runtime_event_tool_result(),
        runtime_event_runtime_update(),
      ],
      safety_policy="Read-only text search inside the selected MoonBook workspace.",
    ),
    runtime_tool_contract_entry(
      id=runtime_tool_todo_write(),
      lane=event_lane_runtime(),
      approval="auto",
      mutates_files=false,
      requires_review=false,
      input_fields=[
        runtime_tool_field(
          "todos",
          "array<object>",
          required=true,
          "Current assistant plan items with content, status, and activeForm.",
        ),
      ],
      output_events=[
        runtime_event_runtime_update(),
        runtime_event_tool_result(),
      ],
      safety_policy="Planning-only progress signal; it must not modify workspace files.",
    ),
    runtime_tool_contract_entry(
      id=runtime_tool_web_fetch(),
      lane=event_lane_tool(),
      approval="auto",
      mutates_files=false,
      requires_review=false,
      input_fields=[
        runtime_tool_field("url", "string", required=true, "URL to read."),
        runtime_tool_field(
          "prompt",
          "string",
          required=true,
          "Question or extraction prompt for the fetched page.",
        ),
      ],
      output_events=[
        runtime_event_tool_result(),
        runtime_event_runtime_update(),
      ],
      safety_policy="Only available when the command enables web_search; results are recorded as read-only context.",
    ),
    runtime_tool_contract_entry(
      id=runtime_tool_web_search(),
      lane=event_lane_tool(),
      approval="auto",
      mutates_files=false,
      requires_review=false,
      input_fields=[
        runtime_tool_field("query", "string", required=true, "Search query."),
        runtime_tool_field(
          "allowed_domains",
          "array<string>",
          required=false,
          "Optional domain allow-list.",
        ),
        runtime_tool_field(
          "blocked_domains",
          "array<string>",
          required=false,
          "Optional domain block-list.",
        ),
      ],
      output_events=[
        runtime_event_tool_result(),
        runtime_event_runtime_update(),
      ],
      safety_policy="Only available when the command enables web_search; results are recorded as read-only context.",
    ),
    runtime_tool_contract_entry(
      id=runtime_tool_moon_cmd(),
      lane=event_lane_test(),
      approval="policy",
      mutates_files=true,
      requires_review=true,
      input_fields=[
        runtime_tool_field(
          "command",
          "string",
          required=true,
          "MoonBit command: check, test, run, info, fmt, or build.",
        ),
        runtime_tool_field(
          "cwd",
          "string",
          required=false,
          "Book-relative working directory.",
        ),
        runtime_tool_field(
          "target",
          "string",
          required=false,
          "Optional MoonBit backend target.",
        ),
        runtime_tool_field(
          "args",
          "array<string>",
          required=false,
          "Additional bounded MoonBit command arguments.",
        ),
        runtime_tool_field(
          "program_args",
          "array<string>",
          required=false,
          "Arguments after -- for moon run.",
        ),
        runtime_tool_field(
          "test_update_kind",
          "string",
          required=false,
          "Required when running snapshot-updating tests: stale_snapshot or intentional_output_change.",
        ),
      ],
      output_events=[
        runtime_event_tool_result(),
        runtime_event_test_result(),
        runtime_event_runtime_update(),
        runtime_event_diff(),
      ],
      safety_policy="Prefer structured MoonBit commands over raw shell; mutation-capable commands such as fmt or test --update require policy approval and diff/test proof.",
    ),
    runtime_tool_contract_entry(
      id=runtime_tool_moon_check(),
      lane=event_lane_test(),
      approval="auto",
      mutates_files=false,
      requires_review=false,
      input_fields=[
        runtime_tool_field(
          "target",
          "string",
          required=false,
          "Optional MoonBit package or file target.",
        ),
        runtime_tool_field(
          "command",
          "string",
          required=false,
          "check, test, build, fmt, or info.",
        ),
      ],
      output_events=[runtime_event_test_result(), runtime_event_tool_result()],
      safety_policy="Surface exit code, command, stdout/stderr summary, and failing target as test_result evidence.",
    ),
    runtime_tool_contract_entry(
      id=runtime_tool_package_app_tool(),
      lane=event_lane_artifact(),
      approval="operator",
      mutates_files=true,
      requires_review=true,
      input_fields=[
        runtime_tool_field(
          "source",
          "string",
          required=true,
          "Book-relative source path to package.",
        ),
        runtime_tool_field(
          "kind",
          "string",
          required=false,
          "tool, miniapp, generated-site, or app-tool.",
        ),
        runtime_tool_field(
          "output",
          "string",
          required=false,
          "Book-relative package output path.",
        ),
      ],
      output_events=[
        runtime_event_diff(),
        runtime_event_artifact(),
        runtime_event_package_manifest(),
        runtime_event_package_index(),
        runtime_event_package_verified(),
        runtime_event_tool_result(),
      ],
      safety_policy="Package accepted executable MoonBook output and emit source inventory plus package verification proof.",
    ),
    runtime_tool_contract_entry(
      id=runtime_tool_finish(),
      lane=event_lane_review(),
      approval="operator",
      mutates_files=false,
      requires_review=true,
      input_fields=[
        runtime_tool_field(
          "summary",
          "string",
          required=true,
          "Final implementation summary.",
        ),
        runtime_tool_field(
          "tests",
          "array<string>",
          required=false,
          "Validation commands and outcomes.",
        ),
        runtime_tool_field(
          "risks",
          "array<string>",
          required=false,
          "Residual risks or missing evidence.",
        ),
      ],
      output_events=["review", runtime_event_runtime_finished()],
      safety_policy="Finish only after file changes, test evidence, and package readiness are available or explicitly called out as missing.",
    ),
  ]
}

///|
fn runtime_tool_contract_entry(
  id~ : String,
  lane~ : String,
  approval~ : String,
  mutates_files~ : Bool,
  requires_review~ : Bool,
  input_fields~ : Array[Json],
  output_events~ : Array[String],
  safety_policy~ : String,
) -> Json {
  {
    "id": id,
    "owner": "moonclaw",
    "lane": lane,
    "approval": approval,
    "input_fields": Json::array(input_fields),
    "output_events": output_events,
    "mutates_files": mutates_files,
    "requires_review": requires_review,
    "executable_boundary": "MoonClaw executes; MoonDesk renders and records review intent; MoonBook stores accepted artifacts.",
    "safety_policy": safety_policy,
  }
}

///|
fn runtime_tool_field(
  name : String,
  type_ : String,
  required~ : Bool,
  description : String,
) -> Json {
  {
    "name": name,
    "type": type_,
    "required": required,
    "description": description,
  }
}

///|
fn runtime_tool_capability_spec(
  id~ : String,
  owner~ : String,
  lane~ : String,
  approval~ : String,
  purpose~ : String,
  outputs~ : Array[String],
) -> Json {
  {
    "id": id,
    "owner": owner,
    "lane": lane,
    "approval": approval,
    "purpose": purpose,
    "outputs": outputs,
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
