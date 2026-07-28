///|
fn mooncode_runtime_turn_control_decision(
  control_state : Json,
  command_id : String,
) -> Json {
  for decision in mooncode_json_array_items(control_state, "decisions") {
    if mooncode_json_string(decision, "command_id", default="") == command_id {
      return decision
    }
  }
  {}
}

///|
fn mooncode_runtime_turn_drops_idle_control(
  command : Json,
  control_effect : String,
) -> Bool {
  let action = mooncode_json_string(command, "command", default="prompt")
  action == "cancel" && control_effect == "drop-cancel"
}

///|
fn mooncode_runtime_turn_defers_idle_steer(
  command : Json,
  control_effect : String,
) -> Bool {
  mooncode_json_string(command, "command", default="prompt") == "steer" &&
  control_effect == "defer-steer"
}

///|
fn mooncode_runtime_turn_dropped_control_execution(
  session_id : String,
  command_id : String,
  command : Json,
  control_decision : Json,
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
    "runtime_control_decision": control_decision,
    "planner_mode": mooncode_planner_mode_runtime_control(),
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
fn mooncode_runtime_turn_deferred_steer_execution(
  session_id : String,
  command_id : String,
  command : Json,
  control_decision : Json,
  events : Array[Json],
  now~ : @clock.Timestamp,
) -> Json {
  events.push(
    mooncode_runtime_turn_deferred_steer_event(
      session_id,
      command_id,
      command,
      now~,
    ),
  )
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
    "control": "steer_deferred",
    "message": "MoonClaw native runtime deferred idle `steer` into the next MoonCode turn",
    "runtime_control_decision": control_decision,
    "planner_mode": mooncode_planner_mode_runtime_control(),
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
fn mooncode_runtime_turn_deferred_steer_event(
  session_id : String,
  command_id : String,
  command : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let steering = mooncode_runtime_turn_prompt_text(command)
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-\{mooncode_event_steer_deferred()}-\{now}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "lane": "runtime",
    "kind": mooncode_event_steer_deferred(),
    "event": mooncode_event_steer_deferred(),
    "title": "MoonCode steering deferred",
    "status": "queued",
    "detail": "MoonClaw saved steering for command \{command_id} and will apply it to the next MoonCode turn.",
    "content": steering,
    "steering_text": steering,
    "settlement": "deferred",
    "created_at": now,
    "source": "moonclaw-native-runtime-turn",
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

///|
fn mooncode_runtime_turn_applied_deferred_steer_event(
  session_id : String,
  turn_command_id : String,
  deferred : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let command_id = mooncode_json_string(deferred, "command_id", default="")
  let steering = mooncode_json_string(deferred, "steering_text", default="")
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-\{mooncode_event_steer_applied()}-\{turn_command_id}-\{now}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "applied_to_command_id": turn_command_id,
    "lane": "runtime",
    "kind": mooncode_event_steer_applied(),
    "event": mooncode_event_steer_applied(),
    "title": "MoonCode steering applied",
    "status": "done",
    "detail": "MoonClaw applied deferred steering from command \{command_id} to turn \{turn_command_id}.",
    "content": steering,
    "steering_text": steering,
    "settlement": "applied",
    "created_at": now,
    "source": "moonclaw-native-runtime-turn",
  }
}

///|
fn mooncode_runtime_turn_pending_deferred_steering(
  events : Array[Json],
) -> Array[Json] {
  let deferred : Array[Json] = []
  for event in events {
    if mooncode_json_string(event, "kind", default="") ==
      mooncode_event_steer_deferred() {
      let command_id = mooncode_json_string(event, "command_id", default="")
      if command_id != "" &&
        !mooncode_runtime_turn_deferred_steer_settled(events, command_id) {
        deferred.push({
          "command_id": command_id,
          "steering_text": mooncode_json_string(
            event,
            "steering_text",
            default=mooncode_json_string(event, "content", default=""),
          ),
          "created_at": mooncode_json_string(event, "created_at", default=""),
          "source_event_id": mooncode_json_string(event, "id", default=""),
        })
      }
    }
  }
  deferred
}

///|
fn mooncode_runtime_turn_deferred_steer_settled(
  events : Array[Json],
  command_id : String,
) -> Bool {
  for event in events {
    if mooncode_json_string(event, "command_id", default="") == command_id {
      let kind = mooncode_json_string(event, "kind", default="")
      if kind == mooncode_event_steer_applied() ||
        kind == mooncode_event_steer_dropped() {
        return true
      }
    }
  }
  false
}

///|
fn mooncode_runtime_turn_command_with_deferred_steering(
  command : Json,
  deferred : Array[Json],
) -> Json {
  if deferred.length() == 0 {
    command
  } else {
    mooncode_json_object_with_field(
      command,
      "deferred_steering",
      Json::array(deferred),
    )
  }
}

///|
/// Select still-pending steering controls that the authoritative control
/// projection targets at the active turn. Decisions preserve command-journal
/// order, so the returned steering messages may be injected in array order.
fn mooncode_runtime_turn_pending_live_steering(
  control_state : Json,
  active_command_id : String,
) -> Array[Json] {
  let steering : Array[Json] = []
  if active_command_id == "" {
    return steering
  }
  for decision in mooncode_json_array_items(control_state, "decisions") {
    if mooncode_json_string(decision, "action", default="") == "steer" &&
      mooncode_json_string(decision, "status", default="") == "pending" &&
      mooncode_json_string(decision, "effect", default="") == "deliver-steer" &&
      mooncode_json_string(decision, "target_command_id", default="") ==
      active_command_id {
      let command_id = mooncode_json_string(decision, "command_id", default="")
      if command_id != "" {
        steering.push({
          "command_id": command_id,
          "applied_to_command_id": active_command_id,
          "steering_text": mooncode_json_string(decision, "text", default=""),
          "created_at": mooncode_json_string(decision, "created_at", default=""),
        })
      }
    }
  }
  steering
}

///|
fn mooncode_runtime_turn_live_steer_receipt(
  session_id : String,
  book_root : String,
  steering : Json,
  now~ : @clock.Timestamp,
) -> Json {
  {
    "kind": mooncode_kind_runtime_receipt(),
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": mooncode_json_string(steering, "command_id", default=""),
    "status": "runtime-completed",
    "runtime_mode": "moonclaw-native-runtime-live-steer",
    "consumer_id": "moonclaw-native-runtime-turn",
    "completed_at": now,
    "control": "steer_applied",
    "message": "MoonClaw applied live steering to the active MoonCode turn.",
    "applied_to_command_id": mooncode_json_string(
      steering,
      "applied_to_command_id",
      default="",
    ),
    "steering_text": mooncode_json_string(steering, "steering_text", default=""),
  }
}

///|
fn mooncode_runtime_turn_applied_live_steer_event(
  session_id : String,
  steering : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let command_id = mooncode_json_string(steering, "command_id", default="")
  let active_command_id = mooncode_json_string(
    steering,
    "applied_to_command_id",
    default="",
  )
  let text = mooncode_json_string(steering, "steering_text", default="")
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-\{mooncode_event_steer_applied()}-\{active_command_id}-\{now}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "applied_to_command_id": active_command_id,
    "lane": "runtime",
    "kind": mooncode_event_steer_applied(),
    "event": mooncode_event_steer_applied(),
    "title": "MoonCode live steering applied",
    "status": "done",
    "detail": "MoonClaw applied live steering from command \{command_id} to active turn \{active_command_id}.",
    "content": text,
    "steering_text": text,
    "settlement": "applied",
    "delivery": "live",
    "created_at": now,
    "source": "moonclaw-native-runtime-turn",
  }
}

///|
/// Receipt persistence is the idempotency boundary: after this call the
/// control projection no longer returns the steering command as pending.
async fn Daemon::mooncode_runtime_turn_claim_live_steering(
  self : Daemon,
  session_id : String,
  book_root : String,
  active_command_id : String,
) -> Array[Json] {
  let control_state = self.mooncode_runtime_control_payload(
    session_id, book_root,
  )
  let steering = mooncode_runtime_turn_pending_live_steering(
    control_state, active_command_id,
  )
  for item in steering {
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_runtime_receipt(),
      mooncode_runtime_turn_live_steer_receipt(
        session_id,
        book_root,
        item,
        now=self.clock.now(),
      ),
    )
  }
  steering
}
