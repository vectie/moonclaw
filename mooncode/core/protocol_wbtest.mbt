///|
test "mooncode core exposes the MoonLib conversation v3 contract" {
  let payload = conversation_contract_json().stringify()
  assert_true(payload.contains("\"kind\":\"moonsuite-conversation-contract\""))
  assert_true(payload.contains("\"contract_id\":\"moonsuite-conversation.v3\""))
  assert_true(payload.contains("\"product_id\":\"mooncode\""))
  assert_true(
    payload.contains("\"conversation_kind\":\"mooncode-conversation\""),
  )
  assert_true(payload.contains("\"turn_kind\":\"mooncode-conversation-turn\""))
  assert_true(payload.contains("\"client_turn_id\""))
  assert_true(payload.contains("\"command_id\""))
  assert_true(
    payload.contains("\"turn_order\":[\"user\",\"work\",\"assistant\"]"),
  )
  assert_true(payload.contains("\"contract_owner\":\"mooncode\""))
  assert_true(payload.contains("\"base_contract_owner\":\"moonlib\""))
  assert_true(
    payload.contains(
      "\"sequence_encoding\":\"canonical nonnegative decimal JSON string\"",
    ),
  )
  assert_true(
    payload.contains(
      "\"journal_write_contract_id\":\"moonsuite-conversation-journal.v2\"",
    ),
  )
  assert_false(payload.contains("internal/mooncode"))
  assert_false(payload.contains("internal/moonwiki"))
  assert_false(payload.contains("Rabbita"))
}

///|
test "mooncode exact conversation watch preserves arbitrary cursors" {
  let response = conversation_watch_response_exact(
    session_id="session",
    revision="92233720368547758081234567890",
    next_sequence="92233720368547758081234567891",
    changed=true,
    heartbeat=false,
    terminal=false,
    retry_after_ms=25,
    snapshot={},
  ).stringify()
  assert_true(
    response.contains("\"contract_id\":\"moonsuite-conversation-watch.v2\""),
  )
  assert_true(
    response.contains("\"revision\":\"92233720368547758081234567890\""),
  )
  assert_true(
    conversation_watch_exact_contract_json()
    .stringify()
    .contains("canonical nonnegative decimal JSON string"),
  )
}

///|
test "mooncode exact cursor builders reject noncanonical values" {
  assert_true(exact_cursor_is_canonical_nonnegative_decimal("0"))
  assert_true(
    exact_cursor_is_canonical_nonnegative_decimal(
      "922337203685477580812345678901234567890",
    ),
  )
  for bad in ["", "00", "01", "-1", "+1", "1.0", "1e3", "a1"] {
    assert_false(exact_cursor_is_canonical_nonnegative_decimal(bad))
    let endpoint_rejected = try {
      ignore(native_stream_endpoint_exact("session", "/book", "jsonl", bad))
      false
    } catch {
      _ => true
    }
    assert_true(endpoint_rejected)
    let watch_rejected = try {
      ignore(
        conversation_watch_response_exact(
          session_id="session",
          revision=bad,
          next_sequence="0",
          changed=false,
          heartbeat=true,
          terminal=false,
          retry_after_ms=25,
          snapshot={},
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(watch_rejected)
  }
  assert_true(
    native_stream_endpoint("session", "/book", "jsonl", -1).contains("since=-1"),
  )
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
  assert_true(
    ownership.contains("MoonDesk chat renders only mooncode_conversation turns"),
  )
  assert_true(ownership.contains("must not rebuild visible chat rows"))
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
    payload.contains("\"contract_id\":\"mooncode-runtime-control.v2\""),
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
test "mooncode core owns runtime consumer contract" {
  assert_eq(
    runtime_consumer_contract_kind(),
    "mooncode-runtime-consumer-contract",
  )
  assert_eq(runtime_claim_state_kind(), "mooncode-runtime-claim-state")
  assert_eq(runtime_claim_response_kind(), "mooncode-runtime-claim")
  assert_eq(runtime_replay_state_kind(), "mooncode-runtime-replay")
  assert_eq(runtime_claim_mode(), "mooncode-runtime-claim")
  assert_eq(runtime_replay_mode(), "mooncode-runtime-replay")
  assert_true(
    runtime_receipt_delivered_statuses().contains("runtime-acknowledged"),
  )
  assert_true(
    runtime_replay_ack_allowed_statuses().contains("runtime-completed"),
  )
  assert_eq(
    runtime_replay_ack_status("runtime-completed", ok=false),
    "runtime-completed",
  )
  assert_eq(
    runtime_replay_ack_status("unknown", ok=true),
    "runtime-acknowledged",
  )
  assert_eq(runtime_replay_ack_status("unknown", ok=false), "failed")
  assert_true(runtime_replay_ack_detail("proof-missing").contains("proof"))
  assert_eq(
    runtime_claim_base_status(
      true,
      runtime_receipt_status_missing(),
      false,
      false,
    ),
    "claimable",
  )
  assert_eq(
    runtime_claim_base_status(
      true,
      runtime_receipt_status_claimed(),
      false,
      false,
    ),
    "claimed",
  )
  assert_eq(
    runtime_claim_status_with_order_blocker("claimable", "cmd-prior"),
    "blocked-by-prior-command",
  )
  assert_eq(
    runtime_replay_base_status(
      true,
      runtime_receipt_status_claimed(),
      true,
      false,
    ),
    "expired-claim-pending-retry",
  )
  assert_eq(
    runtime_replay_status_with_order_blocker("pending", "cmd-prior"),
    "blocked-by-prior-command",
  )
  assert_true(runtime_replay_status_blocks_following("claimed"))
  assert_false(runtime_replay_status_blocks_following("failed-pending-retry"))
  assert_true(runtime_replay_ack_order_statuses().contains("consumer-mismatch"))
  assert_eq(
    runtime_claim_endpoint("session one"),
    "/api/mooncode/sessions/session%20one/runtime-claim",
  )
  assert_eq(
    runtime_replay_endpoint("session one"),
    "/api/mooncode/sessions/session%20one/runtime-replay",
  )
  assert_true(
    runtime_claim_ordering_rule().contains("session-journal sequence"),
  )
  assert_true(runtime_claim_lease_policy().contains("lease_expires_at"))
  assert_true(runtime_replay_duplicate_guard().contains("runtime-completed"))
  let payload = runtime_consumer_contract_json("session one").stringify()
  assert_true(
    payload.contains("\"kind\":\"mooncode-runtime-consumer-contract\""),
  )
  assert_true(
    payload.contains("\"contract_id\":\"mooncode-runtime-consumer.v2\""),
  )
  assert_true(payload.contains("\"runtime-claimed\""))
  assert_true(payload.contains("\"blocked-by-prior-command\""))
  assert_true(
    payload.contains("\"/api/mooncode/sessions/session%20one/runtime-claim\""),
  )
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
  assert_eq(runtime_tool_read_skill(), "read_skill")
  assert_eq(runtime_tool_apply_patch(), "apply_patch")
  assert_eq(runtime_tool_web_search(), "web_search")
  let runtime_tools = runtime_tool_names()
  assert_true(runtime_tools.contains("spawn_workers"))
  assert_true(runtime_tools.contains("wait_workers"))
  assert_eq(
    runtime_tool_capability_names().length(),
    runtime_tools.length() + 1,
  )
  assert_true(runtime_tool_is_supported("moon_cmd"))
  assert_false(runtime_tool_is_supported("delete_world"))
  assert_true(runtime_tool_requires_authorization_snapshot("moon_check"))
  assert_true(runtime_tool_requires_authorization_snapshot("moon_cmd"))
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
  for row in runtime_tool_alias_rows() {
    let alias_name = runtime_tool_test_string(row, "alias")
    let canonical = runtime_tool_test_string(row, "canonical")
    assert_eq(runtime_tool_canonical_name(alias_name), canonical)
    assert_true(runtime_tool_is_supported(alias_name))
  }
  let mappings = runtime_tool_moonclaw_mapping_rows().map(row => {
    runtime_tool_test_string(row, "source") +
    "->" +
    runtime_tool_test_string(row, "mooncode_tool")
  })
  assert_true(mappings.contains("execute_command->shell"))
  assert_true(mappings.contains("replace_in_file->edit"))
  assert_true(mappings.contains("WebSearch->web_search"))
  for row in runtime_tool_moonclaw_mapping_rows() {
    assert_eq(
      runtime_tool_from_moonclaw_tool(runtime_tool_test_string(row, "source")),
      runtime_tool_test_string(row, "mooncode_tool"),
    )
  }
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
fn native_event_projection_test_int(json : Json, key : String) -> Int32 {
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
test "mooncode core names standalone package boundaries" {
  let payload = standalone_boundary_json().stringify()
  assert_true(payload.contains("\"kind\":\"mooncode-standalone-boundary\""))
  assert_true(payload.contains("\"protocol\":\"mooncode.v1\""))
  assert_true(payload.contains("\"core_package\":\"mooncode/core\""))
  assert_true(
    payload.contains("\"projection_component\":\"mooncode.projection\""),
  )
  assert_true(payload.contains("\"host_component\":\"book.host\""))
  assert_true(
    payload.contains("\"runtime_component\":\"moonclaw.standalone-runtime\""),
  )
  assert_true(
    payload.contains("\"runtime_substrate\":\"moonclaw.shared-runtime\""),
  )
  assert_true(payload.contains("\"id\":\"mooncode-coding-lane\""))
  assert_true(payload.contains("\"id\":\"book-workflow-lane\""))
  assert_true(payload.contains("\"id\":\"moonclaw-task-lane\""))
  assert_true(payload.contains("\"id\":\"mooncode-core\""))
  assert_true(payload.contains("\"id\":\"mooncode-projection\""))
  assert_true(payload.contains("\"id\":\"book-host\""))
  assert_true(payload.contains("\"id\":\"moonclaw-standalone-runtime\""))
  assert_true(payload.contains("shared runtime substrate"))
  assert_true(
    payload.contains(
      "MoonClaw must remain usable as a standalone agent runtime",
    ),
  )
  assert_true(
    payload.contains(
      "MoonCode, book workflows, and generic tasks share MoonClaw",
    ),
  )
  assert_true(
    payload.contains("mooncode/core must contain only stable protocol"),
  )
  assert_false(payload.contains("vectie/moondesk"))
  assert_false(payload.contains("internal/mooncode"))
  assert_false(payload.contains("internal/moonwiki"))
  assert_false(payload.contains("../moonclaw"))
}
