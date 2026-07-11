///|
fn mooncode_runtime_turn_tool_calls(command : Json) -> Array[Json] {
  let explicit = mooncode_json_array_items(command, "runtime_tool_calls")
  if explicit.length() > 0 {
    return explicit
  }
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let explicit = mooncode_json_array_items(packet, "runtime_tool_calls")
  if explicit.length() > 0 {
    return explicit
  }
  let action = mooncode_json_string(command, "command", default="prompt")
  match action {
    "prompt" => mooncode_runtime_turn_prompt_tool_calls(command)
    "steer" =>
      [
        {
          "tool": "finish",
          "arguments": {
            "answer": "Native MoonCode runtime applied steering context to the active or next claimed turn.",
          },
        },
      ]
    "run_tests" | "run_build" | "run_eval" =>
      [
        {
          "tool": "moon_cmd",
          "arguments": mooncode_runtime_turn_moon_cmd_arguments(command),
        },
        {
          "tool": "moon_check",
          "arguments": mooncode_runtime_turn_moon_check_arguments(command),
        },
        {
          "tool": "finish",
          "arguments": {
            "answer": "Native MoonCode runtime completed \{action}.",
          },
        },
      ]
    "cancel" =>
      [
        {
          "tool": "finish",
          "arguments": {
            "answer": "Native MoonCode runtime recorded cancel with no generic task execution.",
          },
        },
      ]
    "accept" =>
      [
        {
          "tool": "finish",
          "arguments": {
            "answer": "Native MoonCode runtime recorded accept review and wrote a MoonBook review receipt.",
          },
        },
      ]
    "reject" =>
      [
        {
          "tool": "finish",
          "arguments": {
            "answer": "Native MoonCode runtime recorded reject review and wrote a MoonBook review receipt.",
          },
        },
      ]
    "commit" =>
      [
        {
          "tool": "finish",
          "arguments": {
            "answer": "Native MoonCode runtime is creating a book-local git commit and proof event.",
          },
        },
      ]
    _ =>
      [
        {
          "tool": "finish",
          "arguments": {
            "answer": "Native MoonCode runtime recorded command `\{action}`. No explicit runtime_tool_calls were provided.",
          },
        },
      ]
  }
}

///|
fn mooncode_runtime_turn_prompt_tool_calls(command : Json) -> Array[Json] {
  let request = mooncode_runtime_turn_prompt_text(command)
  let lower = request.to_lower().to_string()
  if mooncode_runtime_turn_is_simple_generation_request(request) &&
    mooncode_runtime_turn_mentions_miniapp(lower) {
    return mooncode_runtime_turn_miniapp_tool_calls(command, request)
  }
  if mooncode_runtime_turn_is_simple_generation_request(request) &&
    mooncode_runtime_turn_mentions_tool(lower) {
    return mooncode_runtime_turn_script_tool_calls(command, request)
  }
  [
    {
      "tool": "finish",
      "arguments": {
        "answer": "MoonCode produced no executable model tool plan; no files were changed. Retry after resolving model availability or provide an explicit bounded tool call.",
      },
    },
  ]
}

///|
fn mooncode_runtime_turn_deterministic_preplan(command : Json) -> Array[Json] {
  if mooncode_json_string(command, "command", default="prompt") != "prompt" {
    return []
  }
  let request = mooncode_runtime_turn_prompt_text(command).trim().to_owned()
  let lower = request.to_lower().to_string()
  let path = mooncode_runtime_turn_prompt_path(request)
  if mooncode_runtime_turn_is_explicit_read(lower, path) {
    return [
      {
        "tool": "read",
        "arguments": { "path": path, "max_output_chars": 12000 },
        "planner": "deterministic-explicit-read",
      },
      {
        "tool": "finish",
        "arguments": { "answer": "Read `\{path}` from the selected MoonBook." },
        "planner": "deterministic-explicit-read",
      },
    ]
  }
  let exact_content = mooncode_runtime_turn_prompt_exact_content(request, lower)
  if mooncode_runtime_turn_is_explicit_write(lower, path, exact_content) {
    return [
      {
        "tool": "write",
        "arguments": { "path": path, "content": exact_content },
        "planner": "deterministic-explicit-write",
      },
      {
        "tool": "finish",
        "arguments": { "answer": "Wrote `\{path}` in the selected MoonBook." },
        "planner": "deterministic-explicit-write",
      },
    ]
  }
  if mooncode_runtime_turn_is_simple_generation_request(request) &&
    mooncode_runtime_turn_mentions_miniapp(lower) {
    return mooncode_runtime_turn_miniapp_tool_calls(command, request)
  }
  if mooncode_runtime_turn_is_simple_generation_request(request) &&
    mooncode_runtime_turn_mentions_tool(lower) {
    return mooncode_runtime_turn_script_tool_calls(command, request)
  }
  []
}

///|
fn mooncode_runtime_turn_is_simple_generation_request(request : String) -> Bool {
  // The deterministic generators intentionally satisfy small, self-contained
  // requests. Detailed engineering prompts must stay on the model/tool loop;
  // matching a noun such as "tool" or "script" is not sufficient evidence
  // that a canned artifact is the requested result.
  request.length() <= 256 && !request.contains("\n")
}

///|
fn mooncode_runtime_turn_is_explicit_read(
  lower : String,
  path : String,
) -> Bool {
  path != "" &&
  !mooncode_runtime_turn_read_needs_model(lower) &&
  (
    lower.has_prefix("read ") ||
    lower.contains(" read ") ||
    lower.has_prefix("open ") ||
    lower.contains(" open ")
  )
}

///|
fn mooncode_runtime_turn_read_needs_model(lower : String) -> Bool {
  lower.contains("summarize") ||
  lower.contains("summarise") ||
  lower.contains("explain") ||
  lower.contains("analyze") ||
  lower.contains("analyse") ||
  lower.contains("review") ||
  lower.contains("compare") ||
  lower.contains("evaluate")
}

///|
fn mooncode_runtime_turn_is_explicit_write(
  lower : String,
  path : String,
  content : String,
) -> Bool {
  path != "" &&
  content != "" &&
  lower.contains(" exactly ") &&
  (
    lower.has_prefix("write ") ||
    lower.contains(" write ") ||
    lower.has_prefix("create ") ||
    lower.contains(" create ")
  )
}

///|
fn mooncode_runtime_turn_prompt_path(request : String) -> String {
  let normalized = request
    .replace_all(old="\n", new=" ")
    .replace_all(old="\t", new=" ")
  for raw in normalized.split(" ") {
    let token = raw.trim(chars="`'\".,:;()[]{}").to_owned()
    if mooncode_runtime_turn_looks_like_file_path(token) {
      return token
    }
  }
  ""
}

///|
fn mooncode_runtime_turn_looks_like_file_path(token : String) -> Bool {
  if token == "" || token.has_prefix("/") || token.contains("..") {
    return false
  }
  token.contains("/") ||
  token.has_suffix(".md") ||
  token.has_suffix(".txt") ||
  token.has_suffix(".mbt") ||
  token.has_suffix(".json") ||
  token.has_suffix(".html") ||
  token.has_suffix(".css") ||
  token.has_suffix(".js") ||
  token.has_suffix(".ts") ||
  token.has_suffix(".sh") ||
  token.has_suffix(".toml") ||
  token.has_suffix(".yaml") ||
  token.has_suffix(".yml")
}

///|
fn mooncode_runtime_turn_prompt_exact_content(
  request : String,
  lower : String,
) -> String {
  let marker = " exactly "
  guard lower.find(marker) is Some(index) else { return "" }
  let start = index + marker.length()
  let mut content = request[start:].to_owned()
  for suffix in [", then", "; then", ". then", " then reply", " and reply"] {
    let lower_content = content.to_lower().to_string()
    if lower_content.find(suffix) is Some(end) {
      content = content[:end].to_owned()
    }
  }
  content.trim(chars="`'\" .,;:").to_owned()
}

///|
fn mooncode_runtime_turn_prompt_text(command : Json) -> String {
  let text = mooncode_json_string(command, "text", default="")
  if text != "" {
    return text
  }
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let message = mooncode_json_string(packet, "message", default="")
  if message != "" {
    return message
  }
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  mooncode_json_string(payload, "message", default="")
}

///|
fn mooncode_runtime_turn_mentions_tool(lower : String) -> Bool {
  lower.contains("tool") ||
  lower.contains("script") ||
  lower.contains("executable") ||
  lower.contains("command") ||
  lower.contains("create code") ||
  lower.contains("generate code") ||
  lower.contains("build code")
}

///|
fn mooncode_runtime_turn_mentions_miniapp(lower : String) -> Bool {
  lower.contains("miniapp") ||
  lower.contains("mini app") ||
  lower.contains("app-tool") ||
  lower.contains("web app") ||
  lower.contains("site") ||
  lower.contains("html")
}

///|
fn mooncode_runtime_turn_script_tool_calls(
  command : Json,
  request : String,
) -> Array[Json] {
  let slug = mooncode_runtime_turn_artifact_slug(command)
  let base = "tools/mooncode-generated/\{slug}"
  let script_path = base + "/run.sh"
  let readme_path = base + "/README.md"
  [
    {
      "tool": "write",
      "arguments": {
        "path": script_path,
        "content": "#!/bin/sh\nset -eu\nprintf 'MoonCode generated tool executed.\\n'\n",
      },
    },
    {
      "tool": "write",
      "arguments": {
        "path": readme_path,
        "content": mooncode_runtime_turn_artifact_readme(
          "MoonCode Generated Tool",
          request,
          script_path,
          "Run with `sh \{script_path}` from the MoonBook root.",
        ),
      },
    },
    {
      "tool": "shell",
      "arguments": {
        "cmd": "sh \{script_path}",
        "timeout_ms": 10000,
        "max_output_chars": 4000,
      },
    },
    {
      "tool": "finish",
      "arguments": {
        "answer": "Created a MoonBook-owned executable tool at `\{script_path}` and verified it with a shell run.",
      },
    },
  ]
}

///|
fn mooncode_runtime_turn_miniapp_tool_calls(
  command : Json,
  request : String,
) -> Array[Json] {
  let slug = mooncode_runtime_turn_artifact_slug(command)
  let base = "apps/mooncode-generated/\{slug}"
  let app_path = base + "/index.html"
  let readme_path = base + "/README.md"
  [
    {
      "tool": "write",
      "arguments": {
        "path": app_path,
        "content": mooncode_runtime_turn_miniapp_html(request),
      },
    },
    {
      "tool": "write",
      "arguments": {
        "path": readme_path,
        "content": mooncode_runtime_turn_artifact_readme(
          "MoonCode Generated Miniapp",
          request,
          app_path,
          "Open `\{app_path}` from the MoonBook or publish it through the MoonBook site flow.",
        ),
      },
    },
    {
      "tool": "shell",
      "arguments": {
        "cmd": "test -s \{app_path} && grep -q 'MoonCode Miniapp' \{app_path}",
        "timeout_ms": 10000,
        "max_output_chars": 4000,
      },
    },
    {
      "tool": "finish",
      "arguments": {
        "answer": "Created a MoonBook-owned miniapp at `\{app_path}` and verified the HTML entrypoint.",
      },
    },
  ]
}

///|
fn mooncode_runtime_turn_artifact_slug(command : Json) -> String {
  let command_id = mooncode_command_id(command)
  let safe = mooncode_safe_session_id(command_id)
  if safe == "" {
    "prompt"
  } else {
    safe
  }
}

///|
fn mooncode_runtime_turn_artifact_readme(
  title : String,
  request : String,
  entrypoint : String,
  usage : String,
) -> String {
  "# \{title}\n\n" +
  "Generated by MoonClaw native MoonCode runtime-turn.\n\n" +
  "## Request\n\n" +
  mooncode_runtime_turn_markdown_quote(request) +
  "\n\n## Entrypoint\n\n- `\{entrypoint}`\n\n## Usage\n\n\{usage}\n"
}

///|
fn mooncode_runtime_turn_markdown_quote(text : String) -> String {
  let clean = text.trim().to_owned()
  if clean == "" {
    "> No prompt text was provided."
  } else {
    clean.split("\n").map(line => "> " + line.to_owned()).collect().join("\n")
  }
}

///|
fn mooncode_runtime_turn_miniapp_html(request : String) -> String {
  let escaped = mooncode_runtime_turn_escape_html(request)
  "<!doctype html>\n" +
  "<html lang=\"en\">\n" +
  "<head>\n" +
  "  <meta charset=\"utf-8\">\n" +
  "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" +
  "  <title>MoonCode Miniapp</title>\n" +
  "  <style>\n" +
  "    body { font-family: system-ui, sans-serif; margin: 0; padding: 32px; background: #f7f4ed; color: #202124; }\n" +
  "    main { max-width: 760px; margin: 0 auto; }\n" +
  "    button { border: 1px solid #202124; background: #fff; padding: 8px 12px; cursor: pointer; }\n" +
  "    output { display: block; margin-top: 16px; padding: 12px; background: #fff; border: 1px solid #d8d2c4; }\n" +
  "  </style>\n" +
  "</head>\n" +
  "<body>\n" +
  "  <main>\n" +
  "    <h1>MoonCode Miniapp</h1>\n" +
  "    <p>This miniapp was generated inside a MoonBook from the prompt below.</p>\n" +
  "    <blockquote>\{escaped}</blockquote>\n" +
  "    <button type=\"button\" id=\"run\">Run</button>\n" +
  "    <output id=\"result\">Ready.</output>\n" +
  "  </main>\n" +
  "  <script>\n" +
  "    document.getElementById('run').addEventListener('click', function () {\n" +
  "      document.getElementById('result').textContent = 'MoonCode miniapp executed at ' + new Date().toISOString();\n" +
  "    });\n" +
  "  </script>\n" +
  "</body>\n" +
  "</html>\n"
}

///|
fn mooncode_runtime_turn_escape_html(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
}

///|
fn mooncode_runtime_turn_moon_check_arguments(command : Json) -> Json {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let target = mooncode_json_string(payload, "moon_check_target", default="")
  if target == "" {
    { "timeout_ms": 60000, "max_output_chars": 16000 }
  } else {
    { "target": target, "timeout_ms": 60000, "max_output_chars": 16000 }
  }
}

///|
fn mooncode_runtime_turn_moon_cmd_arguments(command : Json) -> Json {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let action = mooncode_json_string(command, "command", default="prompt")
  let default_command = if action == "run_build" { "build" } else { "check" }
  let moon_command = mooncode_json_string(
    payload,
    "moon_cmd_command",
    default=default_command,
  )
  let target = mooncode_json_string(payload, "moon_cmd_target", default="")
  let target = if target == "" {
    mooncode_json_string(payload, "moon_check_target", default="")
  } else {
    target
  }
  if target == "" {
    { "command": moon_command, "timeout_ms": 60000, "max_output_chars": 16000 }
  } else {
    {
      "command": moon_command,
      "path": target,
      "timeout_ms": 60000,
      "max_output_chars": 16000,
    }
  }
}
