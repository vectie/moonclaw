///|
fn harness_replay_validate_policy(
  policy : Json,
) -> Unit raise HarnessReplayError {
  for
    name in [
      "minimum_samples_per_cohort", "max_cost_regression_ppm", "max_cache_ratio_drop_ppm",
      "max_latency_p50_regression_ppm", "max_latency_p95_regression_ppm",
    ] {
    if harness_replay_required_int(policy, name) < 0 {
      harness_replay_invalid("negative-policy-value:\{name}")
    }
  }
  if harness_replay_required_int(policy, "minimum_samples_per_cohort") < 1 {
    harness_replay_invalid("minimum-samples-must-be-positive")
  }
}

///|
fn harness_replay_validate_observation(
  observation : Json,
) -> Unit raise HarnessReplayError {
  let task_success = harness_replay_required_bool(observation, "task_success")
  let verifier_success = harness_replay_required_bool(
    observation, "verifier_success",
  )
  ignore(harness_replay_required_bool(observation, "safety_recovery_success"))
  if verifier_success && !task_success {
    harness_replay_invalid("verifier-success-without-task-success")
  }
  for
    name in [
      "prompt_tokens", "cache_read_tokens", "request_chars", "latency_ms", "retry_count",
    ] {
    if harness_replay_required_int(observation, name) < 0 {
      harness_replay_invalid("negative-observation-value:\{name}")
    }
  }
  let prompt_tokens = harness_replay_required_int(observation, "prompt_tokens")
  let cache_read_tokens = harness_replay_required_int(
    observation, "cache_read_tokens",
  )
  if cache_read_tokens > prompt_tokens {
    harness_replay_invalid("cache-read-exceeds-prompt-tokens")
  }
  if !harness_replay_known_outcomes().contains(
      harness_replay_string(observation, "outcome"),
    ) {
    harness_replay_invalid("invalid-outcome")
  }
  let phases = harness_replay_object(observation, "phase_metrics")
  harness_phase_metrics_validate(phases)
  if harness_replay_required_int(phases, "total_ms") !=
    harness_replay_required_int(observation, "latency_ms") {
    harness_replay_invalid("phase-total-does-not-match-latency")
  }
}

///|
fn harness_replay_validate_case(case : Json) -> Unit raise HarnessReplayError {
  let case_id = harness_replay_string(case, "case_id")
  if !case_id.has_prefix("anon-") {
    harness_replay_invalid("case-id-is-not-anonymized")
  }
  let cohort = harness_replay_string(case, "cohort")
  if !harness_replay_known_cohorts().contains(cohort) {
    harness_replay_invalid("invalid-cohort")
  }
  let serialized = case.stringify()
  for
    forbidden in [
      "\"prompt\"", "\"path\"", "\"session_id\"", "\"tool_arguments\"", "\"output\"",
    ] {
    if serialized.contains(forbidden) {
      harness_replay_invalid("raw-content-field-forbidden")
    }
  }
  harness_replay_validate_observation(harness_replay_object(case, "baseline"))
  harness_replay_validate_observation(harness_replay_object(case, "variant"))
}

///|
fn harness_replay_observation_summary(observations : ArrayView[Json]) -> Json {
  let mut task_success_count = 0
  let mut verifier_success_count = 0
  let mut safety_recovery_success_count = 0
  let mut total_prompt_tokens = 0L
  let mut total_cache_read_tokens = 0L
  let fresh_input_tokens : Array[Int] = []
  let request_chars : Array[Int] = []
  let latencies : Array[Int] = []
  let outcomes : Map[String, Int] = Map([])
  for outcome in harness_replay_known_outcomes() {
    outcomes[outcome] = 0
  }
  for observation in observations {
    if harness_replay_bool(observation, "task_success") == Some(true) {
      task_success_count += 1
    }
    if harness_replay_bool(observation, "verifier_success") == Some(true) {
      verifier_success_count += 1
    }
    if harness_replay_bool(observation, "safety_recovery_success") == Some(true) {
      safety_recovery_success_count += 1
    }
    let prompt = harness_replay_int(observation, "prompt_tokens").unwrap_or(0)
    let cached = harness_replay_int(observation, "cache_read_tokens").unwrap_or(
      0,
    )
    total_prompt_tokens += prompt.to_int64()
    total_cache_read_tokens += cached.to_int64()
    fresh_input_tokens.push(prompt - cached)
    request_chars.push(
      harness_replay_int(observation, "request_chars").unwrap_or(0),
    )
    latencies.push(harness_replay_int(observation, "latency_ms").unwrap_or(0))
    let outcome = harness_replay_string(observation, "outcome")
    outcomes[outcome] = outcomes.get(outcome).unwrap_or(0) + 1
  }
  let cache_read_ratio_ppm = if total_prompt_tokens == 0L {
    0
  } else {
    (total_cache_read_tokens * 1_000_000L / total_prompt_tokens).to_int()
  }
  let outcome_json : Map[String, Json] = Map([])
  for outcome, count in outcomes {
    outcome_json[outcome] = count.to_json()
  }
  {
    "sample_count": observations.length(),
    "task_success_count": task_success_count,
    "verifier_success_count": verifier_success_count,
    "safety_recovery_success_count": safety_recovery_success_count,
    "fresh_input_tokens": {
      "p50": harness_replay_percentile(fresh_input_tokens, 50),
      "p95": harness_replay_percentile(fresh_input_tokens, 95),
    },
    "request_chars": {
      "p50": harness_replay_percentile(request_chars, 50),
      "p95": harness_replay_percentile(request_chars, 95),
    },
    "cache_read_ratio_ppm": cache_read_ratio_ppm,
    "latency_ms": {
      "p50": harness_replay_percentile(latencies, 50),
      "p95": harness_replay_percentile(latencies, 95),
    },
    "outcomes": Json::object(outcome_json),
    "phase_metrics": harness_phase_metrics_summary(observations),
  }
}

///|
fn harness_replay_summary_percentile(
  summary : Json,
  metric : String,
  percentile : String,
) -> Int {
  harness_replay_int(harness_replay_object(summary, metric), percentile).unwrap_or(
    0,
  )
}

///|
fn harness_replay_within_regression_ppm(
  variant : Int,
  baseline : Int,
  allowed_ppm : Int,
) -> Bool {
  if baseline == 0 {
    return variant == 0
  }
  variant.to_int64() * 1_000_000L <=
  baseline.to_int64() * (1_000_000L + allowed_ppm.to_int64())
}

///|
fn harness_replay_gate(name : String, passed : Bool, reason : String) -> Json {
  { "name": name, "passed": passed, "reason": reason }
}

///|
fn harness_replay_cohort_report(
  cohort : String,
  cases : ArrayView[Json],
  policy : Json,
) -> Json {
  let baseline = cases.map(case => harness_replay_object(case, "baseline"))
  let variant = cases.map(case => harness_replay_object(case, "variant"))
  let baseline_summary = harness_replay_observation_summary(baseline)
  let variant_summary = harness_replay_observation_summary(variant)
  let minimum_samples = harness_replay_int(policy, "minimum_samples_per_cohort").unwrap_or(
    1,
  )
  let sample_count_ready = cases.length() >= minimum_samples
  let task_success = harness_replay_int(variant_summary, "task_success_count").unwrap_or(
      0,
    ) >=
    harness_replay_int(baseline_summary, "task_success_count").unwrap_or(0)
  let verifier_success = harness_replay_int(
      variant_summary, "verifier_success_count",
    ).unwrap_or(0) >=
    harness_replay_int(baseline_summary, "verifier_success_count").unwrap_or(0)
  let safety_recovery = harness_replay_int(
      variant_summary, "safety_recovery_success_count",
    ).unwrap_or(0) >=
    harness_replay_int(baseline_summary, "safety_recovery_success_count").unwrap_or(
      0,
    )
  let max_cost_regression = harness_replay_int(
    policy, "max_cost_regression_ppm",
  ).unwrap_or(0)
  let fresh_cost = harness_replay_within_regression_ppm(
    harness_replay_summary_percentile(
      variant_summary, "fresh_input_tokens", "p95",
    ),
    harness_replay_summary_percentile(
      baseline_summary, "fresh_input_tokens", "p95",
    ),
    max_cost_regression,
  )
  let request_cost = harness_replay_within_regression_ppm(
    harness_replay_summary_percentile(variant_summary, "request_chars", "p95"),
    harness_replay_summary_percentile(baseline_summary, "request_chars", "p95"),
    max_cost_regression,
  )
  let cache_ratio = harness_replay_int(variant_summary, "cache_read_ratio_ppm").unwrap_or(
      0,
    ) +
    harness_replay_int(policy, "max_cache_ratio_drop_ppm").unwrap_or(0) >=
    harness_replay_int(baseline_summary, "cache_read_ratio_ppm").unwrap_or(0)
  let cost_cache = fresh_cost && request_cost && cache_ratio
  let latency_p50 = harness_replay_within_regression_ppm(
    harness_replay_summary_percentile(variant_summary, "latency_ms", "p50"),
    harness_replay_summary_percentile(baseline_summary, "latency_ms", "p50"),
    harness_replay_int(policy, "max_latency_p50_regression_ppm").unwrap_or(0),
  )
  let latency_p95 = harness_replay_within_regression_ppm(
    harness_replay_summary_percentile(variant_summary, "latency_ms", "p95"),
    harness_replay_summary_percentile(baseline_summary, "latency_ms", "p95"),
    harness_replay_int(policy, "max_latency_p95_regression_ppm").unwrap_or(0),
  )
  let latency = latency_p50 && latency_p95
  let gates = [
    harness_replay_gate(
      "task_success",
      task_success,
      if task_success {
        "non-regressed"
      } else {
        "variant-task-success-regressed"
      },
    ),
    harness_replay_gate(
      "verifier_success",
      verifier_success,
      if verifier_success {
        "non-regressed"
      } else {
        "variant-verifier-regressed"
      },
    ),
    harness_replay_gate(
      "safety_recovery",
      safety_recovery,
      if safety_recovery {
        "non-regressed"
      } else {
        "variant-safety-recovery-regressed"
      },
    ),
    harness_replay_gate(
      "cost_cache",
      cost_cache,
      if cost_cache {
        "within-explicit-policy"
      } else {
        "variant-cost-cache-regressed"
      },
    ),
    harness_replay_gate(
      "latency",
      latency,
      if latency {
        "within-explicit-policy"
      } else {
        "variant-latency-regressed"
      },
    ),
  ]
  let mut first_failed_gate = ""
  if !sample_count_ready {
    first_failed_gate = "sample_count"
  } else {
    for gate in gates {
      if !harness_replay_bool(gate, "passed").unwrap_or(false) {
        first_failed_gate = harness_replay_string(gate, "name")
        break
      }
    }
  }
  {
    "cohort": cohort,
    "sample_count": cases.length(),
    "minimum_sample_count": minimum_samples,
    "sample_count_ready": sample_count_ready,
    "passed": first_failed_gate == "",
    "first_failed_gate": first_failed_gate,
    "baseline": baseline_summary,
    "variant": variant_summary,
    "gates": Json::array(gates),
  }
}

///|
pub fn evaluate_harness_replay(fixture : Json) -> Json raise HarnessReplayError {
  if harness_replay_string(fixture, "contract") !=
    HARNESS_REPLAY_FIXTURE_CONTRACT {
    harness_replay_invalid("invalid-fixture-contract")
  }
  if harness_replay_bool(fixture, "anonymized") != Some(true) {
    harness_replay_invalid("fixture-must-be-anonymized")
  }
  let policy = harness_replay_object(fixture, "policy")
  harness_replay_validate_policy(policy)
  let cases = harness_replay_array(fixture, "cases")
  if cases.is_empty() {
    harness_replay_invalid("fixture-has-no-cases")
  }
  let grouped : Map[String, Array[Json]] = Map([])
  let seen_case_ids : Map[String, Bool] = Map([])
  for case in cases {
    harness_replay_validate_case(case)
    let case_id = harness_replay_string(case, "case_id")
    if seen_case_ids.contains(case_id) {
      harness_replay_invalid("duplicate-case-id")
    }
    seen_case_ids[case_id] = true
    let cohort = harness_replay_string(case, "cohort")
    match grouped.get(cohort) {
      Some(items) => items.push(case)
      None => grouped[cohort] = [case]
    }
  }
  let cohort_reports : Array[Json] = []
  let mut overall_passed = true
  let mut first_failed_gate = ""
  for cohort in harness_replay_known_cohorts() {
    let cohort_cases = grouped.get(cohort).unwrap_or([])
    let report = harness_replay_cohort_report(cohort, cohort_cases, policy)
    cohort_reports.push(report)
    if !harness_replay_bool(report, "passed").unwrap_or(false) {
      overall_passed = false
      if first_failed_gate == "" {
        first_failed_gate = harness_replay_string(report, "first_failed_gate")
      }
    }
  }
  {
    "contract": HARNESS_REPLAY_REPORT_CONTRACT,
    "fixture_contract": HARNESS_REPLAY_FIXTURE_CONTRACT,
    "anonymized": true,
    "overall_passed": overall_passed,
    "first_failed_gate": first_failed_gate,
    "gate_order": [
      "task_success", "verifier_success", "safety_recovery", "cost_cache", "latency",
    ],
    "policy": policy,
    "total_sample_count": cases.length(),
    "cohort_count": cohort_reports.length(),
    "cohorts": Json::array(cohort_reports),
  }
}
