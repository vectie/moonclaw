///|
test "mooncode core protocol surface is stable" {
  assert_eq(protocol_version(), "mooncode.v1")
  assert_eq(
    native_capability_contract_id(),
    "mooncode-native-capability-surface.v1",
  )
  assert_true(
    native_capability_required_endpoints().contains("/v1/code/capabilities"),
  )
  assert_true(
    native_capability_required_endpoints().contains(
      "/v1/code/sessions/<id>/runtime-service?book_root=<path>",
    ),
  )
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
