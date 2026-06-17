///|
async fn Daemon::mooncode_serve_scheduler(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let session_id = session_id.to_owned()
  let book_root = mooncode_request_book_root(r)
  let state = self.mooncode_serve_scheduler_payload(session_id, book_root)
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(state.stringify(indent=2))
}

///|
async fn Daemon::mooncode_serve_scheduler_payload(
  self : Daemon,
  session_id : String,
  book_root : String,
) -> Json {
  ignore(self)
  let commands_path = mooncode_commands_path(book_root, session_id)
  let dispatches_path = mooncode_runtime_dispatches_path(book_root, session_id)
  let commands = mooncode_read_jsonl(commands_path)
  let receipts = mooncode_read_jsonl(dispatches_path)
  mooncode_serve_scheduler_state_from_logs(
    session_id,
    book_root,
    commands,
    receipts,
    commands_path~,
    dispatches_path~,
  )
}

///|
fn mooncode_serve_scheduler_state_from_logs(
  session_id : String,
  book_root : String,
  commands : Array[Json],
  receipts : Array[Json],
  commands_path~ : String,
  dispatches_path~ : String,
) -> Json {
  let latest_receipts = mooncode_latest_receipts_by_command_id(receipts)
  let lifecycle_items : Array[Json] = []
  for index in 0..<commands.length() {
    let command = commands[index]
    let command_id = mooncode_runtime_command_entry_id(command)
    let receipt = if command_id == "" {
      None
    } else {
      latest_receipts.get(command_id)
    }
    lifecycle_items.push(
      mooncode_serve_scheduler_lifecycle_item(command, index, receipt),
    )
  }
  let active_turn_id = mooncode_serve_scheduler_active_turn_id(lifecycle_items)
  let pending_turn_ids = mooncode_serve_scheduler_pending_turn_ids(
    lifecycle_items,
  )
  let decisions = mooncode_serve_scheduler_decisions(
    commands, lifecycle_items, active_turn_id, pending_turn_ids,
  )
  {
    "kind": "mooncode-serve-scheduler-state",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "runtime_owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "runtime_command_log_path": commands_path,
    "runtime_dispatch_log_path": dispatches_path,
    "command_count": commands.length(),
    "receipt_count": receipts.length(),
    "lifecycle_command_count": lifecycle_items.length(),
    "active_turn_id": active_turn_id,
    "pending_turn_ids": Json::array(
      [
        for id in pending_turn_ids => Json::string(id)
      ],
    ),
    "pending_turn_count": pending_turn_ids.length(),
    "decision_count": decisions.length(),
    "decisions": Json::array(decisions),
    "lifecycle_commands": Json::array(lifecycle_items),
    "contract": mooncode_serve_scheduler_contract(),
    "ordering_rule": "MoonClaw projects OpenSeek serve-mode semantics from one append-only command queue: turn-starting commands run one at a time, steer targets the active or next pending turn, and cancel targets the active turn or withdraws the next pending turn.",
  }
}

///|
fn mooncode_latest_receipts_by_command_id(
  receipts : Array[Json],
) -> Map[String, Json] {
  let latest : Map[String, Json] = {}
  for receipt in receipts {
    let command_id = mooncode_json_string(receipt, "command_id", default="")
    if command_id != "" {
      latest[command_id] = receipt
    }
  }
  latest
}

///|
fn mooncode_serve_scheduler_lifecycle_item(
  command_entry : Json,
  index : Int,
  receipt : Json?,
) -> Json {
  let command = mooncode_json_object_field_or_empty(command_entry, "command")
  let command_id = mooncode_runtime_command_entry_id(command_entry)
  let receipt_status = match receipt {
    Some(value) => mooncode_json_string(value, "status", default="")
    None => ""
  }
  let status = mooncode_serve_scheduler_lifecycle_status(
    command_id, receipt_status,
  )
  {
    "kind": "mooncode-serve-scheduler-lifecycle-item",
    "protocol": mooncode_protocol_version(),
    "index": index,
    "command_id": command_id,
    "action": mooncode_serve_scheduler_command_action(command_entry),
    "status": status,
    "receipt_status": receipt_status,
    "command": command,
    "command_entry": command_entry,
    "receipt": match receipt {
      Some(value) => value
      None => null
    },
  }
}

///|
fn mooncode_serve_scheduler_lifecycle_status(
  command_id : String,
  receipt_status : String,
) -> String {
  if command_id == "" {
    return "blocked-invalid"
  }
  match receipt_status {
    "runtime-claimed" => "running"
    "runtime-failed" | "runtime-rejected" => "failed"
    "runtime-delivered"
    | "runtime-completed"
    | "runtime-succeeded"
    | "runtime-finished"
    | "runtime-cancelled" => "completed"
    _ => "pending"
  }
}

///|
fn mooncode_serve_scheduler_active_turn_id(
  lifecycle_items : Array[Json],
) -> String {
  for item in lifecycle_items {
    let action = mooncode_json_string(item, "action", default="prompt")
    let status = mooncode_json_string(item, "status", default="")
    if mooncode_serve_scheduler_turn_starting_action(action) &&
      status == "running" {
      return mooncode_json_string(item, "command_id", default="")
    }
  }
  ""
}

///|
fn mooncode_serve_scheduler_pending_turn_ids(
  lifecycle_items : Array[Json],
) -> Array[String] {
  let ids : Array[String] = []
  for item in lifecycle_items {
    let action = mooncode_json_string(item, "action", default="prompt")
    let status = mooncode_json_string(item, "status", default="")
    let command_id = mooncode_json_string(item, "command_id", default="")
    if command_id != "" &&
      mooncode_serve_scheduler_turn_starting_action(action) &&
      status == "pending" {
      ids.push(command_id)
    }
  }
  ids
}

///|
fn mooncode_serve_scheduler_decisions(
  commands : Array[Json],
  lifecycle_items : Array[Json],
  active_turn_id : String,
  pending_turn_ids : Array[String],
) -> Array[Json] {
  let decisions : Array[Json] = []
  for index in 0..<commands.length() {
    let command = commands[index]
    let action = mooncode_serve_scheduler_command_action(command)
    let command_id = mooncode_runtime_command_entry_id(command)
    let status = mooncode_serve_scheduler_lifecycle_status_for(
      lifecycle_items,
      command_id,
      default="unknown",
    )
    let decision = match action {
      "steer" =>
        mooncode_serve_scheduler_control_decision(
          index,
          command,
          action,
          status,
          active_turn_id,
          pending_turn_ids,
          active_effect="deliver-steer",
          pending_effect="queue-steer",
          idle_effect="drop-steer",
        )
      "cancel" =>
        mooncode_serve_scheduler_control_decision(
          index,
          command,
          action,
          status,
          active_turn_id,
          pending_turn_ids,
          active_effect="cancel-active",
          pending_effect="withdraw-pending",
          idle_effect="drop-cancel",
        )
      "note" =>
        mooncode_serve_scheduler_decision(
          index,
          command,
          status,
          effect="record-note",
          target_command_id="",
          target_state="recorded",
          detail="Note is recorded in the session and does not start an agent turn.",
        )
      _ =>
        mooncode_serve_scheduler_turn_decision(
          index, command, status, active_turn_id, pending_turn_ids,
        )
    }
    decisions.push(decision)
  }
  decisions
}

///|
fn mooncode_serve_scheduler_turn_decision(
  index : Int,
  command : Json,
  status : String,
  active_turn_id : String,
  pending_turn_ids : Array[String],
) -> Json {
  let command_id = mooncode_runtime_command_entry_id(command)
  if status == "completed" {
    return mooncode_serve_scheduler_decision(
      index,
      command,
      status,
      effect="already-completed",
      target_command_id=command_id,
      target_state="terminal",
      detail="Turn already completed; no scheduler action is required.",
    )
  }
  if status == "failed" {
    return mooncode_serve_scheduler_decision(
      index,
      command,
      status,
      effect="failed",
      target_command_id=command_id,
      target_state="terminal",
      detail="Turn failed; retry or operator review is required before later queued work should proceed.",
    )
  }
  if status == "blocked-invalid" {
    return mooncode_serve_scheduler_decision(
      index,
      command,
      status,
      effect="blocked",
      target_command_id=command_id,
      target_state="blocked",
      detail="Turn is blocked by an invalid or missing command id.",
    )
  }
  if command_id == active_turn_id {
    return mooncode_serve_scheduler_decision(
      index,
      command,
      status,
      effect="active-turn",
      target_command_id=command_id,
      target_state="active",
      detail="This turn owns the active MoonCode runtime slot.",
    )
  }
  if active_turn_id != "" {
    return mooncode_serve_scheduler_decision(
      index,
      command,
      status,
      effect="queue-turn",
      target_command_id=active_turn_id,
      target_state="active",
      detail="A prior turn is active; this turn must wait in command-log order.",
    )
  }
  if pending_turn_ids.length() > 0 && pending_turn_ids[0] == command_id {
    mooncode_serve_scheduler_decision(
      index,
      command,
      status,
      effect="start-turn",
      target_command_id=command_id,
      target_state="pending",
      detail="No turn is active; this is the next pending turn to start.",
    )
  } else {
    mooncode_serve_scheduler_decision(
      index,
      command,
      status,
      effect="queue-turn",
      target_command_id=if pending_turn_ids.length() > 0 {
        pending_turn_ids[0]
      } else {
        ""
      },
      target_state="pending",
      detail="A prior pending turn must be consumed before this command.",
    )
  }
}

///|
fn mooncode_serve_scheduler_control_decision(
  index : Int,
  command : Json,
  action : String,
  status : String,
  active_turn_id : String,
  pending_turn_ids : Array[String],
  active_effect~ : String,
  pending_effect~ : String,
  idle_effect~ : String,
) -> Json {
  if active_turn_id != "" {
    return mooncode_serve_scheduler_decision(
      index,
      command,
      status,
      effect=active_effect,
      target_command_id=active_turn_id,
      target_state="active",
      detail="\{action} targets the active MoonCode turn.",
    )
  }
  if pending_turn_ids.length() > 0 {
    return mooncode_serve_scheduler_decision(
      index,
      command,
      status,
      effect=pending_effect,
      target_command_id=pending_turn_ids[0],
      target_state="pending",
      detail="\{action} targets the next pending MoonCode turn.",
    )
  }
  mooncode_serve_scheduler_decision(
    index,
    command,
    status,
    effect=idle_effect,
    target_command_id="",
    target_state="idle",
    detail="\{action} arrived with no active or pending MoonCode turn.",
  )
}

///|
fn mooncode_serve_scheduler_decision(
  index : Int,
  command_entry : Json,
  status : String,
  effect~ : String,
  target_command_id~ : String,
  target_state~ : String,
  detail~ : String,
) -> Json {
  let command = mooncode_json_object_field_or_empty(command_entry, "command")
  let action = mooncode_serve_scheduler_command_action(command_entry)
  {
    "kind": "mooncode-serve-scheduler-decision",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "index": index,
    "command_id": mooncode_runtime_command_entry_id(command_entry),
    "action": action,
    "dispatch": mooncode_command_control(action),
    "status": status,
    "effect": effect,
    "target_command_id": target_command_id,
    "target_state": target_state,
    "text": mooncode_serve_scheduler_command_text(command),
    "created_at": mooncode_json_string(command_entry, "created_at", default=""),
    "openseek_wire_command": mooncode_serve_scheduler_wire_command(command),
    "detail": detail,
  }
}

///|
fn mooncode_serve_scheduler_lifecycle_status_for(
  lifecycle_items : Array[Json],
  command_id : String,
  default~ : String,
) -> String {
  for item in lifecycle_items {
    if mooncode_json_string(item, "command_id", default="") == command_id {
      return mooncode_json_string(item, "status", default~)
    }
  }
  default
}

///|
fn mooncode_serve_scheduler_command_action(command_entry : Json) -> String {
  let direct = mooncode_json_string(command_entry, "action", default="")
  if direct != "" {
    return direct
  }
  let command = mooncode_json_object_field_or_empty(command_entry, "command")
  let action = mooncode_json_string(command, "command", default="")
  if action != "" {
    action
  } else {
    "prompt"
  }
}

///|
fn mooncode_serve_scheduler_turn_starting_action(action : String) -> Bool {
  action != "steer" && action != "cancel" && action != "note"
}

///|
fn mooncode_serve_scheduler_command_text(command : Json) -> String {
  let message = mooncode_json_string(command, "message", default="")
  if message != "" {
    return message
  }
  let text = mooncode_json_string(command, "text", default="")
  if text != "" {
    return text
  }
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  mooncode_json_string(
    packet,
    "message",
    default=mooncode_json_string(packet, "text", default=""),
  )
}

///|
fn mooncode_serve_scheduler_wire_command(command : Json) -> Json {
  let action = mooncode_json_string(command, "command", default="prompt")
  match action {
    "steer" =>
      {
        "command": "steer",
        "text": mooncode_serve_scheduler_command_text(command),
      }
    "cancel" => { "command": "cancel" }
    _ =>
      {
        "command": "prompt",
        "text": mooncode_serve_scheduler_command_text(command),
      }
  }
}

///|
fn mooncode_serve_scheduler_contract() -> Json {
  {
    "kind": "mooncode-serve-scheduler-contract",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "reference": "../openseek/cmd/openseek/serve.mbt",
    "rule": "Prompt and command actions start turns, steer targets the active turn or next pending turn, and cancel targets the active turn or withdraws the next pending turn.",
    "wire_effects": [
      "start-turn", "queue-turn", "deliver-steer", "queue-steer", "drop-steer", "cancel-active",
      "withdraw-pending", "drop-cancel", "record-note", "already-completed", "failed",
      "blocked",
    ],
  }
}
