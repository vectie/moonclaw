///|
fn harness_phase_metrics_test_value(total_ms : Int) -> Json {
  {
    "contract": "moonclaw.harness-phase-metrics.v1",
    "queue_ms": 2,
    "request_build_ms": 3,
    "provider_ms": 10,
    "tool_execution_ms": 4,
    "verification_ms": 1,
    "total_ms": total_ms,
  }
}

///|
test "phase metrics accept overlap and preserve named phases" {
  let metrics = harness_phase_metrics_test_value(12)
  harness_phase_metrics_validate(metrics)
  assert_eq(harness_phase_metric_names(), [
    "queue_ms", "request_build_ms", "provider_ms", "tool_execution_ms", "verification_ms",
    "total_ms",
  ])
}

///|
test "phase metrics reject invalid contract negative and impossible phase" {
  let invalid : Array[(Json, String)] = [
    (
      (
        {
          "contract": "wrong",
          "queue_ms": 0,
          "request_build_ms": 0,
          "provider_ms": 0,
          "tool_execution_ms": 0,
          "verification_ms": 0,
          "total_ms": 0,
        } : Json),
      "invalid-phase-metrics-contract",
    ),
    (
      (
        {
          "contract": "moonclaw.harness-phase-metrics.v1",
          "queue_ms": -1,
          "request_build_ms": 0,
          "provider_ms": 0,
          "tool_execution_ms": 0,
          "verification_ms": 0,
          "total_ms": 1,
        } : Json),
      "negative-phase-metric:queue_ms",
    ),
    (harness_phase_metrics_test_value(5), "phase-exceeds-total:provider_ms"),
  ]
  for item in invalid {
    let (metrics, expected) = item
    try harness_phase_metrics_validate(metrics) catch {
      InvalidFixture(code) => assert_eq(code, expected)
    } noraise {
      _ => fail("expected phase metric rejection")
    }
  }
}

///|
test "percentiles use deterministic nearest rank" {
  assert_eq(harness_replay_percentile([40, 10, 30, 20], 50), 20)
  assert_eq(harness_replay_percentile([40, 10, 30, 20], 95), 40)
  let empty : Array[Int] = []
  assert_eq(harness_replay_percentile(empty, 95), 0)
}
