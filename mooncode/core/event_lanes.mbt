///|
pub fn event_lane_contract_id() -> String {
  "mooncode-event-lanes.v1"
}

///|
pub fn event_lane_transcript() -> String {
  "transcript"
}

///|
pub fn event_lane_runtime() -> String {
  "runtime"
}

///|
pub fn event_lane_tool() -> String {
  "tool"
}

///|
pub fn event_lane_diff() -> String {
  "diff"
}

///|
pub fn event_lane_test() -> String {
  "test"
}

///|
pub fn event_lane_artifact() -> String {
  "artifact"
}

///|
pub fn event_lane_review() -> String {
  "review"
}

///|
pub fn event_lane_default() -> String {
  event_lane_runtime()
}

///|
pub fn event_lanes() -> Array[String] {
  [
    event_lane_transcript(),
    event_lane_runtime(),
    event_lane_tool(),
    event_lane_diff(),
    event_lane_test(),
    event_lane_artifact(),
    event_lane_review(),
  ]
}

///|
pub fn event_progress_lanes() -> Array[String] {
  [
    event_lane_runtime(),
    event_lane_tool(),
    event_lane_diff(),
    event_lane_test(),
    event_lane_artifact(),
    event_lane_review(),
  ]
}

///|
pub fn event_lane_is_supported(lane : String) -> Bool {
  event_lanes().contains(lane)
}

///|
pub fn event_lane_is_progress(lane : String) -> Bool {
  event_progress_lanes().contains(lane)
}

///|
pub fn event_lane_normalize(lane : String) -> String {
  if event_lane_is_supported(lane) {
    lane
  } else {
    event_lane_default()
  }
}

///|
pub fn event_lane_contract_json() -> Json {
  {
    "kind": "mooncode-event-lane-contract",
    "protocol": protocol_version(),
    "contract_id": event_lane_contract_id(),
    "default_lane": event_lane_default(),
    "lanes": event_lanes(),
    "progress_lanes": event_progress_lanes(),
    "rules": [
      "mooncode/core owns the supported event lane vocabulary", "internal MoonCode may emit lane values but must not own the supported lane list",
      "unknown lanes normalize to runtime before projection", "transcript is an event lane only; canonical conversation turns own chat rendering",
    ],
  }
}
