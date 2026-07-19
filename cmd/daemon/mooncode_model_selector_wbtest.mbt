///|
test "MoonCode canonicalizes only the exact gpt-5.6-sol compatibility alias" {
  assert_true(
    mooncode_runtime_model_selector("gpt-5.6-sol") is Some("codex/gpt-5.6-sol"),
  )
  assert_true(
    mooncode_runtime_model_selector("codex/gpt-5.6-sol")
    is Some("codex/gpt-5.6-sol"),
  )
  for
    rejected in [
      "gpt-5.4", "gpt-5.3-codex", "gpt-5.6", "not-a-model", "codex", "codex/", "/gpt-5.6-sol",
      "codex//gpt-5.6-sol", " codex/gpt-5.6-sol", "codex/gpt-5.6-sol ",
    ] {
    assert_true(mooncode_runtime_model_selector(rejected) is None)
  }
  assert_true(
    mooncode_runtime_model_selector("codex/gpt-5.4") is None,
  )
}

///|
test "MoonCode rewrites the exact alias at every supported command boundary" {
  let canonical = mooncode_command_with_canonical_model_selector({
    "model": "gpt-5.6-sol",
    "payload": { "model": "gpt-5.6-sol", "planner_model": "gpt-5.6-sol" },
    "packet": {
      "model": "gpt-5.6-sol",
      "payload": { "model": "gpt-5.6-sol", "planner_model": "gpt-5.6-sol" },
    },
  })
  assert_eq(
    mooncode_runtime_turn_requested_model(canonical),
    "codex/gpt-5.6-sol",
  )
  let payload = mooncode_json_object_field_or_empty(canonical, "payload")
  assert_eq(
    mooncode_json_string(payload, "planner_model", default=""),
    "codex/gpt-5.6-sol",
  )
  let packet = mooncode_json_object_field_or_empty(canonical, "packet")
  assert_eq(
    mooncode_json_string(packet, "model", default=""),
    "codex/gpt-5.6-sol",
  )
  let packet_payload = mooncode_json_object_field_or_empty(packet, "payload")
  assert_eq(
    mooncode_json_string(packet_payload, "planner_model", default=""),
    "codex/gpt-5.6-sol",
  )
  guard mooncode_command_with_canonical_model_selector({
      "model": "codex/gpt-5.6-sol",
    })
    is { "payload"? : None, "packet"? : None, .. } else {
    fail("canonicalization must not add absent command containers")
  }
}

///|
test "MoonCode inherits exact session model and journals explicit call provenance" {
  for action in ["prompt", "package", "steer"] {
    let inherited = mooncode_command_with_session_model(
      { "command": action, "text": "create x exactly y" },
      "codex/gpt-5.6-sol",
    )
    assert_eq(
      mooncode_runtime_turn_requested_model(inherited),
      "codex/gpt-5.6-sol",
    )
    assert_false(inherited.stringify().contains("explicit-tool-calls"))
    assert_true(mooncode_runtime_turn_uses_exact_model(inherited))
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
  assert_eq(
    mooncode_json_string(explicit, "model", default=""),
    "codex/gpt-5.6-sol",
  )
  assert_false(explicit.stringify().contains("explicit-tool-calls"))
}

///|
async test "MoonCode exact selector resolves to the OAuth wire model" {
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
    for requested in ["gpt-5.6-sol", "codex/gpt-5.6-sol"] {
      guard mooncode_runtime_model_selector(requested) is Some(selector) else {
        fail("expected exact MoonCode selector")
      }
      guard loader.get_model(name=selector) is Some(model) else {
        fail("valid exact selector with OAuth credentials must resolve")
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
