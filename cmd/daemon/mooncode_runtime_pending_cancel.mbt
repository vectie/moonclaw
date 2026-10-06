///|
priv enum MoonCodeCancelSelection {
  Settled(Json)
  Active(Json)
}

///|
fn mooncode_runtime_cancel_control_receipt(
  session_id : String,
  book_root : String,
  command : Json,
  target_command_id : String,
  cancelled_event : Json,
  interrupted_runtime~ : Bool,
  cancel_status? : String = "",
  target_status? : String = "",
  now~ : @clock.Timestamp,
) -> Json {
  let receipt = mooncode_runtime_control_receipt(
    session_id,
    book_root,
    command,
    action="cancel",
    message=if cancel_status == "already-terminal" {
      "MoonClaw preserved the terminal outcome of request `\{target_command_id}`."
    } else if target_command_id == "" {
      "MoonClaw found no active or pending MoonCode request to cancel."
    } else {
      "MoonClaw cancelled request `\{target_command_id}`."
    },
    now~,
  )
  guard receipt is Object(fields) else { return receipt }
  fields["target_command_id"] = target_command_id.to_json()
  fields["cancelled_event"] = cancelled_event
  fields["interrupted_runtime"] = interrupted_runtime.to_json()
  fields["cancel_status"] = (if cancel_status != "" {
    cancel_status
  } else if target_command_id == "" {
    "idle"
  } else {
    "cancelled"
  }).to_json()
  fields["target_status"] = target_status.to_json()
  receipt
}

///|
fn mooncode_runtime_cancel_response(receipt : Json) -> Json {
  let target = mooncode_json_string(receipt, "target_command_id", default="")
  {
    "kind": "mooncode-cancel-control",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "accepted": true,
    "session_id": mooncode_json_string(receipt, "session_id", default=""),
    "book_root": mooncode_json_string(receipt, "book_root", default=""),
    "interrupted_runtime": mooncode_json_bool(
      receipt,
      "interrupted_runtime",
      default=false,
    ),
    "target_command_id": target,
    "status": mooncode_json_string(
      receipt,
      "cancel_status",
      default=if target == "" { "idle" } else { "cancelled" },
    ),
    "target_status": mooncode_json_string(receipt, "target_status", default=""),
    "cancelled_event": mooncode_json_object_field_or_empty(
      receipt, "cancelled_event",
    ),
    "control_receipt": receipt,
  }
}

///|
/// Resolve controls under the same existing session lock used by atomic claims.
/// A pending target is terminal before the cancel itself becomes completed.
async fn mooncode_runtime_cancel_pending_atomic(
  session_id : String,
  book_root : String,
  command : Json,
  now~ : @clock.Timestamp,
) -> MoonCodeCancelSelection {
  let lifecycle_gate = mooncode_open_session_lifecycle_gate(
    book_root, session_id,
  )
  defer lifecycle_gate.close()
  lifecycle_gate.lock(Shared)
  defer lifecycle_gate.unlock()
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Exclusive)
  defer session_lock.unlock()
  mooncode_require_active_session_state_locked(
    book_root,
    session_id,
    allow_create=true,
  )
  let path = mooncode_session_journal_path(book_root, session_id)
  let journal = mooncode_read_session_journal_path(path, session_id)
  let commands = mooncode_journal_entries(journal, mooncode_journal_command())
  let receipts = mooncode_journal_entries(
    journal,
    mooncode_journal_runtime_receipt(),
  )
  let control_id = mooncode_command_id(command)
  mooncode_runtime_cancel_require_command(commands, command)
  for receipt in receipts {
    if mooncode_json_string(receipt, "command_id", default="") == control_id &&
      mooncode_json_string(receipt, "status", default="") == "runtime-completed" &&
      mooncode_json_string(receipt, "control", default="") == "cancel" {
      return Settled(mooncode_runtime_cancel_response(receipt))
    }
  }
  // A process can stop after the target receipt but before the control receipt.
  // The control identity must remain pinned to that already settled target.
  for receipt in receipts {
    if mooncode_json_string(receipt, "status", default="") ==
      "runtime-cancelled" &&
      mooncode_json_string(receipt, "control_command_id", default="") ==
      control_id {
      let events = mooncode_json_array_items(receipt, "events")
      let event = if events.is_empty() { Json::object({}) } else { events[0] }
      return mooncode_runtime_finish_cancel_locked(
        session_id,
        book_root,
        command,
        mooncode_json_string(receipt, "command_id", default=""),
        event,
        interrupted_runtime=mooncode_json_bool(
          receipt,
          "interrupted_runtime",
          default=false,
        ),
        now~,
      )
    }
  }
  // Older active cancellation receipts did not carry their control identity.
  // Recover it only from the explicit matching active cancellation event.
  let events = mooncode_journal_entries(journal, mooncode_journal_event()).filter(event => {
      mooncode_json_string(event, "control_id", default="") == control_id &&
      mooncode_json_string(event, "control_command_id", default="") ==
      control_id
    },
  )
  for event in events {
    for receipt in receipts {
      if mooncode_runtime_legacy_cancel_matches(
          session_id, book_root, control_id, event, receipt,
        ) {
        return mooncode_runtime_finish_cancel_locked(
          session_id,
          book_root,
          command,
          mooncode_json_string(receipt, "command_id", default=""),
          event,
          interrupted_runtime=mooncode_json_bool(
            receipt,
            "interrupted_runtime",
            default=false,
          ),
          now~,
        )
      }
    }
  }
  // Pin an active selection before releasing the lock or interrupting a task.
  // Retries must never reinterpret an untargeted control against later work.
  for receipt in receipts {
    if mooncode_json_string(receipt, "command_id", default="") == control_id &&
      mooncode_json_string(receipt, "status", default="") ==
      "runtime-cancel-requested" {
      let selected = mooncode_json_object_field_or_empty(receipt, "target_item")
      mooncode_runtime_cancel_require_command(
        commands,
        mooncode_json_object_field_or_empty(selected, "command"),
      )
      return Active(selected)
    }
  }
  let claim_state = mooncode_runtime_claim_state_from_logs(
    session_id,
    book_root,
    commands,
    receipts,
    journal_path=path,
  )
  let claimed = mooncode_json_array_items(claim_state, "claimed_commands")
  let active_item = if claimed.is_empty() {
    Json::object({})
  } else {
    claimed[0]
  }
  let active_id = mooncode_json_string(active_item, "command_id", default="")
  let requested = mooncode_runtime_control_field(command, "target_command_id")
  if active_id != "" && (requested == "" || requested == active_id) {
    ignore(
      mooncode_append_session_journal_once_locked(
        book_root,
        session_id,
        mooncode_journal_runtime_receipt(),
        {
          "kind": mooncode_kind_runtime_receipt(),
          "protocol": mooncode_protocol_version(),
          "owner": "moonclaw",
          "session_id": session_id,
          "book_root": book_root,
          "command_id": control_id,
          "status": "runtime-cancel-requested",
          "control": "cancel",
          "command": command,
          "target_command_id": active_id,
          "target_item": active_item,
          "created_at": now,
        },
      ),
    )
    return Active(active_item)
  }
  let control_state = mooncode_runtime_control_state_from_logs(
    session_id,
    book_root,
    commands,
    receipts,
    journal_path=path,
  )
  let pending_ids = mooncode_json_array_items(control_state, "pending_turn_ids")
  let mut target = ""
  for id in pending_ids {
    if id is String(id) && (requested == "" || requested == id) {
      target = id
      break
    }
  }
  if requested != "" && target == "" {
    raise json_error(409, "Conflict", {
      "error": {
        "code": -1,
        "message": "MoonCode cancellation does not target an active or pending request",
        "metadata": {
          "session_id": session_id,
          "requested_target_command_id": requested,
          "active_target_command_id": active_id,
        },
      },
    })
  }
  let mut event = Json::object({})
  if target != "" {
    let mut target_item = Json::object({})
    for item in mooncode_json_array_items(control_state, "lifecycle_commands") {
      if mooncode_json_string(item, "command_id", default="") == target {
        target_item = item
        break
      }
    }
    event = {
      "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{target}-cancelled-\{control_id}",
      "protocol": mooncode_protocol_version(),
      "contract_id": @moonlib_conversation.control_contract_id(),
      "control_kind": "turn-cancellation",
      "control_id": control_id,
      "session_id": session_id,
      "command_id": target,
      "target_command_id": target,
      "control_command_id": control_id,
      "lane": "runtime",
      "kind": @moonlib_conversation.cancellation_event_kind(),
      "event": @moonlib_conversation.cancellation_event_kind(),
      "title": "Pending request cancelled",
      "status": "cancelled",
      "state": "cancelled",
      "detail": "MoonClaw withdrew this pending request before execution.",
      "created_at": now,
      // A pending withdrawal must not cancel an unrelated active goal.
      "source": "moonclaw-native-runtime-pending-control",
    }
    let receipt = mooncode_runtime_cancelled_receipt(
      session_id,
      book_root,
      target_item,
      now~,
    )
    if receipt is Object(fields) {
      fields["control_command_id"] = control_id.to_json()
      fields["message"] = "MoonClaw withdrew this pending MoonCode request.".to_json()
      fields["execution"] = {
        "accepted": false,
        "cancelled": true,
        "control": "cancelled",
        "message": "MoonClaw withdrew this pending MoonCode request.",
        "events": Json::array([event]),
      }
      fields["events"] = Json::array([event])
    }
    ignore(
      mooncode_append_session_journal_once_locked(
        book_root,
        session_id,
        mooncode_journal_runtime_receipt(),
        receipt,
      ),
    )
  }
  mooncode_runtime_finish_cancel_locked(
    session_id,
    book_root,
    command,
    target,
    event,
    interrupted_runtime=false,
    now~,
  )
}

///|
async fn mooncode_runtime_finish_cancel_locked(
  session_id : String,
  book_root : String,
  command : Json,
  target : String,
  event : Json,
  interrupted_runtime~ : Bool,
  cancel_status? : String = "",
  target_status? : String = "",
  now~ : @clock.Timestamp,
) -> MoonCodeCancelSelection {
  if mooncode_json_string(event, "id", default="") != "" {
    ignore(
      mooncode_append_session_journal_once_locked(
        book_root,
        session_id,
        mooncode_journal_event(),
        event,
      ),
    )
  }
  let receipt = mooncode_runtime_cancel_control_receipt(
    session_id,
    book_root,
    command,
    target,
    event,
    interrupted_runtime~,
    cancel_status~,
    target_status~,
    now~,
  )
  ignore(
    mooncode_append_session_journal_once_locked(
      book_root,
      session_id,
      mooncode_journal_runtime_receipt(),
      receipt,
    ),
  )
  Settled(mooncode_runtime_cancel_response(receipt))
}

///|
fn mooncode_runtime_legacy_cancel_matches(
  session_id : String,
  book_root : String,
  control_id : String,
  event : Json,
  receipt : Json,
) -> Bool {
  let target = mooncode_json_string(event, "target_command_id", default="")
  mooncode_goal_runtime_is_active_cancel_source(event) &&
  mooncode_json_string(event, "contract_id", default="") ==
  @moonlib_conversation.control_contract_id() &&
  mooncode_json_string(event, "session_id", default="") == session_id &&
  mooncode_json_string(event, "control_id", default="") == control_id &&
  mooncode_json_string(receipt, "session_id", default="") == session_id &&
  mooncode_json_string(receipt, "book_root", default="") == book_root &&
  mooncode_json_string(receipt, "command_id", default="") == target &&
  mooncode_json_string(receipt, "status", default="") == "runtime-cancelled" &&
  mooncode_json_string(receipt, "control", default="") == "cancelled" &&
  mooncode_json_string(receipt, "runtime_mode", default="") ==
  "moonclaw-native-runtime-control" &&
  mooncode_json_string(receipt, "control_command_id", default="") == ""
}
