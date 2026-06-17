///|
test "mooncode core protocol surface is stable" {
  assert_eq(protocol_version(), "mooncode.v1")
  assert_eq(
    native_capability_contract_id(),
    "mooncode-native-capability-surface.v1",
  )
  assert_true(
    native_capability_required_endpoints().contains("/v1/mooncode/capabilities"),
  )
  assert_true(native_capability_required_tools().contains("apply_patch"))
  assert_eq(native_capability_surface_fingerprint().length(), 64)
  let surface = native_capability_surface_json().stringify()
  assert_true(
    surface.contains("\"kind\":\"mooncode-native-capability-surface\""),
  )
  assert_true(surface.contains("\"capability_surface_fingerprint\""))
}
