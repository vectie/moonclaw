///|
test "mooncode core protocol surface is stable" {
  assert_eq(protocol_version(), "mooncode.v1")
  assert_eq(conversation_contract_id(), "moonsuite-conversation.v1")
  assert_eq(conversation_kind(), "mooncode-conversation")
  assert_eq(conversation_turn_kind(), "mooncode-conversation-turn")
  assert_true(conversation_message_roles().contains("progress"))
  assert_true(conversation_turn_required_fields().contains("client_turn_id"))
  assert_eq(
    native_capability_contract_id(),
    "mooncode-native-capability-surface.v1",
  )
  let endpoints = native_capability_endpoints()
  assert_eq(endpoints.capabilities, "/v1/code/capabilities")
  assert_eq(
    endpoints.runtime_service,
    "/v1/code/sessions/<id>/runtime-service?book_root=<path>",
  )
  assert_eq(
    endpoints.required_endpoints().length(),
    native_capability_required_endpoints().length(),
  )
  for endpoint in endpoints.required_endpoints() {
    assert_true(native_capability_required_endpoints().contains(endpoint))
  }
  assert_true(
    native_capability_target_description().contains(endpoints.capabilities),
  )
  assert_true(
    native_capability_target_description().contains(endpoints.runtime_events),
  )
  assert_eq(
    native_session_commands_endpoint("session one"),
    "/v1/code/sessions/session%20one/commands",
  )
  assert_eq(
    native_runtime_service_endpoint("session one", "/tmp/moon book"),
    "/v1/code/sessions/session%20one/runtime-service?book_root=%2Ftmp%2Fmoon%20book",
  )
  assert_eq(
    native_session_listing_endpoint("/tmp/moon book"),
    "/v1/code/sessions?book_root=%2Ftmp%2Fmoon%20book&format=json",
  )
  assert_eq(
    native_stream_endpoint("session one", "/tmp/moon book", "sse", 7),
    "/v1/code/sessions/session%20one/stream?book_root=%2Ftmp%2Fmoon%20book&format=sse&since=7&wait_ms=0&poll_ms=100",
  )
  assert_eq(native_endpoint_component("safe-_.~"), "safe-_.~")
  assert_eq(native_endpoint_component("!*'()"), "%21%2A%27%28%29")
  assert_eq(native_endpoint_component("中文"), "%E4%B8%AD%E6%96%87")
  assert_true(
    native_capability_required_endpoints().contains("/v1/code/capabilities"),
  )
  assert_true(
    native_capability_required_endpoints().contains(
      "/v1/code/sessions/<id>/runtime-service?book_root=<path>",
    ),
  )
  assert_eq(event_lane_contract_id(), "mooncode-event-lanes.v1")
  assert_eq(event_lane_default(), "runtime")
  assert_eq(event_lanes().length(), 7)
  assert_eq(event_lanes()[0], "transcript")
  assert_eq(event_lanes()[event_lanes().length() - 1], "review")
  assert_true(event_lane_is_supported("artifact"))
  assert_false(event_lane_is_supported("debug"))
  assert_true(event_lane_is_progress("runtime"))
  assert_false(event_lane_is_progress("transcript"))
  assert_eq(event_lane_normalize("diff"), "diff")
  assert_eq(event_lane_normalize("debug"), "runtime")
  assert_eq(runtime_event_name_contract_id(), "mooncode-runtime-event-names.v1")
  assert_true(runtime_event_names().contains("assistant_delta"))
  assert_true(runtime_event_names().contains("runtime_finished"))
  assert_true(runtime_event_names().contains("package_verified"))
  assert_true(runtime_event_name_is_supported("tool_call"))
  assert_false(runtime_event_name_is_supported("debug_event"))
  assert_true(runtime_command_output_event_names().contains("tool_result"))
  assert_false(runtime_command_output_event_names().contains("usage"))
  assert_true(runtime_failure_event_names().contains("runtime_unavailable"))
  assert_true(runtime_failure_event_name_is_supported("command_error"))
  assert_true(runtime_diagnostic_event_names().contains("runtime_loop"))
  assert_true(
    runtime_diagnostic_event_name_is_supported("runtime.service_finished"),
  )
  assert_eq(command_action_contract_id(), "mooncode-command-actions.v1")
  assert_eq(command_turn_actions().length(), 3)
  assert_eq(command_turn_actions()[0], "prompt")
  assert_eq(command_turn_actions()[2], "cancel")
  assert_true(command_advertised_actions().contains("run_eval"))
  assert_true(command_advertised_actions().contains("apply_patch"))
  assert_false(command_advertised_actions().contains("note"))
  assert_true(command_supported_actions().contains("note"))
  assert_true(command_action_is_supported("prompt"))
  assert_false(command_action_is_supported("deploy_global"))
  assert_true(native_capability_required_tools().contains("apply_patch"))
  assert_true(native_command_body_required_fields().contains("session_id"))
  assert_true(native_command_body_supported_fields().contains("packet"))
  assert_true(native_command_body_field_is_supported("tool_authorization"))
  assert_false(native_command_body_field_is_supported("extra_mode"))
  assert_eq(native_capability_surface_fingerprint().length(), 64)
  let surface = native_capability_surface_json().stringify()
  assert_true(
    surface.contains("\"kind\":\"mooncode-native-capability-surface\""),
  )
  assert_true(surface.contains("\"capability_surface_fingerprint\""))
  assert_true(surface.contains("\"command_body_required_fields\""))
  assert_true(surface.contains("\"command_body_supported_fields\""))
  assert_true(surface.contains("\"runtime_loop_options\""))
  assert_true(surface.contains("\"live_wait_ms\""))
  assert_true(surface.contains("\"stream_options\""))
  assert_true(surface.contains("\"wait_ms\""))
  assert_true(surface.contains("\"poll_ms\""))
  assert_true(surface.contains("\"event_lane_contract\""))
  assert_true(surface.contains("\"contract_id\":\"mooncode-event-lanes.v1\""))
  assert_true(surface.contains("\"runtime_event_name_contract\""))
  assert_true(
    surface.contains("\"contract_id\":\"mooncode-runtime-event-names.v1\""),
  )
  assert_true(surface.contains("\"command_action_contract\""))
  assert_true(
    surface.contains("\"contract_id\":\"mooncode-command-actions.v1\""),
  )
}

///|
test "mooncode core delegates conversation contract to moonlib" {
  let payload = conversation_contract_json().stringify()
  assert_true(payload.contains("\"kind\":\"moonsuite-conversation-contract\""))
  assert_true(payload.contains("\"contract_id\":\"moonsuite-conversation.v1\""))
  assert_true(payload.contains("\"product_id\":\"mooncode\""))
  assert_true(
    payload.contains("\"conversation_kind\":\"mooncode-conversation\""),
  )
  assert_true(payload.contains("\"turn_kind\":\"mooncode-conversation-turn\""))
  assert_true(payload.contains("\"client_turn_id\""))
  assert_true(payload.contains("\"command_id\""))
  assert_true(
    payload.contains("\"turn_order\":[\"user\",\"progress\",\"assistant\"]"),
  )
  assert_true(payload.contains("\"shared_contract_owner\":\"moonlib\""))
  assert_false(payload.contains("internal/mooncode"))
  assert_false(payload.contains("internal/moonwiki"))
  assert_false(payload.contains("Rabbita"))
}

///|
test "mooncode core owns event lane contract" {
  let payload = event_lane_contract_json().stringify()
  assert_true(payload.contains("\"kind\":\"mooncode-event-lane-contract\""))
  assert_true(payload.contains("\"protocol\":\"mooncode.v1\""))
  assert_true(payload.contains("\"contract_id\":\"mooncode-event-lanes.v1\""))
  assert_true(
    payload.contains(
      "\"lanes\":[\"transcript\",\"runtime\",\"tool\",\"diff\",\"test\",\"artifact\",\"review\"]",
    ),
  )
  assert_true(
    payload.contains(
      "\"progress_lanes\":[\"runtime\",\"tool\",\"diff\",\"test\",\"artifact\",\"review\"]",
    ),
  )
  assert_true(payload.contains("\"default_lane\":\"runtime\""))
  assert_true(payload.contains("canonical conversation turns own chat"))
  assert_false(payload.contains("internal/mooncode"))
  assert_false(payload.contains("internal/moonwiki"))
  assert_false(payload.contains("Rabbita"))
}

///|
test "mooncode core owns runtime event name contract" {
  let payload = runtime_event_name_contract_json().stringify()
  assert_true(
    payload.contains("\"kind\":\"mooncode-runtime-event-name-contract\""),
  )
  assert_true(payload.contains("\"protocol\":\"mooncode.v1\""))
  assert_true(
    payload.contains("\"contract_id\":\"mooncode-runtime-event-names.v1\""),
  )
  assert_true(payload.contains("\"event_lane_contract_id\""))
  assert_true(payload.contains("\"accepted_events\""))
  assert_true(payload.contains("\"assistant_delta\""))
  assert_true(payload.contains("\"runtime_finished\""))
  assert_true(payload.contains("\"package_verified\""))
  assert_true(payload.contains("\"command_output_events\""))
  assert_true(payload.contains("\"failure_events\""))
  assert_true(payload.contains("\"runtime_unavailable\""))
  assert_true(payload.contains("\"diagnostic_events\""))
  assert_true(payload.contains("\"runtime.service_finished\""))
  assert_false(payload.contains("internal/mooncode"))
  assert_false(payload.contains("internal/moonwiki"))
  assert_false(payload.contains("Rabbita"))
}

///|
test "mooncode core owns command action contract" {
  assert_eq(command_prompt(), "prompt")
  assert_eq(command_steer(), "steer")
  assert_eq(command_cancel(), "cancel")
  assert_true(command_action_is_turn("prompt"))
  assert_false(command_action_is_turn("run_tests"))
  assert_true(command_action_is_test("run_tests"))
  assert_true(command_action_is_test("run_build"))
  assert_true(command_action_is_eval("run_eval"))
  assert_true(command_action_is_package("package"))
  assert_true(command_action_is_commit("commit"))
  assert_true(command_action_is_review_decision("accept"))
  assert_true(command_action_is_review_decision("reject"))
  assert_true(command_action_is_tool_approval("approve_tool"))
  assert_true(command_action_is_tool_approval("reject_tool"))
  assert_true(command_action_is_patch("apply_patch"))
  assert_true(command_action_is_patch("revert_patch"))
  assert_true(command_action_requires_tool_harness("prompt"))
  assert_true(command_action_requires_tool_harness("apply_patch"))
  assert_false(command_action_requires_tool_harness("cancel"))
  assert_true(command_action_requires_runtime_completion_proof("commit"))
  assert_false(command_action_requires_runtime_completion_proof("prompt"))
  assert_true(command_action_writes_review_receipt("package"))
  assert_false(command_action_writes_review_receipt("run_tests"))
  assert_eq(command_action_control("prompt"), "prompt")
  assert_eq(command_action_control("package"), "command")
  assert_eq(command_action_approval("run_eval"), "auto")
  assert_eq(command_action_approval("commit"), "operator")
  assert_eq(command_action_approval("steer"), "user")
  assert_eq(command_action_lane("run_tests"), "test")
  assert_eq(command_action_lane("package"), "artifact")
  assert_eq(command_action_lane("commit"), "review")
  assert_eq(command_action_lane("prompt"), "runtime")
  assert_true(command_action_expected_lanes("prompt").contains("transcript"))
  assert_true(command_action_expected_lanes("apply_patch").contains("diff"))
  assert_true(command_action_tool_hints("prompt").contains("finish"))
  assert_true(command_action_tool_hints("package").contains("package_app_tool"))
  assert_eq(command_action_title("run_tests", "queued"), "Run tests: queued")
  let payload = command_action_contract_json().stringify()
  assert_true(payload.contains("\"kind\":\"mooncode-command-action-contract\""))
  assert_true(payload.contains("\"protocol\":\"mooncode.v1\""))
  assert_true(
    payload.contains("\"contract_id\":\"mooncode-command-actions.v1\""),
  )
  assert_true(payload.contains("\"event_lane_contract_id\""))
  assert_true(payload.contains("\"runtime_event_name_contract_id\""))
  assert_true(
    payload.contains("\"turn_actions\":[\"prompt\",\"steer\",\"cancel\"]"),
  )
  assert_true(payload.contains("\"advertised_actions\""))
  assert_true(payload.contains("\"supported_actions\""))
  assert_true(payload.contains("\"apply_patch\""))
  assert_true(payload.contains("\"requires_runtime_completion_proof\""))
  assert_false(payload.contains("internal/mooncode"))
  assert_false(payload.contains("internal/moonwiki"))
  assert_false(payload.contains("Rabbita"))
}

///|
test "mooncode core defines executable book lifecycle contract" {
  assert_eq(
    executable_book_lifecycle_contract_id(),
    "mooncode-executable-book-lifecycle.v1",
  )
  let steps = executable_book_lifecycle_steps()
  assert_eq(steps.length(), 9)
  assert_eq(steps[0], "select_book")
  assert_eq(steps[steps.length() - 1], "resume_session")
  assert_true(steps.contains("edit_code"))
  assert_true(steps.contains("verify_code"))
  assert_true(steps.contains("review_diff"))
  assert_true(steps.contains("accept_result"))
  assert_true(steps.contains("package_output"))
  let payload = executable_book_lifecycle_contract_json().stringify()
  assert_true(
    payload.contains("\"kind\":\"mooncode-executable-book-lifecycle\""),
  )
  assert_true(payload.contains("\"runtime_owner\":\"moonclaw\""))
  assert_true(payload.contains("\"artifact_owner\":\"moonbook\""))
  assert_true(payload.contains("\"acceptance_owner\":\"bookkeeper\""))
  assert_true(
    payload.contains(
      ".moonsuite/products/moonclaw/mooncode/sessions/<id>/session.json",
    ),
  )
  assert_true(payload.contains("commands.jsonl"))
  assert_true(payload.contains("runtime-receipts.jsonl"))
  assert_true(payload.contains("package_verified"))
  assert_true(payload.contains("readiness projection"))
  assert_false(payload.contains("vectie/moondesk"))
  assert_false(payload.contains("internal/mooncode"))
  assert_false(payload.contains("internal/moonwiki"))
  assert_false(payload.contains("Rabbita"))
  assert_false(payload.contains("rabbita"))
}

///|
test "mooncode core names standalone package boundaries" {
  let payload = standalone_boundary_json().stringify()
  assert_true(payload.contains("\"kind\":\"mooncode-standalone-boundary\""))
  assert_true(payload.contains("\"protocol\":\"mooncode.v1\""))
  assert_true(payload.contains("\"core_package\":\"mooncode/core\""))
  assert_true(
    payload.contains("\"projection_component\":\"mooncode.projection\""),
  )
  assert_true(payload.contains("\"host_component\":\"moonwiki.host\""))
  assert_true(
    payload.contains("\"runtime_component\":\"moonclaw.standalone-runtime\""),
  )
  assert_true(
    payload.contains("\"runtime_substrate\":\"moonclaw.shared-runtime\""),
  )
  assert_true(payload.contains("\"id\":\"mooncode-coding-lane\""))
  assert_true(payload.contains("\"id\":\"moonwiki-book-lane\""))
  assert_true(payload.contains("\"id\":\"moonclaw-task-lane\""))
  assert_true(payload.contains("\"id\":\"mooncode-core\""))
  assert_true(payload.contains("\"id\":\"mooncode-projection\""))
  assert_true(payload.contains("\"id\":\"moonwiki-host\""))
  assert_true(payload.contains("\"id\":\"moonclaw-standalone-runtime\""))
  assert_true(payload.contains("shared runtime substrate"))
  assert_true(
    payload.contains(
      "MoonClaw must remain usable as a standalone agent runtime",
    ),
  )
  assert_true(
    payload.contains("MoonCode, MoonWiki, and generic tasks share MoonClaw"),
  )
  assert_true(
    payload.contains("mooncode/core must contain only stable protocol"),
  )
  assert_false(payload.contains("vectie/moondesk"))
  assert_false(payload.contains("internal/mooncode"))
  assert_false(payload.contains("internal/moonwiki"))
  assert_false(payload.contains("../moonclaw"))
}
