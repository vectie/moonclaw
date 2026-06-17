///|
/// In-memory binding between a Moondesk MoonCode session id and the MoonClaw
/// task that executes commands for that session.
priv struct MoonCodeSessionBinding {
  session_id : String
  task_id : @uuid.Uuid
  mut book_root : String
  mut command_count : Int
  mut first_user_prompt : String
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
    "first_user_prompt": self.first_user_prompt,
    "last_command_id": self.last_command_id,
    "last_updated": self.last_updated,
    "persisted_task_event_count": self.persisted_task_event_count,
  }
}

///|
async fn Daemon::mooncode_get_session(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let session_id = session_id.to_owned()
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
    web_search=mooncode_command_web_search(body),
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
        first_user_prompt: "",
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
        first_user_prompt: "",
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
fn MoonCodeSessionBinding::remember_first_user_prompt(
  self : MoonCodeSessionBinding,
  body : Json,
) -> Unit {
  if self.first_user_prompt != "" {
    return
  }
  let command = mooncode_json_string(body, "command", default="prompt")
  if command != "prompt" && command != "steer" {
    return
  }
  let text = mooncode_json_string(body, "text", default="").trim()
  if text != "" {
    self.first_user_prompt = text.to_owned()
  }
}
