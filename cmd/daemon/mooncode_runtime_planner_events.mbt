///|
fn mooncode_runtime_turn_planner_progress_events(
  session_id : String,
  command_id : String,
  plan : Json,
  tool_calls : Array[Json],
  step_index~ : Int,
  now~ : @clock.Timestamp,
) -> Array[Json] {
  let step = step_index + 1
  let mode = mooncode_json_string(
    plan,
    "planner_mode",
    default=mooncode_planner_mode_deterministic_fallback(),
  )
  let model = mooncode_json_string(plan, "model", default="")
  let events : Array[Json] = [
    mooncode_runtime_turn_reasoning_event(
      session_id,
      command_id,
      step~,
      mode~,
      model~,
      tool_count=tool_calls.length(),
      now~,
    ),
  ]
  let response_message = mooncode_json_object_field_or_empty(
    plan, "model_response_message",
  )
  let assistant_content = mooncode_json_string(
    response_message,
    "content",
    default="",
  )
  if assistant_content != "" {
    events.push(
      mooncode_runtime_turn_assistant_event(
        session_id,
        command_id,
        step~,
        content=assistant_content,
        now~,
      ),
    )
  }
  for index in 0..<tool_calls.length() {
    if mooncode_json_string(tool_calls[index], "tool", default="") != "finish" {
      events.push(
        mooncode_runtime_turn_tool_call_event(
          session_id,
          command_id,
          tool_calls[index],
          step~,
          index~,
          mode~,
          model~,
          now~,
        ),
      )
    }
  }
  events
}

///|
fn mooncode_runtime_turn_reasoning_event(
  session_id : String,
  command_id : String,
  step~ : Int,
  mode~ : String,
  model~ : String,
  tool_count~ : Int,
  now~ : @clock.Timestamp,
) -> Json {
  let model_detail = if model == "" { "" } else { " with model `\{model}`" }
  let content = "Planner step \{step} used \{mode}\{model_detail} and selected \{tool_count} tool call(s)."
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-planner-step-\{step}-\{now}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "lane": "runtime",
    "kind": "reasoning_delta",
    "event": "reasoning_delta",
    "title": "MoonCode planner step \{step}",
    "status": "running",
    "detail": content,
    "content": content,
    "planner_step": step,
    "planner_mode": mode,
    "model": model,
    "tool_call_count": tool_count,
    "created_at": now,
    "source": "moonclaw-native-runtime-turn",
  }
}

///|
fn mooncode_runtime_turn_assistant_event(
  session_id : String,
  command_id : String,
  step~ : Int,
  content~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-assistant-step-\{step}-\{now}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "lane": "transcript",
    "kind": "assistant_delta",
    "event": "assistant_delta",
    "title": "MoonCode assistant update",
    "status": "running",
    "detail": content,
    "content": content,
    "planner_step": step,
    "created_at": now,
    "source": "moonclaw-native-runtime-turn",
  }
}

///|
fn mooncode_runtime_turn_tool_call_event(
  session_id : String,
  command_id : String,
  tool_call : Json,
  step~ : Int,
  index~ : Int,
  mode~ : String,
  model~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let tool_call_id = mooncode_runtime_turn_tool_call_id(
    tool_call,
    step~,
    index~,
  )
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  let path = mooncode_json_string(arguments, "path", default="")
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-tool-call-\{step}-\{index}-\{tool}-\{now}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "lane": mooncode_runtime_turn_tool_call_lane(tool, path),
    "kind": mooncode_event_tool_call(),
    "event": mooncode_event_tool_call(),
    "title": "Tool started: \{tool}",
    "status": "running",
    "detail": arguments.stringify(indent=2),
    "content": arguments.stringify(indent=2),
    "tool": tool,
    "tool_name": tool,
    "tool_call_id": tool_call_id,
    "arguments": arguments.stringify(indent=2),
    "tool_call": {
      "id": tool_call_id,
      "type": "function",
      "function": { "name": tool, "arguments": arguments.stringify(indent=2) },
    },
    "path": path,
    "planner_step": step,
    "planner_mode": mode,
    "model": model,
    "created_at": now,
    "source": "moonclaw-native-runtime-turn",
  }
}

///|
fn mooncode_runtime_turn_tool_call_id(
  tool_call : Json,
  step~ : Int,
  index~ : Int,
) -> String {
  let id = mooncode_json_string(tool_call, "tool_call_id", default="")
  if id != "" {
    return id
  }
  "runtime-step-\{step}-tool-\{index}"
}

///|
fn mooncode_runtime_turn_tool_call_lane(tool : String, path : String) -> String {
  match tool {
    "moon_cmd" => "test"
    "moon_check" => "test"
    "write" | "edit" => "diff"
    "finish" => "review"
    _ if path != "" => "diff"
    _ => "tool"
  }
}

///|
fn mooncode_runtime_turn_failed_planner_result(
  command : Json,
  model_name : String,
  message : String,
  started : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let session_id = mooncode_json_string(command, "session_id", default="")
  let command_id = mooncode_command_id(command)
  let failed = mooncode_event(
    session_id~,
    command_id~,
    lane="runtime",
    kind="runtime.planner_failed",
    title="MoonCode model planner fell back",
    status="failed",
    detail=message,
    now~,
  )
  {
    "kind": mooncode_kind_runtime_turn_planner(),
    "protocol": mooncode_protocol_version(),
    "planner_mode": mooncode_planner_mode_deterministic_fallback(),
    "model": model_name,
    "tool_calls": Json::array([]),
    "events": Json::array([started, failed]),
    "message": message,
  }
}
