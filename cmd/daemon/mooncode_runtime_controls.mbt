///|
fn mooncode_runtime_turn_scheduler_decision(
  scheduler_state : Json,
  command_id : String,
) -> Json {
  for decision in mooncode_json_array_items(scheduler_state, "decisions") {
    if mooncode_json_string(decision, "command_id", default="") == command_id {
      return decision
    }
  }
  {}
}

///|
fn mooncode_runtime_turn_drops_idle_control(
  command : Json,
  scheduler_effect : String,
) -> Bool {
  let action = mooncode_json_string(command, "command", default="prompt")
  (action == "steer" && scheduler_effect == "drop-steer") ||
  (action == "cancel" && scheduler_effect == "drop-cancel")
}

///|
fn mooncode_runtime_turn_dropped_control_execution(
  session_id : String,
  command_id : String,
  command : Json,
  scheduler_decision : Json,
  events : Array[Json],
  now~ : @clock.Timestamp,
) -> Json {
  let action = mooncode_json_string(command, "command", default="prompt")
  let event = if action == "steer" {
    mooncode_runtime_turn_steer_settlement_event(
      session_id,
      command_id,
      command,
      accepted=false,
      now~,
    )
  } else {
    mooncode_event(
      session_id~,
      command_id~,
      lane="runtime",
      kind=mooncode_event_cancel_dropped(),
      title="MoonCode cancel dropped",
      status="done",
      detail="MoonClaw dropped cancel command \{command_id} because no native MoonCode turn was active or pending.",
      now~,
    )
  }
  events.push(event)
  events.push(
    mooncode_runtime_turn_finished_event(
      session_id,
      command_id,
      accepted=true,
      tool_count=0,
      now~,
    ),
  )
  {
    "accepted": true,
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "web_search": mooncode_command_web_search(command),
    "control": if action == "cancel" {
      "cancel_dropped"
    } else {
      action
    },
    "message": if action == "cancel" {
      "MoonClaw native runtime dropped idle `cancel`"
    } else {
      "MoonClaw native runtime dropped idle `steer`"
    },
    "serve_scheduler_decision": scheduler_decision,
    "planner_mode": mooncode_planner_mode_serve_scheduler_control(),
    "planner_step_count": 0,
    "model_step_limit": 0,
    "tool_results": Json::array([]),
    "test_results": Json::array([]),
    "test_events": Json::array([]),
    "eval_results": Json::array([]),
    "eval_events": Json::array([]),
    "commit_results": Json::array([]),
    "commit_events": Json::array([]),
    "review_receipts": Json::array([]),
    "review_events": Json::array([]),
    "events": Json::array(events),
  }
}

///|
fn mooncode_runtime_turn_steer_settlement_event(
  session_id : String,
  command_id : String,
  command : Json,
  accepted~ : Bool,
  now~ : @clock.Timestamp,
) -> Json {
  let steering = mooncode_runtime_turn_prompt_text(command)
  let kind = if accepted {
    mooncode_event_steer_applied()
  } else {
    mooncode_event_steer_dropped()
  }
  let title = if accepted {
    "MoonCode steering applied"
  } else {
    "MoonCode steering dropped"
  }
  let detail = if accepted {
    "MoonClaw applied steering for command \{command_id}."
  } else {
    "MoonClaw could not apply steering for command \{command_id}."
  }
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-\{kind}-\{now}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "lane": "runtime",
    "kind": kind,
    "event": kind,
    "title": title,
    "status": if accepted {
      "done"
    } else {
      "failed"
    },
    "detail": detail,
    "content": steering,
    "steering_text": steering,
    "settlement": if accepted {
      "applied"
    } else {
      "dropped"
    },
    "created_at": now,
    "source": "moonclaw-native-runtime-turn",
  }
}
