///|
pub fn package_review_flow_contract_id() -> String {
  "mooncode-package-review-model-flow.v1"
}

///|
pub fn package_review_flow_contract_kind() -> String {
  "mooncode-package-review-model-flow-contract"
}

///|
pub fn package_review_flow_report_kind() -> String {
  "mooncode-package-review-model-flow-report"
}

///|
pub fn package_review_flow_status_accepted() -> String {
  "accepted"
}

///|
pub fn package_review_flow_status_rejected() -> String {
  "rejected"
}

///|
pub fn package_review_flow_status_failed() -> String {
  "failed"
}

///|
pub fn package_review_flow_status_running() -> String {
  "running"
}

///|
pub fn package_review_flow_status_stale() -> String {
  "stale"
}

///|
pub fn package_review_flow_status_empty() -> String {
  "empty"
}

///|
pub fn package_review_flow_status_waiting_for_manifest() -> String {
  "waiting-for-manifest"
}

///|
pub fn package_review_flow_status_waiting_for_review() -> String {
  "waiting-for-review"
}

///|
pub fn package_review_flow_status_waiting_for_tests() -> String {
  "waiting-for-tests"
}

///|
pub fn package_review_flow_status_waiting_for_readiness() -> String {
  "waiting-for-readiness"
}

///|
pub fn package_review_flow_status_waiting_for_assistant() -> String {
  "waiting-for-assistant"
}

///|
pub fn package_review_flow_terminal_statuses() -> Array[String] {
  [
    package_review_flow_status_accepted(),
    package_review_flow_status_rejected(),
    package_review_flow_status_failed(),
  ]
}

///|
pub fn package_review_flow_status_is_terminal(status : String) -> Bool {
  package_review_flow_terminal_statuses().contains(status)
}

///|
pub fn package_review_flow_reason_missing_command_owner() -> String {
  "missing-command-owner"
}

///|
pub fn package_review_flow_reason_evidence_without_package_command() -> String {
  "evidence-without-package-command"
}

///|
pub fn package_review_flow_missing_step_assistant_summary() -> String {
  "assistant_summary"
}

///|
pub fn package_review_flow_missing_step_package_manifest() -> String {
  "package_manifest"
}

///|
pub fn package_review_flow_missing_step_review_accept_receipt() -> String {
  "review_accept_receipt"
}

///|
pub fn package_review_flow_missing_step_test_evidence() -> String {
  "test_evidence"
}

///|
pub fn package_review_flow_missing_step_package_verified() -> String {
  "package_verified"
}

///|
pub fn package_review_flow_command_kinds() -> Array[String] {
  ["command.package"]
}

///|
pub fn package_review_flow_manifest_kinds() -> Array[String] {
  [
    runtime_event_package_manifest(),
    runtime_event_package_index(),
    "package.manifest",
    "package.index",
    "mooncode-package-manifest",
    "mooncode-package-index",
  ]
}

///|
pub fn package_review_flow_diff_review_kinds() -> Array[String] {
  [
    "diff",
    "file_change",
    "patch_set.manifest",
    "change_set.manifest",
    runtime_event_receipt_accept(),
    runtime_event_receipt_reject(),
  ]
}

///|
pub fn package_review_flow_accept_kinds() -> Array[String] {
  [runtime_event_receipt_accept()]
}

///|
pub fn package_review_flow_reject_kinds() -> Array[String] {
  [runtime_event_receipt_reject()]
}

///|
pub fn package_review_flow_readiness_kinds() -> Array[String] {
  [
    runtime_event_package_built(),
    runtime_event_package_verified(),
    "runtime.package_built",
    "runtime.package_verified",
  ]
}

///|
pub fn package_review_flow_assistant_summary_kinds() -> Array[String] {
  ["assistant", "finish"]
}

///|
pub fn package_review_flow_failure_kinds() -> Array[String] {
  [
    runtime_event_command_error(),
    runtime_event_turn_failed(),
    runtime_event_max_steps_exhausted(),
    runtime_event_planner_failed(),
    "runtime.planner_failed",
  ]
}

///|
pub fn package_review_flow_accepted_sequence() -> Array[String] {
  [
    "command.package",
    "package.manifest",
    runtime_event_receipt_accept(),
    "test_result with exit_code 0",
    "runtime.package_verified",
    "assistant summary",
  ]
}

///|
pub fn package_review_flow_rejected_sequence() -> Array[String] {
  ["command.package", runtime_event_receipt_reject(), "assistant summary"]
}

///|
pub fn package_review_flow_failed_sequence() -> Array[String] {
  [
    "command.package", "command-scoped failed test_result, package proof, planner failure, command_error, turn_failed, or max_steps_exhausted",
  ]
}

///|
pub fn package_review_flow_event_is_package_command(event : Json) -> Bool {
  let kind = package_review_flow_event_kind(event)
  let action = package_review_flow_event_action(event)
  kind == "command.package" ||
  (kind == "command" && action == command_package())
}

///|
pub fn package_review_flow_event_is_package_manifest(event : Json) -> Bool {
  package_review_flow_manifest_kinds().contains(
    package_review_flow_event_kind(event),
  )
}

///|
pub fn package_review_flow_event_is_accept(event : Json) -> Bool {
  package_review_flow_accept_kinds().contains(
    package_review_flow_event_kind(event),
  )
}

///|
pub fn package_review_flow_event_is_reject(event : Json) -> Bool {
  package_review_flow_reject_kinds().contains(
    package_review_flow_event_kind(event),
  )
}

///|
pub fn package_review_flow_event_is_diff_review(event : Json) -> Bool {
  let kind = package_review_flow_event_kind(event)
  let lane = package_review_flow_json_string(event, "lane", default="")
  lane == event_lane_diff() ||
  package_review_flow_diff_review_kinds().contains(kind)
}

///|
pub fn package_review_flow_event_is_test_result(event : Json) -> Bool {
  package_review_flow_event_kind(event) == runtime_event_test_result()
}

///|
pub fn package_review_flow_event_is_package_readiness(event : Json) -> Bool {
  package_review_flow_readiness_kinds().contains(
    package_review_flow_event_kind(event),
  )
}

///|
pub fn package_review_flow_event_is_package_built(event : Json) -> Bool {
  let kind = package_review_flow_event_kind(event)
  kind == runtime_event_package_built() || kind == "runtime.package_built"
}

///|
pub fn package_review_flow_event_is_package_verified(event : Json) -> Bool {
  let kind = package_review_flow_event_kind(event)
  kind == runtime_event_package_verified() || kind == "runtime.package_verified"
}

///|
pub fn package_review_flow_event_is_assistant_summary(event : Json) -> Bool {
  let kind = package_review_flow_event_kind(event)
  let lane = package_review_flow_json_string(event, "lane", default="")
  kind == "assistant" || (kind == "finish" && lane == event_lane_review())
}

///|
pub fn package_review_flow_event_is_failure(event : Json) -> Bool {
  let kind = package_review_flow_event_kind(event)
  package_review_flow_failure_kinds().contains(kind) ||
  (
    package_review_flow_event_is_failure_eligible(event) &&
    package_review_flow_event_failed(event)
  )
}

///|
pub fn package_review_flow_event_is_failure_eligible(event : Json) -> Bool {
  package_review_flow_event_is_test_result(event) ||
  package_review_flow_event_is_package_readiness(event)
}

///|
pub fn package_review_flow_event_is_evidence(event : Json) -> Bool {
  package_review_flow_event_is_package_manifest(event) ||
  package_review_flow_event_is_diff_review(event) ||
  package_review_flow_event_is_test_result(event) ||
  package_review_flow_event_is_package_readiness(event) ||
  package_review_flow_event_is_assistant_summary(event) ||
  package_review_flow_event_is_failure(event)
}

///|
pub fn package_review_flow_event_failed(event : Json) -> Bool {
  package_review_flow_json_string(event, "status", default="") == "failed" ||
  package_review_flow_json_int(event, "exit_code", default=0) != 0
}

///|
pub fn package_review_flow_contract_json() -> Json {
  {
    "kind": package_review_flow_contract_kind(),
    "protocol": protocol_version(),
    "contract_id": package_review_flow_contract_id(),
    "owner": {
      "runtime": "moonclaw",
      "projection": "mooncode",
      "ui": "moondesk",
      "artifact": "moonbook",
    },
    "command_action_contract_id": command_action_contract_id(),
    "event_name_contract_id": runtime_event_name_contract_id(),
    "event_lane_contract_id": event_lane_contract_id(),
    "command_scope_keys": native_event_projection_command_scope_keys(),
    "command_scope_rule": "Package/review readiness must be proven by events that carry the same package command_id. Evidence from another command or without a command owner is stale diagnostics.",
    "accepted_sequence": package_review_flow_accepted_sequence(),
    "rejected_sequence": package_review_flow_rejected_sequence(),
    "failed_sequence": package_review_flow_failed_sequence(),
    "terminal_statuses": package_review_flow_terminal_statuses(),
    "stale_reasons": [
      package_review_flow_reason_missing_command_owner(),
      package_review_flow_reason_evidence_without_package_command(),
    ],
    "missing_steps": [
      package_review_flow_missing_step_package_manifest(),
      package_review_flow_missing_step_review_accept_receipt(),
      package_review_flow_missing_step_test_evidence(),
      package_review_flow_missing_step_package_verified(),
      package_review_flow_missing_step_assistant_summary(),
    ],
    "event_kinds": {
      "package_commands": package_review_flow_command_kinds(),
      "manifests": package_review_flow_manifest_kinds(),
      "diff_review": package_review_flow_diff_review_kinds(),
      "accepted": package_review_flow_accept_kinds(),
      "rejected": package_review_flow_reject_kinds(),
      "readiness": package_review_flow_readiness_kinds(),
      "assistant_summary": package_review_flow_assistant_summary_kinds(),
      "failure": package_review_flow_failure_kinds(),
    },
    "stale_rule": "A package manifest, review receipt, test result, package proof, or assistant summary cannot settle a package/review command unless it names an existing package command owner.",
  }
}

///|
fn package_review_flow_event_kind(event : Json) -> String {
  package_review_flow_json_string(event, "kind", default="")
}

///|
fn package_review_flow_event_action(event : Json) -> String {
  let command = package_review_flow_json_string(event, "command", default="")
  if command != "" {
    return command
  }
  let action = package_review_flow_json_string(event, "action", default="")
  if action != "" {
    return action
  }
  let packet = package_review_flow_json_object_field_or_empty(
    event, "command_packet",
  )
  package_review_flow_json_string(packet, "action", default="")
}

///|
fn package_review_flow_json_object_field_or_empty(
  json : Json,
  key : String,
) -> Json {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(value) => value
        None => Json::object({})
      }
    _ => Json::object({})
  }
}

///|
fn package_review_flow_json_string(
  json : Json,
  key : String,
  default~ : String,
) -> String {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(String(value)) => value
        _ => default
      }
    _ => default
  }
}

///|
fn package_review_flow_json_int(
  json : Json,
  key : String,
  default~ : Int,
) -> Int {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(Number(value, ..)) => value.to_int()
        Some(String(value)) => @string.parse_int(value) catch { _ => default }
        _ => default
      }
    _ => default
  }
}
