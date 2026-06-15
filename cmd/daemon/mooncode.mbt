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
      "/v1/mooncode/capabilities", "/v1/mooncode/sessions/<id>/commands", "/v1/mooncode/sessions/<id>/stream",
      "/v1/mooncode/sessions/<id>/eval-report", "/v1/mooncode/sessions/<id>/package-result",
    ],
    "control_commands": ["prompt", "steer", "cancel"],
    "tools": ["read", "edit", "write", "shell", "moon_check", "finish"],
    "execution_boundary": "MoonClaw accepts Moondesk MoonCode command packets and executes them through the existing MoonClaw task/agent runtime for the target book root.",
    "package_result_endpoint": "POST /v1/mooncode/sessions/<id>/package-result accepts package_built/package_verified proof packets for MoonBook-owned executable artifacts.",
    "durable_session_store": ".moonclaw/mooncode/sessions/<session-id>/session.json plus commands.jsonl, events.jsonl, and package-results.jsonl under the selected book root.",
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
  let command_id = mooncode_command_id(body)
  let action = mooncode_json_string(body, "command", default="prompt")
  if action == "cancel" {
    self.mooncode_cancel_command(session_id~, body, w)
    return
  }
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
  self.mooncode_persist_command(body, binding, events)
  w.header().set("Content-Type", "application/json")
  w.write_header(202, reason="Accepted")
  w.write(
    (
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
        "binding": binding.to_json(),
        "events": Json::array(events),
      } : Json).stringify(indent=2),
  )
}

///|
async fn Daemon::mooncode_cancel_command(
  self : Daemon,
  session_id~ : String,
  body : Json,
  w : @httpx.ResponseWriter,
) -> Unit {
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
    binding.command_count += 1
    binding.last_command_id = command_id
    binding.last_updated = now
    binding.events.put(event)
    self.mooncode_persist_event(binding, event)
    self.mooncode_persist_session(binding)
    w.header().set("Content-Type", "application/json")
    w.write_header(202, reason="Accepted")
    w.write(
      (
        {
          "accepted": false,
          "protocol": "mooncode.v1",
          "session_id": session_id,
          "command_id": command_id,
          "control": "cancel",
          "message": "MoonCode cancel has no active MoonClaw task",
          "binding": binding.to_json(),
          "events": Json::array([event]),
        } : Json).stringify(indent=2),
    )
    return
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
  self.mooncode_persist_command(body, binding, [event])
  w.header().set("Content-Type", "application/json")
  w.write_header(202, reason="Accepted")
  w.write(
    (
      {
        "accepted": true,
        "protocol": "mooncode.v1",
        "session_id": session_id,
        "command_id": command_id,
        "control": "cancel",
        "task": task,
        "task_id": task.id,
        "message": "MoonClaw MoonCode runtime accepted `cancel`",
        "cancel": cancel_payload,
        "binding": binding.to_json(),
        "events": Json::array([event]),
      } : Json).stringify(indent=2),
  )
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
  book_root
  |> @pathx.join(".moonclaw")
  |> @pathx.join("mooncode")
  |> @pathx.join("sessions")
  |> @pathx.join(mooncode_safe_session_id(session_id))
}

///|
fn mooncode_session_snapshot_path(
  book_root : String,
  session_id : String,
) -> String {
  mooncode_session_dir(book_root, session_id) |> @pathx.join("session.json")
}

///|
fn mooncode_commands_path(book_root : String, session_id : String) -> String {
  mooncode_session_dir(book_root, session_id) |> @pathx.join("commands.jsonl")
}

///|
fn mooncode_events_path(book_root : String, session_id : String) -> String {
  mooncode_session_dir(book_root, session_id) |> @pathx.join("events.jsonl")
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
  assert_true(payload.contains("/v1/mooncode/sessions/<id>/commands"))
  assert_true(payload.contains("/v1/mooncode/sessions/<id>/package-result"))
  assert_true(payload.contains(".moonclaw/mooncode/sessions/<session-id>"))
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
    @fsx.read_file(mooncode_events_path(binding.book_root, binding.session_id)).contains(
      "\"assistant_delta\"",
    ),
  )
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
