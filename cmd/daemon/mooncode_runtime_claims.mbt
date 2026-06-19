///|
async fn Daemon::mooncode_runtime_claim_state(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let session_id = session_id.to_owned()
  let book_root = mooncode_request_book_root(r)
  let state = self.mooncode_runtime_claim_state_payload(session_id, book_root)
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(state.stringify(indent=2))
}

///|
async fn Daemon::mooncode_runtime_claim(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
  let body : Json = reader.read() catch { _ => Json::object({}) }
  let session_id = session_id.to_owned()
  let requested_book_root = mooncode_request_book_root(r)
  let book_root = if requested_book_root == "" {
    mooncode_json_string(body, "book_root", default="")
  } else {
    requested_book_root
  }
  if book_root == "" {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": "MoonCode runtime claim requires book_root query or JSON field",
        "metadata": { "session_id": session_id },
      },
    })
  }
  let before = self.mooncode_runtime_claim_state_payload(session_id, book_root)
  let receipts = mooncode_runtime_claim_receipts(
    session_id,
    book_root,
    before,
    body,
    now=self.clock.now(),
  )
  for receipt in receipts {
    mooncode_append_jsonl(
      mooncode_runtime_dispatches_path(book_root, session_id),
      receipt,
    )
  }
  let after = self.mooncode_runtime_claim_state_payload(session_id, book_root)
  w.header().set("Content-Type", "application/json")
  w.write_header(202, reason="Accepted")
  w.write(
    (
      {
        "kind": "mooncode-runtime-claim",
        "protocol": mooncode_protocol_version(),
        "owner": "moonclaw",
        "session_id": session_id,
        "book_root": book_root,
        "claimed_count": receipts.length(),
        "claimed_commands": Json::array(receipts),
        "claim_state": after,
        "previous_claim_state": before,
      } : Json).stringify(indent=2),
  )
}

///|
async fn Daemon::mooncode_runtime_dispatch(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
  let body : Json = reader.read() catch { _ => Json::object({}) }
  let session_id = session_id.to_owned()
  let requested_book_root = mooncode_request_book_root(r)
  let book_root = if requested_book_root == "" {
    mooncode_json_string(body, "book_root", default="")
  } else {
    requested_book_root
  }
  if book_root == "" {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": "MoonCode runtime dispatch requires book_root query or JSON field",
        "metadata": { "session_id": session_id },
      },
    })
  }
  let consumer_id = mooncode_json_string(
    body,
    "consumer_id",
    default="moonclaw-daemon",
  )
  let before = self.mooncode_runtime_claim_state_payload(session_id, book_root)
  let claim_receipts = if mooncode_json_array_items(before, "claimed_commands").length() ==
    0 {
    mooncode_runtime_claim_receipts(
      session_id,
      book_root,
      before,
      body,
      now=self.clock.now(),
    )
  } else {
    []
  }
  for receipt in claim_receipts {
    mooncode_append_jsonl(
      mooncode_runtime_dispatches_path(book_root, session_id),
      receipt,
    )
  }
  let claimed_state = self.mooncode_runtime_claim_state_payload(
    session_id, book_root,
  )
  let claimed = mooncode_json_array_items(claimed_state, "claimed_commands")
  if claimed.length() == 0 {
    w.header().set("Content-Type", "application/json")
    w.write_header(200)
    w.write(
      (
        {
          "kind": "mooncode-runtime-dispatch",
          "protocol": mooncode_protocol_version(),
          "owner": "moonclaw",
          "session_id": session_id,
          "book_root": book_root,
          "dispatched": false,
          "message": "No claimable or claimed MoonCode command is ready for dispatch.",
          "claim_receipts": Json::array(claim_receipts),
          "claim_state": claimed_state,
          "previous_claim_state": before,
        } : Json).stringify(indent=2),
    )
    return
  }
  let item = claimed[0]
  let command = mooncode_json_object_field_or_empty(item, "command")
  let report = mooncode_validate_command_body(session_id, command)
  let execution = if mooncode_json_bool(report, "ok", default=false) {
    let action = mooncode_json_string(command, "command", default="prompt")
    if action == "cancel" {
      self.mooncode_cancel_command_response(
        session_id~,
        command,
        persist_command=false,
        dispatch_source="moonclaw-native-runtime-dispatch",
      )
    } else {
      self.mooncode_forward_command_to_task(
        group~,
        session_id~,
        command,
        persist_command=false,
        dispatch_source="moonclaw-native-runtime-dispatch",
      )
    }
  } else {
    {
      "accepted": false,
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": mooncode_json_string(item, "command_id", default=""),
      "control": "invalid",
      "message": mooncode_json_string(
        report,
        "message",
        default="Invalid MoonCode command",
      ),
      "validation": report,
      "events": Json::array([]),
    }
  }
  let receipt = mooncode_runtime_dispatch_receipt(
    session_id,
    book_root,
    item,
    execution,
    consumer_id~,
    now=self.clock.now(),
  )
  mooncode_append_jsonl(
    mooncode_runtime_dispatches_path(book_root, session_id),
    receipt,
  )
  let after = self.mooncode_runtime_claim_state_payload(session_id, book_root)
  w.header().set("Content-Type", "application/json")
  w.write_header(202, reason="Accepted")
  w.write(
    (
      {
        "kind": "mooncode-runtime-dispatch",
        "protocol": mooncode_protocol_version(),
        "owner": "moonclaw",
        "session_id": session_id,
        "book_root": book_root,
        "dispatched": mooncode_json_bool(execution, "accepted", default=false),
        "command_id": mooncode_json_string(item, "command_id", default=""),
        "claim_receipts": Json::array(claim_receipts),
        "dispatch_receipt": receipt,
        "execution": execution,
        "claim_state": after,
        "previous_claim_state": before,
      } : Json).stringify(indent=2),
  )
}

///|
async fn Daemon::mooncode_runtime_claim_state_payload(
  self : Daemon,
  session_id : String,
  book_root : String,
) -> Json {
  ignore(self)
  let commands_path = mooncode_commands_path(book_root, session_id)
  let dispatches_path = mooncode_runtime_dispatches_path(book_root, session_id)
  let commands = mooncode_read_jsonl(commands_path)
  let receipts = mooncode_read_jsonl(dispatches_path)
  mooncode_runtime_claim_state_from_logs(
    session_id,
    book_root,
    commands,
    receipts,
    commands_path~,
    dispatches_path~,
  )
}

///|
fn mooncode_runtime_claim_state_from_logs(
  session_id : String,
  book_root : String,
  commands : Array[Json],
  receipts : Array[Json],
  commands_path~ : String,
  dispatches_path~ : String,
) -> Json {
  let latest_receipts : Map[String, Json] = {}
  for receipt in receipts {
    let command_id = mooncode_json_string(receipt, "command_id", default="")
    if command_id != "" {
      latest_receipts[command_id] = receipt
    }
  }
  let claimable : Array[Json] = []
  let claimed : Array[Json] = []
  let delivered : Array[Json] = []
  let invalid : Array[Json] = []
  let order_blocked : Array[Json] = []
  let mut active_blocker = ""
  for index in 0..<commands.length() {
    let command = commands[index]
    let command_id = mooncode_runtime_command_entry_id(command)
    let receipt = if command_id == "" {
      None
    } else {
      latest_receipts.get(command_id)
    }
    let receipt_status = match receipt {
      Some(value) => mooncode_json_string(value, "status", default="")
      None => ""
    }
    if command_id == "" {
      let item = mooncode_runtime_claim_item(
        command,
        index,
        receipt,
        claim_status="invalid",
        order_blocked_by=active_blocker,
      )
      invalid.push(item)
      if active_blocker == "" {
        active_blocker = "invalid-command:\{index}"
      }
    } else if mooncode_runtime_receipt_status_delivered(receipt_status) {
      let item = mooncode_runtime_claim_item(
        command,
        index,
        receipt,
        claim_status="delivered",
        order_blocked_by=active_blocker,
      )
      delivered.push(item)
    } else if receipt_status == "runtime-claimed" {
      let item = mooncode_runtime_claim_item(
        command,
        index,
        receipt,
        claim_status="claimed",
        order_blocked_by=active_blocker,
      )
      claimed.push(item)
      if active_blocker == "" {
        active_blocker = command_id
      }
    } else if active_blocker != "" {
      let item = mooncode_runtime_claim_item(
        command,
        index,
        receipt,
        claim_status="order-blocked",
        order_blocked_by=active_blocker,
      )
      order_blocked.push(item)
    } else {
      let item = mooncode_runtime_claim_item(
        command,
        index,
        receipt,
        claim_status="claimable",
        order_blocked_by="",
      )
      claimable.push(item)
      active_blocker = command_id
    }
  }
  {
    "kind": "mooncode-runtime-claim-state",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "runtime_command_log_path": commands_path,
    "runtime_dispatch_log_path": dispatches_path,
    "command_count": commands.length(),
    "receipt_count": receipts.length(),
    "claimable_command_count": claimable.length(),
    "claimed_command_count": claimed.length(),
    "delivered_command_count": delivered.length(),
    "invalid_command_count": invalid.length(),
    "order_blocked_command_count": order_blocked.length(),
    "claim_ready": claimable.length() > 0,
    "claim_endpoint": "/v1/code/sessions/\{session_id}/runtime-claim?book_root=<path>",
    "ordering_rule": "MoonClaw claims the next unresolved command from commands.jsonl in append order; active claims and invalid commands block later commands until a runtime-dispatch receipt resolves the blocker.",
    "claimable_commands": Json::array(claimable),
    "claimed_commands": Json::array(claimed),
    "delivered_commands": Json::array(delivered),
    "invalid_commands": Json::array(invalid),
    "order_blocked_commands": Json::array(order_blocked),
  }
}

///|
fn mooncode_runtime_claim_item(
  command_entry : Json,
  index : Int,
  receipt : Json?,
  claim_status~ : String,
  order_blocked_by~ : String,
) -> Json {
  let command = mooncode_json_object_field_or_empty(command_entry, "command")
  let command_id = mooncode_runtime_command_entry_id(command_entry)
  {
    "kind": "mooncode-runtime-claim-item",
    "protocol": mooncode_protocol_version(),
    "index": index,
    "command_id": command_id,
    "action": mooncode_json_string(command, "command", default="prompt"),
    "session_id": mooncode_json_string(
      command_entry,
      "session_id",
      default=mooncode_json_string(command, "session_id", default=""),
    ),
    "claim_status": claim_status,
    "order_blocked_by": order_blocked_by,
    "command": command,
    "command_entry": command_entry,
    "receipt": match receipt {
      Some(value) => value
      None => null
    },
  }
}

///|
fn mooncode_runtime_command_entry_id(command_entry : Json) -> String {
  let command_id = mooncode_json_string(command_entry, "command_id", default="")
  if command_id != "" {
    return command_id
  }
  let command = mooncode_json_object_field_or_empty(command_entry, "command")
  mooncode_command_id(command)
}

///|
fn mooncode_runtime_receipt_status_delivered(status : String) -> Bool {
  status == "runtime-delivered" ||
  status == "runtime-completed" ||
  status == "runtime-succeeded" ||
  status == "runtime-finished" ||
  status == "runtime-failed" ||
  status == "runtime-cancelled" ||
  status == "runtime-rejected"
}

///|
fn mooncode_runtime_claim_receipts(
  session_id : String,
  book_root : String,
  claim_state : Json,
  payload : Json,
  now~ : @clock.Timestamp,
) -> Array[Json] {
  let consumer_id = mooncode_json_string(
    payload,
    "consumer_id",
    default="moonclaw-daemon",
  )
  let claimable = mooncode_json_array_items(claim_state, "claimable_commands")
  let receipts : Array[Json] = []
  if claimable.length() == 0 {
    return receipts
  }
  let item = claimable[0]
  let command_id = mooncode_json_string(item, "command_id", default="")
  if command_id == "" {
    return receipts
  }
  receipts.push({
    "kind": mooncode_kind_runtime_dispatch(),
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "status": "runtime-claimed",
    "dispatch_mode": "moonclaw-native-runtime-claim",
    "claim_id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-\{now}",
    "consumer_id": consumer_id,
    "claimed_at": now,
    "command": mooncode_json_object_field_or_empty(item, "command"),
    "command_entry": mooncode_json_object_field_or_empty(item, "command_entry"),
  })
  receipts
}

///|
fn mooncode_runtime_dispatch_receipt(
  session_id : String,
  book_root : String,
  claim_item : Json,
  execution : Json,
  consumer_id~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  let command_id = mooncode_json_string(claim_item, "command_id", default="")
  let accepted = mooncode_json_bool(execution, "accepted", default=false)
  let control = mooncode_json_string(execution, "control", default="")
  let receipt = mooncode_json_object_field_or_empty(claim_item, "receipt")
  let claim_id = mooncode_json_string(receipt, "claim_id", default="")
  let status = if control == "cancel" && accepted {
    "runtime-cancelled"
  } else if accepted {
    "runtime-delivered"
  } else {
    "runtime-failed"
  }
  {
    "kind": mooncode_kind_runtime_dispatch(),
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "web_search": mooncode_command_web_search(
      mooncode_json_object_field_or_empty(claim_item, "command"),
    ),
    "status": status,
    "dispatch_mode": "moonclaw-native-runtime-dispatch",
    "claim_id": claim_id,
    "consumer_id": consumer_id,
    "delivered_at": now,
    "task_id": mooncode_json_string(execution, "task_id", default=""),
    "message_id": mooncode_json_string(execution, "message_id", default=""),
    "control": control,
    "message": mooncode_json_string(execution, "message", default=""),
    "command": mooncode_json_object_field_or_empty(claim_item, "command"),
    "command_entry": mooncode_json_object_field_or_empty(
      claim_item, "command_entry",
    ),
    "execution": execution,
    "events": Json::array(mooncode_json_array_items(execution, "events")),
  }
}
