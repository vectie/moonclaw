///|
pub fn native_event_projection_contract_id() -> String {
  "mooncode-native-event-projection.v1"
}

///|
pub fn native_event_projection_contract_kind() -> String {
  "mooncode-native-event-projection-contract"
}

///|
pub fn native_event_projection_report_kind() -> String {
  "mooncode-native-runtime-contract-report"
}

///|
pub fn moonclaw_event_mapping_json() -> Json {
  {
    "AssistantMessageDelta": {
      "event": runtime_event_assistant_delta(),
      "lane": event_lane_transcript(),
      "status": "running",
    },
    "AssistantMessage": {
      "event": runtime_event_assistant_message(),
      "lane": event_lane_transcript(),
      "status": "done",
    },
    "PreToolCall": {
      "event": runtime_event_tool_call(),
      "lane": event_lane_tool(),
      "status": "running",
    },
    "PostToolCall": {
      "event": runtime_event_tool_result(),
      "lane": event_lane_tool(),
      "status": "done-or-failed",
    },
    "Cancelled": {
      "event": runtime_event_runtime_aborted(),
      "lane": event_lane_review(),
      "status": "failed",
    },
    "Failed": {
      "event": runtime_event_runtime_aborted(),
      "lane": event_lane_review(),
      "status": "failed",
    },
  }
}

///|
pub fn native_event_projection_command_scope_keys() -> Array[String] {
  ["command_id", "commandId", "mooncode_command_id"]
}

///|
pub fn native_event_projection_diagnostic_sources() -> Array[String] {
  ["moonclaw-native-moon-check-watcher"]
}

///|
pub fn native_event_projection_diagnostic_titles() -> Array[String] {
  ["MoonCode moon_check update"]
}

///|
pub fn native_event_has_command_scope(event : Json) -> Bool {
  let packet = native_event_json_object_field_or_empty(event, "command_packet")
  native_event_json_string(packet, "command_id", default="") != "" ||
  native_event_first_string(
    event,
    native_event_projection_command_scope_keys(),
    default="",
  ) !=
  ""
}

///|
pub fn native_event_is_diagnostic_only(event : Json) -> Bool {
  let kind = native_event_kind(event)
  let source = native_event_json_string(event, "source", default="")
  let title = native_event_json_string(event, "title", default="")
  runtime_diagnostic_event_name_is_supported(kind) ||
  native_event_projection_diagnostic_sources().contains(source) ||
  native_event_projection_diagnostic_titles().contains(title)
}

///|
pub fn native_event_requires_command_scope(event : Json) -> Bool {
  let lane = native_event_json_string(
    event,
    "lane",
    default=event_lane_default(),
  )
  let kind = native_event_kind(event)
  lane == event_lane_transcript() ||
  lane == event_lane_tool() ||
  lane == event_lane_diff() ||
  lane == event_lane_test() ||
  lane == event_lane_artifact() ||
  lane == event_lane_review() ||
  runtime_command_output_event_names().contains(kind) ||
  kind == "assistant" ||
  runtime_failure_event_name_is_supported(kind)
}

///|
pub fn native_event_is_transcript(event : Json) -> Bool {
  native_event_json_string(event, "lane", default="") == event_lane_transcript()
}

///|
pub fn native_event_is_progress(event : Json) -> Bool {
  let lane = native_event_json_string(event, "lane", default="")
  event_lane_is_progress(lane)
}

///|
pub fn native_event_projection_problem(event : Json, reason~ : String) -> Json {
  {
    "reason": reason,
    "id": native_event_json_string(event, "id", default=""),
    "lane": native_event_json_string(
      event,
      "lane",
      default=event_lane_default(),
    ),
    "kind": native_event_kind(event),
    "title": native_event_json_string(event, "title", default=""),
    "status": native_event_json_string(event, "status", default=""),
    "created_at": native_event_json_string(event, "created_at", default=""),
  }
}

///|
pub fn native_event_projection_report(
  native_report : Json,
  session_id~ : String,
  observed_at~ : String,
) -> Json {
  let events = native_event_json_array_items(native_report, "events")
  let problems : Array[Json] = []
  let mut scoped_count = 0
  let mut diagnostic_count = 0
  let mut unscoped_projection_count = 0
  let mut transcript_count = 0
  let mut progress_count = 0
  for event in events {
    if native_event_has_command_scope(event) {
      scoped_count += 1
    } else if native_event_is_diagnostic_only(event) {
      diagnostic_count += 1
    } else if native_event_requires_command_scope(event) {
      unscoped_projection_count += 1
      problems.push(
        native_event_projection_problem(
          event,
          reason="user-facing-native-event-without-command-scope",
        ),
      )
    } else {
      diagnostic_count += 1
    }
    if native_event_is_transcript(event) {
      transcript_count += 1
    } else if native_event_is_progress(event) {
      progress_count += 1
    }
  }
  let rejected_count = native_event_json_int(
    native_report,
    "rejected_count",
    default=0,
  )
  let status = if unscoped_projection_count > 0 {
    "unsafe"
  } else if events.length() == 0 && rejected_count > 0 {
    "rejected"
  } else {
    "projection-safe"
  }
  {
    "kind": native_event_projection_report_kind(),
    "protocol": protocol_version(),
    "projection_contract_id": native_event_projection_contract_id(),
    "session_id": session_id,
    "observed_at": observed_at,
    "status": status,
    "projection_safe": unscoped_projection_count == 0,
    "accepted_event_count": events.length(),
    "rejected_event_count": rejected_count,
    "command_scoped_event_count": scoped_count,
    "diagnostic_event_count": diagnostic_count,
    "unscoped_projection_event_count": unscoped_projection_count,
    "transcript_event_count": transcript_count,
    "progress_event_count": progress_count,
    "problems": Json::array(problems),
    "rule": "Accepted native runtime events may affect canonical chat only when they carry command_packet.command_id or direct command_id normalized into a command packet. Unscoped service, watcher, usage, and runtime-loop records remain diagnostics.",
    "owner": {
      "runtime": "moonclaw",
      "projection": "mooncode",
      "ui": "moondesk",
    },
  }
}

///|
pub fn native_events_for_canonical_projection(
  native_report : Json,
) -> Array[Json] {
  let events = native_event_json_array_items(native_report, "events")
  let projected : Array[Json] = []
  for event in events {
    if native_event_has_command_scope(event) ||
      native_event_is_diagnostic_only(event) {
      projected.push(event)
    }
  }
  projected
}

///|
pub fn native_event_projection_contract_json() -> Json {
  {
    "kind": native_event_projection_contract_kind(),
    "protocol": protocol_version(),
    "contract_id": native_event_projection_contract_id(),
    "runtime_owner": "moonclaw",
    "projection_owner": "mooncode",
    "ui_owner": "moondesk",
    "event_name_contract_id": runtime_event_name_contract_id(),
    "event_lane_contract_id": event_lane_contract_id(),
    "moonclaw_event_mapping": moonclaw_event_mapping_json(),
    "command_scope_keys": native_event_projection_command_scope_keys(),
    "diagnostic_events": runtime_diagnostic_event_names(),
    "diagnostic_sources": native_event_projection_diagnostic_sources(),
    "diagnostic_titles": native_event_projection_diagnostic_titles(),
    "user_visible_events_require_command_scope": [
      event_lane_transcript(),
      event_lane_tool(),
      event_lane_diff(),
      event_lane_test(),
      event_lane_artifact(),
      event_lane_review(),
      runtime_event_reasoning_delta(),
      runtime_event_reasoning_message(),
      runtime_event_runtime_update(),
      runtime_event_assistant_delta(),
      runtime_event_assistant_message(),
      runtime_event_tool_call(),
      runtime_event_tool_result(),
      "assistant",
    ],
    "rules": [
      "mooncode/core owns MoonClaw event mapping and native projection policy", "command-scoped native events may feed canonical conversation and progress projection",
      "diagnostic native events remain visible as diagnostics but do not settle chat turns",
      "unscoped user-visible native events are unsafe and must be reported before projection",
    ],
  }
}

///|
fn native_event_kind(event : Json) -> String {
  native_event_first_string(event, ["kind", "event"], default="")
}

///|
fn native_event_json_object_field(json : Json, key : String) -> Json? {
  match json {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn native_event_json_object_field_or_empty(json : Json, key : String) -> Json {
  match native_event_json_object_field(json, key) {
    Some(value) => value
    None => Json::object({})
  }
}

///|
fn native_event_json_array_items(json : Json, key : String) -> Array[Json] {
  match native_event_json_object_field(json, key) {
    Some(Array(values)) => values
    _ => []
  }
}

///|
fn native_event_first_string(
  json : Json,
  keys : Array[String],
  default~ : String,
) -> String {
  for key in keys {
    let value = native_event_json_string(json, key, default="")
    if value != "" {
      return value
    }
  }
  default
}

///|
fn native_event_json_string(
  json : Json,
  key : String,
  default~ : String,
) -> String {
  match native_event_json_object_field(json, key) {
    Some(String(value)) => value
    Some(value) => value.stringify()
    None => default
  }
}

///|
fn native_event_json_int(json : Json, key : String, default~ : Int) -> Int {
  match native_event_json_object_field(json, key) {
    Some(Number(value, ..)) => value.to_int()
    Some(String(value)) => @string.parse_int(value) catch { _ => default }
    _ => default
  }
}
