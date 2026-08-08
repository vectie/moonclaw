///|
fn mooncode_runtime_continuation_kind() -> String {
  "runtime.turn_checkpointed"
}

///|
/// Checkpoints retain the current plan's transcript once so the first
/// post-restart follow-up preserves model context. Historical planner steps
/// need only their selected calls and response metadata; duplicating the same
/// accumulated transcript in every step makes checkpoint records quadratic.
fn mooncode_runtime_compact_plan(plan : Json) -> Json {
  let compact : Map[String, Json] = {}
  match plan {
    Object(fields) =>
      for key, value in fields.iter2() {
        if key == "kind" ||
          key == "protocol" ||
          key == "planner_mode" ||
          key == "model" ||
          key == "failed" ||
          key == "tool_call_count" {
          compact[key] = value
        }
      }
    _ => ()
  }
  Json::object(compact)
}

///|
/// Persist references to already-journaled tool results instead of copying the
/// complete accumulated result history into every restart checkpoint.
fn mooncode_runtime_compact_continuation_history(
  planner_steps : Array[Json],
  tool_results : Array[Json],
  step_results : Array[Json],
) -> Json {
  let compact_planner_steps : Array[Json] = []
  for planner_step in planner_steps {
    compact_planner_steps.push(mooncode_runtime_compact_plan(planner_step))
  }
  let tool_result_references : Array[Json] = []
  for execution in tool_results {
    let event = mooncode_json_object_field_or_empty(execution, "event")
    let event_id = mooncode_json_string(event, "id", default="")
    let journaled_result = mooncode_json_string(event, "event", default="") ==
      "tool_result" &&
      event_id != ""
    if journaled_result {
      let compact_execution : Map[String, Json] = {}
      match execution {
        Object(fields) =>
          for key, value in fields.iter2() {
            if key != "result" && key != "event" {
              compact_execution[key] = value
            }
          }
        _ => ()
      }
      tool_result_references.push({
        "event_id": event_id,
        "event_digest": mooncode_goal_runtime_sha256_hex(event.stringify()),
        "execution": Json::object(compact_execution),
        "journaled_result": true,
      })
    } else {
      tool_result_references.push({
        "inline_execution": execution,
        "journaled_result": false,
      })
    }
  }
  {
    "planner_steps": Json::array(compact_planner_steps),
    "tool_result_count": tool_results.length(),
    "tool_result_digest": mooncode_goal_runtime_sha256_hex(
      Json::array(tool_results).stringify(),
    ),
    "tool_result_references": Json::array(tool_result_references),
    "step_result_suffix_count": step_results.length(),
  }
}

///|
fn mooncode_runtime_continuation_event(
  session_id : String,
  command_id : String,
  plan : Json,
  planner_steps : Array[Json],
  tool_results : Array[Json],
  step_results : Array[Json],
  approval : Json,
  step_index~ : Int,
  tool_index~ : Int,
  planner_turn_end_step~ : Int,
  now~ : @clock.Timestamp,
) -> Json {
  let approval_id = mooncode_json_string(approval, "approval_id", default="")
  let state = if approval_id == "" { "after-step" } else { "awaiting-approval" }
  let history = mooncode_runtime_compact_continuation_history(
    planner_steps, tool_results, step_results,
  )
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-continuation-\{state}-\{step_index}-\{tool_index}-\{approval_id}",
    "protocol": mooncode_protocol_version(),
    "contract_id": @moonlib_conversation.control_contract_id(),
    "session_id": session_id,
    "command_id": command_id,
    "target_command_id": command_id,
    "lane": "runtime-control",
    "kind": mooncode_runtime_continuation_kind(),
    "event": mooncode_runtime_continuation_kind(),
    "state": state,
    "status": if state == "awaiting-approval" {
      "waiting"
    } else {
      "running"
    },
    "approval_id": approval_id,
    "step_index": step_index,
    "tool_index": tool_index,
    "planner_turn_end_step": planner_turn_end_step,
    "plan": plan,
    "planner_steps": Json::array(
      mooncode_json_array_items(history, "planner_steps"),
    ),
    "tool_result_count": mooncode_json_int(
      history,
      "tool_result_count",
      default=0,
    ),
    "tool_result_digest": mooncode_json_string(
      history,
      "tool_result_digest",
      default="",
    ),
    "tool_result_references": Json::array(
      mooncode_json_array_items(history, "tool_result_references"),
    ),
    "step_result_suffix_count": mooncode_json_int(
      history,
      "step_result_suffix_count",
      default=0,
    ),
    "approval": approval,
    "created_at": now,
    "source": "moonclaw-native-runtime-continuation",
  }
}

///|
fn mooncode_runtime_planner_continuation_event(
  session_id : String,
  command_id : String,
  plan : Json,
  planner_steps : Array[Json],
  tool_results : Array[Json],
  step_results : Array[Json],
  next_step_index~ : Int,
  now~ : @clock.Timestamp,
) -> Json {
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-planner-checkpoint-\{next_step_index}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "target_command_id": command_id,
    "lane": "runtime-control",
    "kind": mooncode_runtime_continuation_kind(),
    "event": mooncode_runtime_continuation_kind(),
    "state": "planner-quantum-paused",
    "status": "paused",
    "reason": "planner-step-quantum",
    "next_step_index": next_step_index,
    "plan": plan,
    "planner_steps": Json::array(planner_steps),
    "tool_results": Json::array(tool_results),
    "step_results": Json::array(step_results),
    "created_at": now,
    "source": "moonclaw-native-runtime-continuation",
  }
}

///|
fn mooncode_runtime_planner_transport_continuation_event(
  session_id : String,
  command_id : String,
  plan : Json,
  planner_steps : Array[Json],
  tool_results : Array[Json],
  step_results : Array[Json],
  pending_live_steering : Array[Json],
  resume_mode~ : String,
  next_step_index~ : Int,
  detail~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-planner-transport-checkpoint-\{resume_mode}-\{next_step_index}-\{now}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "target_command_id": command_id,
    "lane": "runtime-control",
    "kind": mooncode_runtime_continuation_kind(),
    "event": mooncode_runtime_continuation_kind(),
    "state": "planner-transport-paused",
    "status": "paused",
    "reason": "planner-transport-interrupted",
    "resume_mode": resume_mode,
    "next_step_index": next_step_index,
    "plan": plan,
    "planner_steps": Json::array(planner_steps),
    "tool_results": Json::array(tool_results),
    "step_results": Json::array(step_results),
    "pending_live_steering": Json::array(pending_live_steering),
    "detail": detail,
    "created_at": now,
    "source": "moonclaw-native-runtime-continuation",
  }
}

///|
fn mooncode_runtime_planner_replan_continuation_event(
  session_id : String,
  command_id : String,
  plan : Json,
  finish_rejected~ : Bool,
  planner_steps : Array[Json],
  tool_results : Array[Json],
  step_results : Array[Json],
  next_step_index~ : Int,
  replan_count~ : Int,
  guidance~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  let history = mooncode_runtime_compact_continuation_history(
    planner_steps, tool_results, step_results,
  )
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-planner-replan-checkpoint-\{next_step_index}-\{replan_count}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "target_command_id": command_id,
    "lane": "runtime-control",
    "kind": mooncode_runtime_continuation_kind(),
    "event": mooncode_runtime_continuation_kind(),
    "state": "planner-replan-paused",
    "status": "paused",
    "reason": "planner-empty-followup",
    "next_step_index": next_step_index,
    "replan_count": replan_count,
    "patient_replan_guidance": guidance,
    "plan": plan,
    "finish_rejected": finish_rejected,
    "planner_steps": Json::array(
      mooncode_json_array_items(history, "planner_steps"),
    ),
    "tool_result_count": mooncode_json_int(
      history,
      "tool_result_count",
      default=0,
    ),
    "tool_result_digest": mooncode_json_string(
      history,
      "tool_result_digest",
      default="",
    ),
    "tool_result_references": Json::array(
      mooncode_json_array_items(history, "tool_result_references"),
    ),
    "step_result_suffix_count": mooncode_json_int(
      history,
      "step_result_suffix_count",
      default=0,
    ),
    "created_at": now,
    "source": "moonclaw-native-runtime-continuation",
  }
}

///|
fn mooncode_runtime_unproject_journal_event(event : Json) -> Json {
  match event {
    Object(fields) => {
      let normalized : Map[String, Json] = {}
      for key, value in fields.iter2() {
        if key != "journal_sequence" {
          normalized[key] = value
        }
      }
      Json::object(normalized)
    }
    _ => event
  }
}

///|
fn mooncode_runtime_continuation_for_command(
  events : Array[Json],
  command_id : String,
) -> Json {
  // Select the latest checkpoint first. Hydrating every historical checkpoint
  // makes recovery quadratic: each checkpoint used to rescan and stringify all
  // preceding tool-result events. Long visual-agent runs can contain hundreds
  // of checkpoints, so only the authoritative latest one is relevant.
  let mut checkpoint = Json::object({})
  for event in events {
    if mooncode_json_string(event, "kind", default="") ==
      mooncode_runtime_continuation_kind() &&
      mooncode_json_string(event, "command_id", default="") == command_id {
      checkpoint = event
    }
  }
  let result_count = mooncode_json_int(
    checkpoint,
    "tool_result_count",
    default=-1,
  )
  if result_count < 0 {
    return checkpoint
  }
  let references = mooncode_json_array_items(
    checkpoint, "tool_result_references",
  )
  if references.length() != result_count {
    return Json::object({})
  }
  let expected_digests : Map[String, String] = {}
  for reference in references {
    if mooncode_json_bool(reference, "journaled_result", default=false) {
      let event_id = mooncode_json_string(reference, "event_id", default="")
      let event_digest = mooncode_json_string(
        reference,
        "event_digest",
        default="",
      )
      if event_id == "" || event_digest == "" {
        return Json::object({})
      }
      expected_digests[event_id] = event_digest
    }
  }
  let matched_events : Map[String, Json] = {}
  let match_counts : Map[String, Int] = {}
  for projected_event in events {
    if mooncode_json_string(projected_event, "command_id", default="") !=
      command_id {
      continue
    }
    let event_id = mooncode_json_string(projected_event, "id", default="")
    match expected_digests.get(event_id) {
      Some(expected_digest) => {
        let referenced_event = mooncode_runtime_unproject_journal_event(
          projected_event,
        )
        if mooncode_goal_runtime_sha256_hex(referenced_event.stringify()) ==
          expected_digest {
          let previous = match match_counts.get(event_id) {
            Some(value) => value
            None => 0
          }
          match_counts[event_id] = previous + 1
          matched_events[event_id] = referenced_event
        }
      }
      None => ()
    }
  }
  let hydrated_results : Array[Json] = []
  for reference in references {
    if mooncode_json_bool(reference, "journaled_result", default=false) {
      let event_id = mooncode_json_string(reference, "event_id", default="")
      match (match_counts.get(event_id), matched_events.get(event_id)) {
        (Some(1), Some(matched_event)) => {
          let with_result = mooncode_json_object_with_field(
            mooncode_json_object_field_or_empty(reference, "execution"),
            "result",
            mooncode_json_object_field_or_empty(matched_event, "tool_result"),
          )
          hydrated_results.push(
            mooncode_json_object_with_field(with_result, "event", matched_event),
          )
        }
        _ => return Json::object({})
      }
    } else {
      match reference {
        Object(fields) =>
          if fields.contains("inline_execution") {
            hydrated_results.push(
              mooncode_json_object_field_or_empty(reference, "inline_execution"),
            )
          }
        _ => ()
      }
    }
  }
  if hydrated_results.length() != result_count {
    return Json::object({})
  }
  let suffix_count = mooncode_json_int(
    checkpoint,
    "step_result_suffix_count",
    default=-1,
  )
  let expected_digest = mooncode_json_string(
    checkpoint,
    "tool_result_digest",
    default="",
  )
  if suffix_count < 0 ||
    suffix_count > result_count ||
    expected_digest == "" ||
    mooncode_goal_runtime_sha256_hex(Json::array(hydrated_results).stringify()) !=
    expected_digest {
    return Json::object({})
  }
  let hydrated_steps = mooncode_json_array_items(checkpoint, "planner_steps")
  if hydrated_steps.is_empty() {
    return Json::object({})
  }
  hydrated_steps[hydrated_steps.length() - 1] = mooncode_json_object_field_or_empty(
    checkpoint, "plan",
  )
  let mut hydrated = mooncode_json_object_with_field(
    checkpoint,
    "planner_steps",
    Json::array(hydrated_steps),
  )
  hydrated = mooncode_json_object_with_field(
    hydrated,
    "tool_results",
    Json::array(hydrated_results),
  )
  mooncode_json_object_with_field(
    hydrated,
    "step_results",
    Json::array(hydrated_results[result_count - suffix_count:].to_owned()),
  )
}

///|
fn mooncode_runtime_continuation_is_active(continuation : Json) -> Bool {
  let approval_id = mooncode_json_string(
    continuation,
    "approval_id",
    default="",
  )
  let command_id = mooncode_json_string(continuation, "command_id", default="")
  let step_index = mooncode_json_int(continuation, "step_index", default=-1)
  let tool_index = mooncode_json_int(continuation, "tool_index", default=-1)
  let planner_turn_end_step = mooncode_json_int(
    continuation,
    "planner_turn_end_step",
    default=0,
  )
  let plan = mooncode_json_object_field_or_empty(continuation, "plan")
  let tool_calls = mooncode_json_array_items(plan, "tool_calls")
  if command_id == "" ||
    step_index < 0 ||
    planner_turn_end_step < 0 ||
    (planner_turn_end_step > 0 && planner_turn_end_step <= step_index) ||
    tool_index < 0 ||
    tool_index > tool_calls.length() {
    return false
  }
  if mooncode_json_string(continuation, "state", default="") == "after-step" {
    return approval_id == "" && tool_index == tool_calls.length()
  }
  if approval_id == "" ||
    mooncode_json_string(continuation, "state", default="") !=
    "awaiting-approval" ||
    tool_index >= tool_calls.length() {
    return false
  }
  let approval = mooncode_json_object_field_or_empty(continuation, "approval")
  mooncode_json_string(approval, "approval_id", default="") == approval_id &&
  mooncode_json_string(approval, "target_command_id", default="") == command_id &&
  mooncode_runtime_tool_approval_id(
    command_id,
    tool_calls[tool_index],
    occurrence=step_index * 1000 + tool_index,
  ) ==
  approval_id
}

///|
fn mooncode_runtime_json_array_has_suffix(
  values : Array[Json],
  suffix : Array[Json],
) -> Bool {
  if suffix.length() > values.length() {
    return false
  }
  let offset = values.length() - suffix.length()
  for index, value in suffix {
    if values[offset + index].stringify() != value.stringify() {
      return false
    }
  }
  true
}

///|
fn mooncode_runtime_planner_continuation_is_active(continuation : Json) -> Bool {
  let session_id = mooncode_json_string(continuation, "session_id", default="")
  let command_id = mooncode_json_string(continuation, "command_id", default="")
  let next_step_index = mooncode_json_int(
    continuation,
    "next_step_index",
    default=-1,
  )
  let plan = mooncode_json_object_field_or_empty(continuation, "plan")
  let tool_calls = mooncode_json_array_items(plan, "tool_calls")
  let planner_steps = mooncode_json_array_items(continuation, "planner_steps")
  let tool_results = mooncode_json_array_items(continuation, "tool_results")
  let step_results = mooncode_json_array_items(continuation, "step_results")
  let expected_id = "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-planner-checkpoint-\{next_step_index}"
  if session_id == "" ||
    command_id == "" ||
    mooncode_json_string(continuation, "id", default="") != expected_id ||
    mooncode_json_string(continuation, "protocol", default="") !=
    mooncode_protocol_version() ||
    mooncode_json_string(continuation, "target_command_id", default="") !=
    command_id ||
    mooncode_json_string(continuation, "kind", default="") !=
    mooncode_runtime_continuation_kind() ||
    mooncode_json_string(continuation, "lane", default="") != "runtime-control" ||
    mooncode_json_string(continuation, "status", default="") != "paused" ||
    mooncode_json_string(continuation, "reason", default="") !=
    "planner-step-quantum" ||
    mooncode_json_string(continuation, "state", default="") !=
    "planner-quantum-paused" ||
    next_step_index <= 0 ||
    mooncode_json_string(plan, "planner_mode", default="") !=
    mooncode_planner_mode_model_tool_calls() ||
    mooncode_json_bool(plan, "failed", default=false) ||
    tool_calls.length() == 0 ||
    mooncode_runtime_turn_tool_calls_include_finish(tool_calls) ||
    planner_steps.length() != next_step_index ||
    step_results.length() != tool_calls.length() ||
    !mooncode_runtime_turn_model_message_present(
      mooncode_json_object_field_or_empty(plan, "model_response_message"),
    ) ||
    mooncode_json_array_items(plan, "model_messages").length() == 0 ||
    !mooncode_runtime_json_array_has_suffix(tool_results, step_results) {
    return false
  }
  planner_steps[planner_steps.length() - 1].stringify() == plan.stringify()
}

///|
fn mooncode_runtime_planner_transport_continuation_is_active(
  continuation : Json,
) -> Bool {
  let session_id = mooncode_json_string(continuation, "session_id", default="")
  let command_id = mooncode_json_string(continuation, "command_id", default="")
  let next_step_index = mooncode_json_int(
    continuation,
    "next_step_index",
    default=-1,
  )
  let resume_mode = mooncode_json_string(
    continuation,
    "resume_mode",
    default="",
  )
  let plan = mooncode_json_object_field_or_empty(continuation, "plan")
  let tool_calls = mooncode_json_array_items(plan, "tool_calls")
  let planner_steps = mooncode_json_array_items(continuation, "planner_steps")
  let tool_results = mooncode_json_array_items(continuation, "tool_results")
  let step_results = mooncode_json_array_items(continuation, "step_results")
  let event_id = mooncode_json_string(continuation, "id", default="")
  let expected_id_prefix = "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-planner-transport-checkpoint-\{resume_mode}-\{next_step_index}-"
  if session_id == "" ||
    command_id == "" ||
    !event_id.has_prefix(expected_id_prefix) ||
    mooncode_json_string(continuation, "protocol", default="") !=
    mooncode_protocol_version() ||
    mooncode_json_string(continuation, "target_command_id", default="") !=
    command_id ||
    mooncode_json_string(continuation, "kind", default="") !=
    mooncode_runtime_continuation_kind() ||
    mooncode_json_string(continuation, "lane", default="") != "runtime-control" ||
    mooncode_json_string(continuation, "status", default="") != "paused" ||
    mooncode_json_string(continuation, "reason", default="") !=
    "planner-transport-interrupted" ||
    mooncode_json_string(continuation, "state", default="") !=
    "planner-transport-paused" ||
    next_step_index < 0 {
    return false
  }
  match resume_mode {
    "initial" =>
      next_step_index == 0 &&
      planner_steps.length() == 0 &&
      step_results.length() == 0
    "followup" =>
      next_step_index > 0 &&
      mooncode_json_string(plan, "planner_mode", default="") ==
      mooncode_planner_mode_model_tool_calls() &&
      !mooncode_json_bool(plan, "failed", default=false) &&
      !mooncode_json_bool(plan, "transient_transport_close", default=false) &&
      tool_calls.length() > 0 &&
      !mooncode_runtime_turn_tool_calls_include_finish(tool_calls) &&
      planner_steps.length() == next_step_index &&
      step_results.length() == tool_calls.length() &&
      mooncode_runtime_turn_model_message_present(
        mooncode_json_object_field_or_empty(plan, "model_response_message"),
      ) &&
      mooncode_json_array_items(plan, "model_messages").length() > 0 &&
      mooncode_runtime_json_array_has_suffix(tool_results, step_results) &&
      planner_steps[planner_steps.length() - 1].stringify() == plan.stringify()
    _ => false
  }
}

///|
fn mooncode_runtime_planner_replan_continuation_is_active(
  continuation : Json,
) -> Bool {
  let session_id = mooncode_json_string(continuation, "session_id", default="")
  let command_id = mooncode_json_string(continuation, "command_id", default="")
  let next_step_index = mooncode_json_int(
    continuation,
    "next_step_index",
    default=-1,
  )
  let replan_count = mooncode_json_int(continuation, "replan_count", default=0)
  let guidance = mooncode_json_string(
    continuation,
    "patient_replan_guidance",
    default="",
  )
  let plan = mooncode_json_object_field_or_empty(continuation, "plan")
  let tool_calls = mooncode_json_array_items(plan, "tool_calls")
  let planner_steps = mooncode_json_array_items(continuation, "planner_steps")
  let tool_results = mooncode_json_array_items(continuation, "tool_results")
  let step_results = mooncode_json_array_items(continuation, "step_results")
  let expected_id = "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-planner-replan-checkpoint-\{next_step_index}-\{replan_count}"
  session_id != "" &&
  command_id != "" &&
  mooncode_json_string(continuation, "id", default="") == expected_id &&
  mooncode_json_string(continuation, "protocol", default="") ==
  mooncode_protocol_version() &&
  mooncode_json_string(continuation, "target_command_id", default="") ==
  command_id &&
  mooncode_json_string(continuation, "kind", default="") ==
  mooncode_runtime_continuation_kind() &&
  mooncode_json_string(continuation, "lane", default="") == "runtime-control" &&
  mooncode_json_string(continuation, "status", default="") == "paused" &&
  mooncode_json_string(continuation, "reason", default="") ==
  "planner-empty-followup" &&
  mooncode_json_string(continuation, "state", default="") ==
  "planner-replan-paused" &&
  next_step_index > 0 &&
  replan_count > 0 &&
  guidance != "" &&
  mooncode_json_string(plan, "planner_mode", default="") ==
  mooncode_planner_mode_model_tool_calls() &&
  !mooncode_json_bool(plan, "failed", default=false) &&
  tool_calls.length() > 0 &&
  (if mooncode_runtime_turn_tool_calls_include_finish(tool_calls) {
    mooncode_json_bool(continuation, "finish_rejected", default=false) &&
    tool_calls.length() == 1 &&
    mooncode_json_string(tool_calls[0], "tool", default="") == "finish"
  } else {
    !mooncode_json_bool(continuation, "finish_rejected", default=false)
  }) &&
  planner_steps.length() == next_step_index &&
  step_results.length() == tool_calls.length() &&
  mooncode_runtime_turn_model_message_present(
    mooncode_json_object_field_or_empty(plan, "model_response_message"),
  ) &&
  mooncode_json_array_items(plan, "model_messages").length() > 0 &&
  mooncode_runtime_json_array_has_suffix(tool_results, step_results) &&
  planner_steps[planner_steps.length() - 1].stringify() == plan.stringify()
}
