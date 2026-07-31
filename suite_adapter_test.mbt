///|
test "legacy MoonCode advertisement resolves to one MoonClaw role" {
  guard @moonclaw.mooncode_moonflow_adapter_capability_json()
    is Object(capability) else {
    fail("expected MoonCode adapter capability")
  }
  assert_true(capability["product_id"] == Json::string("moonclaw"))
  assert_true(capability["role"] == Json::string("mooncode"))
  assert_true(
    capability["operation_ref"] ==
    Json::string("moonclaw/agent.goal.execute@0.1.5"),
  )
  assert_true(capability["default_model"] == Json::string("gpt-5.6-sol"))
  assert_true(capability["separate_runtime"] == Json::boolean(false))
  assert_true(capability["human_acceptance_implied"] == Json::boolean(false))
}

///|
test "MoonClaw publishes one canonical agent-goal declaration" {
  guard @moonclaw.moonclaw_agent_goal_adapter_declaration_json()
    is Object(declaration) &&
    declaration["operations"] is Array([Object(operation)]) else {
    fail("expected canonical MoonClaw agent-goal declaration")
  }
  assert_true(
    declaration["contract_id"] ==
    Json::string("moonflow.adapter-declaration.v1"),
  )
  assert_true(declaration["pack_version"] == Json::string("0.1.5"))
  assert_true(operation["operation_id"] == Json::string("agent.goal.execute"))
  assert_true(operation["claim_ceiling"] == Json::string("digital-artifact"))
  assert_true(operation["supports_cancel"] == Json::boolean(true))
  assert_true(operation["supports_reconcile"] == Json::boolean(true))
}

///|
test "MoonClaw health attestation is evidence-bound and expiring" {
  guard @moonclaw.moonclaw_agent_goal_health_attestation_json(
      checked_at="2026-07-31T00:00:00Z",
      valid_until="2026-07-31T00:05:00Z",
      evidence_ref="health/moonclaw-agent-goal-v1.json",
      evidence_digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    )
    is Object(health) else {
    fail("expected MoonClaw health attestation")
  }
  assert_true(
    health["contract_id"] == Json::string("moonflow.adapter-health.v1"),
  )
  assert_true(health["valid_until"] == Json::string("2026-07-31T00:05:00Z"))
  assert_true(
    health["evidence_ref"] == Json::string("health/moonclaw-agent-goal-v1.json"),
  )
}

///|
test "MoonClaw exposes durable control without product judgment" {
  guard @moonclaw.moonclaw_moonflow_adapter_capability_json()
    is Object(capability) else {
    fail("expected MoonClaw adapter capability")
  }
  assert_true(
    capability["contract_id"] ==
    Json::string("moonclaw.pack-capability-host.v1"),
  )
  assert_true(capability["protocol"] == Json::string("moonflow.adapter.v2"))
  assert_true(capability["supports_reconcile"] == Json::boolean(true))
  assert_true(
    capability["completion_judgment_forbidden"] == Json::boolean(true),
  )
  guard capability["operations"] is Array(operations) else {
    fail("expected MoonClaw operations")
  }
  assert_true(operations.is_empty())
  assert_true(
    capability["operations_source"] ==
    Json::string("compiled-installed-pack-catalog"),
  )
  assert_true(
    capability["manifest_derived_operations_only"] == Json::boolean(true),
  )
  assert_true(
    capability["unknown_effect_reexecution_forbidden"] == Json::boolean(true),
  )
  guard capability["authority_classes"] is Array(authorities) else {
    fail("expected MoonClaw authorities")
  }
  assert_true(authorities.contains(Json::string("sandbox-execution")))
  assert_true(authorities.contains(Json::string("external-effect")))
  assert_true(authorities.contains(Json::string("physical-effect")))
  assert_true(capability["domain_policy_forbidden"] == Json::boolean(true))
}
