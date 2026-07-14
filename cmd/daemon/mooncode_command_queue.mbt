///|
async fn Daemon::mooncode_accept_command(
  self : Daemon,
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
          "message": "Invalid JSON body for MoonCode command",
        },
      })
  }
  let session_id = session_id.to_owned()
  let report = mooncode_validate_command_body(session_id, body)
  if !mooncode_json_bool(report, "ok", default=false) {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": mooncode_json_string(
          report,
          "message",
          default="Invalid MoonCode command",
        ),
        "metadata": report,
      },
    })
  }
  let response = self.mooncode_queue_command_response(
    session_id~,
    body,
    queue_source="moonclaw-native-command-queue",
  )
  w.header().set("Content-Type", "application/json")
  w.write_header(202, reason="Accepted")
  w.write(response.stringify(indent=2))
}

///|
async fn Daemon::mooncode_queue_command_response(
  self : Daemon,
  session_id~ : String,
  body : Json,
  queue_source~ : String,
) -> Json {
  let command_id = mooncode_command_id(body)
  let action = mooncode_json_string(body, "command", default="prompt")
  let book_root = mooncode_book_root(body)
  let now = self.clock.now()
  let binding = self.mooncode_binding_for_session(session_id)
  if !binding.bind_book_root(book_root) {
    raise json_error(409, "Conflict", {
      "error": {
        "code": -1,
        "message": "MoonCode session is already bound to a different MoonBook root",
        "metadata": {
          "session_id": session_id,
          "bound_book_root": binding.book_root,
          "requested_book_root": book_root,
        },
      },
    })
  }
  binding.restore_first_user_prompt()
  binding.command_count += 1
  binding.remember_workspace(body)
  binding.remember_first_user_prompt(body)
  binding.last_command_id = command_id
  binding.last_updated = now
  let event = mooncode_event(
    session_id~,
    command_id~,
    lane="runtime",
    kind="command.queued_for_runtime_turn",
    title="MoonCode command queued for native runtime turn",
    status="queued",
    detail="Queued `\{action}` for MoonClaw native runtime-turn execution without spawning a generic task.",
    now~,
  )
  binding.events.put(event)
  self.mooncode_persist_command(body, binding, [event])
  {
    "accepted": true,
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "queued": true,
    "control": mooncode_command_control(action),
    "message": "MoonClaw queued `\{action}` for native runtime-turn execution",
    "queue_source": queue_source,
    "runtime_turn_endpoint": "/v1/code/sessions/\{session_id}/runtime-turn?book_root=<path>",
    "binding": binding.to_json(),
    "events": Json::array([event]),
  }
}

///|
fn mooncode_validate_command_body(session_id : String, body : Json) -> Json {
  let protocol = mooncode_json_string(body, "protocol", default="")
  let body_session = mooncode_json_string(body, "session_id", default="")
  let book_root = mooncode_book_root(body)
  let command_id = mooncode_command_id(body)
  let missing : Array[Json] = []
  if protocol != mooncode_protocol_version() {
    missing.push("protocol".to_json())
  }
  if body_session != session_id {
    missing.push("session_id".to_json())
  }
  if book_root == "" {
    missing.push("book_root".to_json())
  }
  if command_id == "" {
    missing.push("command_id".to_json())
  }
  let unsupported = mooncode_unsupported_command_fields(body)
  {
    "ok": missing.length() == 0 && unsupported.length() == 0,
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "missing": Json::array(missing),
    "unsupported": Json::array(unsupported),
    "message": if unsupported.length() > 0 {
      "MoonCode command uses unsupported fields: \{unsupported.map(item => item.stringify()).join(", ")}"
    } else if missing.length() == 0 {
      "MoonCode command is valid"
    } else {
      "MoonCode command is missing required fields: \{missing.map(item => item.stringify()).join(", ")}"
    },
  }
}

///|
fn mooncode_unsupported_command_fields(body : Json) -> Array[Json] {
  let unsupported : Array[Json] = []
  match body {
    Object(fields) =>
      for name, _ in fields.iter2() {
        if !mooncode_command_field_is_supported(name) {
          unsupported.push(name.to_json())
        }
      }
    _ => ()
  }
  unsupported
}

///|
fn mooncode_command_field_is_supported(name : String) -> Bool {
  mooncode_native_command_body_field_is_supported(name)
}

///|
fn mooncode_command_control(action : String) -> String {
  match action {
    "steer" => "steer"
    "cancel" => "cancel"
    _ => "prompt"
  }
}

///|
fn mooncode_command_id(body : Json) -> String {
  let packet = mooncode_json_object_field_or_empty(body, "packet")
  mooncode_json_string(packet, "command_id", default="")
}

///|
fn mooncode_book_root(body : Json) -> String {
  mooncode_json_string(body, "book_root", default="")
}

///|
fn mooncode_command_web_search(body : Json) -> Bool {
  let payload = mooncode_json_object_field_or_empty(body, "payload")
  mooncode_json_bool(
    body,
    "web_search",
    default=mooncode_json_bool(payload, "web_search", default=false),
  )
}
