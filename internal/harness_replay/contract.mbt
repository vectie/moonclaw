///|
pub(all) suberror HarnessReplayError {
  InvalidFixture(String)
} derive(Debug)

///|
const HARNESS_REPLAY_FIXTURE_CONTRACT : String = "moonclaw.harness-replay-fixture.v1"

///|
const HARNESS_REPLAY_REPORT_CONTRACT : String = "moonclaw.harness-replay-report.v1"

///|
const HARNESS_PHASE_METRICS_CONTRACT : String = "moonclaw.harness-phase-metrics.v1"

///|
fn harness_replay_invalid(code : String) -> Unit raise HarnessReplayError {
  raise InvalidFixture(code)
}

///|
fn harness_replay_field(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn harness_replay_string(value : Json, key : String) -> String {
  match harness_replay_field(value, key) {
    Some(String(text)) => text
    _ => ""
  }
}

///|
fn harness_replay_bool(value : Json, key : String) -> Bool? {
  match harness_replay_field(value, key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
fn harness_replay_int(value : Json, key : String) -> Int? {
  match harness_replay_field(value, key) {
    Some(encoded) => Some(@json.from_json(encoded)) catch { _ => None }
    None => None
  }
}

///|
fn harness_replay_array(value : Json, key : String) -> Array[Json] {
  match harness_replay_field(value, key) {
    Some(Array(items)) => items
    _ => []
  }
}

///|
fn harness_replay_object(value : Json, key : String) -> Json {
  match harness_replay_field(value, key) {
    Some(Object(_) as object) => object
    _ => Json::empty_object()
  }
}

///|
fn harness_replay_required_int(
  value : Json,
  key : String,
) -> Int raise HarnessReplayError {
  match harness_replay_int(value, key) {
    Some(number) => number
    None => {
      harness_replay_invalid("missing-or-invalid-integer:\{key}")
      0
    }
  }
}

///|
fn harness_replay_required_bool(
  value : Json,
  key : String,
) -> Bool raise HarnessReplayError {
  match harness_replay_bool(value, key) {
    Some(flag) => flag
    None => {
      harness_replay_invalid("missing-or-invalid-boolean:\{key}")
      false
    }
  }
}

///|
fn harness_replay_known_cohorts() -> Array[String] {
  [
    "read_only_inspection", "generic_edit", "moonbit_validation", "ui_browser", "delegated_workers",
    "long_context_follow_up", "failure_retry",
  ]
}

///|
fn harness_replay_known_outcomes() -> Array[String] {
  ["selected", "no_tool_calls", "recovered", "failed"]
}
