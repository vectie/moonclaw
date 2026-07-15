///|
fn mooncode_runtime_continuation_kind() -> String {
  "runtime.turn_checkpointed"
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
  now~ : @clock.Timestamp,
) -> Json {
  let approval_id = mooncode_json_string(approval, "approval_id", default="")
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-continuation-\{approval_id}",
    "protocol": mooncode_protocol_version(),
    "contract_id": @moonlib_conversation.control_contract_id(),
    "session_id": session_id,
    "command_id": command_id,
    "target_command_id": command_id,
    "lane": "runtime-control",
    "kind": mooncode_runtime_continuation_kind(),
    "event": mooncode_runtime_continuation_kind(),
    "state": "awaiting-approval",
    "status": "waiting",
    "approval_id": approval_id,
    "step_index": step_index,
    "tool_index": tool_index,
    "plan": plan,
    "planner_steps": Json::array(planner_steps),
    "tool_results": Json::array(tool_results),
    "step_results": Json::array(step_results),
    "approval": approval,
    "created_at": now,
    "source": "moonclaw-native-runtime-continuation",
  }
}

///|
fn mooncode_runtime_continuation_for_command(
  events : Array[Json],
  command_id : String,
) -> Json {
  let mut latest = Json::object({})
  for event in events {
    if mooncode_json_string(event, "kind", default="") ==
      mooncode_runtime_continuation_kind() &&
      mooncode_json_string(event, "command_id", default="") == command_id &&
      mooncode_json_string(event, "approval_id", default="") != "" {
      latest = event
    }
  }
  latest
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
  let plan = mooncode_json_object_field_or_empty(continuation, "plan")
  let tool_calls = mooncode_json_array_items(plan, "tool_calls")
  if approval_id == "" ||
    command_id == "" ||
    mooncode_json_string(continuation, "state", default="") !=
    "awaiting-approval" ||
    step_index < 0 ||
    tool_index < 0 ||
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
