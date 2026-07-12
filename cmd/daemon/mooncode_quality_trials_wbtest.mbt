///|
fn quality_command(packet : Json) -> Json {
  { "session_id": "quality-session", "command": "run_eval", "packet": packet }
}

///|
fn passing_native_eval() -> Json {
  { "ok": true, "status": "accepted" }
}

///|
fn complete_quality_packet() -> Json {
  {
    "command_id": "quality-command",
    "nearest_module_inventory": ["package", "api", "tests"],
    "domain_assumptions_reviewed": true,
    "native_check_passed": true,
    "native_tests_passed": true,
    "positive_cases": ["valid input succeeds"],
    "negative_cases": ["invalid authority fails closed"],
    "expected_exit_codes": [0, 1],
    "package_proof_ref": "evidence/package.json",
    "review_receipt_ref": "evidence/review.json",
    "unsupported_claims": [],
    "quality_attempt": 1,
    "prior_diagnoses": [],
    "input_revision": "r1",
    "quality_output_refs": ["evidence/eval.json"],
  }
}

///|
test "quality trial accepts only complete native and review evidence" {
  let trial = mooncode_quality_trial(
    quality_command(complete_quality_packet()),
    passing_native_eval(),
  )
  assert_true(mooncode_json_bool(trial, "qualified", default=false))
  assert_eq(
    mooncode_json_string(trial, "decision", default=""),
    "accept-for-review",
  )
  assert_false(
    mooncode_json_bool(trial, "scenario_answer_embedded", default=true),
  )
}

///|
test "missing negative cases revises a general input instead of leaking an answer" {
  let packet = complete_quality_packet()
  guard packet is Object(fields) else { fail("expected packet") }
  fields["negative_cases"] = Json::array([])
  let trial = mooncode_quality_trial(
    quality_command(packet),
    passing_native_eval(),
  )
  assert_eq(
    mooncode_json_string(trial, "diagnosis", default=""),
    "missing-negative-tests",
  )
  assert_eq(
    mooncode_json_string(trial, "decision", default=""),
    "revise-input-and-retry",
  )
  assert_true(
    mooncode_json_string(trial, "next_input_instruction", default="").contains(
      "without embedding scenario answers",
    ),
  )
}

///|
test "repeated identical failure becomes a Bookkeeper execution gap" {
  let packet = complete_quality_packet()
  guard packet is Object(fields) else { fail("expected packet") }
  fields["negative_cases"] = Json::array([])
  fields["quality_attempt"] = Json::number(3.0)
  fields["prior_diagnoses"] = [
    "missing-negative-tests", "missing-negative-tests",
  ]
  let trial = mooncode_quality_trial(
    quality_command(packet),
    passing_native_eval(),
  )
  assert_eq(
    mooncode_json_string(trial, "decision", default=""),
    "open-bookkeeper-execution-gap",
  )
  assert_eq(mooncode_json_int(trial, "inspection_budget", default=-1), 0)
  assert_true(
    mooncode_json_bool(trial, "preserves_failed_evidence", default=false),
  )
}

///|
test "native failure is never accepted as a quality success" {
  let trial = mooncode_quality_trial(
    quality_command(complete_quality_packet()),
    { "ok": false },
  )
  assert_eq(
    mooncode_json_string(trial, "diagnosis", default=""),
    "syntax-or-tool-uncertainty",
  )
  assert_false(mooncode_json_bool(trial, "qualified", default=true))
}
