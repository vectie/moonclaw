///|
test "MoonCode plans and reviews without claiming execution authority" {
  guard @moonclaw.mooncode_moonflow_adapter_capability_json()
    is Object(capability) else {
    fail("expected MoonCode adapter capability")
  }
  assert_true(capability["product_id"] == Json::string("mooncode"))
  assert_true(capability["direct_shell_forbidden"] == Json::boolean(true))
  guard capability["authority_classes"] is Array(authorities) else {
    fail("expected MoonCode authorities")
  }
  assert_false(authorities.contains(Json::string("sandbox-execution")))
  assert_false(authorities.contains(Json::string("external-effect")))
}

///|
test "MoonClaw exposes durable control without product judgment" {
  guard @moonclaw.moonclaw_moonflow_adapter_capability_json()
    is Object(capability) else {
    fail("expected MoonClaw adapter capability")
  }
  assert_true(capability["protocol"] == Json::string("moonflow.adapter.v1"))
  assert_true(capability["supports_cancel"] == Json::boolean(true))
  assert_true(capability["supports_reconcile"] == Json::boolean(true))
  assert_true(
    capability["completion_judgment_forbidden"] == Json::boolean(true),
  )
  guard capability["operations"] is Array(operations) else {
    fail("expected MoonClaw operations")
  }
  assert_true(operations.contains(Json::string("cancel-job")))
  assert_true(operations.contains(Json::string("reconcile-job")))
  guard capability["authority_classes"] is Array(authorities) else {
    fail("expected MoonClaw authorities")
  }
  assert_true(authorities.contains(Json::string("sandbox-execution")))
  assert_false(authorities.contains(Json::string("external-effect")))
  assert_false(authorities.contains(Json::string("physical-effect")))
}
