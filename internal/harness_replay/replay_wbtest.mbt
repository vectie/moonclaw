///|
async fn harness_replay_test_fixture() -> Json {
  @json.parse(@fsx.read_file("testdata/harness_replay/anonymized_cases.json"))
}

///|
fn harness_replay_test_first_variant(
  fixture : Json,
) -> Map[String, Json] raise HarnessReplayError {
  guard fixture is Object(root) else {
    raise InvalidFixture("test-fixture-not-object")
  }
  guard root.get("cases") is Some(Array([Object(first), ..])) else {
    raise InvalidFixture("test-fixture-has-no-first-case")
  }
  guard first.get("variant") is Some(Object(variant)) else {
    raise InvalidFixture("test-fixture-has-no-variant")
  }
  variant
}

///|
fn harness_replay_test_first_cohort(report : Json) -> Json {
  match harness_replay_array(report, "cohorts") {
    [first, ..] => first
    _ => Json::empty_object()
  }
}

///|
async test "anonymized replay fixture passes all quality-first gates" {
  let report = evaluate_harness_replay(harness_replay_test_fixture())
  assert_eq(
    harness_replay_string(report, "contract"),
    "moonclaw.harness-replay-report.v1",
  )
  assert_eq(harness_replay_bool(report, "overall_passed"), Some(true))
  assert_eq(harness_replay_int(report, "total_sample_count"), Some(14))
  assert_eq(harness_replay_int(report, "cohort_count"), Some(7))
  let first = harness_replay_test_first_cohort(report)
  assert_eq(harness_replay_string(first, "cohort"), "read_only_inspection")
  assert_eq(harness_replay_int(first, "sample_count"), Some(2))
  let baseline = harness_replay_object(first, "baseline")
  assert_eq(
    harness_replay_summary_percentile(baseline, "latency_ms", "p50"),
    100,
  )
  assert_eq(
    harness_replay_summary_percentile(baseline, "latency_ms", "p95"),
    140,
  )
  let phase_summary = harness_replay_object(baseline, "phase_metrics")
  let distributions = harness_replay_object(phase_summary, "distributions")
  let provider = harness_replay_object(distributions, "provider_ms")
  assert_eq(harness_replay_int(provider, "p50"), Some(70))
  assert_eq(harness_replay_int(provider, "p95"), Some(100))
}

///|
async test "task quality regression blocks lower cost and latency" {
  let fixture = harness_replay_test_fixture()
  let variant = harness_replay_test_first_variant(fixture)
  variant["task_success"] = false.to_json()
  variant["verifier_success"] = false.to_json()
  variant["prompt_tokens"] = (1).to_json()
  variant["cache_read_tokens"] = (1).to_json()
  variant["request_chars"] = (1).to_json()
  let report = evaluate_harness_replay(fixture)
  assert_eq(harness_replay_bool(report, "overall_passed"), Some(false))
  assert_eq(harness_replay_string(report, "first_failed_gate"), "task_success")
  assert_eq(
    harness_replay_string(
      harness_replay_test_first_cohort(report),
      "first_failed_gate",
    ),
    "task_success",
  )
}

///|
async test "verifier and safety gates precede efficiency" {
  let verifier_fixture = harness_replay_test_fixture()
  harness_replay_test_first_variant(verifier_fixture)["verifier_success"] = false.to_json()
  let verifier_report = evaluate_harness_replay(verifier_fixture)
  assert_eq(
    harness_replay_string(verifier_report, "first_failed_gate"),
    "verifier_success",
  )

  let safety_fixture = harness_replay_test_fixture()
  harness_replay_test_first_variant(safety_fixture)["safety_recovery_success"] = false.to_json()
  let safety_report = evaluate_harness_replay(safety_fixture)
  assert_eq(
    harness_replay_string(safety_report, "first_failed_gate"),
    "safety_recovery",
  )
}

///|
async test "cost cache and latency use explicit distribution policies" {
  let cost_fixture = harness_replay_test_fixture()
  let costly = harness_replay_test_first_variant(cost_fixture)
  costly["prompt_tokens"] = (10000).to_json()
  costly["cache_read_tokens"] = (0).to_json()
  costly["request_chars"] = (100000).to_json()
  let cost_report = evaluate_harness_replay(cost_fixture)
  assert_eq(
    harness_replay_string(cost_report, "first_failed_gate"),
    "cost_cache",
  )

  let latency_fixture = harness_replay_test_fixture()
  let slow = harness_replay_test_first_variant(latency_fixture)
  slow["latency_ms"] = (1000).to_json()
  guard slow.get("phase_metrics") is Some(Object(phase_fields)) else {
    fail("expected phase object")
  }
  phase_fields["total_ms"] = (1000).to_json()
  let latency_report = evaluate_harness_replay(latency_fixture)
  assert_eq(
    harness_replay_string(latency_report, "first_failed_gate"),
    "latency",
  )
}

///|
async test "replay fixtures reject raw user content fields" {
  let fixture = harness_replay_test_fixture()
  let variant = harness_replay_test_first_variant(fixture)
  variant["prompt"] = "private raw text".to_json()
  try evaluate_harness_replay(fixture) catch {
    InvalidFixture(code) => assert_eq(code, "raw-content-field-forbidden")
  } noraise {
    _ => fail("expected raw content rejection")
  }
}

///|
async test "missing cohort is an explicit sample count failure" {
  let fixture = harness_replay_test_fixture()
  guard fixture is Object(root) else { fail("expected fixture object") }
  guard root.get("cases") is Some(Array(cases)) else {
    fail("expected fixture cases")
  }
  let retained = cases.filter(case => {
    harness_replay_string(case, "cohort") != "failure_retry"
  })
  root["cases"] = retained.to_json()
  let report = evaluate_harness_replay(fixture)
  assert_eq(harness_replay_bool(report, "overall_passed"), Some(false))
  assert_eq(harness_replay_string(report, "first_failed_gate"), "sample_count")
  assert_eq(harness_replay_int(report, "cohort_count"), Some(7))
  let cohort_reports = harness_replay_array(report, "cohorts")
  let missing = cohort_reports[6]
  assert_eq(harness_replay_string(missing, "cohort"), "failure_retry")
  assert_eq(harness_replay_int(missing, "sample_count"), Some(0))
  assert_eq(harness_replay_bool(missing, "sample_count_ready"), Some(false))
}

///|
async test "paired replay cases require unique anonymized identifiers" {
  let fixture = harness_replay_test_fixture()
  guard fixture is Object(root) else { fail("expected fixture object") }
  guard root.get("cases") is Some(Array([first, second, ..])) else {
    fail("expected two fixture cases")
  }
  guard first is Object(first_fields) else {
    fail("expected first case object")
  }
  guard second is Object(second_fields) else {
    fail("expected second case object")
  }
  second_fields["case_id"] = first_fields.get("case_id").unwrap()
  try evaluate_harness_replay(fixture) catch {
    InvalidFixture(code) => assert_eq(code, "duplicate-case-id")
  } noraise {
    _ => fail("expected duplicate case rejection")
  }
}
