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
  assert_eq(
    native_event_projection_contract_id(),
    "mooncode-native-event-projection.v1",
  )
  assert_eq(
    native_event_projection_contract_kind(),
    "mooncode-native-event-projection-contract",
  )
  assert_true(native_event_has_command_scope({ "command_id": "cmd-core" }))
  assert_true(
    native_event_is_diagnostic_only({ "kind": "runtime.service_started" }),
  )
  assert_true(
    native_event_requires_command_scope({ "kind": "assistant_message" }),
  )
  assert_eq(
    model_planner_evidence_contract_id(),
    "mooncode-model-planner-evidence.v1",
  )
  assert_true(model_planner_command_action_is_supported(command_prompt()))
  assert_true(model_planner_command_event_kind_is_supported("command.prompt"))
  assert_true(
    model_planner_event_is_planner_evidence(runtime_event_planner_started(), ""),
  )
  assert_true(
    model_planner_event_is_planner_evidence(
      runtime_event_reasoning_delta(),
      model_planner_mode_model_tool_calls(),
    ),
  )
  assert_false(
    model_planner_event_is_planner_evidence(runtime_event_reasoning_delta(), ""),
  )
  assert_eq(
    conversation_ownership_contract_id(),
    "mooncode-conversation-ownership.v1",
  )
  assert_eq(runtime_control_contract_id(), "mooncode-runtime-control.v1")
  assert_true(runtime_control_action_starts_turn(command_prompt()))
  assert_true(runtime_control_action_starts_turn(command_package()))
  assert_false(runtime_control_action_starts_turn(command_steer()))
  assert_true(runtime_control_status_is_active("runtime-started"))
  assert_true(runtime_control_status_is_blocked("blocked-missing-proof"))
  assert_true(runtime_control_effect_allows_turn("start-turn"))
  assert_true(runtime_control_effect_allows_turn("queue-turn"))
  assert_false(runtime_control_effect_allows_turn("drop-cancel"))
  assert_true(
    runtime_control_settlement_events(
      command_cancel(),
      runtime_control_effect_cancel_active(),
    ).contains(runtime_event_runtime_aborted()),
  )
  assert_eq(
    package_review_flow_contract_id(),
    "mooncode-package-review-model-flow.v1",
  )
  assert_true(package_review_flow_status_is_terminal("accepted"))
  assert_true(package_review_flow_status_is_terminal("failed"))
  assert_false(package_review_flow_status_is_terminal("waiting-for-tests"))
  assert_true(
    package_review_flow_event_is_package_command({
      "kind": "command",
      "action": "package",
    }),
  )
  assert_true(
    package_review_flow_event_is_evidence({ "kind": "package.manifest" }),
  )
  assert_true(
    package_review_flow_event_is_failure({
      "kind": "test_result",
      "status": "failed",
    }),
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
  assert_eq(runtime_tool_contract_id(), "mooncode-runtime-tools.v1")
  assert_true(runtime_tool_names().contains("moon_check"))
  assert_true(runtime_tool_names().contains("web_search"))
  assert_true(runtime_tool_capability_names().contains("eval_harness"))
  assert_true(runtime_tool_native_required_tools().contains("apply_patch"))
  assert_eq(runtime_tool_canonical_name("Bash"), "shell")
  assert_eq(runtime_tool_canonical_name("FileRead"), "read")
  assert_eq(runtime_tool_from_moonclaw_tool("execute_command"), "shell")
  assert_eq(runtime_tool_from_moonclaw_tool("replace_in_file"), "edit")
  assert_true(runtime_tool_mutates_files("write"))
  assert_false(runtime_tool_mutates_files("read"))
  assert_true(runtime_tool_requires_review("shell"))
  assert_false(runtime_tool_requires_review("moon_check"))
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
  assert_true(surface.contains("\"native_event_projection_contract\""))
  assert_true(
    surface.contains("\"contract_id\":\"mooncode-native-event-projection.v1\""),
  )
  assert_true(surface.contains("\"model_planner_evidence_contract\""))
  assert_true(
    surface.contains("\"contract_id\":\"mooncode-model-planner-evidence.v1\""),
  )
  assert_true(surface.contains("\"conversation_ownership_contract\""))
  assert_true(
    surface.contains("\"contract_id\":\"mooncode-conversation-ownership.v1\""),
  )
  assert_true(surface.contains("\"runtime_control_contract\""))
  assert_true(
    surface.contains("\"contract_id\":\"mooncode-runtime-control.v1\""),
  )
  assert_true(surface.contains("\"package_review_flow_contract\""))
  assert_true(
    surface.contains(
      "\"contract_id\":\"mooncode-package-review-model-flow.v1\"",
    ),
  )
  assert_true(surface.contains("\"command_action_contract\""))
  assert_true(
    surface.contains("\"contract_id\":\"mooncode-command-actions.v1\""),
  )
  assert_true(surface.contains("\"runtime_tool_contract\""))
  assert_true(surface.contains("\"runtime_tool_call_contract\""))
  assert_true(surface.contains("\"contract_id\":\"mooncode-runtime-tools.v1\""))
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
test "mooncode core owns native event projection contract" {
  assert_eq(
    native_event_projection_report_kind(),
    "mooncode-native-runtime-contract-report",
  )
  let mapping = moonclaw_event_mapping_json().stringify()
  assert_true(mapping.contains("\"AssistantMessageDelta\""))
  assert_true(mapping.contains("\"assistant_delta\""))
  assert_true(mapping.contains("\"PreToolCall\""))
  assert_true(mapping.contains("\"tool_call\""))
  assert_true(mapping.contains("\"Cancelled\""))
  assert_true(mapping.contains("\"runtime_aborted\""))
  assert_true(
    native_event_projection_command_scope_keys().contains("command_id"),
  )
  assert_true(
    native_event_projection_diagnostic_sources().contains(
      "moonclaw-native-moon-check-watcher",
    ),
  )
  assert_true(
    native_event_has_command_scope({
      "command_packet": { "command_id": "cmd-packet" },
    }),
  )
  assert_true(
    native_event_has_command_scope({ "mooncode_command_id": "cmd-direct" }),
  )
  assert_false(native_event_has_command_scope({ "kind": "assistant_message" }))
  assert_true(native_event_is_transcript({ "lane": "transcript" }))
  assert_true(native_event_is_progress({ "lane": "tool" }))
  assert_false(native_event_is_progress({ "lane": "transcript" }))
  assert_true(
    native_event_is_diagnostic_only({ "kind": "runtime.service_finished" }),
  )
  assert_true(
    native_event_is_diagnostic_only({
      "source": "moonclaw-native-moon-check-watcher",
      "kind": "runtime_update",
    }),
  )
  assert_true(
    native_event_requires_command_scope({ "kind": "assistant_message" }),
  )
  assert_true(native_event_requires_command_scope({ "kind": "tool_call" }))
  assert_true(native_event_requires_command_scope({ "lane": "diff" }))
  assert_false(
    native_event_requires_command_scope({ "kind": "runtime.service_finished" }),
  )
  let native_report : Json = {
    "rejected_count": 1,
    "events": [
      {
        "id": "scoped-answer",
        "kind": "assistant_message",
        "lane": "transcript",
        "command_id": "cmd-live",
        "status": "done",
      },
      {
        "id": "watcher",
        "kind": "runtime_update",
        "source": "moonclaw-native-moon-check-watcher",
        "status": "running",
      },
      {
        "id": "unsafe-answer",
        "kind": "assistant_message",
        "lane": "transcript",
        "status": "done",
      },
    ],
  }
  let report = native_event_projection_report(
    native_report,
    session_id="session-core",
    observed_at="2026-07-04T00:00:00Z",
  )
  assert_eq(
    runtime_tool_test_string(report, "kind"),
    "mooncode-native-runtime-contract-report",
  )
  assert_eq(runtime_tool_test_string(report, "status"), "unsafe")
  assert_eq(
    runtime_tool_test_string(report, "projection_contract_id"),
    native_event_projection_contract_id(),
  )
  assert_eq(native_event_projection_test_int(report, "accepted_event_count"), 3)
  assert_eq(
    native_event_projection_test_int(report, "command_scoped_event_count"),
    1,
  )
  assert_eq(
    native_event_projection_test_int(report, "diagnostic_event_count"),
    1,
  )
  assert_eq(
    native_event_projection_test_int(report, "unscoped_projection_event_count"),
    1,
  )
  let projected = native_events_for_canonical_projection(native_report)
  assert_eq(projected.length(), 2)
  let contract = native_event_projection_contract_json().stringify()
  assert_true(
    contract.contains("\"kind\":\"mooncode-native-event-projection-contract\""),
  )
  assert_true(
    contract.contains("\"contract_id\":\"mooncode-native-event-projection.v1\""),
  )
  assert_true(contract.contains("\"moonclaw_event_mapping\""))
  assert_true(contract.contains("\"diagnostic_sources\""))
  assert_true(contract.contains("\"command_scope_keys\""))
  assert_false(contract.contains("internal/mooncode"))
  assert_false(contract.contains("internal/moonwiki"))
  assert_false(contract.contains("Rabbita"))
}

///|
test "mooncode core owns model planner evidence contract" {
  assert_eq(
    model_planner_evidence_contract_kind(),
    "mooncode-model-planner-evidence-contract",
  )
  assert_eq(
    model_planner_evidence_report_kind(),
    "mooncode-model-planner-evidence-report",
  )
  assert_eq(model_planner_command_actions().length(), 3)
  assert_true(model_planner_command_actions().contains("prompt"))
  assert_true(model_planner_command_actions().contains("steer"))
  assert_true(model_planner_command_actions().contains("package"))
  assert_false(model_planner_command_action_is_supported("run_tests"))
  assert_true(model_planner_command_event_kinds().contains("command.package"))
  assert_true(
    model_planner_planner_event_kinds().contains("runtime.planner_selected"),
  )
  assert_true(
    model_planner_terminal_event_kinds().contains("runtime_unavailable"),
  )
  assert_true(model_planner_status_is_running("service-started"))
  assert_true(model_planner_status_is_running("running"))
  assert_false(model_planner_status_is_running("pending"))
  assert_true(model_planner_status_is_contract_failure("contract-failed"))
  assert_eq(
    model_planner_missing_evidence_reason(),
    "missing-model-planner-evidence-after-turn-start",
  )
  let payload = model_planner_evidence_contract_json().stringify()
  assert_true(
    payload.contains("\"kind\":\"mooncode-model-planner-evidence-contract\""),
  )
  assert_true(
    payload.contains("\"contract_id\":\"mooncode-model-planner-evidence.v1\""),
  )
  assert_true(payload.contains("\"model_planned_actions\""))
  assert_true(payload.contains("\"runtime.planner_started\""))
  assert_true(payload.contains("\"model-tool-calls\""))
  assert_true(payload.contains("\"command_action_contract_id\""))
  assert_true(payload.contains("\"event_name_contract_id\""))
  assert_true(payload.contains("\"runtime_tool_contract_id\""))
}

///|
test "mooncode core owns runtime control contract" {
  assert_eq(
    conversation_ownership_contract_kind(),
    "mooncode-conversation-ownership-contract",
  )
  let ownership = conversation_ownership_contract_json().stringify()
  assert_true(
    ownership.contains("\"contract_id\":\"mooncode-conversation-ownership.v1\""),
  )
  assert_true(ownership.contains("\"conversation_contract_id\""))
  assert_true(
    ownership.contains("Unscoped runtime/progress/assistant/failure events"),
  )
  assert_false(ownership.contains("internal/mooncode"))
  assert_false(ownership.contains("internal/moonwiki"))
  assert_false(ownership.contains("Rabbita"))
  assert_eq(
    runtime_control_contract_kind(),
    "mooncode-runtime-control-contract",
  )
  assert_eq(runtime_control_state_kind(), "mooncode-runtime-control-state")
  assert_eq(
    runtime_control_scheduler_boundary_unit(),
    "native-runtime-scheduler-boundary",
  )
  assert_true(runtime_control_active_statuses().contains("running"))
  assert_true(runtime_control_terminal_statuses().contains("completed"))
  assert_true(
    runtime_control_blocked_statuses().contains("blocked-tool-authorization"),
  )
  assert_true(runtime_control_effects().contains("active-turn"))
  assert_true(runtime_control_effects().contains("already-completed"))
  assert_true(runtime_control_effects().contains("failed"))
  assert_true(runtime_control_target_states().contains("recorded"))
  assert_true(runtime_control_action_starts_turn("run_tests"))
  assert_false(runtime_control_action_starts_turn("cancel"))
  assert_true(runtime_control_status_is_pending("pending"))
  assert_true(runtime_control_status_is_terminal("failed"))
  assert_true(runtime_control_effect_is_terminal("already-completed"))
  assert_true(
    runtime_control_settlement_required(
      command_steer(),
      runtime_control_effect_queue_steer(),
    ),
  )
  assert_false(
    runtime_control_settlement_required(
      command_steer(),
      runtime_control_effect_failed(),
    ),
  )
  assert_true(
    runtime_control_settlement_events(
      command_steer(),
      runtime_control_effect_defer_steer(),
    ).contains(runtime_event_steer_deferred()),
  )
  assert_true(
    runtime_control_settlement_events(
      command_cancel(),
      runtime_control_effect_drop_cancel(),
    ).contains(runtime_event_cancel_dropped()),
  )
  let payload = runtime_control_contract_json().stringify()
  assert_true(
    payload.contains("\"kind\":\"mooncode-runtime-control-contract\""),
  )
  assert_true(
    payload.contains("\"contract_id\":\"mooncode-runtime-control.v1\""),
  )
  assert_true(payload.contains("\"command_action_contract_id\""))
  assert_true(payload.contains("\"event_name_contract_id\""))
  assert_true(payload.contains("\"conversation_ownership_contract_id\""))
  assert_true(payload.contains("\"protocol_effects\""))
  assert_true(payload.contains("\"active-turn\""))
  assert_true(payload.contains("\"already-completed\""))
  assert_true(payload.contains("\"settlement_boundary\""))
  assert_true(payload.contains("\"runtime_aborted\""))
  assert_true(payload.contains("\"turn_ownership\""))
  assert_false(payload.contains("internal/mooncode"))
  assert_false(payload.contains("internal/moonwiki"))
  assert_false(payload.contains("Rabbita"))
}

///|
test "mooncode core owns package review model flow contract" {
  assert_eq(
    package_review_flow_contract_kind(),
    "mooncode-package-review-model-flow-contract",
  )
  assert_eq(
    package_review_flow_report_kind(),
    "mooncode-package-review-model-flow-report",
  )
  assert_true(package_review_flow_terminal_statuses().contains("accepted"))
  assert_true(package_review_flow_terminal_statuses().contains("rejected"))
  assert_true(package_review_flow_terminal_statuses().contains("failed"))
  assert_true(package_review_flow_status_is_terminal("accepted"))
  assert_false(package_review_flow_status_is_terminal("running"))
  assert_eq(
    package_review_flow_reason_missing_command_owner(),
    "missing-command-owner",
  )
  assert_eq(
    package_review_flow_reason_evidence_without_package_command(),
    "evidence-without-package-command",
  )
  assert_true(package_review_flow_command_kinds().contains("command.package"))
  assert_true(package_review_flow_manifest_kinds().contains("package.manifest"))
  assert_true(
    package_review_flow_diff_review_kinds().contains("patch_set.manifest"),
  )
  assert_true(
    package_review_flow_readiness_kinds().contains("package_verified"),
  )
  assert_true(
    package_review_flow_failure_kinds().contains("runtime.planner_failed"),
  )
  assert_true(
    package_review_flow_event_is_package_command({ "kind": "command.package" }),
  )
  assert_true(
    package_review_flow_event_is_package_command({
      "kind": "command",
      "action": "package",
    }),
  )
  assert_true(
    package_review_flow_event_is_package_manifest({
      "kind": "mooncode-package-index",
    }),
  )
  assert_true(
    package_review_flow_event_is_diff_review({ "kind": "file_change" }),
  )
  assert_true(
    package_review_flow_event_is_diff_review({
      "lane": "diff",
      "kind": "custom",
    }),
  )
  assert_true(package_review_flow_event_is_accept({ "kind": "receipt.accept" }))
  assert_true(package_review_flow_event_is_reject({ "kind": "receipt.reject" }))
  assert_true(
    package_review_flow_event_is_test_result({ "kind": "test_result" }),
  )
  assert_true(
    package_review_flow_event_is_package_readiness({
      "kind": "package_verified",
    }),
  )
  assert_true(
    package_review_flow_event_is_package_verified({
      "kind": "runtime.package_verified",
    }),
  )
  assert_true(
    package_review_flow_event_is_package_built({
      "kind": "runtime.package_built",
    }),
  )
  assert_true(
    package_review_flow_event_is_assistant_summary({ "kind": "assistant" }),
  )
  assert_true(
    package_review_flow_event_is_assistant_summary({
      "kind": "finish",
      "lane": "review",
    }),
  )
  assert_true(package_review_flow_event_is_failure({ "kind": "command_error" }))
  assert_true(
    package_review_flow_event_is_failure({
      "kind": "test_result",
      "exit_code": 1,
    }),
  )
  assert_false(
    package_review_flow_event_is_failure({
      "kind": "test_result",
      "exit_code": 0,
    }),
  )
  assert_true(
    package_review_flow_event_is_evidence({ "kind": "package_verified" }),
  )
  let payload = package_review_flow_contract_json().stringify()
  assert_true(
    payload.contains("\"kind\":\"mooncode-package-review-model-flow-contract\""),
  )
  assert_true(
    payload.contains(
      "\"contract_id\":\"mooncode-package-review-model-flow.v1\"",
    ),
  )
  assert_true(payload.contains("\"command_action_contract_id\""))
  assert_true(payload.contains("\"event_name_contract_id\""))
  assert_true(payload.contains("\"accepted_sequence\""))
  assert_true(payload.contains("\"receipt.accept\""))
  assert_true(payload.contains("\"stale_reasons\""))
  assert_true(payload.contains("\"missing_steps\""))
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
test "mooncode core owns runtime tool contract" {
  assert_eq(runtime_tool_contract_kind(), "mooncode-tool-contract")
  assert_eq(runtime_tool_call_contract_kind(), "mooncode-tool-call-contract")
  assert_eq(runtime_tool_read(), "read")
  assert_eq(runtime_tool_apply_patch(), "apply_patch")
  assert_eq(runtime_tool_web_search(), "web_search")
  assert_eq(runtime_tool_names().length(), 16)
  assert_eq(runtime_tool_capability_names().length(), 17)
  assert_true(runtime_tool_is_supported("moon_cmd"))
  assert_false(runtime_tool_is_supported("delete_world"))
  assert_true(runtime_tool_requires_authorization_snapshot("moon_check"))
  assert_false(runtime_tool_requires_authorization_snapshot("read"))
  let aliases = runtime_tool_alias_rows().map(row => {
    runtime_tool_test_string(row, "alias") +
    "->" +
    runtime_tool_test_string(row, "canonical")
  })
  assert_true(aliases.contains("Bash->shell"))
  assert_true(aliases.contains("FileRead->read"))
  assert_true(aliases.contains("TodoWrite->todo_write"))
  assert_true(aliases.contains("WebSearch->web_search"))
  let mappings = runtime_tool_moonclaw_mapping_rows().map(row => {
    runtime_tool_test_string(row, "source") +
    "->" +
    runtime_tool_test_string(row, "mooncode_tool")
  })
  assert_true(mappings.contains("execute_command->shell"))
  assert_true(mappings.contains("replace_in_file->edit"))
  assert_true(mappings.contains("WebSearch->web_search"))
  let call_contract = runtime_tool_call_contract_json().stringify()
  assert_true(
    call_contract.contains("\"kind\":\"mooncode-tool-call-contract\""),
  )
  assert_true(call_contract.contains("\"supported_tools\""))
  assert_true(call_contract.contains("\"accepted_aliases\""))
  let tool_contract = runtime_tool_contract_json()
  let tool_payload = tool_contract.stringify()
  assert_true(tool_payload.contains("\"kind\":\"mooncode-tool-contract\""))
  assert_true(
    tool_payload.contains("\"contract_id\":\"mooncode-runtime-tools.v1\""),
  )
  assert_true(tool_payload.contains("\"supported_tools\""))
  assert_true(tool_payload.contains("\"accepted_aliases\""))
  assert_true(tool_payload.contains("\"moonclaw_tool_mappings\""))
  assert_true(tool_payload.contains("\"package_app_tool\""))
  assert_true(tool_payload.contains("\"path_rule\""))
  let ids = runtime_tool_contract_tool_ids(tool_contract)
  assert_eq(ids.length(), runtime_tool_names().length())
  for tool in runtime_tool_names() {
    assert_true(ids.contains(tool))
  }
  let specs = runtime_tool_capability_specs()
  assert_eq(specs.length(), runtime_tool_capability_names().length())
  let spec_ids = specs.map(spec => runtime_tool_test_string(spec, "id"))
  for tool in runtime_tool_capability_names() {
    assert_true(spec_ids.contains(tool))
  }
  assert_false(tool_payload.contains("internal/mooncode"))
  assert_false(tool_payload.contains("internal/moonwiki"))
  assert_false(tool_payload.contains("Rabbita"))
}

///|
fn runtime_tool_test_string(json : Json, key : String) -> String {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
fn native_event_projection_test_int(json : Json, key : String) -> Int {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(Number(value, ..)) => value.to_int()
        _ => 0
      }
    _ => 0
  }
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
