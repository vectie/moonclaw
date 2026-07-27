///|
fn mooncode_runtime_turn_finished_event(
  session_id : String,
  command_id : String,
  accepted~ : Bool,
  tool_count~ : Int,
  completion_reason? : String = "",
  now~ : @clock.Timestamp,
) -> Json {
  mooncode_event(
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
    "execution": execution,
    "events": Json::array(mooncode_json_array_items(execution, "events")),
  }
}
