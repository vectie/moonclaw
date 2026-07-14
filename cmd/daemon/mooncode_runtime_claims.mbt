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
    ignore(
      mooncode_append_session_journal(
        book_root,
        session_id,
        mooncode_journal_runtime_receipt(),
        receipt,
      ),
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
async fn Daemon::mooncode_runtime_claim_state_payload(
  self : Daemon,
  session_id : String,
  book_root : String,
) -> Json {
  ignore(self)
  let journal_path = mooncode_session_journal_path(book_root, session_id)
  let journal = mooncode_read_session_journal(book_root, session_id)
  let commands = mooncode_journal_entries(journal, mooncode_journal_command())
  let receipts = mooncode_journal_entries(
    journal,
    mooncode_journal_runtime_receipt(),
  )
  mooncode_runtime_claim_state_from_logs(
    session_id,
    book_root,
    commands,
    receipts,
    journal_path~,
  )
}

///|
fn mooncode_runtime_claim_state_from_logs(
  session_id : String,
  book_root : String,
  commands : Array[Json],
  receipts : Array[Json],
  journal_path~ : String,
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
    "journal_path": journal_path,
    "command_count": commands.length(),
    "receipt_count": receipts.length(),
    "claimable_command_count": claimable.length(),
    "claimed_command_count": claimed.length(),
    "delivered_command_count": delivered.length(),
    "invalid_command_count": invalid.length(),
    "order_blocked_command_count": order_blocked.length(),
    "claim_ready": claimable.length() > 0,
    "claim_endpoint": "/v1/code/sessions/\{session_id}/runtime-claim?book_root=<path>",
    "ordering_rule": "MoonClaw claims the next unresolved command from the session journal's total order; active claims and invalid commands block later commands until a runtime-receipt record resolves the blocker.",
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
    "kind": mooncode_kind_runtime_receipt(),
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "status": "runtime-claimed",
    "runtime_mode": "moonclaw-native-runtime-claim",
    "claim_id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-\{now}",
    "consumer_id": consumer_id,
    "claimed_at": now,
    "command": mooncode_json_object_field_or_empty(item, "command"),
    "command_entry": mooncode_json_object_field_or_empty(item, "command_entry"),
  })
  receipts
}
