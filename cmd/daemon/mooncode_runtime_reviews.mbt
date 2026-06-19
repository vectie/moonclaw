///|
fn mooncode_runtime_turn_writes_review_receipt(action : String) -> Bool {
  action == "accept" || action == "reject"
}

///|
async fn mooncode_runtime_turn_review_receipts(
  session_id : String,
  book_root : String,
  command : Json,
  action~ : String,
  now~ : @clock.Timestamp,
) -> Array[Json] {
  let command_id = mooncode_command_id(command)
  let relative = mooncode_runtime_turn_review_receipt_relative_path(
    session_id, command_id, action,
  )
  let absolute = @pathx.join(book_root, relative)
  let context_path = mooncode_runtime_turn_context_path(command)
  let receipt : Json = {
    "kind": "mooncode-review-receipt",
    "protocol": mooncode_protocol_version(),
    "status": "recorded",
    "action": action,
    "decision": if action == "reject" {
      "rejected"
    } else {
      "accepted"
    },
    "session_id": session_id,
    "workspace_id": mooncode_json_string(command, "workspace_id", default=""),
    "workspace_name": mooncode_json_string(
      command,
      "workspace_name",
      default="",
    ),
    "task_id": "",
    "book_root": book_root,
    "context_path": context_path,
    "command_id": command_id,
    "command_created_at": mooncode_json_string(
      command,
      "created_at",
      default="",
    ),
    "recorded_at": now,
    "receipt_path": relative,
    "absolute_receipt_path": absolute,
    "detail": mooncode_runtime_turn_review_detail(action, context_path),
    "command_packet": mooncode_json_object_field_or_empty(command, "packet"),
    "owner": {
      "ui": "moondesk",
      "runtime": "moonclaw",
      "artifact": "moonbook",
      "review": "moonbook",
      "standalone_component": "mooncode",
    },
  }
  mooncode_runtime_turn_write_json_manifest(book_root, relative, receipt)
  [receipt]
}

///|
fn mooncode_runtime_turn_review_receipt_event(
  session_id : String,
  command_id : String,
  command : Json,
  receipt : Json,
  action~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  let receipt_path = mooncode_json_string(receipt, "receipt_path", default="")
  let context_path = mooncode_json_string(receipt, "context_path", default="")
  let status = if action == "reject" { "rejected" } else { "accepted" }
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-receipt-\{action}-\{now}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": mooncode_book_root(command),
    "command_id": command_id,
    "lane": "review",
    "kind": "receipt.\{action}",
    "event": "review_receipt",
    "title": "MoonBook review receipt",
    "status": status,
    "detail": "MoonClaw recorded `\{action}` review receipt at \{receipt_path}.",
    "path": if context_path == "" {
      receipt_path
    } else {
      context_path
    },
    "receipt_path": receipt_path,
    "review_receipt": receipt,
    "command": action,
    "command_packet": mooncode_json_object_field_or_empty(command, "packet"),
    "created_at": now,
    "source": "moonclaw-native-runtime-turn",
  }
}

///|
fn mooncode_runtime_turn_review_receipt_relative_path(
  session_id : String,
  command_id : String,
  action : String,
) -> String {
  let safe_session = mooncode_safe_session_id(session_id)
  let safe_command = mooncode_safe_session_id(command_id)
  let safe_action = if action == "reject" { "reject" } else { "accept" }
  "wiki/reviews/mooncode/\{safe_session}/\{safe_action}-\{safe_command}.json"
}

///|
fn mooncode_runtime_turn_context_path(command : Json) -> String {
  let direct = mooncode_json_string(command, "context_path", default="")
  if direct != "" {
    return direct
  }
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let payload_path = mooncode_json_string(payload, "context_path", default="")
  if payload_path != "" {
    return payload_path
  }
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let packet_path = mooncode_json_string(packet, "context_path", default="")
  if packet_path != "" {
    return packet_path
  }
  mooncode_json_string(packet, "path", default="")
}

///|
fn mooncode_runtime_turn_review_detail(
  action : String,
  context_path : String,
) -> String {
  let target = if context_path == "" {
    "the selected MoonCode result"
  } else {
    "`\{context_path}`"
  }
  if action == "reject" {
    "MoonClaw recorded operator rejection for \{target}."
  } else {
    "MoonClaw recorded operator acceptance for \{target}."
  }
}
