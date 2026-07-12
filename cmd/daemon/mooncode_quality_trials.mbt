///|
fn mooncode_quality_diagnosis(
  command : Json,
  native_eval_report : Json,
) -> String {
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  if mooncode_json_array_items(packet, "nearest_module_inventory").is_empty() {
    return "incomplete-module-inventory"
  }
  if !mooncode_json_bool(packet, "domain_assumptions_reviewed", default=false) {
    return "wrong-domain-assumptions"
  }
  if !mooncode_json_bool(native_eval_report, "ok", default=false) ||
    !mooncode_json_bool(packet, "native_check_passed", default=false) ||
    !mooncode_json_bool(packet, "native_tests_passed", default=false) {
    return "syntax-or-tool-uncertainty"
  }
  if mooncode_json_array_items(packet, "positive_cases").is_empty() {
    return "missing-positive-tests"
  }
  if mooncode_json_array_items(packet, "negative_cases").is_empty() {
    return "missing-negative-tests"
  }
  if mooncode_json_array_items(packet, "expected_exit_codes").is_empty() {
    return "missing-exit-code-proof"
  }
  if mooncode_json_string(packet, "package_proof_ref", default="") == "" {
    return "incomplete-packaging"
  }
  if mooncode_json_string(packet, "review_receipt_ref", default="") == "" {
    return "missing-review-receipt"
  }
  if !mooncode_json_array_items(packet, "unsupported_claims").is_empty() {
    return "unsupported-claims"
  }
  "qualified"
}

///|
fn mooncode_quality_next_input(diagnosis : String) -> String {
  match diagnosis {
    "incomplete-module-inventory" =>
      "Inventory the nearest module, package boundary, public API, and existing tests before selecting a mutation."
    "wrong-domain-assumptions" =>
      "State and review the domain assumptions that affect the change; preserve unresolved assumptions as evidence gaps."
    "syntax-or-tool-uncertainty" =>
      "Use native IDE/check output to isolate the smallest failing boundary, then make one bounded general correction."
    "missing-positive-tests" =>
      "Add declared positive cases tied to the acceptance criteria and record their exact receipts."
    "missing-negative-tests" =>
      "Add fail-closed negative cases for authority, input, evidence, and boundary violations without embedding scenario answers."
    "missing-exit-code-proof" =>
      "Declare and verify exact success and failure exit codes for the executable surface."
    "incomplete-packaging" =>
      "Produce package/build proof that binds the verified source to the runnable artifact."
    "missing-review-receipt" =>
      "Request an explicit review receipt; execution success alone cannot become acceptance."
    "unsupported-claims" =>
      "Lower or remove claims that exceed the attached evidence and product claim ceiling."
    _ => "Retain the qualified input and its evidence lineage."
  }
}

///|
fn mooncode_quality_trial(command : Json, native_eval_report : Json) -> Json {
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let diagnosis = mooncode_quality_diagnosis(command, native_eval_report)
  let prior = mooncode_json_array_items(packet, "prior_diagnoses")
  let repeated = prior.filter(item => item == Json::string(diagnosis)).length()
  let attempt = mooncode_json_int(packet, "quality_attempt", default=1)
  let qualified = diagnosis == "qualified"
  let decision = if qualified {
    "accept-for-review"
  } else if repeated >= 2 || attempt >= 3 {
    "open-bookkeeper-execution-gap"
  } else {
    "revise-input-and-retry"
  }
  {
    "contract_id": "mooncode.quality-trial.v1",
    "trial_id": "trial-\{mooncode_command_id(command)}-\{attempt}",
    "hypothesis": mooncode_json_string(
      packet,
      "quality_hypothesis",
      default="The revised general input will close the diagnosed quality gap.",
    ),
    "input_revision": mooncode_json_string(
      packet,
      "input_revision",
      default="r\{attempt}",
    ),
    "expected_improvement": mooncode_quality_next_input(diagnosis),
    "output_refs": Json::array(
      mooncode_json_array_items(packet, "quality_output_refs"),
    ),
    "diagnosis": diagnosis,
    "decision": decision,
    "qualified": qualified,
    "attempt": attempt,
    "same_diagnosis_count": repeated + 1,
    "next_input_instruction": mooncode_quality_next_input(diagnosis),
    "preserves_failed_evidence": true,
    "scenario_answer_embedded": false,
    "inspection_budget": if qualified {
      0
    } else if diagnosis == "incomplete-module-inventory" {
      2
    } else if repeated == 0 {
      1
    } else {
      0
    },
  }
}
