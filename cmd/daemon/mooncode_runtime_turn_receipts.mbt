///|
fn mooncode_runtime_turn_finished_event(
  session_id : String,
  command_id : String,
  accepted~ : Bool,
  tool_count~ : Int32,
  completion_reason~ : String = "",
  completion_verdict~ : Json = Json::null(),
  now~ : @clock.Timestamp,
) -> Json {
  let event = mooncode_event(
    session_id~,
    command_id~,
    lane="runtime",
    kind=mooncode_event_runtime_turn_finished(),
    title=if accepted {
      "MoonCode native runtime turn completed"
    } else {
      "MoonCode native runtime turn failed"
    },
    status=if accepted { "done" } else { "failed" },
    detail=if completion_reason == "" {
      "MoonClaw native runtime turn executed \{tool_count} tool call(s)."
    } else {
      "MoonClaw native runtime turn executed \{tool_count} tool call(s): \{completion_reason}."
    },
    now~,
  )
  mooncode_json_object_with_field(
    event, "completion_verdict", completion_verdict,
  )
}

///|
fn mooncode_runtime_turn_receipt_execution(execution : Json) -> Json {
  let finish_results : Array[Json] = []
  for result in mooncode_json_array_items(execution, "tool_results") {
    if mooncode_json_string(result, "tool", default="") == "finish" {
      finish_results.push(result)
    }
  }
  {
    "accepted": mooncode_json_bool(execution, "accepted", default=false),
    "control": mooncode_json_string(execution, "control", default=""),
    "message": mooncode_json_string(execution, "message", default=""),
    "planner_mode": mooncode_json_string(execution, "planner_mode", default=""),
    "completion_verdict": mooncode_json_object_field_or_empty(
      execution, "completion_verdict",
    ),
    "tool_results": Json::array(finish_results),
  }
}

///|
fn mooncode_runtime_turn_receipt(
  session_id : String,
  book_root : String,
  claim_item : Json,
  execution : Json,
  consumer_id~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  let command_id = mooncode_json_string(claim_item, "command_id", default="")
  let accepted = mooncode_json_bool(execution, "accepted", default=false)
  let receipt = mooncode_json_object_field_or_empty(claim_item, "receipt")
  let claim_id = mooncode_json_string(receipt, "claim_id", default="")
  {
    "kind": mooncode_kind_runtime_receipt(),
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "web_search": mooncode_command_web_search(
      mooncode_json_object_field_or_empty(claim_item, "command"),
    ),
    "status": if accepted {
      "runtime-completed"
    } else {
      "runtime-failed"
    },
    "runtime_mode": "moonclaw-native-runtime-turn",
    "claim_id": claim_id,
    "consumer_id": consumer_id,
    "completed_at": now,
    "control": mooncode_json_string(execution, "control", default=""),
    "message": mooncode_json_string(execution, "message", default=""),
    "command": mooncode_json_object_field_or_empty(claim_item, "command"),
    "command_entry": mooncode_json_object_field_or_empty(
      claim_item, "command_entry",
    ),
    "execution": mooncode_runtime_turn_receipt_execution(execution),
    "events": [],
  }
}

///|
fn mooncode_runtime_turn_execution_compact(execution : Json) -> Json {
  let planner = mooncode_json_object_field_or_empty(execution, "planner")
  {
    "accepted": mooncode_json_bool(execution, "accepted", default=false),
    "protocol": mooncode_json_string(execution, "protocol", default=""),
    "session_id": mooncode_json_string(execution, "session_id", default=""),
    "command_id": mooncode_json_string(execution, "command_id", default=""),
    "web_search": mooncode_json_bool(execution, "web_search", default=false),
    "control": mooncode_json_string(execution, "control", default=""),
    "message": mooncode_json_string(execution, "message", default=""),
    "completed": mooncode_json_bool(execution, "completed", default=true),
    "paused": mooncode_json_bool(execution, "paused", default=false),
    "pause_reason": mooncode_json_string(execution, "pause_reason", default=""),
    "next_step_index": mooncode_json_int(
      execution,
      "next_step_index",
      default=0,
    ),
    "waiting_approval": mooncode_json_bool(
      execution,
      "waiting_approval",
      default=false,
    ),
    "approval": mooncode_json_object_field_or_empty(execution, "approval"),
    "planner_mode": mooncode_json_string(execution, "planner_mode", default=""),
    "planner_step_count": mooncode_json_int(
      execution,
      "planner_step_count",
      default=0,
    ),
    "model_step_limit": mooncode_json_int(
      execution,
      "model_step_limit",
      default=0,
    ),
    "completion_verdict": mooncode_json_object_field_or_empty(
      execution, "completion_verdict",
    ),
    "planner": {
      "planner_mode": mooncode_json_string(planner, "planner_mode", default=""),
      "model": mooncode_json_string(planner, "model", default=""),
      "tool_call_count": mooncode_json_int(
        planner,
        "tool_call_count",
        default=0,
      ),
    },
    "tool_results": Json::array(
      mooncode_json_array_items(execution, "tool_results"),
    ),
    "test_results": Json::array(
      mooncode_json_array_items(execution, "test_results"),
    ),
    "eval_results": Json::array(
      mooncode_json_array_items(execution, "eval_results"),
    ),
    "commit_results": Json::array(
      mooncode_json_array_items(execution, "commit_results"),
    ),
    "review_receipts": Json::array(
      mooncode_json_array_items(execution, "review_receipts"),
    ),
    "deferred_steering": Json::array(
      mooncode_json_array_items(execution, "deferred_steering"),
    ),
    "applied_live_steering": Json::array(
      mooncode_json_array_items(execution, "applied_live_steering"),
    ),
  }
}

///|
fn mooncode_runtime_claim_state_compact(state : Json) -> Json {
  {
    "kind": mooncode_json_string(state, "kind", default=""),
    "protocol": mooncode_json_string(state, "protocol", default=""),
    "owner": mooncode_json_string(state, "owner", default=""),
    "session_id": mooncode_json_string(state, "session_id", default=""),
    "book_root": mooncode_json_string(state, "book_root", default=""),
    "command_count": mooncode_json_int(state, "command_count", default=0),
    "receipt_count": mooncode_json_int(state, "receipt_count", default=0),
    "claimable_command_count": mooncode_json_int(
      state,
      "claimable_command_count",
      default=0,
    ),
    "claimed_command_count": mooncode_json_int(
      state,
      "claimed_command_count",
      default=0,
    ),
    "delivered_command_count": mooncode_json_int(
      state,
      "delivered_command_count",
      default=0,
    ),
    "invalid_command_count": mooncode_json_int(
      state,
      "invalid_command_count",
      default=0,
    ),
    "order_blocked_command_count": mooncode_json_int(
      state,
      "order_blocked_command_count",
      default=0,
    ),
    "claim_ready": mooncode_json_bool(state, "claim_ready", default=false),
  }
}

///|
fn mooncode_runtime_receipt_compact(receipt : Json) -> Json {
  {
    "kind": mooncode_json_string(receipt, "kind", default=""),
    "protocol": mooncode_json_string(receipt, "protocol", default=""),
    "owner": mooncode_json_string(receipt, "owner", default=""),
    "session_id": mooncode_json_string(receipt, "session_id", default=""),
    "book_root": mooncode_json_string(receipt, "book_root", default=""),
    "command_id": mooncode_json_string(receipt, "command_id", default=""),
    "status": mooncode_json_string(receipt, "status", default=""),
    "runtime_mode": mooncode_json_string(receipt, "runtime_mode", default=""),
    "claim_id": mooncode_json_string(receipt, "claim_id", default=""),
    "consumer_id": mooncode_json_string(receipt, "consumer_id", default=""),
    "control": mooncode_json_string(receipt, "control", default=""),
    "message": mooncode_json_string(receipt, "message", default=""),
  }
}

///|
fn mooncode_runtime_control_state_compact(state : Json) -> Json {
  {
    "kind": mooncode_json_string(state, "kind", default=""),
    "protocol": mooncode_json_string(state, "protocol", default=""),
    "owner": mooncode_json_string(state, "owner", default=""),
    "session_id": mooncode_json_string(state, "session_id", default=""),
    "book_root": mooncode_json_string(state, "book_root", default=""),
    "command_count": mooncode_json_int(state, "command_count", default=0),
    "receipt_count": mooncode_json_int(state, "receipt_count", default=0),
    "active_turn_id": mooncode_json_string(state, "active_turn_id", default=""),
    "pending_turn_count": mooncode_json_int(
      state,
      "pending_turn_count",
      default=0,
    ),
    "decision_count": mooncode_json_int(state, "decision_count", default=0),
  }
}

///|
fn mooncode_runtime_control_decision_compact(decision : Json) -> Json {
  {
    "kind": mooncode_json_string(decision, "kind", default=""),
    "protocol": mooncode_json_string(decision, "protocol", default=""),
    "command_id": mooncode_json_string(decision, "command_id", default=""),
    "action": mooncode_json_string(decision, "action", default=""),
    "control": mooncode_json_string(decision, "control", default=""),
    "status": mooncode_json_string(decision, "status", default=""),
    "effect": mooncode_json_string(decision, "effect", default=""),
    "target_command_id": mooncode_json_string(
      decision,
      "target_command_id",
      default="",
    ),
    "target_state": mooncode_json_string(decision, "target_state", default=""),
    "detail": mooncode_json_string(decision, "detail", default=""),
  }
}

///|
fn mooncode_runtime_package_manifest_compact(manifest : Json) -> Json {
  {
    "kind": mooncode_json_string(manifest, "kind", default=""),
    "protocol": mooncode_json_string(manifest, "protocol", default=""),
    "status": mooncode_json_string(manifest, "status", default=""),
    "package_kind": mooncode_json_string(manifest, "package_kind", default=""),
    "context_path": mooncode_json_string(manifest, "context_path", default=""),
    "source_inventory_count": mooncode_json_int(
      manifest,
      "source_inventory_count",
      default=0,
    ),
    "source_present_count": mooncode_json_int(
      manifest,
      "source_present_count",
      default=0,
    ),
    "promoted_source_count": mooncode_json_int(
      manifest,
      "promoted_source_count",
      default=0,
    ),
    "source_promotion_status": mooncode_json_string(
      manifest,
      "source_promotion_status",
      default="",
    ),
    "manifest_path": mooncode_json_string(manifest, "manifest_path", default=""),
    "promoted_source_root": mooncode_json_string(
      manifest,
      "promoted_source_root",
      default="",
    ),
  }
}

///|
fn mooncode_runtime_package_result_compact(result : Json) -> Json {
  {
    "protocol": mooncode_json_string(result, "protocol", default=""),
    "session_id": mooncode_json_string(result, "session_id", default=""),
    "command_id": mooncode_json_string(result, "command_id", default=""),
    "event": mooncode_json_string(result, "event", default=""),
    "path": mooncode_json_string(result, "path", default=""),
    "detail": mooncode_json_string(result, "detail", default=""),
    "package_manifest": mooncode_runtime_package_manifest_compact(
      mooncode_json_object_field_or_empty(result, "package_manifest"),
    ),
  }
}

///|
fn mooncode_runtime_book_result_compact(result : Json) -> Json {
  let book_result = mooncode_json_object_field_or_empty(result, "book_result")
  let event = mooncode_json_object_field_or_empty(
    result, "executable_book_event",
  )
  {
    "kind": mooncode_json_string(result, "kind", default=""),
    "protocol": mooncode_json_string(result, "protocol", default=""),
    "owner": mooncode_json_string(result, "owner", default=""),
    "session_id": mooncode_json_string(result, "session_id", default=""),
    "command_id": mooncode_json_string(result, "command_id", default=""),
    "result_id": mooncode_json_string(result, "result_id", default=""),
    "result_path": mooncode_json_string(result, "result_path", default=""),
    "book_result": {
      "result_id": mooncode_json_string(book_result, "result_id", default=""),
      "summary": mooncode_json_string(book_result, "summary", default=""),
      "artifacts": Json::array(
        mooncode_json_array_items(book_result, "artifacts"),
      ),
      "requires_review": mooncode_json_bool(
        book_result,
        "requires_review",
        default=false,
      ),
      "notify_town": mooncode_json_bool(
        book_result,
        "notify_town",
        default=false,
      ),
    },
    "executable_book_event": {
      "protocol": mooncode_json_string(event, "protocol", default=""),
      "id": mooncode_json_string(event, "id", default=""),
      "book_id": mooncode_json_string(event, "book_id", default=""),
      "command_id": mooncode_json_string(event, "command_id", default=""),
      "result_id": mooncode_json_string(event, "result_id", default=""),
      "event_type": mooncode_json_string(event, "event_type", default=""),
      "accepted": mooncode_json_bool(event, "accepted", default=false),
      "requires_review": mooncode_json_bool(
        event,
        "requires_review",
        default=false,
      ),
      "notify_town": mooncode_json_bool(event, "notify_town", default=false),
    },
  }
}
