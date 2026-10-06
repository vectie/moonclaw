///|
async fn Daemon::mooncode_submit_turn(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
  let body : Json = reader.read() catch {
    _ =>
      raise json_error(400, "Bad Request", {
        "error": {
          "code": -1,
          "message": "Invalid JSON body for MoonCode turn",
        },
      })
  }
  let session_id = session_id.to_owned()
  let response = self.mooncode_submit_turn_response(group~, session_id, body)
  w.header().set("Content-Type", "application/json")
  w.write_header(202, reason="Accepted")
  w.write(response.stringify(indent=2))
}

///|
async fn Daemon::mooncode_submit_turn_response(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  session_id : String,
  body : Json,
) -> Json {
  let report = mooncode_validate_command_body(session_id, body)
  if !mooncode_json_bool(report, "ok", default=false) {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": mooncode_json_string(
          report,
          "message",
          default="Invalid MoonCode turn",
        ),
        "metadata": report,
      },
    })
  }
  let book_root = mooncode_book_root(body)
  let action = mooncode_json_string(body, "command", default="prompt")
  if action == "approve_tool" || action == "reject_tool" {
    ignore(
      mooncode_runtime_tool_approval_control_request(
        session_id, book_root, body,
      ),
    )
  }
  let queue = self.mooncode_queue_command_response(
    session_id~,
    body,
    queue_source="moonclaw-submit-turn",
  )
  let service = if mooncode_json_bool(queue, "duplicate", default=false) {
    // Reconcile the durable command before a retry. If a process stopped
    // between queueing and starting the service, resume that same command.
    // Delivered commands and controls never start another service here.
    // An accepted but unsettled cancel must finish its durable settlement.
    let claim_state = self.mooncode_runtime_claim_state_payload(
      session_id, book_root,
    )
    if action == "cancel" {
      self.mooncode_submit_cancel_control(session_id, book_root, body)
    } else if (action == "prompt" || action == "package" || action == "steer") &&
      mooncode_runtime_command_pending(claim_state, mooncode_command_id(body)) {
      self.mooncode_start_runtime_service(group~, session_id, book_root, body)
    } else {
      mooncode_runtime_service_state_payload(
        session_id,
        book_root,
        self.mooncode_runtime_service_events(session_id, book_root),
        service_id="",
      )
    }
  } else if action == "cancel" {
    self.mooncode_submit_cancel_control(session_id, book_root, body)
  } else if action == "approve_tool" || action == "reject_tool" {
    self.mooncode_submit_tool_approval_control(
      group~,
      session_id,
      book_root,
      body,
    )
  } else {
    self.mooncode_start_runtime_service(group~, session_id, book_root, body)
  }
  let session = self
    .mooncode_session_record(session_id, book_root)
    .unwrap_or(Json::object({}))
  {
    "kind": "mooncode-turn-accepted",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "accepted": true,
    "session_id": session_id,
    "command_id": mooncode_command_id(body),
    "book_root": book_root,
    "queue": queue,
    "service": service,
    "session": session,
  }
}

///|
fn mooncode_runtime_command_pending(state : Json, command_id : String) -> Bool {
  for
    field in [
      "claimable_commands", "claimed_commands", "order_blocked_commands",
    ] {
    for item in mooncode_json_array_items(state, field) {
      if mooncode_json_string(item, "command_id", default="") == command_id {
        return true
      }
    }
  }
  false
}

///|
test "native submit retry resumes only unresolved command identities" {
  let state : Json = {
    "claimable_commands": [{ "command_id": "queued" }],
    "claimed_commands": [{ "command_id": "running" }],
    "order_blocked_commands": [{ "command_id": "waiting" }],
    "delivered_commands": [{ "command_id": "done" }],
  }
  assert_true(mooncode_runtime_command_pending(state, "queued"))
  assert_true(mooncode_runtime_command_pending(state, "running"))
  assert_true(mooncode_runtime_command_pending(state, "waiting"))
  assert_false(mooncode_runtime_command_pending(state, "done"))
  assert_false(mooncode_runtime_command_pending(state, "unknown"))
}
