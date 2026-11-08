///|
let mooncode_native_tool_catalog : Array[@openai.ChatCompletionToolParam] = mooncode_build_native_tool_catalog()

///|
fn mooncode_runtime_turn_model_tools() -> Array[@openai.ChatCompletionToolParam] {
  mooncode_native_tool_catalog.copy()
}

///|
fn mooncode_tool_schema(tool : String) -> Json? {
  let name = if tool == "revert_patch" { "apply_patch" } else { tool }
  for entry in mooncode_native_tool_catalog {
    if entry is Function(definition) && definition.name == name {
      return Some(definition.parameters)
    }
  }
  None
}

///|
fn mooncode_tool_supported(tool : String) -> Bool {
  mooncode_tool_schema(tool) is Some(_)
}

///|
fn mooncode_tool_arguments_error(tool : String, arguments : Json) -> String? {
  guard mooncode_tool_schema(tool) is Some(schema) else {
    return Some("Unsupported tool: " + tool)
  }
  @mooncode_tools.arguments_error(schema, arguments)
}

///|
/// Grant payloads are bound by the runtime, outside the model-facing ABI.
fn mooncode_tool_execution_arguments_error(
  tool : String,
  arguments : Json,
) -> String? {
  let public_arguments = match arguments {
    Object(fields) =>
      Json::object(
        fields.filter(fn(key, _) {
          ![
            "_execution_sandbox_plan", "_execution_sandbox_plan_error", "requires_approval",
            "approval",
          ].contains(key)
        }),
      )
    value => value
  }
  mooncode_tool_arguments_error(tool, public_arguments)
}

///|
fn mooncode_build_native_tool_catalog() -> Array[
  @openai.ChatCompletionToolParam,
] {
  [
    mooncode_runtime_turn_model_tool(
      "ask_user",
      "Ask a necessary question with a stable id and optional short choices; wait before dependent work. Not for tool approvals.",
      {
        "type": "object",
        "properties": {
          "id": { "type": "string" },
          "question": { "type": "string" },
          "options": { "type": "array", "items": { "type": "string" } },
        },
        "required": ["id", "question"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "read",
      "Read file lines by path, or saved output by evidence_ref without rerunning. details=true reads result JSON; end_ref lists a result range.",
      {
        "type": "object",
        "properties": {
          "path": { "type": "string" },
          "evidence_ref": { "type": "string" },
          "details": { "type": "boolean" },
          "end_ref": { "type": "string" },
          "start_line": { "type": "integer", "minimum": 1 },
          "end_line": { "type": "integer", "minimum": 1 },
          "max_output_chars": { "type": "integer" },
        },
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "view_image",
      "Inspect pixels of a MoonBook PNG, JPEG, WebP or GIF file.",
      {
        "type": "object",
        "properties": { "path": { "type": "string" } },
        "required": ["path"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "write",
      "Write a complete file inside the selected MoonBook.",
      {
        "type": "object",
        "properties": {
          "path": { "type": "string" },
          "content": { "type": "string" },
          "expected_fingerprint": { "type": "string" },
        },
        "required": ["path", "content"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "edit",
      "Atomically apply edits in order. Keep matches short and exact; avoid large unchanged regions. Write only after every replacement validates.",
      {
        "type": "object",
        "properties": {
          "path": { "type": "string" },
          "edits": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "old_string": { "type": "string" },
                "new_string": { "type": "string" },
                "replace_all": { "type": "boolean" },
              },
              "required": ["old_string", "new_string"],
              "additionalProperties": false,
            },
          },
        },
        "required": ["path", "edits"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "shell",
      "Run a foreground command in a fresh disposable MoonBook snapshot. Changes/build outputs do not persist between calls; use edit/write/apply_patch for persistent edits. Background processes are unsupported. Set verification_kind only if exit zero proves that check/test/build.",
      {
        "type": "object",
        "properties": {
          "cmd": { "type": "string" },
          "cwd": { "type": "string" },
          "timeout_ms": { "type": "integer" },
          "max_output_chars": { "type": "integer" },
          "background": { "type": "boolean" },
          "verification_kind": {
            "type": "string",
            "enum": ["check", "test", "build"],
          },
        },
        "required": ["cmd"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "moon_ide",
      "Run read-only MoonBit semantic navigation inside the selected MoonBook.",
      {
        "type": "object",
        "properties": {
          "action": {
            "type": "string",
            "enum": ["doc", "outline", "peek_def", "hover", "find_references"],
          },
          "query": { "type": "string" },
          "path": { "type": "string" },
          "loc": { "type": "string" },
          "target": { "type": "string" },
          "no_check": { "type": "boolean" },
          "timeout_ms": { "type": "integer" },
          "max_output_chars": { "type": "integer" },
        },
        "required": ["action"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "moon_cmd",
      "Run a MoonBit command at its module root. cwd selects a module; paths infer the nearest module. args pass command options; program_args follow run's --. For fmt omit target and package selectors; file paths and formatter options are valid.",
      {
        "type": "object",
        "properties": {
          "command": {
            "type": "string",
            "enum": ["check", "test", "run", "info", "fmt", "build"],
          },
          "cwd": { "type": "string" },
          "target": {
            "type": "string",
            "enum": ["wasm", "wasm-gc", "js", "native", "llvm", "all"],
          },
          "args": { "type": "array", "items": { "type": "string" } },
          "paths": { "type": "array", "items": { "type": "string" } },
          "program_args": { "type": "array", "items": { "type": "string" } },
          "expected_exit_code": {
            "type": "integer",
            "description": "Default 0; MoonBit test failures return 2. Set for intentional negative checks.",
          },
          "timeout_ms": { "type": "integer" },
          "max_output_chars": { "type": "integer" },
        },
        "required": ["command"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "finish",
      "Deliver completed work with a concise summary and verification.",
      {
        "type": "object",
        "properties": { "answer": { "type": "string" } },
        "required": ["answer"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "apply_patch",
      "Apply a MoonBook unified diff with --- a/path, +++ b/path and @@ headers; no *** Begin Patch markers. Multi-file diffs select paths from headers; omit path.",
      {
        "type": "object",
        "properties": {
          "path": { "type": "string" },
          "before": { "type": "string" },
          "after": { "type": "string" },
          "diff": { "type": "string" },
          "context_path": { "type": "string" },
          "target": { "type": "string" },
          "hunk_index": { "type": "integer", "minimum": 1 },
        },
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "checkpoint",
      "Save optional, revisable progress and a next action; not completion evidence.",
      {
        "type": "object",
        "properties": {
          "horizon_id": { "type": "string" },
          "milestones": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "id": { "type": "string" },
                "title": { "type": "string" },
                "status": {
                  "type": "string",
                  "enum": ["pending", "active", "done"],
                },
              },
              "required": ["id", "title", "status"],
              "additionalProperties": false,
            },
          },
          "next_action": { "type": "string" },
        },
        "required": ["horizon_id", "milestones", "next_action"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "read_skill",
      "Load a complete installed Skill or referenced path; omit name to list full descriptions. Declared tools become available next turn.",
      {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "path": { "type": "string" },
        },
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "mcp_list_tools",
      "Discover enabled MCP tool schemas. Omit server for all connections; server/cursor fetch the next page.",
      {
        "type": "object",
        "properties": {
          "server": { "type": "string" },
          "cursor": { "type": "string" },
        },
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "mcp_call_tool",
      "Call a configured MCP tool using its discovered schema and exact server/name/arguments.",
      {
        "type": "object",
        "properties": {
          "server": { "type": "string" },
          "name": { "type": "string" },
          "arguments": { "type": "object", "additionalProperties": true },
        },
        "required": ["server", "name", "arguments"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "spawn_workers",
      "Spawn child prompt sessions in caller-supplied isolated MoonBooks; the parent controls them.",
      {
        "type": "object",
        "properties": {
          "workers": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "id": { "type": "string" },
                "book_root": { "type": "string" },
                "prompt": { "type": "string" },
                "model": { "type": "string" },
                "task_intent": {
                  "type": "string",
                  "enum": ["workspace_change", "read_only"],
                },
              },
              "required": ["id", "book_root", "prompt"],
              "additionalProperties": false,
            },
          },
        },
        "required": ["workers"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "wait_workers",
      "Project durable child-session state for any or all selected workers.",
      {
        "type": "object",
        "properties": {
          "mode": { "type": "string", "enum": ["any", "all"] },
          "worker_ids": { "type": "array", "items": { "type": "string" } },
        },
        "required": ["mode"],
        "additionalProperties": false,
      },
    ),
  ]
}

///|
fn mooncode_runtime_turn_model_tool(
  name : String,
  description : String,
  parameters : Json,
) -> @openai.ChatCompletionToolParam {
  @openai.tool(name~, description~, parameters~, strict=true)
}
