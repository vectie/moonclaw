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
  ignore(command)
  []
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
    lower.has_prefix("open ") ||
    lower.has_prefix("please read ") ||
    lower.has_prefix("please open ")
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
      "target": target,
      "timeout_ms": 60000,
      "max_output_chars": 16000,
    }
  }
}

///|
#warnings("-unused_value")
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
        "arguments": {
          "path": path,
          "max_output_chars": MOONCODE_DEFAULT_TOOL_OUTPUT_CHARS,
        },
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
  []
}
