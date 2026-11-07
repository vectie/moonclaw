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
fn mooncode_runtime_turn_moon_cmd_arguments(command : Json) -> Json {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let action = mooncode_json_string(command, "command", default="prompt")
  let default_command = match action {
    "run_build" => "build"
    "run_tests" => "test"
    _ => "check"
  }
  let moon_command = mooncode_json_string(
    payload,
    "moon_cmd_command",
    default=default_command,
  )
  let target = mooncode_json_string(payload, "moon_cmd_target", default="")
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
