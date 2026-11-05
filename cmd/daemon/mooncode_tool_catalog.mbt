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
  let finish_description = "Deliver completed work with a concise summary. For tool authorization, select the exact tool call and let the runtime handle approval."
  [
    mooncode_runtime_turn_model_tool(
      "ask_user",
      "Ask a necessary product or planning question and wait for the user's answer before dependent work. Give short choices when useful; use a stable id for this question. Do not use this for tool approvals.",
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
      "Read a whole file or an inclusive line range inside the selected MoonBook. Prefer start_line/end_line over shell-based sed slices.",
      {
        "type": "object",
        "properties": {
          "path": { "type": "string" },
          "start_line": { "type": "integer", "minimum": 1 },
          "end_line": { "type": "integer", "minimum": 1 },
          "max_output_chars": { "type": "integer" },
        },
        "required": ["path"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "view_image",
      "Inspect PNG, JPEG, WebP, or GIF pixels from a file inside the selected MoonBook. The image is attached to the next model turn without embedding its bytes in the durable journal.",
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
      "Atomically replace text in an existing MoonBook file. Use old_string/new_string for one edit, or edits for an ordered multi-edit; the file is written only after every edit validates.",
      {
        "type": "object",
        "properties": {
          "path": { "type": "string" },
          "old_string": { "type": "string" },
          "new_string": { "type": "string" },
          "replace_all": { "type": "boolean" },
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
        "required": ["path"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "shell",
      "Run one bounded foreground shell command through the configured MoonFort grant. Use cwd for a directory inside the selected MoonBook. Background processes are unsupported. Set verification_kind only for a command whose zero exit status directly proves that check, test or build.",
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
      "browser",
      "Operate an isolated native browser session for UI-to-UI work. Prefer snapshot for semantic state, screenshot plus view_image for visual judgment, and console/errors for diagnosis. Snapshot returns element refs such as e21; pass them to click/fill/wait as selectors with the required @ prefix (for example @e21). Visible labels such as button text are not selectors. Take a fresh snapshot after navigation or a DOM-changing action before reusing refs.",
      {
        "type": "object",
        "properties": {
          "action": {
            "type": "string",
            "enum": [
              "open", "snapshot", "screenshot", "set_viewport", "click", "fill",
              "press", "wait", "get", "eval", "console", "errors", "reload", "close",
            ],
          },
          "url": { "type": "string" },
          "selector": {
            "type": "string",
            "description": "CSS, XPath, or a snapshot element reference with @ prefix such as @e21; never pass visible label text as the selector.",
          },
          "text": { "type": "string" },
          "key": { "type": "string" },
          "path": { "type": "string" },
          "full_page": { "type": "boolean" },
          "interactive": { "type": "boolean" },
          "compact": { "type": "boolean" },
          "depth": { "type": "integer" },
          "width": { "type": "integer" },
          "height": { "type": "integer" },
          "what": { "type": "string" },
          "attribute": { "type": "string" },
          "script": { "type": "string" },
          "wait_ms": { "type": "integer" },
          "timeout_ms": { "type": "integer" },
          "max_output_chars": { "type": "integer" },
        },
        "required": ["action"],
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
      "Run a structured MoonBit command at a MoonBit module root. Use cwd for a known nested module, or path/paths so the runtime can infer the nearest module. `fmt` accepts paths and formatter options but no target or package selector; check/test/info/build preserve valid target and package/file selectors.",
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
            "description": "Backend for check, test, info, build, or run. Omit for fmt.",
            "enum": ["wasm", "wasm-gc", "js", "native", "llvm", "all"],
          },
          "arg": {
            "type": "string",
            "description": "One command-specific option. Do not put target or package selectors here for fmt.",
          },
          "args": {
            "type": "array",
            "description": "Command-specific options. Do not put target or package selectors here for fmt.",
            "items": { "type": "string" },
          },
          "path": {
            "type": "string",
            "description": "One package directory or file selector; may identify a nested module when cwd is omitted.",
          },
          "paths": {
            "type": "array",
            "description": "Package directory or file selectors within one MoonBit module.",
            "items": { "type": "string" },
          },
          "program_args": { "type": "array", "items": { "type": "string" } },
          "expected_exit_code": {
            "type": "integer",
            "description": "Expected process exit code; use 1 for intentional negative-path CLI validation.",
          },
          "test_update_kind": { "type": "string" },
          "test_update_reason": { "type": "string" },
          "timeout_ms": { "type": "integer" },
          "max_output_chars": { "type": "integer" },
        },
        "required": ["command"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "moon_check",
      "Run moon check inside the selected MoonBook.",
      {
        "type": "object",
        "properties": {
          "cwd": {
            "type": "string",
            "description": "MoonBook-relative directory containing moon.mod; use this for nested modules.",
          },
          "target": {
            "type": "string",
            "enum": ["wasm", "wasm-gc", "js", "native", "llvm", "all"],
          },
          "timeout_ms": { "type": "integer" },
          "max_output_chars": { "type": "integer" },
        },
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool("finish", finish_description, {
      "type": "object",
      "properties": { "answer": { "type": "string" } },
      "required": ["answer"],
      "additionalProperties": false,
    }),
    mooncode_runtime_turn_model_tool(
      "apply_patch",
      "Apply one unified diff, including a multi-file diff, inside the selected MoonBook. The diff must use standard `--- a/path`, `+++ b/path`, and `@@` syntax; do not wrap it in `*** Begin Patch` / `*** Update File` markers. For a diff, omit path because targets come from its file headers.",
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
      "Save optional working progress and a useful next action. Milestones may be revised or reopened; they do not establish completion.",
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
      "Load the complete installed SKILL.md, or a referenced file inside that selected skill. Use path only after SKILL.md identifies the resource as relevant.",
      {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "path": { "type": "string" },
        },
        "required": ["name"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "mcp_list_tools",
      "Discover tools and their input schemas on enabled MCP integrations. Omit server to list all configured connections. Use cursor with server to fetch the next page.",
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
      "Call a configured MCP integration tool. First inspect its schema with mcp_list_tools; provide the exact server, tool name and arguments.",
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
      "Spawn ordinary MoonCode prompt sessions in caller-supplied isolated MoonBook roots. The parent session remains the controller.",
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
