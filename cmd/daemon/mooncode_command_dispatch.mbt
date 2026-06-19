///|
async fn Daemon::mooncode_accept_command(
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
  let action = mooncode_json_string(body, "command", default="prompt")
  if mooncode_json_string(body, "native_dispatch_mode", default="") ==
    "queue-only" {
    let response = self.mooncode_queue_command_response(
      session_id~,
      body,
      dispatch_source="moonclaw-native-command-queue-only",
    )
    w.header().set("Content-Type", "application/json")
    w.write_header(202, reason="Accepted")
    w.write(response.stringify(indent=2))
    return
  }
  if action == "cancel" {
    let response = self.mooncode_cancel_command_response(
      session_id~,
      body,
      persist_command=true,
      dispatch_source="moonclaw-native-command-endpoint",
    )
    w.header().set("Content-Type", "application/json")
    w.write_header(202, reason="Accepted")
    w.write(response.stringify(indent=2))
    return
  }
  let response = self.mooncode_forward_command_to_task(
    group~,
    session_id~,
    body,
    persist_command=true,
    dispatch_source="moonclaw-native-command-endpoint",
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
  dispatch_source~ : String,
) -> Json {
  let command_id = mooncode_command_id(body)
  let action = mooncode_json_string(body, "command", default="prompt")
  let book_root = mooncode_book_root(body)
  let now = self.clock.now()
  let binding = self.mooncode_binding_for_session(session_id)
  if binding.book_root == "" {
    binding.book_root = book_root
  }
  binding.command_count += 1
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
    "dispatch_source": dispatch_source,
    "native_dispatch_mode": "queue-only",
    "runtime_turn_endpoint": "/v1/code/sessions/\{session_id}/runtime-turn?book_root=<path>",
    "binding": binding.to_json(),
    "events": Json::array([event]),
  }
}

///|
async fn Daemon::mooncode_forward_command_to_task(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  session_id~ : String,
  body : Json,
  persist_command~ : Bool,
  dispatch_source~ : String,
) -> Json {
  let command_id = mooncode_command_id(body)
  let action = mooncode_json_string(body, "command", default="prompt")
  let task = self.mooncode_ensure_task(group~, session_id~, body)
  let text = mooncode_runtime_message(body)
  let response = task.create_message(
    @server.CreateMessageRequest::new(
      message=@ai.user_message(content=text),
      web_search=mooncode_command_web_search(body),
    ),
  )
  let response_json = response.to_json()
  let now = self.clock.now()
  let binding = self.mooncode_binding_for_session(session_id)
  binding.command_count += 1
  binding.remember_first_user_prompt(body)
  binding.last_command_id = command_id
  binding.last_updated = now
  let events = [
    mooncode_event(
      session_id~,
      command_id~,
      lane="runtime",
      kind=mooncode_accept_event_kind(action),
      title=mooncode_accept_event_title(action),
      status=if mooncode_json_bool(response_json, "queued", default=false) {
        "queued"
      } else {
        "running"
      },
      detail="Forwarded `\{action}` to MoonClaw task \{task.id}",
      now~,
    ),
  ]
  for event in events {
    binding.events.put(event)
  }
  if persist_command {
    self.mooncode_persist_command(body, binding, events)
  } else {
    self.mooncode_persist_session(binding)
    for event in events {
      self.mooncode_persist_event(binding, event)
    }
  }
  {
    "accepted": true,
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "task": task,
    "task_id": task.id,
    "message_id": mooncode_json_string(response_json, "id", default=""),
    "queued": mooncode_json_bool(response_json, "queued", default=false),
    "message": "MoonClaw MoonCode runtime accepted `\{action}`",
    "control": mooncode_command_control(action),
    "dispatch_source": dispatch_source,
    "binding": binding.to_json(),
    "events": Json::array(events),
  }
}

///|
async fn Daemon::mooncode_cancel_command_response(
  self : Daemon,
  session_id~ : String,
  body : Json,
  persist_command~ : Bool,
  dispatch_source~ : String,
) -> Json {
  let command_id = mooncode_command_id(body)
  let now = self.clock.now()
  guard self.mooncode_task_for_existing_session(session_id, body) is Some(task) else {
    let event = mooncode_event(
      session_id~,
      command_id~,
      lane="runtime",
      kind="cancel.no_active_task",
      title="MoonCode cancel had no active MoonClaw task",
      status="failed",
      detail="No bound MoonClaw task exists for this MoonCode session, so native cancel did not spawn or stop anything.",
      now~,
    )
    let binding = self.mooncode_binding_for_session(session_id)
    if binding.book_root == "" {
      binding.book_root = mooncode_book_root(body)
    }
    binding.command_count += 1
    binding.last_command_id = command_id
    binding.last_updated = now
    binding.events.put(event)
    if persist_command {
      self.mooncode_persist_command(body, binding, [event])
    } else {
      self.mooncode_persist_event(binding, event)
      self.mooncode_persist_session(binding)
    }
    return {
      "accepted": false,
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": command_id,
      "control": "cancel",
      "message": "MoonCode cancel has no active MoonClaw task",
      "dispatch_source": dispatch_source,
      "binding": binding.to_json(),
      "events": Json::array([event]),
    }
  }
  let cancel_payload = task.cancel()
  let binding = self.mooncode_binding_for_session(session_id)
  binding.command_count += 1
  binding.last_command_id = command_id
  binding.last_updated = now
  let event = mooncode_event(
    session_id~,
    command_id~,
    lane="runtime",
    kind="cancel.requested",
    title="MoonCode cancel requested",
    status="cancelled",
    detail="Requested cooperative cancellation for MoonClaw task \{task.id}",
    now~,
  )
  binding.events.put(event)
  if persist_command {
    self.mooncode_persist_command(body, binding, [event])
  } else {
    self.mooncode_persist_session(binding)
    self.mooncode_persist_event(binding, event)
  }
  {
    "accepted": true,
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "control": "cancel",
    "task": task,
    "task_id": task.id,
    "message": "MoonClaw MoonCode runtime accepted `cancel`",
    "dispatch_source": dispatch_source,
    "cancel": cancel_payload,
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
  {
    "ok": missing.length() == 0,
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "missing": Json::array(missing),
    "message": if missing.length() == 0 {
      "MoonCode command is valid"
    } else {
      "MoonCode command is missing required fields: \{missing.map(item => item.stringify()).join(", ")}"
    },
  }
}

///|
fn mooncode_runtime_message(body : Json) -> String {
  let command = mooncode_json_string(body, "command", default="prompt")
  let text = mooncode_json_string(body, "text", default="")
  let context_path = mooncode_json_string(body, "context_path", default="")
  let book_root = mooncode_book_root(body)
  let packet = mooncode_json_object_field_or_empty(body, "packet")
  "Moondesk MoonCode command:\n" +
  "- command: \{command}\n" +
  "- session: \{mooncode_json_string(body, "session_id", default="")}\n" +
  "- command id: \{mooncode_command_id(body)}\n" +
  "- book root: \{book_root}\n" +
  "- selected path: \{if context_path == "" { "not provided" } else { context_path }}\n\n" +
  "User request:\n\{text}\n\n" +
  "Command packet:\n\{packet.stringify(indent=2)}"
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
fn mooncode_accept_event_kind(action : String) -> String {
  match action {
    "steer" => "steer.accepted"
    _ => "command.accepted"
  }
}

///|
fn mooncode_accept_event_title(action : String) -> String {
  match action {
    "steer" => "MoonClaw accepted MoonCode steering"
    _ => "MoonClaw accepted MoonCode command"
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
