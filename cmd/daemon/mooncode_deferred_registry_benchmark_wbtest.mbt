///|
test "mooncode deferred registry benchmark reports schema reduction and lookup latency" {
  let command = mooncode_deferred_test_command(true)
  let baseline = mooncode_runtime_turn_model_tools()
  let dynamic = mooncode_runtime_turn_model_tools_for_command(command)
  let baseline_chars = baseline.to_json().stringify().length()
  let dynamic_chars = dynamic.to_json().stringify().length()
  let registry = mooncode_runtime_turn_deferred_tool_catalog()
  let queries = [
    "browser screenshot", "inspect image pixels", "moonbit semantic outline", "moonbit test build",
    "delegate independent workers", "wait for worker state", "artifact validation",
    "unknown capability",
  ]
  let iterations = 500
  let operations = iterations * queries.length()
  let started = @clock.epoch.now()
  let mut checksum = 0
  for _ in 0..<iterations {
    for query in queries {
      checksum += mooncode_runtime_turn_deferred_tool_matches_in_catalog(
        registry,
        query,
        MOONCODE_DEFERRED_TOOL_SEARCH_MAX_RESULTS,
      ).length()
    }
  }
  let elapsed_ms = @clock.epoch.now().ms_since(started).to_int().max(0)
  assert_true(registry.length() > 0)
  assert_true(checksum > 0)
  assert_true(dynamic_chars < baseline_chars)
  // This is a regression guard, not a microbenchmark SLA. The generous bound
  // catches accidental unbounded scans while remaining stable on slow CI.
  assert_true(elapsed_ms < 5000)
  println(
    (
      {
        "contract": "moonclaw.deferred-registry-benchmark.v1",
        "authoritative_tool_count": baseline.length(),
        "deferred_registry_count": registry.length(),
        "initial_dynamic_tool_count": dynamic.length(),
        "baseline_schema_chars": baseline_chars,
        "dynamic_schema_chars": dynamic_chars,
        "schema_chars_saved": baseline_chars - dynamic_chars,
        "schema_reduction_basis_points": (baseline_chars - dynamic_chars) *
        10000 /
        baseline_chars,
        "lookup_operations": operations,
        "lookup_elapsed_ms": elapsed_ms,
        "lookup_average_microseconds": elapsed_ms * 1000 / operations,
        "lookup_checksum": checksum,
      } : Json).stringify(),
  )
}
