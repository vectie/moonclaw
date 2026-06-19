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
  assert_eq(native_capability_surface_fingerprint().length(), 64)
  let surface = native_capability_surface_json().stringify()
  assert_true(
    surface.contains("\"kind\":\"mooncode-native-capability-surface\""),
  )
  assert_true(surface.contains("\"capability_surface_fingerprint\""))
  assert_true(surface.contains("\"runtime_loop_options\""))
  assert_true(surface.contains("\"live_wait_ms\""))
  assert_true(surface.contains("\"stream_options\""))
  assert_true(surface.contains("\"wait_ms\""))
  assert_true(surface.contains("\"poll_ms\""))
}

///|
test "mooncode core names standalone package boundaries" {
  let payload = standalone_boundary_json().stringify()
  assert_true(payload.contains("\"kind\":\"mooncode-standalone-boundary\""))
  assert_true(payload.contains("\"protocol\":\"mooncode.v1\""))
  assert_true(payload.contains("\"core_package\":\"mooncode/core\""))
  assert_true(
    payload.contains(
      "\"moondesk_projection_package\":\"vectie/moondesk/internal/mooncode\"",
    ),
  )
  assert_true(
    payload.contains(
      "\"moonwiki_host_package\":\"vectie/moondesk/internal/moonwiki\"",
    ),
  )
  assert_true(payload.contains("\"runtime_package\":\"mooncode\""))
  assert_true(payload.contains("\"id\":\"mooncode-core\""))
  assert_true(payload.contains("\"id\":\"moondesk-projection\""))
  assert_true(payload.contains("\"id\":\"moonwiki-host\""))
  assert_true(payload.contains("\"id\":\"runtime-engine\""))
  assert_true(
    payload.contains("mooncode/core must not import internal/mooncode"),
  )
}
