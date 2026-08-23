///|
fn mooncode_test_model_tool_names(
  tools : Array[@openai.ChatCompletionToolParam],
) -> Array[String] {
  tools.map(tool => {
    let function = mooncode_json_object_field_or_empty(
      tool.to_json(),
      "function",
    )
    mooncode_json_string(function, "name", default="")
  })
}

///|
test "mooncode dynamic tool bundles are disabled by default" {
  let command : Json = {
    "command": "prompt",
    "text": "Fix the parser and run tests.",
  }
  let names = mooncode_test_model_tool_names(
    mooncode_runtime_turn_model_tools_for_command(command),
  )
  assert_true(names.contains("browser"))
  assert_true(names.contains("moon_cmd"))
  assert_true(names.contains("spawn_workers"))
}

///|
test "mooncode dynamic tool bundles select only task capabilities" {
  let command : Json = {
    "command": "prompt",
    "text": "Fix the parser and run tests.",
    "payload": {
      "task_intent": "workspace_change",
      "planner_dynamic_tool_bundles": true,
    },
  }
  let names = mooncode_test_model_tool_names(
    mooncode_runtime_turn_model_tools_for_command(command),
  )
  for
    name in [
      "read", "write", "edit", "shell", "finish", "apply_patch", "checkpoint", "read_skill",
    ] {
    assert_true(names.contains(name))
  }
  assert_false(names.contains("browser"))
  assert_false(names.contains("view_image"))
  assert_false(names.contains("moon_cmd"))
  assert_false(names.contains("spawn_workers"))
}

///|
test "mooncode dynamic tool bundles add ui moonbit and worker capabilities" {
  let ui : Json = {
    "command": "prompt",
    "text": "Test the web app UI in the browser and inspect screenshots.",
    "payload": {
      "task_intent": "workspace_change",
      "planner_dynamic_tool_bundles": true,
    },
  }
  let ui_names = mooncode_test_model_tool_names(
    mooncode_runtime_turn_model_tools_for_command(ui),
  )
  assert_true(ui_names.contains("browser"))
  assert_true(ui_names.contains("view_image"))
  assert_false(ui_names.contains("moon_cmd"))

  let moonbit : Json = {
    "command": "prompt",
    "text": "Refactor the MoonBit package, delegate independent checks to workers, and run moon test.",
    "payload": {
      "task_intent": "workspace_change",
      "planner_dynamic_tool_bundles": true,
    },
  }
  let moonbit_names = mooncode_test_model_tool_names(
    mooncode_runtime_turn_model_tools_for_command(moonbit),
  )
  assert_true(moonbit_names.contains("moon_ide"))
  assert_true(moonbit_names.contains("moon_cmd"))
  assert_true(moonbit_names.contains("moon_check"))
  assert_true(moonbit_names.contains("spawn_workers"))
  assert_true(moonbit_names.contains("wait_workers"))
}

///|
test "mooncode explicit planner allow-list takes precedence over bundles" {
  let command : Json = {
    "command": "prompt",
    "text": "Fix the MoonBit UI with workers.",
    "payload": {
      "task_intent": "workspace_change",
      "planner_dynamic_tool_bundles": true,
      "planner_allowed_tools": ["read", "finish"],
    },
  }
  assert_eq(
    mooncode_test_model_tool_names(
      mooncode_runtime_turn_model_tools_for_command(command),
    ),
    ["read", "finish"],
  )
}

///|
test "mooncode dynamic bundle is explicit in the system prompt" {
  let command : Json = {
    "command": "prompt",
    "text": "Fix the parser and run tests.",
    "payload": {
      "task_intent": "workspace_change",
      "planner_dynamic_tool_bundles": true,
    },
  }
  let messages = mooncode_runtime_turn_model_initial_messages(command)
  let system = mooncode_json_string(messages[0], "content", default="")
  assert_true(system.contains("Active tool bundle for this request:"))
  assert_true(system.contains("read, write, edit, shell"))
  assert_true(system.contains("supplied bundle is authoritative"))
}
