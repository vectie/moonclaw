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
test "default tasks share one catalog regardless of language or inferred purpose" {
  let expected = mooncode_test_model_tool_names(
    mooncode_runtime_turn_model_tools(),
  ).filter(name => name != "spawn_workers" && name != "wait_workers")
  for
    text in [
      "Fix the parser and run tests.", "Refactor the MoonBit package.", "Fix the web UI and inspect screenshots.",
      "修复解析器并验证结果", "Choose a plan, then implement it.", "Explain the word fix",
      "请解释 fix 的含义", "Review the implementation without editing", "Reply briefly",
    ] {
    let command : Json = { "command": "prompt", "text": text }
    let names = mooncode_test_model_tool_names(
      mooncode_runtime_turn_model_tools_for_command(command),
    )
    assert_eq(names, expected, msg=text)
    for
      needed in [
        "ask_user", "read", "write", "edit", "apply_patch", "shell", "moon_ide",
        "moon_cmd", "browser", "view_image", "mcp_list_tools", "mcp_call_tool", "finish",
      ] {
      assert_true(names.contains(needed), msg=needed)
    }
  }
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
    needed in [
      "read", "view_image", "moon_ide", "read_skill", "mcp_list_tools", "finish",
    ] {
    assert_true(names.contains(needed))
  }
  for
    omitted in [
      "write", "edit", "apply_patch", "shell", "spawn_workers", "wait_workers",
    ] {
    assert_false(names.contains(omitted))
  }
}
