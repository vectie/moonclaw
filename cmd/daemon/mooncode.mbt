///|
/// In-memory binding between a Moondesk MoonCode session id and the MoonClaw
/// task that executes commands for that session.
priv struct MoonCodeSessionBinding {
  session_id : String
  task_id : @uuid.Uuid
  mut book_root : String
  mut command_count : Int
  mut last_command_id : String
  mut last_updated : @clock.Timestamp
  mut persisted_task_event_count : Int
  events : @broadcast.Broadcast[Json]
}

///|
fn MoonCodeSessionBinding::to_json(self : MoonCodeSessionBinding) -> Json {
  {
    "session_id": self.session_id,
    "task_id": self.task_id,
    "book_root": self.book_root,
    "command_count": self.command_count,
    "last_command_id": self.last_command_id,
    "last_updated": self.last_updated,
    "persisted_task_event_count": self.persisted_task_event_count,
  }
}

///|
fn mooncode_capabilities_payload() -> Json {
  {
    "component": "mooncode",
    "provider": "moonclaw",
    "protocol": "mooncode.v1",
    "native_runtime_ready": true,
    "bridge_mode": "moonclaw-daemon-native-mooncode",
    "runtime_owner": "moonclaw",
    "session_owner": "moondesk",
    "endpoints": [
      "/v1/mooncode/capabilities", "/v1/mooncode/sessions?book_root=<path>", "/v1/mooncode/sessions/<id>?book_root=<path>",
      "/v1/mooncode/sessions/<id>/commands", "/v1/mooncode/sessions/<id>/stream",
      "/v1/mooncode/sessions/<id>/eval-report", "/v1/mooncode/sessions/<id>/package-result",
      "/v1/mooncode/sessions/<id>/runtime-claim?book_root=<path>", "/v1/mooncode/sessions/<id>/runtime-dispatch?book_root=<path>",
      "/v1/mooncode/sessions/<id>/runtime-events?book_root=<path>", "/v1/mooncode/sessions/<id>/tool-exec?book_root=<path>",
    ],
    "control_commands": ["prompt", "steer", "cancel"],
    "tools": ["read", "edit", "write", "shell", "moon_check", "finish"],
    "execution_boundary": "MoonClaw accepts Moondesk MoonCode command packets and executes them through the existing MoonClaw task/agent runtime for the target book root.",
    "package_result_endpoint": "POST /v1/mooncode/sessions/<id>/package-result accepts package_built/package_verified proof packets for MoonBook-owned executable artifacts.",
    "durable_session_store": ".moonclaw/mooncode/sessions/<session-id>/session.json plus commands.jsonl, runtime-dispatches.jsonl, events.jsonl, and package-results.jsonl under the selected book root.",
    "runtime_claim_endpoint": "GET/POST /v1/mooncode/sessions/<id>/runtime-claim?book_root=<path> projects and appends native runtime-claimed receipts over the durable command queue without spawning a task.",
    "runtime_dispatch_endpoint": "POST /v1/mooncode/sessions/<id>/runtime-dispatch?book_root=<path> claims the next durable command if needed, forwards it to the MoonClaw task runtime, and appends a runtime-delivered receipt.",
    "runtime_events_endpoint": "GET/POST /v1/mooncode/sessions/<id>/runtime-events?book_root=<path> reads or appends normalized MoonCode runtime evidence into events.jsonl.",
    "tool_execution_endpoint": "POST /v1/mooncode/sessions/<id>/tool-exec?book_root=<path> executes the native MoonCode read/edit/write/shell/moon_check/finish tool contract against the selected MoonBook root and appends command-scoped proof events.",
    "ordering_rule": "Prompt and command packets are accepted per session and forwarded to the bound MoonClaw task in request order. Steer packets are delivered as steering context to the same task. Cancel packets target an existing bound task and never spawn a new task. Package-result proof packets append command-scoped runtime evidence for already accepted package commands.",
  }
}

///|
async fn Daemon::mooncode_capabilities(
  self : Daemon,
  w : @httpx.ResponseWriter,
) -> Unit {
  ignore(self)
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(mooncode_capabilities_payload().stringify())
}

///|
async fn Daemon::mooncode_list_sessions(
  self : Daemon,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let book_root = mooncode_request_book_root(r)
  let records = self.mooncode_session_records(book_root)
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(
    (
      {
        "kind": "mooncode-session-list",
        "protocol": "mooncode.v1",
        "owner": "moonclaw",
        "book_root": book_root,
        "durable_store": mooncode_sessions_root(book_root),
        "durable_store_loaded": book_root != "",
        "session_count": records.length(),
        "sessions": Json::array(records),
      } : Json).stringify(indent=2),
  )
}

///|
async fn Daemon::mooncode_get_session(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let session_id = session_id.to_string()
  let book_root = mooncode_request_book_root(r)
  guard self.mooncode_session_record(session_id, book_root) is Some(record) else {
    raise json_error(404, "Not Found", {
      "error": {
        "code": -1,
        "message": "MoonCode session not found",
        "metadata": {
          "session_id": session_id,
          "book_root": book_root,
          "durable_store": mooncode_sessions_root(book_root),
        },
      },
    })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(record.stringify(indent=2))
}

///|
async fn Daemon::mooncode_runtime_claim_state(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let session_id = session_id.to_string()
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
  let session_id = session_id.to_string()
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
        "protocol": "mooncode.v1",
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
  let session_id = session_id.to_string()
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
          "protocol": "mooncode.v1",
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
      "protocol": "mooncode.v1",
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
        "protocol": "mooncode.v1",
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
  let session_id = session_id.to_string()
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
      web_search=mooncode_json_bool(
        mooncode_json_object_field_or_empty(body, "payload"),
        "web_search",
        default=false,
      ),
    ),
  )
  let response_json = response.to_json()
  let now = self.clock.now()
  let binding = self.mooncode_binding_for_session(session_id)
  binding.command_count += 1
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
    "protocol": "mooncode.v1",
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
      "protocol": "mooncode.v1",
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
    "protocol": "mooncode.v1",
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
async fn Daemon::mooncode_stream(
  self : Daemon,
  session_id~ : StringView,
  w : @httpx.ResponseWriter,
) -> Unit {
  let session_id = session_id.to_string()
  guard self.mooncode_sessions.get(session_id) is Some(binding) else {
    w.header().set("Content-Type", "application/x-ndjson")
    w.write_header(200)
    w.write(
      mooncode_event(
        session_id~,
        command_id="",
        lane="runtime",
        kind="session.idle",
        title="MoonCode session has no MoonClaw command yet",
        status="idle",
        detail="No native MoonCode command has been accepted for this session in the current daemon lifetime.",
        now=self.clock.now(),
      ).stringify() +
      "\n",
    )
    return
  }
  w.header().set("Content-Type", "application/x-ndjson")
  w.write_header(200)
  for event in binding.events.values() {
    w.write(event.stringify() + "\n")
  }
  match self.by_id.get(binding.task_id) {
    Some(Running(task)) => {
      let mut persisted_task_event_count = binding.persisted_task_event_count
      for index, event in task.broadcast.values() {
        let mooncode_event = mooncode_event_from_task_stream(
          session_id~,
          command_id=binding.last_command_id,
          task_id=task.id.to_string(),
          event,
          index~,
        )
        w.write(mooncode_event.stringify() + "\n")
        if index >= binding.persisted_task_event_count {
          self.mooncode_persist_event(binding, mooncode_event)
          persisted_task_event_count = index + 1
        }
      }
      if persisted_task_event_count != binding.persisted_task_event_count {
        binding.persisted_task_event_count = persisted_task_event_count
        binding.last_updated = self.clock.now()
        self.mooncode_persist_session(binding)
      }
    }
    _ => ()
  }
  w.flush()
}

///|
async fn Daemon::mooncode_eval_report(
  self : Daemon,
  session_id~ : StringView,
  w : @httpx.ResponseWriter,
) -> Unit {
  let session_id = session_id.to_string()
  let binding = self.mooncode_sessions.get(session_id)
  let report = mooncode_eval_report_payload(
    session_id,
    binding,
    now=self.clock.now(),
  )
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(report.stringify(indent=2))
}

///|
async fn Daemon::mooncode_package_result(
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
          "message": "Invalid JSON body for MoonCode package result",
        },
      })
  }
  let session_id = session_id.to_string()
  let report = mooncode_validate_package_result_body(session_id, body)
  if !mooncode_json_bool(report, "ok", default=false) {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": mooncode_json_string(
          report,
          "message",
          default="Invalid MoonCode package result",
        ),
        "metadata": report,
      },
    })
  }
  let command_id = mooncode_package_result_command_id(body)
  let event_name = mooncode_package_result_event(body)
  let now = self.clock.now()
  let binding = self.mooncode_binding_for_session(session_id)
  binding.command_count += 1
  binding.last_command_id = command_id
  binding.last_updated = now
  let event = mooncode_package_result_event_record(
    session_id~,
    command_id~,
    body,
    now~,
  )
  binding.events.put(event)
  let book_root = mooncode_json_string(body, "book_root", default="")
  if binding.book_root == "" && book_root != "" {
    binding.book_root = book_root
  }
  self.mooncode_persist_package_result(body, binding, event)
  w.header().set("Content-Type", "application/json")
  w.write_header(202, reason="Accepted")
  w.write(
    (
      {
        "accepted": true,
        "protocol": "mooncode.v1",
        "session_id": session_id,
        "command_id": command_id,
        "event": event_name,
        "status": mooncode_package_result_status(event_name),
        "message": "MoonClaw recorded MoonCode package result `\{event_name}`",
        "binding": binding.to_json(),
        "package_result": mooncode_package_result_payload(body),
        "events": Json::array([event]),
      } : Json).stringify(indent=2),
  )
}

///|
async fn Daemon::mooncode_ensure_task(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  session_id~ : String,
  body : Json,
) -> Running {
  if self.mooncode_sessions.get(session_id) is Some(binding) {
    match self.by_id.get(binding.task_id) {
      Some(Running(task)) => return task
      _ => ()
    }
  }
  let book_root = mooncode_book_root(body)
  let task_lock = self.by_cwd.get_or_init(book_root, () => TaskLock::new())
  if task_lock.running is Some(task) {
    self.mooncode_bind_session(session_id, task, book_root)
    return task
  }
  let model = mooncode_json_string(
    mooncode_json_object_field_or_empty(body, "payload"),
    "model",
    default="",
  )
  let model = if model == "" { None } else { Some(model) }
  guard self.models.get_model(name?=model) is Some(model_value) else {
    raise json_error(404, "Not Found", {
      "error": {
        "code": -1,
        "message": "Model not found for MoonCode command",
        "metadata": { "model": model.unwrap_or("") },
      },
    })
  }
  task_lock.spawn_mutex.acquire()
  defer task_lock.spawn_mutex.release()
  if task_lock.running is Some(task) {
    self.mooncode_bind_session(session_id, task, book_root)
    return task
  }
  let task = self.spawn_task(
    group~,
    name="MoonCode - \{session_id}",
    model=model_value,
    web_search=mooncode_json_bool(
      mooncode_json_object_field_or_empty(body, "payload"),
      "web_search",
      default=false,
    ),
    cwd=book_root,
  )
  task_lock.running = Some(task)
  self.mooncode_bind_session(session_id, task, book_root)
  task
}

///|
fn Daemon::mooncode_bind_session(
  self : Daemon,
  session_id : String,
  task : Running,
  book_root : String,
) -> Unit {
  match self.mooncode_sessions.get(session_id) {
    Some(binding) => {
      binding.last_updated = self.clock.now()
      binding.last_command_id = binding.last_command_id
    }
    None =>
      self.mooncode_sessions[session_id] = MoonCodeSessionBinding::{
        session_id,
        task_id: task.id,
        book_root,
        command_count: 0,
        last_command_id: "",
        last_updated: self.clock.now(),
        persisted_task_event_count: 0,
        events: @broadcast.Broadcast::new(),
      }
  }
}

///|
fn Daemon::mooncode_binding_for_session(
  self : Daemon,
  session_id : String,
) -> MoonCodeSessionBinding {
  match self.mooncode_sessions.get(session_id) {
    Some(binding) => binding
    None => {
      let binding = MoonCodeSessionBinding::{
        session_id,
        task_id: @uuid.nil,
        book_root: "",
        command_count: 0,
        last_command_id: "",
        last_updated: self.clock.now(),
        persisted_task_event_count: 0,
        events: @broadcast.Broadcast::new(),
      }
      self.mooncode_sessions[session_id] = binding
      binding
    }
  }
}

///|
fn Daemon::mooncode_task_for_existing_session(
  self : Daemon,
  session_id : String,
  body : Json,
) -> Running? {
  match self.mooncode_sessions.get(session_id) {
    Some(binding) =>
      match self.by_id.get(binding.task_id) {
        Some(Running(task)) => return Some(task)
        _ => ()
      }
    None => ()
  }
  let packet = mooncode_json_object_field_or_empty(body, "packet")
  let task_id = mooncode_json_string(packet, "task_id", default="")
  if task_id == "" {
    return None
  }
  let id = @uuid.parse(task_id) catch { _ => return None }
  match self.by_id.get(id) {
    Some(Running(task)) => Some(task)
    _ => None
  }
}

///|
async fn Daemon::mooncode_session_records(
  self : Daemon,
  book_root : String,
) -> Array[Json] {
  let records = []
  let seen : Map[String, Bool] = {}
  if book_root != "" {
    for record in mooncode_durable_session_records(book_root) {
      let session_id = mooncode_json_string(record, "session_id", default="")
      if session_id != "" {
        seen[session_id] = true
      }
      records.push(record)
    }
  }
  for binding in self.mooncode_sessions.values() {
    if book_root == "" || binding.book_root == book_root {
      if !seen.contains(binding.session_id) {
        records.push(
          mooncode_session_record_from_parts(
            binding.session_id,
            binding.book_root,
            Some(binding),
            None,
            source="memory",
          ),
        )
      }
    }
  }
  records
}

///|
async fn Daemon::mooncode_session_record(
  self : Daemon,
  session_id : String,
  book_root : String,
) -> Json? {
  match self.mooncode_sessions.get(session_id) {
    Some(binding) if book_root == "" || binding.book_root == book_root =>
      return Some(
        mooncode_session_record_from_parts(
          session_id,
          binding.book_root,
          Some(binding),
          Some(mooncode_load_session_snapshot(binding.book_root, session_id)),
          source="memory",
        ),
      )
    _ => ()
  }
  if book_root == "" {
    return None
  }
  let snapshot = mooncode_load_session_snapshot(book_root, session_id)
  if mooncode_json_string(snapshot, "load_status", default="") == "missing" {
    None
  } else {
    Some(
      mooncode_session_record_from_parts(
        session_id,
        book_root,
        self.mooncode_sessions.get(
          mooncode_json_string(snapshot, "session_id", default=session_id),
        ),
        Some(snapshot),
        source="sidecar",
      ),
    )
  }
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
    "protocol": "mooncode.v1",
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
    "claim_endpoint": "/v1/mooncode/sessions/\{session_id}/runtime-claim?book_root=<path>",
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
    "protocol": "mooncode.v1",
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
    "kind": "mooncode.runtime-dispatch",
    "protocol": "mooncode.v1",
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
    "kind": "mooncode.runtime-dispatch",
    "protocol": "mooncode.v1",
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
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

///|
async fn mooncode_durable_session_records(book_root : String) -> Array[Json] {
  let records = []
  let root = mooncode_sessions_root(book_root)
  if !(@fsx.exists(root) catch { _ => false }) {
    return records
  }
  let entries = @fsx.list_directory(root) catch { _ => return records }
  for entry in entries {
    if entry.kind is @fsx.FileKind::Directory {
      let snapshot = mooncode_load_session_snapshot_by_safe_id(
        book_root,
        entry.name,
      )
      let session_id = mooncode_json_string(
        snapshot,
        "session_id",
        default=entry.name,
      )
      records.push(
        mooncode_session_record_from_parts(
          session_id,
          book_root,
          None,
          Some(snapshot),
          source="sidecar",
        ),
      )
    }
  }
  records
}

///|
async fn mooncode_load_session_snapshot(
  book_root : String,
  session_id : String,
) -> Json {
  mooncode_load_session_snapshot_by_safe_id(
    book_root,
    mooncode_safe_session_id(session_id),
  )
}

///|
async fn mooncode_load_session_snapshot_by_safe_id(
  book_root : String,
  safe_session_id : String,
) -> Json {
  let path = mooncode_session_snapshot_path_by_safe_id(
    book_root, safe_session_id,
  )
  if book_root == "" || !(@fsx.exists(path) catch { _ => false }) {
    return mooncode_missing_session_snapshot(
      book_root,
      safe_session_id,
      path,
      load_status="missing",
    )
  }
  @json.parse(@fsx.read_file(path)) catch {
    _ =>
      mooncode_missing_session_snapshot(
        book_root,
        safe_session_id,
        path,
        load_status="invalid-json",
      )
  }
}

///|
fn mooncode_missing_session_snapshot(
  book_root : String,
  safe_session_id : String,
  path : String,
  load_status~ : String,
) -> Json {
  {
    "kind": "mooncode-session-snapshot",
    "protocol": "mooncode.v1",
    "owner": "moonclaw",
    "session_id": safe_session_id,
    "book_root": book_root,
    "load_status": load_status,
    "storage": {
      "session_json": path,
      "commands_jsonl": mooncode_commands_path_by_safe_id(
        book_root, safe_session_id,
      ),
      "runtime_dispatches_jsonl": mooncode_runtime_dispatches_path_by_safe_id(
        book_root, safe_session_id,
      ),
      "events_jsonl": mooncode_events_path_by_safe_id(
        book_root, safe_session_id,
      ),
      "package_results_jsonl": mooncode_package_results_path_by_safe_id(
        book_root, safe_session_id,
      ),
    },
  }
}

///|
async fn mooncode_session_record_from_parts(
  session_id : String,
  book_root : String,
  live_binding : MoonCodeSessionBinding?,
  snapshot : Json?,
  source~ : String,
) -> Json {
  let safe_session_id = mooncode_safe_session_id(session_id)
  let resolved_snapshot = match snapshot {
    Some(value) => value
    None =>
      match live_binding {
        Some(binding) => mooncode_session_snapshot(binding)
        None =>
          mooncode_missing_session_snapshot(
            book_root,
            safe_session_id,
            mooncode_session_snapshot_path_by_safe_id(
              book_root, safe_session_id,
            ),
            load_status="not-loaded",
          )
      }
  }
  let commands_path = mooncode_commands_path_by_safe_id(
    book_root, safe_session_id,
  )
  let events_path = mooncode_events_path_by_safe_id(book_root, safe_session_id)
  let runtime_dispatches_path = mooncode_runtime_dispatches_path_by_safe_id(
    book_root, safe_session_id,
  )
  let package_results_path = mooncode_package_results_path_by_safe_id(
    book_root, safe_session_id,
  )
  {
    "kind": "mooncode-session-record",
    "protocol": "mooncode.v1",
    "owner": "moonclaw",
    "source": source,
    "session_id": mooncode_json_string(
      resolved_snapshot,
      "session_id",
      default=session_id,
    ),
    "safe_session_id": safe_session_id,
    "book_root": book_root,
    "live_binding_ready": live_binding is Some(_),
    "binding": match live_binding {
      Some(binding) => binding.to_json()
      None => null
    },
    "snapshot": resolved_snapshot,
    "storage": {
      "session_json": mooncode_session_snapshot_path_by_safe_id(
        book_root, safe_session_id,
      ),
      "commands_jsonl": commands_path,
      "runtime_dispatches_jsonl": runtime_dispatches_path,
      "events_jsonl": events_path,
      "package_results_jsonl": package_results_path,
    },
    "command_log_count": mooncode_jsonl_line_count(commands_path),
    "runtime_dispatch_log_count": mooncode_jsonl_line_count(
      runtime_dispatches_path,
    ),
    "event_log_count": mooncode_jsonl_line_count(events_path),
    "package_result_log_count": mooncode_jsonl_line_count(package_results_path),
    "resume_state": if live_binding is Some(_) {
      "live"
    } else if mooncode_json_string(
        resolved_snapshot,
        "load_status",
        default="loaded",
      ) ==
      "missing" {
      "missing"
    } else {
      "durable"
    },
  }
}

///|
async fn mooncode_jsonl_line_count(path : String) -> Int {
  if path == "" || !(@fsx.exists(path) catch { _ => false }) {
    return 0
  }
  let text = @fsx.read_file(path) catch { _ => return 0 }
  let mut count = 0
  for line in text.split("\n") {
    if !line.trim().is_empty() {
      count += 1
    }
  }
  count
}

///|
async fn mooncode_read_jsonl(path : String) -> Array[Json] {
  let records : Array[Json] = []
  if path == "" || !(@fsx.exists(path) catch { _ => false }) {
    return records
  }
  let text = @fsx.read_file(path) catch { _ => return records }
  for line in text.split("\n") {
    let line = line.trim()
    if line.is_empty() {
      continue
    }
    let parsed = @json.parse(line) catch { _ => continue }
    records.push(parsed)
  }
  records
}

///|
fn mooncode_request_book_root(r : @httpx.RequestReader) -> String {
  let parts = r.path.split("?").to_array()
  if parts.length() < 2 {
    return ""
  }
  let query = @codex.parse_query_string(parts[1])
  query.get("book_root").unwrap_or("")
}

///|
fn mooncode_validate_command_body(session_id : String, body : Json) -> Json {
  let protocol = mooncode_json_string(body, "protocol", default="")
  let body_session = mooncode_json_string(body, "session_id", default="")
  let book_root = mooncode_book_root(body)
  let command_id = mooncode_command_id(body)
  let missing : Array[Json] = []
  if protocol != "mooncode.v1" {
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
    "protocol": "mooncode.v1",
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
fn mooncode_validate_package_result_body(
  session_id : String,
  body : Json,
) -> Json {
  let protocol = mooncode_json_string(body, "protocol", default="")
  let body_session = mooncode_json_string(body, "session_id", default="")
  let command_id = mooncode_package_result_command_id(body)
  let event = mooncode_package_result_event(body)
  let path = mooncode_package_result_path(body)
  let missing : Array[Json] = []
  if protocol != "mooncode.v1" {
    missing.push("protocol".to_json())
  }
  if body_session != session_id {
    missing.push("session_id".to_json())
  }
  if command_id == "" {
    missing.push("command_id".to_json())
  }
  if event != "package_built" && event != "package_verified" {
    missing.push("event".to_json())
  }
  if path == "" {
    missing.push("path".to_json())
  }
  {
    "ok": missing.length() == 0,
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "command_id": command_id,
    "event": event,
    "path": path,
    "missing": Json::array(missing),
    "message": if missing.length() == 0 {
      "MoonCode package result is valid"
    } else {
      "MoonCode package result is missing required fields: \{missing.map(item => item.stringify()).join(", ")}"
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
fn mooncode_package_result_command_id(body : Json) -> String {
  let command_id = mooncode_json_string(body, "command_id", default="")
  if command_id != "" {
    return command_id
  }
  let packet = mooncode_json_object_field_or_empty(body, "command_packet")
  mooncode_json_string(packet, "command_id", default="")
}

///|
fn mooncode_package_result_event(body : Json) -> String {
  let event = mooncode_json_string(body, "event", default="")
  if event != "" {
    return event
  }
  mooncode_json_string(body, "kind", default="")
}

///|
fn mooncode_package_result_path(body : Json) -> String {
  let path = mooncode_json_string(body, "path", default="")
  if path != "" {
    return path
  }
  mooncode_json_string(body, "artifact_path", default="")
}

///|
fn mooncode_package_result_status(event : String) -> String {
  match event {
    "package_verified" => "verified"
    "package_built" => "built"
    _ => "recorded"
  }
}

///|
fn mooncode_package_result_payload(body : Json) -> Json {
  {
    "event": mooncode_package_result_event(body),
    "status": mooncode_package_result_status(
      mooncode_package_result_event(body),
    ),
    "path": mooncode_package_result_path(body),
    "detail": mooncode_json_string(body, "detail", default=""),
    "package_manifest": mooncode_json_object_field_or_empty(
      body, "package_manifest",
    ),
    "package_index": mooncode_json_object_field_or_empty(body, "package_index"),
    "command_packet": mooncode_json_object_field_or_empty(
      body, "command_packet",
    ),
  }
}

///|
fn mooncode_package_result_event_record(
  session_id~ : String,
  command_id~ : String,
  body : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let event = mooncode_package_result_event(body)
  let path = mooncode_package_result_path(body)
  let detail = mooncode_json_string(body, "detail", default="")
  {
    "id": "moonclaw-\{session_id}-\{command_id}-\{event}-\{now}",
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "command_id": command_id,
    "lane": "artifact",
    "kind": "runtime.\{event}",
    "event": event,
    "title": if event == "package_verified" {
      "MoonCode package verified"
    } else {
      "MoonCode package built"
    },
    "status": mooncode_package_result_status(event),
    "detail": if detail == "" {
      "MoonClaw recorded package result at \{path}"
    } else {
      detail
    },
    "path": path,
    "package_result": mooncode_package_result_payload(body),
    "created_at": now,
    "source": "moonclaw-native-mooncode",
  }
}

///|
fn mooncode_event_from_task_stream(
  session_id~ : String,
  command_id~ : String,
  task_id~ : String,
  event : @server.ServerStreamEvent,
  index~ : Int,
) -> Json {
  match event {
    @server.Moonclaw({ id, created, desc }) => {
      let desc_json = desc.to_json()
      let msg = mooncode_json_string(desc_json, "msg", default="")
      {
        "id": "moonclaw-\{session_id}-\{task_id}-task-event-\{index}",
        "protocol": "mooncode.v1",
        "session_id": session_id,
        "command_id": command_id,
        "task_id": task_id,
        "lane": mooncode_task_event_lane(msg),
        "kind": mooncode_task_event_kind(msg),
        "title": mooncode_task_event_title(msg),
        "status": mooncode_task_event_status(msg),
        "detail": mooncode_task_event_detail(desc_json),
        "created_at": created,
        "source": "moonclaw-task-stream",
        "moonclaw_event_id": id,
        "moonclaw_event": desc_json,
      }
    }
    @server.MoonclawQueuedMessagesSynchronized(messages) =>
      {
        "id": "moonclaw-\{session_id}-\{task_id}-queued-\{index}",
        "protocol": "mooncode.v1",
        "session_id": session_id,
        "command_id": command_id,
        "task_id": task_id,
        "lane": "runtime",
        "kind": "runtime.queue_synchronized",
        "title": "MoonClaw queued messages synchronized",
        "status": "running",
        "detail": "MoonClaw task has \{messages.length()} queued message(s)",
        "created_at": @clock.epoch.now(),
        "source": "moonclaw-task-stream",
        "queued_messages": messages,
      }
  }
}

///|
async fn Daemon::mooncode_persist_command(
  self : Daemon,
  body : Json,
  binding : MoonCodeSessionBinding,
  events : Array[Json],
) -> Unit {
  if binding.book_root == "" {
    return
  }
  self.mooncode_persist_session(binding)
  mooncode_append_jsonl(
    mooncode_commands_path(binding.book_root, binding.session_id),
    {
      "kind": "mooncode-command",
      "protocol": "mooncode.v1",
      "session_id": binding.session_id,
      "command_id": mooncode_command_id(body),
      "created_at": self.clock.now(),
      "command": body,
    },
  )
  for event in events {
    self.mooncode_persist_event(binding, event)
  }
}

///|
async fn Daemon::mooncode_persist_package_result(
  self : Daemon,
  body : Json,
  binding : MoonCodeSessionBinding,
  event : Json,
) -> Unit {
  if binding.book_root == "" {
    return
  }
  self.mooncode_persist_session(binding)
  mooncode_append_jsonl(
    mooncode_package_results_path(binding.book_root, binding.session_id),
    {
      "kind": "mooncode-package-result",
      "protocol": "mooncode.v1",
      "session_id": binding.session_id,
      "command_id": mooncode_package_result_command_id(body),
      "created_at": self.clock.now(),
      "package_result": mooncode_package_result_payload(body),
    },
  )
  self.mooncode_persist_event(binding, event)
}

///|
async fn Daemon::mooncode_persist_event(
  self : Daemon,
  binding : MoonCodeSessionBinding,
  event : Json,
) -> Unit {
  ignore(self)
  if binding.book_root == "" {
    return
  }
  mooncode_append_jsonl(
    mooncode_events_path(binding.book_root, binding.session_id),
    event,
  )
}

///|
async fn Daemon::mooncode_persist_session(
  self : Daemon,
  binding : MoonCodeSessionBinding,
) -> Unit {
  ignore(self)
  if binding.book_root == "" {
    return
  }
  let dir = mooncode_session_dir(binding.book_root, binding.session_id)
  @fsx.make_directory(dir, recursive=true, exists_ok=true)
  @fsx.write_to_file(
    mooncode_session_snapshot_path(binding.book_root, binding.session_id),
    mooncode_session_snapshot(binding).stringify(indent=2),
  )
}

///|
fn mooncode_session_snapshot(binding : MoonCodeSessionBinding) -> Json {
  {
    "kind": "mooncode-session-snapshot",
    "protocol": "mooncode.v1",
    "owner": "moonclaw",
    "session_id": binding.session_id,
    "task_id": binding.task_id,
    "book_root": binding.book_root,
    "command_count": binding.command_count,
    "last_command_id": binding.last_command_id,
    "last_updated": binding.last_updated,
    "storage": {
      "session_json": mooncode_session_snapshot_path(
        binding.book_root,
        binding.session_id,
      ),
      "commands_jsonl": mooncode_commands_path(
        binding.book_root,
        binding.session_id,
      ),
      "runtime_dispatches_jsonl": mooncode_runtime_dispatches_path(
        binding.book_root,
        binding.session_id,
      ),
      "events_jsonl": mooncode_events_path(
        binding.book_root,
        binding.session_id,
      ),
      "package_results_jsonl": mooncode_package_results_path(
        binding.book_root,
        binding.session_id,
      ),
    },
  }
}

///|
async fn mooncode_append_jsonl(path : String, entry : Json) -> Unit {
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  let existing = if @fsx.exists(path) { @fsx.read_file(path) } else { "" }
  let line = entry.stringify()
  let content = if existing.is_blank() { line } else { "\{existing}\n\{line}" }
  @fsx.write_to_file(path, content)
}

///|
fn mooncode_session_dir(book_root : String, session_id : String) -> String {
  mooncode_session_dir_by_safe_id(
    book_root,
    mooncode_safe_session_id(session_id),
  )
}

///|
fn mooncode_sessions_root(book_root : String) -> String {
  book_root
  |> @pathx.join(".moonclaw")
  |> @pathx.join("mooncode")
  |> @pathx.join("sessions")
}

///|
fn mooncode_session_dir_by_safe_id(
  book_root : String,
  safe_session_id : String,
) -> String {
  mooncode_sessions_root(book_root) |> @pathx.join(safe_session_id)
}

///|
fn mooncode_session_snapshot_path(
  book_root : String,
  session_id : String,
) -> String {
  mooncode_session_dir(book_root, session_id) |> @pathx.join("session.json")
}

///|
fn mooncode_session_snapshot_path_by_safe_id(
  book_root : String,
  safe_session_id : String,
) -> String {
  mooncode_session_dir_by_safe_id(book_root, safe_session_id)
  |> @pathx.join("session.json")
}

///|
fn mooncode_commands_path(book_root : String, session_id : String) -> String {
  mooncode_session_dir(book_root, session_id) |> @pathx.join("commands.jsonl")
}

///|
fn mooncode_commands_path_by_safe_id(
  book_root : String,
  safe_session_id : String,
) -> String {
  mooncode_session_dir_by_safe_id(book_root, safe_session_id)
  |> @pathx.join("commands.jsonl")
}

///|
fn mooncode_runtime_dispatches_path(
  book_root : String,
  session_id : String,
) -> String {
  mooncode_session_dir(book_root, session_id)
  |> @pathx.join("runtime-dispatches.jsonl")
}

///|
fn mooncode_runtime_dispatches_path_by_safe_id(
  book_root : String,
  safe_session_id : String,
) -> String {
  mooncode_session_dir_by_safe_id(book_root, safe_session_id)
  |> @pathx.join("runtime-dispatches.jsonl")
}

///|
fn mooncode_events_path(book_root : String, session_id : String) -> String {
  mooncode_session_dir(book_root, session_id) |> @pathx.join("events.jsonl")
}

///|
fn mooncode_events_path_by_safe_id(
  book_root : String,
  safe_session_id : String,
) -> String {
  mooncode_session_dir_by_safe_id(book_root, safe_session_id)
  |> @pathx.join("events.jsonl")
}

///|
fn mooncode_package_results_path(
  book_root : String,
  session_id : String,
) -> String {
  mooncode_session_dir(book_root, session_id)
  |> @pathx.join("package-results.jsonl")
}

///|
fn mooncode_package_results_path_by_safe_id(
  book_root : String,
  safe_session_id : String,
) -> String {
  mooncode_session_dir_by_safe_id(book_root, safe_session_id)
  |> @pathx.join("package-results.jsonl")
}

///|
fn mooncode_safe_session_id(session_id : String) -> String {
  let safe = session_id
    .replace_all(old="/", new="_")
    .replace_all(old="\\", new="_")
    .replace_all(old=":", new="_")
    .replace_all(old="..", new="_")
    .trim()
    .to_string()
  if safe == "" {
    "session"
  } else {
    safe
  }
}

///|
fn mooncode_task_event_lane(msg : String) -> String {
  match msg {
    "AssistantMessage" | "AssistantMessageDelta" => "transcript"
    "PreToolCall" | "PostToolCall" => "tool"
    "Cancelled" | "Failed" => "review"
    _ => "runtime"
  }
}

///|
fn mooncode_task_event_kind(msg : String) -> String {
  match msg {
    "AssistantMessageDelta" => "assistant_delta"
    "AssistantMessage" => "assistant_message"
    "PreToolCall" => "tool_call"
    "PostToolCall" => "tool_result"
    "Cancelled" => "agent_aborted"
    "Failed" => "agent_aborted"
    _ => "runtime.\{msg}"
  }
}

///|
fn mooncode_task_event_title(msg : String) -> String {
  match msg {
    "AssistantMessageDelta" => "Assistant streaming"
    "AssistantMessage" => "Assistant message"
    "PreToolCall" => "Tool call started"
    "PostToolCall" => "Tool result"
    "Cancelled" => "MoonClaw task cancelled"
    "Failed" => "MoonClaw task failed"
    _ => "MoonClaw runtime event"
  }
}

///|
fn mooncode_task_event_status(msg : String) -> String {
  match msg {
    "AssistantMessageDelta" | "PreToolCall" => "running"
    "Cancelled" => "cancelled"
    "Failed" => "failed"
    _ => "done"
  }
}

///|
fn mooncode_task_event_detail(desc : Json) -> String {
  let msg = mooncode_json_string(desc, "msg", default="")
  match msg {
    "AssistantMessageDelta" | "AssistantMessage" =>
      mooncode_json_string(desc, "content", default="")
    "PreToolCall" | "PostToolCall" =>
      mooncode_json_string(desc, "name", default="tool")
    "Failed" => "MoonClaw task failed"
    "Cancelled" => "MoonClaw task was cancelled"
    _ => msg
  }
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
fn mooncode_event(
  session_id~ : String,
  command_id~ : String,
  lane~ : String,
  kind~ : String,
  title~ : String,
  status~ : String,
  detail~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  {
    "id": "moonclaw-\{session_id}-\{command_id}-\{kind}-\{now}",
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "command_id": command_id,
    "lane": lane,
    "kind": kind,
    "title": title,
    "status": status,
    "detail": detail,
    "created_at": now,
    "source": "moonclaw-native-mooncode",
  }
}

///|
fn mooncode_eval_report_payload(
  session_id : String,
  binding : MoonCodeSessionBinding?,
  now~ : @clock.Timestamp,
) -> Json {
  let command_count = match binding {
    Some(binding) => binding.command_count
    None => 0
  }
  {
    "kind": "mooncode-native-eval-report",
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "status": if command_count > 0 {
      "accepted"
    } else {
      "pending"
    },
    "generated_at": now,
    "harnesses": [
      {
        "id": "native-command-ingest",
        "status": if command_count > 0 {
          "passed"
        } else {
          "pending"
        },
        "evidence": "MoonClaw accepted \{command_count} native MoonCode command(s) for this session.",
      },
      {
        "id": "tool-loop-execution",
        "status": "delegated",
        "evidence": "Execution is delegated to the existing MoonClaw task agent and its tool runtime.",
      },
    ],
    "binding": match binding {
      Some(binding) => binding.to_json()
      None => Json::object({})
    },
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
fn mooncode_json_string(json : Json, key : String, default~ : String) -> String {
  match json {
    Json::Object(object) =>
      match object.get(key) {
        Some(Json::String(value)) => value
        _ => default
      }
    _ => default
  }
}

///|
fn mooncode_json_bool(json : Json, key : String, default~ : Bool) -> Bool {
  match json {
    Json::Object(object) =>
      match object.get(key) {
        Some(value) => @json.from_json(value) catch { _ => default }
        None => default
      }
    _ => default
  }
}

///|
fn mooncode_json_array_items(json : Json, key : String) -> Array[Json] {
  match json {
    Json::Object(object) =>
      match object.get(key) {
        Some(Json::Array(items)) => items
        _ => []
      }
    _ => []
  }
}

///|
fn mooncode_json_object_field_or_empty(json : Json, key : String) -> Json {
  match json {
    Json::Object(object) =>
      match object.get(key) {
        Some(Json::Object(_) as value) => value
        _ => Json::object({})
      }
    _ => Json::object({})
  }
}

///|
test "mooncode capabilities expose native daemon endpoints" {
  let payload = mooncode_capabilities_payload().stringify()
  assert_true(payload.contains("/v1/mooncode/capabilities"))
  assert_true(payload.contains("/v1/mooncode/sessions?book_root=<path>"))
  assert_true(payload.contains("/v1/mooncode/sessions/<id>?book_root=<path>"))
  assert_true(payload.contains("/v1/mooncode/sessions/<id>/commands"))
  assert_true(payload.contains("/v1/mooncode/sessions/<id>/package-result"))
  assert_true(
    payload.contains(
      "/v1/mooncode/sessions/<id>/runtime-claim?book_root=<path>",
    ),
  )
  assert_true(
    payload.contains(
      "/v1/mooncode/sessions/<id>/runtime-dispatch?book_root=<path>",
    ),
  )
  assert_true(
    payload.contains(
      "/v1/mooncode/sessions/<id>/runtime-events?book_root=<path>",
    ),
  )
  assert_true(
    payload.contains("/v1/mooncode/sessions/<id>/tool-exec?book_root=<path>"),
  )
  assert_true(payload.contains(".moonclaw/mooncode/sessions/<session-id>"))
  assert_true(payload.contains("runtime-dispatches.jsonl"))
  assert_true(payload.contains("\"native_runtime_ready\":true"))
  assert_true(
    payload.contains("\"control_commands\":[\"prompt\",\"steer\",\"cancel\"]"),
  )
}

///|
test "mooncode validates native command body" {
  let body : Json = {
    "protocol": "mooncode.v1",
    "session_id": "session-demo",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Build a miniapp",
    "packet": { "command_id": "cmd-1" },
  }
  let report = mooncode_validate_command_body("session-demo", body)
  assert_true(mooncode_json_bool(report, "ok", default=false))
  assert_eq(mooncode_json_string(report, "command_id", default=""), "cmd-1")
}

///|
test "mooncode validation reports mismatched session and missing command id" {
  let body : Json = {
    "protocol": "mooncode.v1",
    "session_id": "other",
    "book_root": "/tmp/book",
    "packet": {},
  }
  let report = mooncode_validate_command_body("session-demo", body)
  assert_false(mooncode_json_bool(report, "ok", default=true))
  let payload = report.stringify()
  assert_true(payload.contains("session_id"))
  assert_true(payload.contains("command_id"))
}

///|
test "mooncode native controls classify prompt steer and cancel" {
  assert_eq(mooncode_command_control("prompt"), "prompt")
  assert_eq(mooncode_command_control("run_tests"), "prompt")
  assert_eq(mooncode_command_control("steer"), "steer")
  assert_eq(mooncode_command_control("cancel"), "cancel")
  assert_eq(mooncode_accept_event_kind("prompt"), "command.accepted")
  assert_eq(mooncode_accept_event_kind("steer"), "steer.accepted")
  assert_eq(
    mooncode_accept_event_title("steer"),
    "MoonClaw accepted MoonCode steering",
  )
}

///|
test "mooncode package result validates command scoped proof" {
  let body : Json = {
    "protocol": "mooncode.v1",
    "session_id": "session-demo",
    "event": "package_verified",
    "path": "portable/app-tool/mooncode/session-demo/package-cmd-1.json",
    "detail": "bundle checks passed",
    "command_packet": { "command_id": "cmd-1", "action": "package" },
    "package_manifest": { "kind": "mooncode-package-manifest" },
    "package_index": { "kind": "mooncode-package-index" },
  }
  let report = mooncode_validate_package_result_body("session-demo", body)
  assert_true(mooncode_json_bool(report, "ok", default=false))
  assert_eq(mooncode_json_string(report, "command_id", default=""), "cmd-1")
  assert_eq(mooncode_package_result_status("package_verified"), "verified")
  let event = mooncode_package_result_event_record(
    session_id="session-demo",
    command_id="cmd-1",
    body,
    now=@clock.Timestamp::from_ms(42L),
  )
  assert_eq(
    mooncode_json_string(event, "kind", default=""),
    "runtime.package_verified",
  )
  assert_eq(mooncode_json_string(event, "lane", default=""), "artifact")
  assert_true(event.stringify().contains("mooncode-package-manifest"))
}

///|
test "mooncode package result rejects missing path and unsupported event" {
  let body : Json = {
    "protocol": "mooncode.v1",
    "session_id": "session-demo",
    "command_id": "cmd-1",
    "event": "package_started",
  }
  let report = mooncode_validate_package_result_body("session-demo", body)
  assert_false(mooncode_json_bool(report, "ok", default=true))
  let payload = report.stringify()
  assert_true(payload.contains("event"))
  assert_true(payload.contains("path"))
}

///|
test "mooncode stream normalizes moonclaw task events into lanes" {
  let assistant = mooncode_event_from_task_stream(
    session_id="session-demo",
    command_id="cmd-1",
    task_id="task-1",
    @server.Moonclaw(
      @event.Event::new(
        id=@uuid.nil,
        created=@clock.Timestamp::from_ms(42L),
        @event.AssistantMessageDelta("working"),
      ),
    ),
    index=0,
  )
  assert_eq(mooncode_json_string(assistant, "lane", default=""), "transcript")
  assert_eq(
    mooncode_json_string(assistant, "kind", default=""),
    "assistant_delta",
  )
  assert_eq(mooncode_json_string(assistant, "detail", default=""), "working")
  let tool = mooncode_event_from_task_stream(
    session_id="session-demo",
    command_id="cmd-1",
    task_id="task-1",
    @server.Moonclaw(
      @event.Event::new(
        id=@uuid.nil,
        created=@clock.Timestamp::from_ms(43L),
        @event.PostToolCall(
          @ai.tool_call(id="tc-1", name="read_file"),
          result=Ok({ "ok": true }),
          rendered="ok",
        ),
      ),
    ),
    index=1,
  )
  assert_eq(mooncode_json_string(tool, "lane", default=""), "tool")
  assert_eq(mooncode_json_string(tool, "kind", default=""), "tool_result")
  assert_eq(mooncode_json_string(tool, "detail", default=""), "read_file")
}

///|
async test "mooncode durable session sidecars use book local storage" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @pathx.join(
    @os.tmpdir(),
    "moonclaw-mooncode-durable-session-test",
  )
  @fsx.make_directory(book_root, recursive=true, exists_ok=true)
  let binding = MoonCodeSessionBinding::{
    session_id: "session/demo:1",
    task_id: @uuid.nil,
    book_root,
    command_count: 2,
    last_command_id: "cmd-2",
    last_updated: @clock.Timestamp::from_ms(42L),
    persisted_task_event_count: 0,
    events: @broadcast.Broadcast::new(),
  }
  let session_path = mooncode_session_snapshot_path(
    binding.book_root,
    binding.session_id,
  )
  @fsx.make_directory(
    @pathx.dirname(session_path),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    session_path,
    mooncode_session_snapshot(binding).stringify(),
  )
  mooncode_append_jsonl(
    mooncode_commands_path(binding.book_root, binding.session_id),
    { "kind": "mooncode-command", "command_id": "cmd-1" },
  )
  mooncode_append_jsonl(
    mooncode_runtime_dispatches_path(binding.book_root, binding.session_id),
    { "kind": "mooncode.runtime-dispatch", "command_id": "cmd-1" },
  )
  mooncode_append_jsonl(
    mooncode_events_path(binding.book_root, binding.session_id),
    { "kind": "assistant_delta", "command_id": "cmd-1" },
  )
  let snapshot = @fsx.read_file(session_path)
  assert_true(snapshot.contains("\"owner\":\"moonclaw\""))
  assert_true(snapshot.contains(".moonclaw/mooncode/sessions/session_demo_1"))
  assert_true(
    @fsx.read_file(
      mooncode_commands_path(binding.book_root, binding.session_id),
    ).contains("\"mooncode-command\""),
  )
  assert_true(
    @fsx.read_file(
      mooncode_runtime_dispatches_path(binding.book_root, binding.session_id),
    ).contains("\"mooncode.runtime-dispatch\""),
  )
  assert_true(
    @fsx.read_file(mooncode_events_path(binding.book_root, binding.session_id)).contains(
      "\"assistant_delta\"",
    ),
  )
}

///|
async test "mooncode durable sidecars list and show without live binding" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-sidecar-list-XXXXXX"),
  )
  let binding = MoonCodeSessionBinding::{
    session_id: "session/resume:1",
    task_id: @uuid.nil,
    book_root,
    command_count: 1,
    last_command_id: "cmd-resume",
    last_updated: @clock.Timestamp::from_ms(77L),
    persisted_task_event_count: 0,
    events: @broadcast.Broadcast::new(),
  }
  @fsx.make_directory(
    mooncode_session_dir(binding.book_root, binding.session_id),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    mooncode_session_snapshot_path(binding.book_root, binding.session_id),
    mooncode_session_snapshot(binding).stringify(),
  )
  mooncode_append_jsonl(
    mooncode_commands_path(binding.book_root, binding.session_id),
    { "kind": "mooncode-command", "command_id": "cmd-resume" },
  )
  mooncode_append_jsonl(
    mooncode_events_path(binding.book_root, binding.session_id),
    { "kind": "assistant_delta", "command_id": "cmd-resume" },
  )
  mooncode_append_jsonl(
    mooncode_package_results_path(binding.book_root, binding.session_id),
    { "kind": "mooncode-package-result", "command_id": "cmd-resume" },
  )
  mooncode_append_jsonl(
    mooncode_runtime_dispatches_path(binding.book_root, binding.session_id),
    { "kind": "mooncode.runtime-dispatch", "command_id": "cmd-resume" },
  )
  let records = mooncode_durable_session_records(book_root)
  assert_eq(records.length(), 1)
  let record = records[0]
  assert_eq(
    mooncode_json_string(record, "kind", default=""),
    "mooncode-session-record",
  )
  assert_eq(
    mooncode_json_string(record, "session_id", default=""),
    "session/resume:1",
  )
  assert_eq(mooncode_json_string(record, "resume_state", default=""), "durable")
  let text = record.stringify()
  assert_true(text.contains("\"command_log_count\":1"))
  assert_true(text.contains("\"runtime_dispatch_log_count\":1"))
  assert_true(text.contains("\"event_log_count\":1"))
  assert_true(text.contains("\"package_result_log_count\":1"))
  assert_true(text.contains("\"live_binding_ready\":false"))
}

///|
test "mooncode runtime claim state leases next durable command" {
  let commands : Array[Json] = [
    {
      "kind": "mooncode-command",
      "protocol": "mooncode.v1",
      "session_id": "session-claim",
      "command_id": "cmd-1",
      "command": {
        "protocol": "mooncode.v1",
        "session_id": "session-claim",
        "book_root": "/tmp/book",
        "command": "prompt",
        "packet": { "command_id": "cmd-1" },
      },
    },
    {
      "kind": "mooncode-command",
      "protocol": "mooncode.v1",
      "session_id": "session-claim",
      "command_id": "cmd-2",
      "command": {
        "protocol": "mooncode.v1",
        "session_id": "session-claim",
        "book_root": "/tmp/book",
        "command": "steer",
        "packet": { "command_id": "cmd-2" },
      },
    },
  ]
  let state = mooncode_runtime_claim_state_from_logs(
    "session-claim",
    "/tmp/book",
    commands,
    [],
    commands_path="/tmp/book/commands.jsonl",
    dispatches_path="/tmp/book/runtime-dispatches.jsonl",
  )
  assert_eq(
    mooncode_json_string(state, "kind", default=""),
    "mooncode-runtime-claim-state",
  )
  assert_true(mooncode_json_bool(state, "claim_ready", default=false))
  assert_true(state.stringify().contains("\"claimable_command_count\":1"))
  assert_true(state.stringify().contains("\"order_blocked_command_count\":1"))
  let claimable = mooncode_json_array_items(state, "claimable_commands")
  assert_eq(
    mooncode_json_string(claimable[0], "command_id", default=""),
    "cmd-1",
  )
  let blocked = mooncode_json_array_items(state, "order_blocked_commands")
  assert_eq(
    mooncode_json_string(blocked[0], "order_blocked_by", default=""),
    "cmd-1",
  )
  let receipts = mooncode_runtime_claim_receipts(
    "session-claim",
    "/tmp/book",
    state,
    { "consumer_id": "test-consumer" },
    now=@clock.Timestamp::from_ms(100L),
  )
  assert_eq(receipts.length(), 1)
  assert_eq(
    mooncode_json_string(receipts[0], "status", default=""),
    "runtime-claimed",
  )
  assert_eq(
    mooncode_json_string(receipts[0], "consumer_id", default=""),
    "test-consumer",
  )
  let claimed_state = mooncode_runtime_claim_state_from_logs(
    "session-claim",
    "/tmp/book",
    commands,
    receipts,
    commands_path="/tmp/book/commands.jsonl",
    dispatches_path="/tmp/book/runtime-dispatches.jsonl",
  )
  assert_true(claimed_state.stringify().contains("\"claimed_command_count\":1"))
  assert_true(
    claimed_state.stringify().contains("\"claimable_command_count\":0"),
  )
}

///|
test "mooncode runtime delivery receipt resolves claimed command" {
  let commands : Array[Json] = [
    {
      "kind": "mooncode-command",
      "protocol": "mooncode.v1",
      "session_id": "session-deliver",
      "command_id": "cmd-1",
      "command": {
        "protocol": "mooncode.v1",
        "session_id": "session-deliver",
        "book_root": "/tmp/book",
        "command": "prompt",
        "packet": { "command_id": "cmd-1" },
      },
    },
    {
      "kind": "mooncode-command",
      "protocol": "mooncode.v1",
      "session_id": "session-deliver",
      "command_id": "cmd-2",
      "command": {
        "protocol": "mooncode.v1",
        "session_id": "session-deliver",
        "book_root": "/tmp/book",
        "command": "run_tests",
        "packet": { "command_id": "cmd-2" },
      },
    },
  ]
  let claimed = {
    "kind": "mooncode.runtime-dispatch",
    "protocol": "mooncode.v1",
    "session_id": "session-deliver",
    "book_root": "/tmp/book",
    "command_id": "cmd-1",
    "status": "runtime-claimed",
    "claim_id": "claim-1",
    "consumer_id": "test-consumer",
  }
  let claimed_state = mooncode_runtime_claim_state_from_logs(
    "session-deliver",
    "/tmp/book",
    commands,
    [claimed],
    commands_path="/tmp/book/commands.jsonl",
    dispatches_path="/tmp/book/runtime-dispatches.jsonl",
  )
  let claimed_items = mooncode_json_array_items(
    claimed_state, "claimed_commands",
  )
  let delivered = mooncode_runtime_dispatch_receipt(
    "session-deliver",
    "/tmp/book",
    claimed_items[0],
    {
      "accepted": true,
      "command_id": "cmd-1",
      "task_id": "task-1",
      "message_id": "message-1",
      "control": "prompt",
      "message": "accepted",
      "events": [{ "kind": "command.accepted" }],
    },
    consumer_id="test-consumer",
    now=@clock.Timestamp::from_ms(120L),
  )
  assert_eq(
    mooncode_json_string(delivered, "status", default=""),
    "runtime-delivered",
  )
  assert_eq(mooncode_json_string(delivered, "claim_id", default=""), "claim-1")
  let after = mooncode_runtime_claim_state_from_logs(
    "session-deliver",
    "/tmp/book",
    commands,
    [claimed, delivered],
    commands_path="/tmp/book/commands.jsonl",
    dispatches_path="/tmp/book/runtime-dispatches.jsonl",
  )
  assert_true(after.stringify().contains("\"delivered_command_count\":1"))
  assert_true(after.stringify().contains("\"claimable_command_count\":1"))
  let claimable = mooncode_json_array_items(after, "claimable_commands")
  assert_eq(
    mooncode_json_string(claimable[0], "command_id", default=""),
    "cmd-2",
  )
}

///|
test "mooncode runtime dispatch receipt classifies cancel as terminal" {
  let item : Json = {
    "kind": "mooncode-runtime-claim-item",
    "protocol": "mooncode.v1",
    "command_id": "cmd-cancel",
    "command": {
      "protocol": "mooncode.v1",
      "session_id": "session-cancel",
      "book_root": "/tmp/book",
      "command": "cancel",
      "packet": { "command_id": "cmd-cancel" },
    },
    "receipt": {
      "kind": "mooncode.runtime-dispatch",
      "status": "runtime-claimed",
      "claim_id": "claim-cancel",
    },
  }
  let receipt = mooncode_runtime_dispatch_receipt(
    "session-cancel",
    "/tmp/book",
    item,
    {
      "accepted": true,
      "command_id": "cmd-cancel",
      "task_id": "task-cancel",
      "control": "cancel",
      "message": "MoonClaw MoonCode runtime accepted `cancel`",
      "events": [{ "kind": "cancel.requested" }],
    },
    consumer_id="test-consumer",
    now=@clock.Timestamp::from_ms(160L),
  )
  assert_eq(
    mooncode_json_string(receipt, "status", default=""),
    "runtime-cancelled",
  )
  assert_true(
    mooncode_runtime_receipt_status_delivered(
      mooncode_json_string(receipt, "status", default=""),
    ),
  )
  assert_eq(mooncode_json_string(receipt, "control", default=""), "cancel")
}

///|
test "mooncode eval report records delegated task execution" {
  let report = mooncode_eval_report_payload(
    "session-demo",
    None,
    now=@clock.Timestamp::from_ms(42L),
  )
  assert_eq(mooncode_json_string(report, "status", default=""), "pending")
  assert_true(report.stringify().contains("tool-loop-execution"))
}
