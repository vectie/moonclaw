///|
priv struct MoonCodeConversationTurnDraft {
  turn_id : String
  client_turn_id : String
  command_id : String
  mut user : Json
  work_steps : Array[Json]
  mut work_live : Json
  mut assistant : Json
  mut assistant_delta : String
  mut status : String
  mut started_at : String
  mut updated_at : String
}

///|
fn mooncode_session_conversation(
  record : Json,
  commands : Array[Json],
  runtime_receipts : Array[Json],
  events : Array[Json],
) -> Json {
  let turns = mooncode_conversation_turns(commands, runtime_receipts, events)
  let turn_json : Array[Json] = []
  for ordinal, turn in turns {
    if mooncode_conversation_turn_visible(turn) {
      turn_json.push(mooncode_conversation_turn_json(turn, ordinal~))
    }
  }
  let revision = commands.length() + runtime_receipts.length() + events.length()
  {
    "kind": @mooncode_core.conversation_kind(),
    "protocol": mooncode_protocol_version(),
    "contract_id": "moonsuite-conversation.v2",
    "session_id": mooncode_json_string(record, "session_id", default=""),
    "workspace_id": mooncode_conversation_workspace_field(
      commands,
      "workspace_id",
      fallback="",
    ),
    "workspace_name": mooncode_conversation_workspace_field(
      commands,
      "workspace_name",
      fallback="",
    ),
    "turn_count": turn_json.length(),
    "revision": revision,
    "last_sequence": revision,
    "source_event_count": events.length(),
    "turns": Json::array(turn_json),
    "ownership_contract": @mooncode_core.conversation_ownership_contract_json(),
    "owner": {
      "projection": "moonclaw",
      "runtime": "moonclaw",
      "ui": "moondesk",
    },
  }
}

///|
fn mooncode_conversation_turns(
  commands : Array[Json],
  runtime_receipts : Array[Json],
  events : Array[Json],
) -> Array[MoonCodeConversationTurnDraft] {
  let turns : Array[MoonCodeConversationTurnDraft] = []
  for command_entry in commands {
    mooncode_conversation_apply_command(turns, command_entry)
  }
  for event in events {
    mooncode_conversation_apply_event(turns, event)
  }
  for receipt in runtime_receipts {
    mooncode_conversation_apply_receipt(turns, receipt)
  }
  turns
}

///|
fn mooncode_conversation_apply_command(
  turns : Array[MoonCodeConversationTurnDraft],
  command_entry : Json,
) -> Unit {
  let command = mooncode_conversation_command_body(command_entry)
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let action = mooncode_conversation_command_action(command, packet)
  if action == "steer" || action == "cancel" || action == "note" {
    return
  }
  let command_id = mooncode_conversation_command_id(command_entry, command)
  if command_id == "" {
    return
  }
  let index = mooncode_conversation_turn_index(turns, command_id)
  let created_at = mooncode_conversation_command_created_at(
    command_entry, command,
  )
  let target = if index >= 0 {
    index
  } else {
    turns.push(
      mooncode_conversation_turn_draft(
        turn_id=command_id,
        client_turn_id=mooncode_conversation_command_client_turn_id(
          command, command_id,
        ),
        command_id~,
        created_at~,
      ),
    )
    turns.length() - 1
  }
  let turn = turns[target]
  turn.user = mooncode_conversation_user_message(command_entry, command)
  turn.status = "queued"
  turn.work_live = Json::object({})
  turn.started_at = mooncode_conversation_first_text(
    turn.started_at,
    created_at,
  )
  turn.updated_at = mooncode_conversation_latest_timestamp(
    turn.updated_at,
    created_at,
  )
  turns[target] = turn
}

///|
fn mooncode_conversation_apply_event(
  turns : Array[MoonCodeConversationTurnDraft],
  event : Json,
) -> Unit {
  if mooncode_conversation_event_is_service_lifecycle(event) {
    return
  }
  let command_id = mooncode_json_string(event, "command_id", default="")
  if command_id == "" {
    return
  }
  let index = mooncode_conversation_turn_index(turns, command_id)
  if index < 0 {
    return
  }
  let turn = turns[index]
  let created_at = mooncode_json_string(event, "created_at", default="")
  if mooncode_conversation_event_is_assistant_delta(event) {
    let content = mooncode_conversation_event_content(event)
    if content != "" {
      turn.assistant_delta = turn.assistant_delta + content
      turn.status = mooncode_conversation_merge_status(turn.status, "running")
      turn.work_live = Json::object({})
    }
  } else if mooncode_conversation_event_is_assistant_final(event) {
    let content = mooncode_conversation_event_assistant_content(event)
    if content != "" {
      turn.assistant = mooncode_conversation_assistant_message(
        event,
        content,
        client_turn_id=turn.client_turn_id,
      )
      turn.assistant_delta = ""
      turn.status = "done"
      turn.work_live = Json::object({})
      mooncode_conversation_settle_work_steps(turn, "done")
    }
  } else if mooncode_conversation_event_is_visible_progress(event) {
    mooncode_conversation_apply_work_event(turn, event)
  } else if mooncode_conversation_event_is_terminal(event) {
    if mooncode_conversation_message_content(turn.assistant) == "" &&
      turn.assistant_delta.trim().to_owned() != "" {
      turn.assistant = mooncode_conversation_assistant_message(
        event,
        turn.assistant_delta.trim().to_owned(),
        client_turn_id=turn.client_turn_id,
      )
      turn.assistant_delta = ""
    }
    if mooncode_conversation_message_content(turn.assistant) == "" &&
      mooncode_json_string(event, "status", default="") == "failed" {
      turn.assistant = mooncode_conversation_assistant_message(
        event,
        "MoonCode could not complete this request. Review the failed work details and try again.",
        client_turn_id=turn.client_turn_id,
      )
    }
    turn.work_live = Json::object({})
    let terminal_status = mooncode_json_string(event, "status", default="done")
    mooncode_conversation_settle_work_steps(turn, terminal_status)
    turn.status = mooncode_conversation_merge_status(
      turn.status,
      terminal_status,
    )
  }
  turn.updated_at = mooncode_conversation_latest_timestamp(
    turn.updated_at,
    created_at,
  )
  turns[index] = turn
}

///|
fn mooncode_conversation_settle_work_steps(
  turn : MoonCodeConversationTurnDraft,
  terminal_status : String,
) -> Unit {
  let settled = if terminal_status == "failed" {
    "failed"
  } else if terminal_status == "cancelled" {
    "cancelled"
  } else {
    "done"
  }
  for index in 0..<turn.work_steps.length() {
    let step = turn.work_steps[index]
    let status = mooncode_json_string(step, "status", default="")
    if status == "running" || status == "queued" {
      turn.work_steps[index] = mooncode_json_object_with_field(
        step,
        "status",
        settled.to_json(),
      )
    }
  }
}

///|
fn mooncode_conversation_apply_receipt(
  turns : Array[MoonCodeConversationTurnDraft],
  receipt : Json,
) -> Unit {
  let command_id = mooncode_json_string(receipt, "command_id", default="")
  let index = mooncode_conversation_turn_index(turns, command_id)
  if index < 0 {
    return
  }
  let turn = turns[index]
  if mooncode_conversation_message_content(turn.assistant) == "" {
    let answer = mooncode_conversation_receipt_answer(receipt)
    if answer != "" {
      turn.assistant = mooncode_conversation_assistant_message(
        receipt,
        answer,
        client_turn_id=turn.client_turn_id,
      )
      turn.assistant_delta = ""
    }
  }
  let status = mooncode_json_string(receipt, "status", default="")
  if status != "" {
    turn.status = if status == "runtime-failed" {
      "failed"
    } else if status == "runtime-cancelled" {
      "cancelled"
    } else {
      "done"
    }
  }
  if status == "runtime-failed" &&
    mooncode_conversation_message_content(turn.assistant) == "" {
    turn.assistant = mooncode_conversation_assistant_message(
      receipt,
      "MoonCode could not complete this request. Review the failed work details and try again.",
      client_turn_id=turn.client_turn_id,
    )
  }
  turn.work_live = Json::object({})
  turn.updated_at = mooncode_conversation_latest_timestamp(
    turn.updated_at,
    mooncode_json_string(receipt, "completed_at", default=""),
  )
  turns[index] = turn
}

///|
fn mooncode_conversation_turn_draft(
  turn_id~ : String,
  client_turn_id~ : String,
  command_id~ : String,
  created_at~ : String,
) -> MoonCodeConversationTurnDraft {
  {
    turn_id,
    client_turn_id,
    command_id,
    user: Json::object({}),
    work_steps: [],
    work_live: Json::object({}),
    assistant: Json::object({}),
    assistant_delta: "",
    status: "queued",
    started_at: created_at,
    updated_at: created_at,
  }
}

///|
fn mooncode_conversation_turn_visible(
  turn : MoonCodeConversationTurnDraft,
) -> Bool {
  mooncode_conversation_message_content(turn.user) != "" ||
  mooncode_conversation_message_content(turn.assistant) != "" ||
  turn.assistant_delta.trim().to_owned() != "" ||
  turn.work_steps.length() > 0 ||
  turn.work_live.stringify() != "{}"
}

///|
fn mooncode_conversation_turn_json(
  turn : MoonCodeConversationTurnDraft,
  ordinal~ : Int,
) -> Json {
  let assistant = if mooncode_conversation_message_content(turn.assistant) != "" {
    turn.assistant
  } else if turn.assistant_delta.trim().to_owned() != "" {
    {
      "role": "assistant",
      "item_id": mooncode_conversation_slot_id(turn.command_id, "assistant"),
      "content": turn.assistant_delta.trim().to_owned(),
      "status": "running",
      "command_id": turn.command_id,
      "client_turn_id": turn.client_turn_id,
    }
  } else {
    Json::object({})
  }
  {
    "kind": @mooncode_core.conversation_turn_kind(),
    "turn_id": turn.turn_id,
    "client_turn_id": turn.client_turn_id,
    "command_id": turn.command_id,
    "ordinal": ordinal,
    "owner": {
      "turn_id": turn.turn_id,
      "client_turn_id": turn.client_turn_id,
      "command_id": turn.command_id,
    },
    "status": mooncode_conversation_final_status(turn, assistant),
    "started_at": turn.started_at,
    "updated_at": turn.updated_at,
    "user": turn.user,
    "work": mooncode_conversation_work_json(turn, assistant),
    "assistant": assistant,
  }
}

///|
fn mooncode_conversation_command_body(command_entry : Json) -> Json {
  let command = mooncode_json_object_field_or_empty(command_entry, "command")
  if command.stringify() == "{}" {
    command_entry
  } else {
    command
  }
}

///|
fn mooncode_conversation_command_id(
  command_entry : Json,
  command : Json,
) -> String {
  let direct = mooncode_json_string(command_entry, "command_id", default="")
  if direct != "" {
    return direct
  }
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let packet_id = mooncode_json_string(packet, "command_id", default="")
  if packet_id != "" {
    return packet_id
  }
  mooncode_json_string(command, "command_id", default="")
}

///|
fn mooncode_conversation_command_client_turn_id(
  command : Json,
  command_id : String,
) -> String {
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let client_turn_id = mooncode_json_string(
    packet,
    "client_turn_id",
    default="",
  )
  if client_turn_id != "" {
    return client_turn_id
  }
  let direct = mooncode_json_string(command, "client_turn_id", default="")
  if direct != "" {
    direct
  } else {
    command_id
  }
}

///|
fn mooncode_conversation_command_created_at(
  command_entry : Json,
  command : Json,
) -> String {
  let entry_created = mooncode_json_string(
    command_entry,
    "created_at",
    default="",
  )
  if entry_created != "" {
    return entry_created
  }
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let packet_created = mooncode_json_string(packet, "created_at", default="")
  if packet_created != "" {
    packet_created
  } else {
    mooncode_json_string(command, "created_at", default="")
  }
}

///|
fn mooncode_conversation_user_message(
  command_entry : Json,
  command : Json,
) -> Json {
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let command_id = mooncode_conversation_command_id(command_entry, command)
  let client_turn_id = mooncode_conversation_command_client_turn_id(
    command, command_id,
  )
  let content = mooncode_conversation_command_message(command, packet)
  if content == "" {
    return Json::object({})
  }
  {
    "role": "user",
    "item_id": mooncode_conversation_slot_id(command_id, "user"),
    "content": content,
    "status": "done",
    "event_id": "",
    "created_at": mooncode_conversation_command_created_at(
      command_entry, command,
    ),
    "turn_id": command_id,
    "client_turn_id": client_turn_id,
    "command_id": command_id,
    "owner": {
      "turn_id": command_id,
      "client_turn_id": client_turn_id,
      "command_id": command_id,
      "action": mooncode_conversation_command_action(command, packet),
    },
  }
}

///|
fn mooncode_conversation_command_message(
  command : Json,
  packet : Json,
) -> String {
  for
    text in [
      mooncode_json_string(command, "text", default=""),
      mooncode_json_string(packet, "message", default=""),
      mooncode_json_string(
        mooncode_json_object_field_or_empty(command, "payload"),
        "message",
        default="",
      ),
    ] {
    let trimmed = text.trim().to_owned()
    if trimmed != "" {
      return trimmed
    }
  }
  ""
}

///|
fn mooncode_conversation_command_action(
  command : Json,
  packet : Json,
) -> String {
  let action = mooncode_json_string(command, "command", default="")
  if action != "" {
    return action
  }
  mooncode_json_string(packet, "action", default="prompt")
}

///|
fn mooncode_conversation_workspace_field(
  commands : Array[Json],
  key : String,
  fallback~ : String,
) -> String {
  for command_entry in commands {
    let command = mooncode_conversation_command_body(command_entry)
    let packet = mooncode_json_object_field_or_empty(command, "packet")
    let value = mooncode_json_string(packet, key, default="")
    if value != "" {
      return value
    }
    let direct = mooncode_json_string(command, key, default="")
    if direct != "" {
      return direct
    }
  }
  fallback
}

///|
fn mooncode_conversation_assistant_message(
  event : Json,
  content : String,
  client_turn_id~ : String,
) -> Json {
  let command_id = mooncode_json_string(event, "command_id", default="")
  {
    "role": "assistant",
    "item_id": mooncode_conversation_slot_id(command_id, "assistant"),
    "content": content.trim().to_owned(),
    "status": mooncode_conversation_assistant_status(event),
    "event_id": mooncode_json_string(event, "id", default=""),
    "created_at": mooncode_conversation_first_text(
      mooncode_json_string(event, "created_at", default=""),
      mooncode_json_string(event, "completed_at", default=""),
    ),
    "turn_id": command_id,
    "client_turn_id": client_turn_id,
    "command_id": command_id,
    "owner": {
      "turn_id": command_id,
      "client_turn_id": client_turn_id,
      "command_id": command_id,
      "event_kind": mooncode_json_string(event, "kind", default=""),
    },
  }
}

///|
fn mooncode_conversation_assistant_status(event : Json) -> String {
  let status = mooncode_json_string(event, "status", default="done")
  if status == "running" {
    "running"
  } else if status == "failed" {
    "failed"
  } else if status == "cancelled" || status == "runtime-cancelled" {
    "cancelled"
  } else {
    "done"
  }
}

///|
fn mooncode_conversation_work_step(event : Json) -> Json {
  let command_id = mooncode_json_string(event, "command_id", default="")
  let step_id = mooncode_conversation_work_step_id(event)
  let source_kind = mooncode_json_string(
    event,
    "kind",
    default="runtime_update",
  )
  {
    "item_id": step_id,
    "step_id": step_id,
    "event_id": mooncode_json_string(event, "id", default=""),
    "lane": mooncode_json_string(event, "lane", default="runtime"),
    "kind": mooncode_conversation_work_step_kind(event),
    "source_kind": source_kind,
    "title": mooncode_conversation_progress_title(event),
    "summary": mooncode_conversation_progress_detail(event),
    "status": if source_kind == "runtime.planner_selected" ||
      source_kind == "runtime.planner_failed" {
      "done"
    } else {
      mooncode_json_string(event, "status", default="running")
    },
    "tool": mooncode_json_string(event, "tool", default=""),
    "evidence": mooncode_conversation_work_evidence(event),
    "created_at": mooncode_json_string(event, "created_at", default=""),
    "turn_id": command_id,
    "command_id": command_id,
  }
}

///|
fn mooncode_conversation_work_evidence(event : Json) -> Json {
  let lane = mooncode_json_string(event, "lane", default="")
  let kind = mooncode_conversation_work_step_kind(event)
  if kind != "edit" && kind != "test" && kind != "artifact" && kind != "tool" {
    return Json::object({})
  }
  let tool_result = mooncode_json_object_field_or_empty(event, "tool_result")
  let metadata = mooncode_json_object_field_or_empty(tool_result, "metadata")
  let path = mooncode_conversation_first_text(
    mooncode_json_string(event, "path", default=""),
    mooncode_json_string(metadata, "path", default=""),
  )
  let diff = mooncode_conversation_first_text(
    mooncode_json_string(event, "diff", default=""),
    mooncode_json_string(metadata, "diff", default=""),
  )
  let output = mooncode_conversation_first_text(
    mooncode_json_string(tool_result, "output", default=""),
    mooncode_json_string(event, "output", default=""),
  )
  let command = mooncode_conversation_first_text(
    mooncode_json_string(metadata, "cmd", default=""),
    mooncode_json_string(event, "command", default=""),
  )
  {
    "kind": kind,
    "state": mooncode_conversation_evidence_state(event, kind, lane),
    "path": path,
    "diff": diff,
    "command": command,
    "output": output,
    "exit_code": mooncode_json_int(
      metadata,
      "status",
      default=mooncode_json_int(event, "exit_code", default=-1),
    ),
    "truncated": mooncode_json_bool(
      metadata,
      "truncated",
      default=mooncode_json_bool(event, "truncated", default=false),
    ),
  }
}

///|
fn mooncode_conversation_evidence_state(
  event : Json,
  kind : String,
  lane : String,
) -> String {
  let status = mooncode_json_string(event, "status", default="running")
  let tool = mooncode_json_string(event, "tool", default="")
  let source_kind = mooncode_json_string(event, "kind", default="")
  if status == "failed" {
    "failed"
  } else if status == "cancelled" {
    "cancelled"
  } else if status == "running" {
    "pending"
  } else if kind == "edit" || lane == "diff" {
    if source_kind == "runtime.patch_reverted" || tool == "revert_patch" {
      "reverted"
    } else {
      "applied"
    }
  } else if kind == "test" || lane == "test" {
    "passed"
  } else {
    "recorded"
  }
}

///|
fn mooncode_conversation_apply_work_event(
  turn : MoonCodeConversationTurnDraft,
  event : Json,
) -> Unit {
  let kind = mooncode_json_string(event, "kind", default="")
  if kind == "runtime.planner_started" {
    turn.work_live = {
      "item_id": mooncode_conversation_slot_id(turn.command_id, "work-live"),
      "event_id": mooncode_json_string(event, "id", default=""),
      "kind": "thought",
      "title": "Planning next steps",
      "summary": "Choosing the tools needed for this request.",
      "status": "running",
    }
    turn.status = mooncode_conversation_merge_status(turn.status, "running")
    return
  }
  if kind == "reasoning_delta" {
    turn.work_live = {
      "item_id": mooncode_conversation_slot_id(turn.command_id, "work-live"),
      "event_id": mooncode_json_string(event, "id", default=""),
      "kind": "thought",
      "title": "Reviewing the request",
      "summary": "Thinking through the request.",
      "status": "running",
    }
    turn.status = mooncode_conversation_merge_status(turn.status, "running")
    return
  }
  let step = mooncode_conversation_work_step(event)
  let index = mooncode_conversation_work_step_index(
    turn.work_steps,
    step,
    event,
  )
  if index >= 0 {
    let stable_id = mooncode_json_string(
      turn.work_steps[index],
      "item_id",
      default="",
    )
    turn.work_steps[index] = step
      |> mooncode_json_object_with_field("item_id", stable_id.to_json())
      |> mooncode_json_object_with_field("step_id", stable_id.to_json())
  } else {
    turn.work_steps.push(step)
  }
  turn.work_live = Json::object({})
  let event_status = if kind == "runtime.planner_failed" {
    "done"
  } else {
    mooncode_json_string(event, "status", default="running")
  }
  turn.status = if event_status == "failed" {
    "failed"
  } else if event_status == "cancelled" {
    "cancelled"
  } else if turn.status == "done" {
    "done"
  } else {
    "running"
  }
}

///|
fn mooncode_conversation_work_step_index(
  steps : Array[Json],
  step : Json,
  event : Json,
) -> Int {
  let item_id = mooncode_json_string(step, "item_id", default="")
  for index, existing in steps {
    if item_id != "" &&
      mooncode_json_string(existing, "item_id", default="") == item_id {
      return index
    }
  }
  let event_name = mooncode_json_string(event, "event", default="")
  let tool = mooncode_json_string(event, "tool", default="")
  if event_name == "tool_result" && tool != "" {
    let path = mooncode_json_string(event, "path", default="")
    if path != "" {
      let mut index = steps.length() - 1
      while index >= 0 {
        let existing = steps[index]
        let evidence = mooncode_json_object_field_or_empty(existing, "evidence")
        if mooncode_json_string(existing, "tool", default="") == tool &&
          mooncode_json_string(evidence, "path", default="") == path &&
          mooncode_json_string(existing, "status", default="") == "running" {
          return index
        }
        index = index - 1
      }
    }
    let mut index = steps.length() - 1
    while index >= 0 {
      let existing = steps[index]
      if mooncode_json_string(existing, "tool", default="") == tool &&
        mooncode_json_string(existing, "status", default="") == "running" {
        return index
      }
      index = index - 1
    }
  }
  -1
}

///|
fn mooncode_conversation_work_step_id(event : Json) -> String {
  let command_id = mooncode_json_string(event, "command_id", default="")
  let kind = mooncode_json_string(event, "kind", default="")
  if kind == "runtime.planner_selected" || kind == "runtime.planner_failed" {
    return "turn:\{command_id}:work:planner"
  }
  let tool_call_id = mooncode_json_string(event, "tool_call_id", default="")
  if tool_call_id != "" {
    return "turn:\{command_id}:work:\{tool_call_id}"
  }
  let event_id = mooncode_json_string(event, "id", default="")
  if event_id != "" {
    return "turn:\{command_id}:work:\{event_id}"
  }
  let kind = mooncode_json_string(event, "kind", default="status")
  let step = mooncode_json_int(event, "planner_step", default=0)
  "turn:\{command_id}:work:\{kind}:\{step}"
}

///|
fn mooncode_conversation_work_step_kind(event : Json) -> String {
  let kind = mooncode_json_string(event, "kind", default="")
  let lane = mooncode_json_string(event, "lane", default="")
  let tool = mooncode_json_string(event, "tool", default="")
  if kind == "reasoning_message" || kind.has_prefix("runtime.planner_") {
    "thought"
  } else if tool == "read" || tool == "grep" || tool == "glob" {
    "context"
  } else if lane == "diff" {
    "edit"
  } else if lane == "test" {
    "test"
  } else if lane == "artifact" {
    "artifact"
  } else if tool != "" {
    "tool"
  } else {
    "status"
  }
}

///|
fn mooncode_conversation_slot_id(command_id : String, slot : String) -> String {
  "turn:\{command_id}:\{slot}"
}

///|
fn mooncode_conversation_work_json(
  turn : MoonCodeConversationTurnDraft,
  assistant : Json,
) -> Json {
  let status = mooncode_conversation_work_status(turn, assistant)
  if status == "queued" &&
    turn.work_steps.length() == 0 &&
    turn.work_live.stringify() == "{}" {
    return Json::object({})
  }
  {
    "item_id": mooncode_conversation_slot_id(turn.command_id, "work"),
    "status": status,
    "summary": mooncode_conversation_work_summary(turn, status),
    "steps": Json::array(turn.work_steps),
    "live": if status == "done" || status == "failed" || status == "cancelled" {
      Json::object({})
    } else {
      turn.work_live
    },
  }
}

///|
fn mooncode_conversation_work_status(
  turn : MoonCodeConversationTurnDraft,
  assistant : Json,
) -> String {
  if turn.status == "failed" || turn.status == "cancelled" {
    turn.status
  } else if mooncode_conversation_message_content(assistant) != "" &&
    mooncode_json_string(assistant, "status", default="") == "done" {
    "done"
  } else if turn.status == "queued" {
    "queued"
  } else {
    "running"
  }
}

///|
fn mooncode_conversation_work_summary(
  turn : MoonCodeConversationTurnDraft,
  status : String,
) -> String {
  let live_title = mooncode_json_string(turn.work_live, "title", default="")
  if status == "running" && live_title != "" {
    return live_title
  }
  if status == "queued" {
    return "Request queued"
  }
  if status == "failed" || status == "cancelled" {
    return "Work interrupted"
  }
  if turn.work_steps.length() > 0 {
    let title = mooncode_json_string(
      turn.work_steps[turn.work_steps.length() - 1],
      "title",
      default="",
    )
    if title != "" {
      return title
    }
  }
  if status == "done" {
    "Completed work"
  } else {
    "Working on request"
  }
}

///|
fn mooncode_conversation_event_is_service_lifecycle(event : Json) -> Bool {
  let kind = mooncode_json_string(event, "kind", default="")
  kind == "runtime.service_started" ||
  kind == "runtime.service_finished" ||
  kind == "runtime.service_failed"
}

///|
fn mooncode_conversation_event_is_assistant_delta(event : Json) -> Bool {
  let kind = mooncode_json_string(event, "kind", default="")
  let event_name = mooncode_json_string(event, "event", default="")
  kind == "assistant_delta" || event_name == "assistant_delta"
}

///|
fn mooncode_conversation_event_is_assistant_final(event : Json) -> Bool {
  let kind = mooncode_json_string(event, "kind", default="")
  let event_name = mooncode_json_string(event, "event", default="")
  kind == "finish" || event_name == "finish"
}

///|
fn mooncode_conversation_event_is_terminal(event : Json) -> Bool {
  let kind = mooncode_json_string(event, "kind", default="")
  kind == mooncode_event_runtime_turn_finished() ||
  kind == "runtime.turn_finished" ||
  mooncode_json_string(event, "status", default="") == "failed"
}

///|
fn mooncode_conversation_event_is_visible_progress(event : Json) -> Bool {
  let kind = mooncode_json_string(event, "kind", default="")
  let event_name = mooncode_json_string(event, "event", default="")
  let lane = mooncode_json_string(event, "lane", default="")
  kind == "runtime.turn_started" ||
  kind == "runtime.planner_started" ||
  kind == "runtime.planner_selected" ||
  kind == "runtime.planner_failed" ||
  kind == "reasoning_delta" ||
  kind == "reasoning_message" ||
  kind == mooncode_event_tool_call() ||
  event_name == mooncode_event_tool_call() ||
  event_name == "tool_result" ||
  kind == mooncode_event_test_result() ||
  kind == mooncode_event_package_built() ||
  lane == "diff" ||
  lane == "artifact" ||
  lane == "test"
}

///|
fn mooncode_conversation_event_content(event : Json) -> String {
  for key in ["content", "detail", "message", "text"] {
    let text = mooncode_json_string(event, key, default="").trim().to_owned()
    if text != "" {
      return text
    }
  }
  ""
}

///|
fn mooncode_conversation_event_assistant_content(event : Json) -> String {
  let tool_result = mooncode_json_object_field_or_empty(event, "tool_result")
  let metadata = mooncode_json_object_field_or_empty(tool_result, "metadata")
  for
    text in [
      mooncode_json_string(metadata, "answer", default=""),
      mooncode_json_string(tool_result, "output", default=""),
      mooncode_json_string(event, "content", default=""),
      mooncode_json_string(event, "detail", default=""),
    ] {
    let trimmed = text.trim().to_owned()
    if trimmed != "" && trimmed != "finished" {
      return trimmed
    }
  }
  ""
}

///|
fn mooncode_conversation_receipt_answer(receipt : Json) -> String {
  let execution = mooncode_json_object_field_or_empty(receipt, "execution")
  for result in mooncode_json_array_items(execution, "tool_results") {
    if mooncode_json_string(result, "tool", default="") == "finish" {
      let metadata = mooncode_json_object_field_or_empty(result, "metadata")
      for
        text in [
          mooncode_json_string(metadata, "answer", default=""),
          mooncode_json_string(result, "output", default=""),
        ] {
        let trimmed = text.trim().to_owned()
        if trimmed != "" {
          return trimmed
        }
      }
    }
  }
  ""
}

///|
fn mooncode_conversation_progress_title(event : Json) -> String {
  let kind = mooncode_json_string(event, "kind", default="")
  let event_name = mooncode_json_string(event, "event", default="")
  let lane = mooncode_json_string(event, "lane", default="")
  let tool = mooncode_json_string(event, "tool", default="")
  let failed = mooncode_json_string(event, "status", default="") == "failed"
  if kind == "runtime.turn_started" {
    "Starting request"
  } else if kind == "runtime.planner_started" {
    "Planning next steps"
  } else if kind == "runtime.planner_selected" {
    "Plan ready"
  } else if kind == "runtime.planner_failed" {
    "Using a local plan"
  } else if kind == "reasoning_delta" || kind == "reasoning_message" {
    "Thinking"
  } else if event_name == mooncode_event_tool_call() ||
    kind == mooncode_event_tool_call() {
    mooncode_conversation_tool_title(lane, tool, started=true, failed~)
  } else if event_name == "tool_result" {
    mooncode_conversation_tool_title(lane, tool, started=false, failed~)
  } else if lane == "test" {
    "Checking result"
  } else if lane == "diff" {
    "Editing files"
  } else if lane == "artifact" {
    "Preparing output"
  } else {
    "Working on request"
  }
}

///|
fn mooncode_conversation_progress_detail(event : Json) -> String {
  let kind = mooncode_json_string(event, "kind", default="")
  let event_name = mooncode_json_string(event, "event", default="")
  let lane = mooncode_json_string(event, "lane", default="")
  let tool = mooncode_json_string(event, "tool", default="")
  let path = mooncode_json_string(event, "path", default="").trim().to_owned()
  let failed = mooncode_json_string(event, "status", default="") == "failed"
  if kind == "runtime.turn_started" {
    "Started working on the request."
  } else if kind == "runtime.planner_started" {
    "Choosing the tools needed for this request."
  } else if kind == "runtime.planner_selected" {
    "Selected the next bounded actions."
  } else if kind == "runtime.planner_failed" {
    "The model plan was unavailable, so MoonClaw continued with a bounded local plan."
  } else if kind == "reasoning_delta" || kind == "reasoning_message" {
    "Reviewed the request."
  } else if event_name == mooncode_event_tool_call() ||
    kind == mooncode_event_tool_call() {
    mooncode_conversation_tool_detail(lane, tool, path, started=true, failed~)
  } else if event_name == "tool_result" {
    mooncode_conversation_tool_detail(lane, tool, path, started=false, failed~)
  } else if lane == "test" {
    "Finished checking the result."
  } else if lane == "diff" {
    if path == "" {
      "Updated the relevant files."
    } else {
      "Updated `\{path}`."
    }
  } else if lane == "artifact" {
    "Prepared the requested output."
  } else {
    "Made progress on the request."
  }
}

///|
fn mooncode_conversation_tool_title(
  lane : String,
  tool : String,
  started~ : Bool,
  failed~ : Bool,
) -> String {
  if tool == "read" || tool == "grep" || tool == "glob" {
    if failed {
      "Could not check context"
    } else if started {
      "Checking context"
    } else {
      "Checked context"
    }
  } else if lane == "diff" {
    if started {
      "Editing files"
    } else {
      "Updated files"
    }
  } else if lane == "test" {
    if started {
      "Checking result"
    } else {
      "Checked result"
    }
  } else if lane == "artifact" {
    if started {
      "Preparing output"
    } else {
      "Prepared output"
    }
  } else if tool == "shell" || tool == "moon_cmd" || tool == "moon_check" {
    if failed {
      "Command failed"
    } else if started {
      "Running command"
    } else {
      "Finished command"
    }
  } else if started {
    "Choosing next action"
  } else {
    "Finished action"
  }
}

///|
fn mooncode_conversation_tool_detail(
  lane : String,
  tool : String,
  path : String,
  started~ : Bool,
  failed~ : Bool,
) -> String {
  if tool == "read" || tool == "grep" || tool == "glob" {
    if failed {
      if path == "" {
        "Could not read project context."
      } else {
        "Could not read `\{path}`."
      }
    } else if started {
      if path == "" {
        "Reading project context."
      } else {
        "Reading `\{path}`."
      }
    } else if path == "" {
      "Checked project context."
    } else {
      "Read `\{path}`."
    }
  } else if lane == "diff" {
    if started {
      if path == "" {
        "Preparing file changes."
      } else {
        "Preparing changes to `\{path}`."
      }
    } else if path == "" {
      "Updated the relevant files."
    } else {
      "Updated `\{path}`."
    }
  } else if lane == "test" {
    if started {
      "Running the requested check."
    } else {
      "Finished checking the result."
    }
  } else if lane == "artifact" {
    if started {
      "Preparing the requested output."
    } else {
      "Prepared the requested output."
    }
  } else if failed {
    "This work step failed."
  } else if started {
    "Chose what to do next."
  } else {
    "Finished a work step."
  }
}

///|
fn mooncode_conversation_turn_index(
  turns : Array[MoonCodeConversationTurnDraft],
  command_id : String,
) -> Int {
  if command_id == "" {
    return -1
  }
  for index, turn in turns {
    if turn.command_id == command_id {
      return index
    }
  }
  -1
}

///|
fn mooncode_conversation_message_content(value : Json) -> String {
  mooncode_json_string(value, "content", default="").trim().to_owned()
}

///|
fn mooncode_conversation_final_status(
  turn : MoonCodeConversationTurnDraft,
  assistant : Json,
) -> String {
  if mooncode_conversation_message_content(assistant) != "" &&
    mooncode_json_string(assistant, "status", default="") == "done" {
    "done"
  } else {
    turn.status
  }
}

///|
fn mooncode_conversation_merge_status(
  current : String,
  next : String,
) -> String {
  if current == "failed" || next == "failed" {
    "failed"
  } else if current == "cancelled" || next == "cancelled" {
    "cancelled"
  } else if current == "done" || next == "done" {
    "done"
  } else if current == "running" || next == "running" {
    "running"
  } else {
    current
  }
}

///|
fn mooncode_conversation_latest_timestamp(
  current : String,
  next : String,
) -> String {
  if next == "" {
    current
  } else if current == "" || next > current {
    next
  } else {
    current
  }
}

///|
fn mooncode_conversation_first_text(a : String, b : String) -> String {
  if a != "" {
    a
  } else {
    b
  }
}
