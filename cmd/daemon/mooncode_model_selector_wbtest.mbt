///|
test "MoonCode preserves opaque provider model selectors" {
  for
    selector in [
      "gpt-5.6-sol", "codex/gpt-5.6-sol", "moongate/kimi-k3", "custom-model",
    ] {
    assert_eq(mooncode_runtime_model_selector(selector).unwrap_or(""), selector)
  }
  for rejected in ["", " moongate/kimi-k3", "moongate/kimi-k3 "] {
    assert_true(mooncode_runtime_model_selector(rejected) is None)
  }
}

///|
test "MoonCode inherits the provider-selected session model" {
  for action in ["prompt", "package", "steer"] {
    let inherited = mooncode_command_with_session_model(
      { "command": action, "text": "create x exactly y" },
      "moongate/provider-selected-model",
    )
    assert_eq(
      mooncode_runtime_turn_requested_model(inherited),
      "moongate/provider-selected-model",
    )
    assert_false(inherited.stringify().contains("explicit-tool-calls"))
  }
  let explicit = mooncode_command_with_session_model(
    {
      "command": "prompt",
      "model": "gpt-5.6-sol",
      "runtime_tool_calls": [
        { "tool": "finish", "arguments": { "answer": "done" } },
      ],
    },
    "",
  )
  assert_eq(mooncode_json_string(explicit, "model", default=""), "gpt-5.6-sol")
  assert_false(explicit.stringify().contains("explicit-tool-calls"))
}

///|
async test "MoonCode uses the provider model selected by the loader" {
  @fsx.with_temporary_directory("moonclaw-mooncode-model-XXXXXX", root => {
    @codex.save_credentials_for_workspace_root(
      {
        idToken: "test-id",
        accessToken: "test-access",
        refreshToken: "test-refresh",
        accountId: "test-account",
      },
      root~,
    )
    let loader = @model.Loader::new(home=root, cwd=root)
    for requested in ["codex/gpt-5.6-sol"] {
      guard mooncode_runtime_model_selector(requested) is Some(selector) else {
        fail("expected provider model selector")
      }
      guard loader.get_model(name=selector) is Some(model) else {
        fail("provider model selector must resolve")
      }
      assert_eq(model.selector(), "codex/gpt-5.6-sol")
      assert_eq(model.model_name, "gpt-5.6-sol")
      let request = mooncode_runtime_turn_model_plan_request(model.model_name, {
        "command": "prompt",
        "text": "Inspect one source file",
      }).to_json()
      assert_eq(
        mooncode_json_string(request, "model", default=""),
        "gpt-5.6-sol",
      )
      assert_false(request.stringify().contains("gpt-5.4"))
    }
  })
}
