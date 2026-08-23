///|
async fn harness_replay_qualification_expanded_fixture() -> Json {
  let fixture = harness_replay_test_fixture()
  guard fixture is Object(root) else { fail("expected fixture object") }
  guard root.get("cases") is Some(Array(cases)) else {
    fail("expected fixture cases")
  }
  let expanded : Array[Json] = []
  for case_index, case in cases {
    for repeat in 0..<10 {
      let clone = @json.parse(case.stringify())
      guard clone is Object(fields) else { fail("expected case object") }
      fields["case_id"] = "anon-qualification-\{case_index}-\{repeat}".to_json()
      expanded.push(clone)
    }
  }
  root["cases"] = expanded.to_json()
  fixture
}

///|
fn harness_replay_qualification_set_variant_latency(
  case : Json,
  latency_ms : Int,
) -> Bool {
  match case {
    Object(case_fields) =>
      match case_fields.get("variant") {
        Some(Object(variant)) =>
          match variant.get("phase_metrics") {
            Some(Object(phases)) => {
              variant["latency_ms"] = latency_ms.to_json()
              phases["total_ms"] = latency_ms.to_json()
              true
            }
            _ => false
          }
        _ => false
      }
    _ => false
  }
}

///|
test "percentile distributions are deterministic and permutation invariant" {
  let ordered = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 100]
  let permuted = [100, 4, 8, 1, 9, 3, 6, 10, 2, 7, 5]
  assert_eq(harness_replay_percentile(ordered, 50), 6)
  assert_eq(harness_replay_percentile(ordered, 95), 100)
  assert_eq(
    harness_replay_percentile(ordered, 50),
    harness_replay_percentile(permuted, 50),
  )
  assert_eq(
    harness_replay_percentile(ordered, 95),
    harness_replay_percentile(permuted, 95),
  )
  assert_true(harness_replay_within_regression_ppm(0, 0, 100000))
  assert_false(harness_replay_within_regression_ppm(1, 0, 100000))
}

///|
async test "expanded replay preserves quality and performance distributions" {
  let report = evaluate_harness_replay(
    harness_replay_qualification_expanded_fixture(),
  )
  assert_eq(harness_replay_bool(report, "overall_passed"), Some(true))
  assert_eq(harness_replay_int(report, "total_sample_count"), Some(140))
  for cohort in harness_replay_array(report, "cohorts") {
    assert_eq(harness_replay_int(cohort, "sample_count"), Some(20))
  }
  let first = harness_replay_test_first_cohort(report)
  let baseline = harness_replay_object(first, "baseline")
  assert_eq(
    harness_replay_summary_percentile(baseline, "latency_ms", "p50"),
    100,
  )
  assert_eq(
    harness_replay_summary_percentile(baseline, "latency_ms", "p95"),
    140,
  )
}

///|
async test "p95 gate ignores one tail sample but catches a sustained tail" {
  let one_outlier = harness_replay_qualification_expanded_fixture()
  guard one_outlier is Object(one_root) else { fail("expected fixture") }
  guard one_root.get("cases") is Some(Array(one_cases)) else {
    fail("expected cases")
  }
  let mut changed = 0
  for case in one_cases {
    if harness_replay_string(case, "cohort") == "read_only_inspection" &&
      harness_replay_int(harness_replay_object(case, "baseline"), "latency_ms") ==
      Some(140) &&
      changed < 1 {
      assert_true(harness_replay_qualification_set_variant_latency(case, 5000))
      changed += 1
    }
  }
  assert_eq(changed, 1)
  let one_report = evaluate_harness_replay(one_outlier)
  assert_eq(harness_replay_bool(one_report, "overall_passed"), Some(true))

  let two_outliers = harness_replay_qualification_expanded_fixture()
  guard two_outliers is Object(two_root) else { fail("expected fixture") }
  guard two_root.get("cases") is Some(Array(two_cases)) else {
    fail("expected cases")
  }
  changed = 0
  for case in two_cases {
    if harness_replay_string(case, "cohort") == "read_only_inspection" &&
      harness_replay_int(harness_replay_object(case, "baseline"), "latency_ms") ==
      Some(140) &&
      changed < 2 {
      assert_true(harness_replay_qualification_set_variant_latency(case, 5000))
      changed += 1
    }
  }
  assert_eq(changed, 2)
  let two_report = evaluate_harness_replay(two_outliers)
  assert_eq(harness_replay_bool(two_report, "overall_passed"), Some(false))
  assert_eq(harness_replay_string(two_report, "first_failed_gate"), "latency")
}
