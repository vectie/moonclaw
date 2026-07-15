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
