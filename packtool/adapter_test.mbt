///|
fn projection() -> @host.HostActivationProjection {
  {
    contract: "moonsuite.pack-host-activation.v1",
    pack_id: "fixture",
    product_id: "fixture",
    version: "1.0.0",
    required_runtime_extensions: [],
    book_templates: [],
    tools: [
      @pack.tool_declaration(
        "fixture.observe",
        "fixture",
        "request",
        "response",
        Observe,
      ),
    ],
    schedules: [],
    app_entrypoints: [],
    provider_ports: [],
    policies: [],
  }
}

///|
test "projection binds tools without product-specific routing" {
  let projected = bindings(projection())
  assert_eq(projected.length(), 1)
  guard resolve(projected, "fixture.observe") is Some(binding) else {
    fail("tool should resolve")
  }
  assert_eq(binding.pack_id, "fixture")
  assert_true(binding.authority == Observe)
}

///|
test "external effects require authority review evidence and budget" {
  let binding : ToolBinding = {
    pack_id: "fixture",
    product_id: "fixture",
    tool_id: "fixture.publish",
    input_schema_id: "request",
    output_schema_id: "response",
    authority: ExternalEffect,
    idempotent: true,
    evidence_outputs: ["records/publications"],
    review_required: true,
  }
  let request : InvocationRequest = {
    tool_id: "fixture.publish",
    input_schema_id: "request",
    output_schema_id: "response",
    evidence_path: "records/publications/run-1.json",
    attempt: 1,
    estimated_cost_micros: 100,
  }
  let denied = authorize(binding, request, {
    granted_authorities: [],
    reviewed_tool_ids: [],
    max_attempts: 1,
    timeout_ms: 30000,
    remaining_budget_micros: 50,
  })
  assert_false(denied.allowed)
  assert_eq(denied.issues.length(), 3)
  let allowed = authorize(binding, request, {
    granted_authorities: [ExternalEffect],
    reviewed_tool_ids: ["fixture.publish"],
    max_attempts: 1,
    timeout_ms: 30000,
    remaining_budget_micros: 100,
  })
  assert_true(allowed.allowed)
}
