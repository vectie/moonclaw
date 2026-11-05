///|
fn mooncode_runtime_continuation_kind() -> String {
  "runtime.turn_checkpointed"
}

///|
priv struct MoonCodeToolResume {
  step_index : Int32
  tool_index : Int32
  turn_end_step : Int32
  executing : Bool
  approval : Json?
}

///|
/// Decoded positions in the existing loop, not an additional execution machine.
priv enum MoonCodeResumePoint {
  ResumeTools(MoonCodeToolResume)
  ResumePlanner(Int32)
  ResumeTransport(Bool, Int32)
  ResumeReplan(Int32)
}

///|
fn mooncode_runtime_resume_point(checkpoint : Json) -> MoonCodeResumePoint? {
  let command_id = mooncode_json_string(checkpoint, "command_id", default="")
  if command_id == "" ||
    mooncode_json_string(checkpoint, "session_id", default="") == "" ||
    mooncode_json_string(checkpoint, "target_command_id", default="") !=
    command_id ||
    mooncode_json_string(checkpoint, "protocol", default="") !=
    mooncode_protocol_version() ||
    mooncode_json_string(checkpoint, "kind", default="") !=
    mooncode_runtime_continuation_kind() ||
    mooncode_json_string(checkpoint, "lane", default="") != "runtime-control" {
    return None
  }
  let state = mooncode_json_string(checkpoint, "state", default="")
  let plan = mooncode_json_object_field_or_empty(checkpoint, "plan")
  let calls = mooncode_json_array_items(plan, "tool_calls")
  match state {
    "executing-tool" | "after-step" | "awaiting-approval" => {
      let step = mooncode_json_int(checkpoint, "step_index", default=-1)
      let tool = mooncode_json_int(checkpoint, "tool_index", default=-1)
      let end = mooncode_json_int(
        checkpoint,
        "planner_turn_end_step",
        default=-1,
      )
      if step < 0 ||
        tool < 0 ||
        tool > calls.length() ||
        end < 0 ||
        (end > 0 && end <= step) {
        return None
      }
      let approval_id = mooncode_json_string(
        checkpoint,
        "approval_id",
        default="",
      )
      let approval = match state {
        "after-step" => {
          if approval_id != "" || tool != calls.length() {
            return None
          }
          None
        }
        "executing-tool" => {
          if approval_id != "" || tool >= calls.length() {
            return None
          }
          None
        }
        _ => {
          if approval_id == "" || tool >= calls.length() {
            return None
          }
          let approval = mooncode_json_object_field_or_empty(
            checkpoint, "approval",
          )
          if mooncode_json_string(approval, "approval_id", default="") !=
            approval_id ||
            mooncode_json_string(approval, "target_command_id", default="") !=
            command_id ||
            mooncode_runtime_tool_approval_id(
              command_id,
              calls[tool],
              occurrence=step * 1000 + tool,
            ) !=
            approval_id {
            return None
          }
          Some(approval)
        }
      }
      return Some(
        ResumeTools({
          step_index: step,
          tool_index: tool,
          turn_end_step: end,
          executing: state == "executing-tool",
          approval,
        }),
      )
    }
    "planner-quantum-paused"
    | "planner-transport-paused"
    | "planner-replan-paused" => ()
    _ => return None
  }
  let next = mooncode_json_int(checkpoint, "next_step_index", default=-1)
  let steps = mooncode_json_array_items(checkpoint, "planner_steps")
  let results = mooncode_json_array_items(checkpoint, "tool_results")
  let suffix = mooncode_json_array_items(checkpoint, "step_results")
  if next < 0 ||
    mooncode_json_string(checkpoint, "status", default="") != "paused" {
    return None
  }
  if state == "planner-transport-paused" &&
    mooncode_json_string(checkpoint, "resume_mode", default="") == "initial" {
    return if next == 0 &&
      steps.is_empty() &&
      results.is_empty() &&
      suffix.is_empty() {
      Some(ResumeTransport(true, 0))
    } else {
      None
    }
  }
  if next == 0 ||
    steps.length() != next ||
    calls.is_empty() ||
    suffix.length() != calls.length() ||
    mooncode_json_string(plan, "planner_mode", default="") !=
    mooncode_planner_mode_model_tool_calls() ||
    mooncode_json_bool(plan, "failed", default=false) ||
    !mooncode_runtime_turn_model_message_present(
      mooncode_json_object_field_or_empty(plan, "model_response_message"),
    ) ||
    mooncode_json_array_items(plan, "model_messages").is_empty() ||
    !mooncode_runtime_json_array_has_suffix(results, suffix) {
    return None
  }
  let has_finish = mooncode_runtime_turn_tool_calls_include_finish(calls)
  match state {
    "planner-quantum-paused" =>
      if has_finish {
        None
      } else {
        Some(ResumePlanner(next))
      }
    "planner-transport-paused" =>
      if has_finish ||
        mooncode_json_string(checkpoint, "resume_mode", default="") !=
        "followup" ||
        mooncode_json_bool(plan, "transient_transport_close", default=false) {
        None
      } else {
        Some(ResumeTransport(false, next))
      }
    _ => {
      let rejected = mooncode_json_bool(
        checkpoint,
        "finish_rejected",
        default=false,
      )
      if mooncode_json_int(checkpoint, "replan_count", default=0) <= 0 ||
        (if has_finish {
          !rejected ||
          calls.length() != 1 ||
          mooncode_json_string(calls[0], "tool", default="") != "finish"
        } else {
          rejected
        }) {
        None
      } else {
        Some(ResumeReplan(next))
      }
    }
  }
}

///|
/// Checkpoints retain the current plan's transcript once so the first
/// post-restart follow-up preserves model context. Historical planner steps
/// need only their selected calls and response metadata; duplicating the same
/// accumulated transcript in every step makes checkpoint records quadratic.
fn mooncode_runtime_compact_plan(plan : Json) -> Json {
  let compact : Map[String, Json] = Map([])
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
    if event_id != "" &&
      event is { "execution": Object(_), "tool_result": Object(_), .. } {
      tool_result_references.push({
        "event_id": event_id,
        "event_digest": mooncode_sha256_hex(event.stringify()),
      })
    } else {
      tool_result_references.push({ "inline_execution": execution })
    }
  }
  {
    "planner_steps": Json::array(compact_planner_steps),
    "tool_result_count": tool_results.length(),
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
  step_index~ : Int32,
  tool_index~ : Int32,
  planner_turn_end_step~ : Int32,
  now~ : @clock.Timestamp,
) -> Json {
  let approval_id = mooncode_json_string(approval, "approval_id", default="")
  let state = if approval_id != "" {
    "awaiting-approval"
  } else if tool_index < mooncode_json_array_items(plan, "tool_calls").length() {
    "executing-tool"
  } else {
    "after-step"
  }
  mooncode_runtime_checkpoint_event(
    session_id,
    command_id,
    plan,
    planner_steps,
    tool_results,
    step_results,
    {
      "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-continuation-\{state}-\{step_index}-\{tool_index}-\{approval_id}",
      "contract_id": @moonlib_conversation.control_contract_id(),
      "state": state,
      "status": if approval_id == "" {
        "running"
      } else {
        "waiting"
      },
      "approval_id": approval_id,
      "approval": approval,
      "step_index": step_index,
      "tool_index": tool_index,
      "planner_turn_end_step": planner_turn_end_step,
    },
    now~,
  )
}

///|
fn mooncode_runtime_planner_continuation_event(
  session_id : String,
  command_id : String,
  plan : Json,
  planner_steps : Array[Json],
  tool_results : Array[Json],
  step_results : Array[Json],
  next_step_index~ : Int32,
  now~ : @clock.Timestamp,
) -> Json {
  mooncode_runtime_checkpoint_event(
    session_id,
    command_id,
    plan,
    planner_steps,
    tool_results,
    step_results,
    {
      "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-planner-checkpoint-\{next_step_index}",
      "state": "planner-quantum-paused",
      "reason": "planner-step-quantum",
      "status": "paused",
      "next_step_index": next_step_index,
    },
    now~,
  )
}

///|
/// A planner pause retains the last executable plan, never the failed or empty
/// response. Both resumed and in-quantum rounds use the same checkpoint shape.
fn mooncode_runtime_planner_pause_event(
  session_id : String,
  command_id : String,
  response : Json,
  previous_plan : Json,
  planner_steps : Array[Json],
  tool_results : Array[Json],
  step_results : Array[Json],
  live_steering : Array[Json],
  next_step_index~ : Int32,
  replan_count~ : Int32,
  now~ : @clock.Timestamp,
) -> (Json, String)? {
  let (details, reason) : (Json, String) = if mooncode_json_bool(
      response,
      "transient_transport_close",
      default=false,
    ) {
    let resume_mode = if planner_steps.is_empty() {
      "initial"
    } else {
      "followup"
    }
    (
      {
        "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-planner-transport-checkpoint-\{resume_mode}-\{next_step_index}-\{now}",
        "state": "planner-transport-paused",
        "reason": "planner-transport-interrupted",
        "status": "paused",
        "resume_mode": resume_mode,
        "next_step_index": next_step_index,
        "pending_live_steering": Json::array(live_steering),
        "detail": mooncode_json_string(response, "message", default=""),
      },
      "planner-transport-interrupted",
    )
  } else if mooncode_json_bool(response, "patient_replan", default=false) {
    let replan_count = replan_count + 1
    (
      {
        "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-planner-replan-checkpoint-\{next_step_index}-\{replan_count}",
        "state": "planner-replan-paused",
        "reason": "planner-empty-followup",
        "status": "paused",
        "next_step_index": next_step_index,
        "replan_count": replan_count,
        "patient_replan_guidance": mooncode_json_string(
          response,
          "patient_replan_guidance",
          default="",
        ),
        "finish_rejected": mooncode_runtime_turn_tool_calls_include_finish(
          mooncode_json_array_items(previous_plan, "tool_calls"),
        ),
      },
      "planner-empty-followup",
    )
  } else {
    return None
  }
  Some(
    (
      mooncode_runtime_checkpoint_event(
        session_id,
        command_id,
        previous_plan,
        planner_steps,
        tool_results,
        step_results,
        details,
        now~,
      ),
      reason,
    ),
  )
}

///|
fn mooncode_runtime_unproject_journal_event(event : Json) -> Json {
  match event {
    Object(fields) => {
      let normalized : Map[String, Json] = Map([])
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
) -> Json raise MoonCodeJournalError {
  // Select the latest checkpoint first. Hydrating every historical checkpoint
  // makes recovery quadratic: each checkpoint used to rescan and stringify all
  // preceding tool-result events. Long visual-agent runs can contain hundreds
  // of checkpoints, so only the authoritative latest one is relevant.
  let mut checkpoint = Json::object({})
  let mut checkpoint_index = -1
  for index, event in events {
    if mooncode_json_string(event, "kind", default="") ==
      mooncode_runtime_continuation_kind() &&
      mooncode_json_string(event, "command_id", default="") == command_id {
      checkpoint = event
      checkpoint_index = index
    }
  }
  if checkpoint_index < 0 {
    return checkpoint
  }
  let result_count = mooncode_json_int(
    checkpoint,
    "tool_result_count",
    default=-1,
  )
  if result_count < 0 {
    raise InvalidJournal("checkpoint has no result reference count")
  }
  let references = mooncode_json_array_items(
    checkpoint, "tool_result_references",
  )
  if references.length() != result_count {
    raise InvalidJournal("checkpoint result references are inconsistent")
  }
  let expected_digests : Map[String, String] = Map([])
  for reference in references {
    if reference is { "event_id": String(_), .. } {
      let event_id = mooncode_json_string(reference, "event_id", default="")
      let event_digest = mooncode_json_string(
        reference,
        "event_digest",
        default="",
      )
      if event_id == "" || event_digest == "" {
        raise InvalidJournal("checkpoint result references are inconsistent")
      }
      if expected_digests.contains(event_id) {
        raise InvalidJournal("checkpoint repeats a result reference")
      }
      expected_digests[event_id] = event_digest
    }
  }
  let matched_events : Map[String, Json] = Map([])
  let match_counts : Map[String, Int32] = Map([])
  let event_positions : Map[String, Int32] = Map([])
  for index, projected_event in events[:checkpoint_index] {
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
        if mooncode_sha256_hex(referenced_event.stringify()) == expected_digest {
          let previous = match match_counts.get(event_id) {
            Some(value) => value
            None => 0
          }
          match_counts[event_id] = previous + 1
          matched_events[event_id] = referenced_event
          event_positions[event_id] = index
        }
      }
      None => ()
    }
  }
  let hydrated_results : Array[Json] = []
  let mut previous_position = -1
  for reference in references {
    if reference is { "event_id": String(_), .. } {
      let event_id = mooncode_json_string(reference, "event_id", default="")
      let position = event_positions.get_or_default(event_id, -1)
      if position <= previous_position {
        raise InvalidJournal("checkpoint result references are out of order")
      }
      previous_position = position
      match (match_counts.get(event_id), matched_events.get(event_id)) {
        (Some(1), Some(matched_event)) =>
          hydrated_results.push(
            mooncode_tool_execution_from_event(matched_event),
          )
        _ =>
          raise InvalidJournal("checkpoint result references are inconsistent")
      }
    } else {
      match reference {
        { "inline_execution": _, .. } =>
          hydrated_results.push(
            mooncode_json_object_field_or_empty(reference, "inline_execution"),
          )
        _ => ()
      }
    }
  }
  if hydrated_results.length() != result_count {
    raise InvalidJournal("checkpoint result references are inconsistent")
  }
  let suffix_count = mooncode_json_int(
    checkpoint,
    "step_result_suffix_count",
    default=-1,
  )
  if suffix_count < 0 || suffix_count > result_count {
    raise InvalidJournal("checkpoint result suffix is inconsistent")
  }
  let hydrated_steps = mooncode_json_array_items(checkpoint, "planner_steps")
  if !hydrated_steps.is_empty() {
    hydrated_steps[hydrated_steps.length() - 1] = mooncode_json_object_field_or_empty(
      checkpoint, "plan",
    )
  }
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
fn mooncode_runtime_json_array_has_suffix(
  values : Array[Json],
  suffix : Array[Json],
) -> Bool {
  if suffix.length() > values.length() {
    return false
  }
  let offset = values.length() - suffix.length()
  for index, value in suffix {
    if values[offset + index] != value {
      return false
    }
  }
  true
}

///|
fn mooncode_runtime_checkpoint_event(
  session_id : String,
  command_id : String,
  plan : Json,
  planner_steps : Array[Json],
  tool_results : Array[Json],
  step_results : Array[Json],
  details : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let history = mooncode_runtime_compact_continuation_history(
    planner_steps, tool_results, step_results,
  )
  let fields : Map[String, Json] = {
    "protocol": Json(mooncode_protocol_version()),
    "session_id": Json(session_id),
    "command_id": Json(command_id),
    "target_command_id": Json(command_id),
    "lane": Json("runtime-control"),
    "kind": Json(mooncode_runtime_continuation_kind()),
    "event": Json(mooncode_runtime_continuation_kind()),
    "plan": plan,
    "created_at": now.to_json(),
    "source": Json("moonclaw-native-runtime-continuation"),
  }
  if history is Object(h) {
    for key, value in h {
      fields[key] = value
    }
  }
  if details is Object(d) {
    for key, value in d {
      fields[key] = value
    }
  }
  Json::object(fields)
}
