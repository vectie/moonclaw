///|
fn mooncode_test_model_tool_names(
  tools : Array[@openai.ChatCompletionToolParam],
) -> Array[String] {
  tools.map(tool => {
    mooncode_json_string(
      mooncode_json_object_field_or_empty(tool.to_json(), "function"),
      "name",
      default="",
    )
  })
}

///|
test "default tools retain base controls and defer additional capabilities" {
  assert_eq(
    mooncode_test_model_tool_names(
      mooncode_runtime_turn_model_tools_for_command({}),
    ),
    [
      "ask_user", "read", "read_result", "write", "edit", "shell", "finish", "read_skill",
      "mcp_list_tools", "mcp_call_tool",
    ],
  )
}

///|
test "explicit tools and optional workers use the same authoritative catalog" {
  for
    allowed in [
      ["read", "finish"],
      ["spawn_workers", "wait_workers"],
      ["mcp_list_tools"],
    ] {
    let command : Json = {
      "command": "prompt",
      "text": "Complete the task",
      "task_context": { "available_mcp_integrations": [] },
      "payload": {
        "planner_allowed_tools": Json::array(allowed.map(name => Json(name))),
      },
    }
    assert_eq(
      mooncode_test_model_tool_names(
        mooncode_runtime_turn_model_tools_for_command(command),
      ),
      allowed,
    )
  }
  for servers in [[], ["configured"]] {
    let names = mooncode_test_model_tool_names(
      mooncode_runtime_turn_model_tools_for_command({
        "task_context": { "available_mcp_integrations": Json(servers) },
      }),
    )
    for name in ["mcp_list_tools", "mcp_call_tool"] {
      assert_eq(names.contains(name), !servers.is_empty())
    }
    assert_true(names.contains("shell"))
  }
}

///|
test "read-only tool selection retains inspection without workspace mutation tools" {
  let command : Json = {
    "command": "prompt",
    "text": "Review this implementation",
    "payload": { "task_intent": "read_only" },
  }
  let names = mooncode_test_model_tool_names(
    mooncode_runtime_turn_model_tools_for_command(command),
  )
  for
    needed in ["read", "read_result", "read_skill", "mcp_list_tools", "finish"] {
    assert_true(names.contains(needed))
  }
  for
    omitted in [
      "write", "edit", "apply_patch", "shell", "spawn_workers", "wait_workers",
    ] {
    assert_false(names.contains(omitted))
  }
  let loaded : Json = {
    "accepted": true,
    "tool": "read_skill",
    "result": {
      "metadata": {
        "allowed_tools": ["view_image", "moon_ide", "write", "spawn_workers"],
      },
    },
  }
  let selected = mooncode_test_model_tool_names(
    mooncode_runtime_turn_model_tools_for_command(command, skill_results=[
      loaded,
    ]),
  )
  assert_true(selected.contains("view_image"))
  assert_true(selected.contains("moon_ide"))
  assert_false(selected.contains("write"))
  assert_false(selected.contains("spawn_workers"))
}
