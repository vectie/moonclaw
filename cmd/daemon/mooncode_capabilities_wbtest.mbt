///|
test "mooncode capabilities expose native daemon endpoints" {
  assert_true(
    mooncode_capability_endpoints().contains(
      "/v1/code/sessions/<id>/runtime-turn?book_root=<path>",
    ),
  )
  assert_true(
    mooncode_native_capability_required_endpoints().contains(
      "/v1/code/sessions/<id>/package-result?book_root=<path>",
    ),
  )
  assert_true(
    mooncode_native_capability_required_endpoints().contains(
      "/v1/code/sessions/<id>/runtime-service?book_root=<path>",
    ),
  )
  assert_true(
    mooncode_native_capability_required_endpoints().contains(
      "/v1/code/sessions?book_root=<path>&format=listing",
    ),
  )
  assert_true(
    mooncode_native_capability_required_endpoints().contains(
      "/v1/code/sessions/<id>/lifecycle",
    ),
  )
  assert_eq(mooncode_native_capability_optional_endpoints().length(), 2)
  assert_true(
    mooncode_native_capability_optional_endpoints().contains(
      "/v1/code/sessions/<id>/goal?book_root=<path>",
    ),
  )
  assert_true(
    mooncode_native_capability_optional_endpoints().contains(
      "/v1/code/sessions/<id>/goal-runtime?book_root=<path>",
    ),
  )
  assert_false(
    mooncode_native_capability_required_endpoints().contains(
      "/v1/code/sessions/<id>/goal?book_root=<path>",
    ),
  )
  assert_false(
    mooncode_native_capability_required_endpoints().contains(
      "/v1/code/sessions/<id>/goal-runtime?book_root=<path>",
    ),
  )
  assert_eq(
    mooncode_capability_endpoints().length(),
    mooncode_native_capability_endpoints().length(),
  )
  assert_true(
    mooncode_native_capability_endpoints().contains(
      "/v1/code/sessions/<id>/stream?book_root=<path>&format=jsonl|sse&since=<canonical-decimal>&wait_ms=<ms>&poll_ms=<ms>",
    ),
  )
  assert_true(
    mooncode_capability_endpoints().contains(
      "/v1/code/sessions/<id>/tool-exec?book_root=<path>",
    ),
  )
  assert_true(mooncode_capability_tools().contains("moon_ide"))
  assert_true(mooncode_capability_tools().contains("moon_cmd"))
  assert_eq(
    mooncode_capability_tools().length(),
    mooncode_native_capability_tools().length(),
  )
  assert_true(mooncode_native_capability_tools().contains("apply_patch"))
  assert_eq(
    mooncode_native_capability_contract_id(),
    "mooncode-native-capability-surface.v2",
  )
  assert_eq(
    mooncode_executable_book_lifecycle_contract_id(),
    "mooncode-executable-book-lifecycle.v2",
  )
  assert_false(
    mooncode_capabilities_payload()
    .stringify()
    .contains("mooncode-executable-book-lifecycle.v1"),
  )
  assert_eq(mooncode_native_capability_surface_fingerprint().length(), 64)
  let surface = mooncode_native_capability_surface_json().stringify()
  assert_true(
    surface.contains("\"kind\":\"mooncode-native-capability-surface\""),
  )
  assert_true(surface.contains("\"capability_surface_fingerprint\""))
  assert_true(surface.contains("\"required_endpoints\""))
  assert_true(surface.contains("\"conversation_contract\""))
  assert_true(surface.contains("\"conversation_watch_write_contract\""))
  assert_true(surface.contains("\"conversation_watch_read_contract_ids\""))
  assert_true(
    surface.contains(
      "\"journal_write_contract_id\":\"moonsuite-conversation-journal.v2\"",
    ),
  )
  assert_true(surface.contains("\"journal_read_contract_ids\""))
  assert_true(surface.contains("\"session_contracts\""))
  assert_true(surface.contains("\"snapshot\":\"mooncode-session-snapshot.v2\""))
  assert_true(surface.contains("\"record\":\"mooncode-session-record.v2\""))
  assert_true(surface.contains("\"listing\":\"mooncode-session-listing.v2\""))
  let payload_json = mooncode_capabilities_payload()
  let payload_surface = mooncode_json_object_field_or_empty(
    payload_json, "capability_surface",
  )
  assert_eq(
    mooncode_json_string(payload_surface, "capability_contract_id", default=""),
    mooncode_native_capability_contract_id(),
  )
  assert_eq(
    mooncode_json_string(
      payload_surface,
      "capability_surface_fingerprint",
      default="",
    ),
    mooncode_native_capability_surface_fingerprint(),
  )
  assert_eq(
    mooncode_json_string(
      payload_json,
      "executable_book_lifecycle_contract_id",
      default="",
    ),
    mooncode_executable_book_lifecycle_contract_id(),
  )
  let lifecycle_contract = mooncode_json_object_field_or_empty(
    payload_json, "executable_book_lifecycle_contract",
  )
  assert_eq(
    mooncode_json_string(lifecycle_contract, "runtime_owner", default=""),
    "moonclaw",
  )
  assert_eq(
    mooncode_json_string(lifecycle_contract, "artifact_owner", default=""),
    "moonbook",
  )
  assert_eq(
    mooncode_json_array_items(lifecycle_contract, "required_steps").length(),
    mooncode_executable_book_lifecycle_steps().length(),
  )
  assert_eq(
    mooncode_json_string(
      payload_json,
      "capability_surface_fingerprint",
      default="",
    ),
    mooncode_native_capability_surface_fingerprint(),
  )
  assert_eq(
    mooncode_json_array_items(payload_json, "endpoints").length(),
    mooncode_json_array_items(payload_surface, "required_endpoints").length() +
    mooncode_native_capability_optional_endpoints().length(),
  )
  assert_eq(
    mooncode_json_array_items(payload_json, "tools").length(),
    mooncode_json_array_items(payload_surface, "required_tools").length(),
  )
  let payload = payload_json.stringify()
  assert_true(payload.contains("/v1/code/capabilities"))
  assert_true(payload.contains("/v1/code/sessions?book_root=<path>"))
  assert_true(payload.contains("/v1/code/sessions/<id>?book_root=<path>"))
  assert_true(payload.contains("/v1/code/sessions/<id>/commands"))
  assert_true(
    payload.contains("/v1/code/sessions/<id>/package-result?book_root=<path>"),
  )
  assert_true(
    payload.contains("/v1/code/sessions/<id>/eval-report?book_root=<path>"),
  )
  assert_true(
    payload.contains("/v1/code/sessions/<id>/runtime-claim?book_root=<path>"),
  )
  assert_true(
    payload.contains("/v1/code/sessions/<id>/runtime-events?book_root=<path>"),
  )
  assert_true(
    payload.contains("/v1/code/sessions/<id>/runtime-service?book_root=<path>"),
  )
  assert_true(
    payload.contains("/v1/code/sessions/<id>/tool-exec?book_root=<path>"),
  )
  assert_true(
    payload.contains(
      ".moonsuite/products/moonclaw/mooncode/sessions/<session-id>",
    ),
  )
  assert_true(
    payload.contains(
      "MoonClaw product home derived from the selected book root",
    ),
  )
  assert_true(payload.contains("journal.jsonl"))
  assert_false(payload.contains("runtime-receipts.jsonl"))
  assert_true(
    payload.contains(
      "\"capability_contract_id\":\"mooncode-native-capability-surface.v2\"",
    ),
  )
  assert_true(payload.contains("\"capability_surface\""))
  assert_true(payload.contains("\"executable_book_lifecycle_contract\""))
  assert_true(payload.contains("mooncode-executable-book-lifecycle.v2"))
  assert_true(payload.contains("\"native_runtime_ready\":true"))
  assert_true(
    payload.contains("\"runtime_mode\":\"moonclaw-daemon-native-mooncode\""),
  )
  assert_true(
    payload.contains("\"control_commands\":[\"prompt\",\"steer\",\"cancel\"]"),
  )
  assert_true(payload.contains("\"apply_patch\""))
  assert_true(payload.contains("\"revert_patch\""))
  assert_true(payload.contains("runtime.patch_applied"))
  assert_true(payload.contains("runtime.patch_reverted"))
  assert_true(payload.contains("hunk_control_scope"))
  assert_true(payload.contains("steer_applied"))
  assert_true(payload.contains("steer_deferred"))
  assert_true(payload.contains("\"runtime_loop_options\""))
  assert_true(payload.contains("\"runtime_service_endpoint\""))
  assert_true(payload.contains("\"runtime_service_options\""))
  assert_true(
    payload.contains("GET/POST /v1/code/sessions/<id>/runtime-service"),
  )
  assert_true(payload.contains("runtime.service_started"))
  assert_true(payload.contains("\"live_wait_ms\""))
  assert_true(payload.contains("\"stream_options\""))
  assert_true(payload.contains("\"wait_ms\""))
  assert_true(payload.contains("\"poll_ms\""))
  assert_true(payload.contains("receipt.accept"))
  assert_true(payload.contains("\"review_receipts\""))
  assert_true(payload.contains("\"default_command_mode\""))
  assert_true(payload.contains("without spawning or messaging"))
  assert_true(payload.contains("\"prompt_planner\""))
  assert_true(
    payload.contains("planner_max_steps is a local resumable quantum"),
  )
  assert_true(payload.contains("accepted=true/completed=false/paused=true"))
  assert_true(payload.contains("\"event_lifecycle\""))
  assert_true(payload.contains("\"ContextPruned\""))
  assert_true(payload.contains("\"Pruned\""))
  assert_true(payload.contains("\"command_scoped_web_search\""))
}

///|
test "mooncode advertised endpoints are unique" {
  let endpoints = mooncode_native_capability_endpoints()
  for i, endpoint in endpoints {
    for j = i + 1; j < endpoints.length(); j = j + 1 {
      if endpoint == endpoints[j] {
        fail("duplicate endpoint: \{endpoint}")
      }
    }
  }
}
