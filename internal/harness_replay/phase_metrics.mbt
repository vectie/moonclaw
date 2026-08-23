///|
fn harness_phase_metric_names() -> Array[String] {
  [
    "queue_ms", "request_build_ms", "provider_ms", "tool_execution_ms", "verification_ms",
    "total_ms",
  ]
}

///|
fn harness_phase_metrics_validate(
  metrics : Json,
) -> Unit raise HarnessReplayError {
  if harness_replay_string(metrics, "contract") !=
    HARNESS_PHASE_METRICS_CONTRACT {
    harness_replay_invalid("invalid-phase-metrics-contract")
  }
  let total = harness_replay_required_int(metrics, "total_ms")
  if total < 0 {
    harness_replay_invalid("negative-phase-metric:total_ms")
  }
  for name in harness_phase_metric_names() {
    let value = harness_replay_required_int(metrics, name)
    if value < 0 {
      harness_replay_invalid("negative-phase-metric:\{name}")
    }
    if name != "total_ms" && value > total {
      harness_replay_invalid("phase-exceeds-total:\{name}")
    }
  }
}

///|
fn harness_replay_percentile(values : Array[Int], percentile : Int) -> Int {
  if values.is_empty() {
    return 0
  }
  let ordered = values.copy()
  ordered.sort()
  let rank = ((ordered.length() * percentile + 99) / 100).max(1)
  ordered[(rank - 1).min(ordered.length() - 1)]
}

///|
fn harness_phase_metrics_summary(observations : ArrayView[Json]) -> Json {
  let summary : Map[String, Json] = Map([])
  for name in harness_phase_metric_names() {
    let values = observations.map(observation => {
      harness_replay_required_int(
        harness_replay_object(observation, "phase_metrics"),
        name,
      ) catch {
        _ => 0
      }
    })
    summary[name] = {
      "p50": harness_replay_percentile(values, 50),
      "p95": harness_replay_percentile(values, 95),
    }
  }
  {
    "contract": HARNESS_PHASE_METRICS_CONTRACT,
    "sample_count": observations.length(),
    "distributions": Json::object(summary),
  }
}
