///|
fn capability_http_test_invocation(
  provider_calls_forbidden : Bool,
) -> @packtool.CapabilityInvocationV1 {
  {
    contract_id: "moonclaw.capability-invocation.v1",
    adapter_id: "test-adapter-v1",
    evaluated_at: "2026-07-31T01:00:00Z",
    recorded_at: "2026-07-31T01:00:01Z",
    attempt: 1,
    request: {
      request_id: "request-1",
      run_id: "run-1",
      book_id: "book-1",
      work_item_id: "work-1",
      declaration_id: "declaration-1",
      attempt_id: "attempt-1",
      idempotency_key: "run-1/work-1/attempt-1",
      product_id: "test-product",
      operation: "test-product/test.execute@1.0.0",
      requested_authority: "sandbox-execution",
      acceptance_criteria: ["result is durable"],
      input_contracts: ["test-product/request@1.0.0"],
      output_contracts: ["test-product/result@1.0.0"],
      required_claim: "execution-result",
      input_digest: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
      input_artifacts: ["inputs/request.json"],
      timeout_ms: 30000,
      created_at: "2026-07-31T00:59:59Z",
    },
    config: { "provider_calls_forbidden": provider_calls_forbidden },
    input: Json::empty_object(),
  }
}

///|
fn capability_http_test_policy(
  route : CapabilityHttpRouteV1,
  approved_provider_route_refs : Array[String],
) -> CapabilityHttpPolicyV1 {
  {
    contract_id: "moonclaw.capability-http-policy.v1",
    catalog_ref: "flow/capability-catalog.json",
    granted_authorities: ["sandbox-execution"],
    reviewed_operation_refs: [],
    max_attempts: 1,
    timeout_ms: 30000,
    remaining_budget_micros: 1000,
    approved_provider_route_refs,
    routes: [route],
  }
}

///|
test "capability HTTP boundary requires exact same-origin loopback routing" {
  inspect(
    capability_http_request_allowed(
      { "host": "127.0.0.1:18123", "origin": "http://127.0.0.1:18123" },
      18123,
      None,
    )
    is Ok(_),
    content="true",
  )
  inspect(
    capability_http_request_allowed(
      { "host": "127.0.0.1:18123", "origin": "http://127.0.0.1:4313" },
      18123,
      None,
    )
    is Err(_),
    content="true",
  )
  inspect(
    capability_http_request_allowed(
      { "host": "127.0.0.1:18123", "authorization": "Bearer exact-token" },
      18123,
      Some("exact-token"),
    )
    is Ok(_),
    content="true",
  )
  inspect(
    capability_http_request_allowed(
      { "host": "127.0.0.1:18123" },
      18123,
      Some("exact-token"),
    )
    is Err(_),
    content="true",
  )
}

///|
test "capability adapter routes are explicit loopback URLs" {
  inspect(
    capability_http_loopback_url(
      "http://127.0.0.1:4313/v1/capability/execute", false,
    ),
    content="true",
  )
  inspect(
    capability_http_loopback_url("http://localhost:8090", true),
    content="true",
  )
  for
    candidate in [
      "https://127.0.0.1:4313/v1/capability/execute", "http://10.0.0.8:4313/v1/capability/execute",
      "http://user@127.0.0.1:4313/v1/capability/execute", "http://127.0.0.1:4313/../secret",
      "http://127.0.0.1:4313/%2e%2e/secret", "http://127.0.0.1:4313/v1/capability/execute?target=elsewhere",
    ] {
    inspect(capability_http_loopback_url(candidate, false), content="false")
  }
}

///|
test "agent-goal provider route must be separately approved and permitted" {
  let route : CapabilityHttpRouteV1 = {
    route_id: "agent-goal",
    operation_ref: "test-product/test.execute@1.0.0",
    adapter_id: "test-adapter-v1",
    transport: "moonclaw.agent-goal-http.v1",
    submit_url: None,
    reconcile_url: None,
    base_url: Some("http://127.0.0.1:8090"),
    estimated_cost_micros: 10,
    provider_route_ref: Some("provider-route-1"),
  }
  try
    capability_http_executor(
      capability_http_test_policy(route, []),
      route,
      capability_http_test_invocation(false),
    )
  catch {
    error =>
      inspect(
        "\{error}".contains("provider route is not approved"),
        content="true",
      )
  } noraise {
    _ => fail("expected an unapproved provider route to be denied")
  }
  try
    capability_http_executor(
      capability_http_test_policy(route, ["provider-route-1"]),
      route,
      capability_http_test_invocation(true),
    )
  catch {
    error =>
      inspect(
        "\{error}".contains("explicitly forbids provider calls"),
        content="true",
      )
  } noraise {
    _ => fail("expected an invocation-level provider denial")
  }
  ignore(
    capability_http_executor(
      capability_http_test_policy(route, ["provider-route-1"]),
      route,
      capability_http_test_invocation(false),
    ),
  )
}

///|
test "uncertain pack transport remains reconcilable" {
  let result = capability_http_uncertain_result("connection closed")
  inspect(result.status, content="unknown")
  assert_eq(result.logs, ["connection closed"])
  inspect(
    result.output.stringify().contains("adapter-transport-uncertain"),
    content="true",
  )
}
