///|
/// In-memory MoonCode session state for a selected MoonBook.
priv struct MoonCodeSessionBinding {
  session_id : String
  mut book_root : String
  mut workspace_id : String
  mut workspace_name : String
  mut command_count : Int
  mut first_user_prompt : String
  mut last_command_id : String
  mut last_updated : @clock.Timestamp
  mut runtime_service_running : Bool
  events : @broadcast.Broadcast[Json]
}

///|
fn MoonCodeSessionBinding::to_json(self : MoonCodeSessionBinding) -> Json {
  {
    "session_id": self.session_id,
    "book_root": self.book_root,
    "workspace_id": self.workspace_id,
    "workspace_name": self.workspace_name,
    "command_count": self.command_count,
    "first_user_prompt": self.first_user_prompt,
    "last_command_id": self.last_command_id,
    "last_updated": self.last_updated,
    "runtime_service_running": self.runtime_service_running,
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
fn Daemon::mooncode_binding_for_session(
  self : Daemon,
  session_id : String,
) -> MoonCodeSessionBinding {
  match self.mooncode_sessions.get(session_id) {
    Some(binding) => binding
    None => {
      let binding = MoonCodeSessionBinding::{
        session_id,
        book_root: "",
        workspace_id: "",
        workspace_name: "",
        command_count: 0,
        first_user_prompt: "",
        last_command_id: "",
        last_updated: self.clock.now(),
        runtime_service_running: false,
        events: @broadcast.Broadcast::new(),
      }
      self.mooncode_sessions[session_id] = binding
      binding
    }
  }
}

///|
fn MoonCodeSessionBinding::bind_book_root(
  self : MoonCodeSessionBinding,
  requested_root : String,
) -> Bool {
  if requested_root == "" {
    return false
  }
  if self.book_root == "" {
    self.book_root = requested_root
    return true
  }
  self.book_root == requested_root
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
async fn Daemon::mooncode_session_listing_records(
  self : Daemon,
  book_root : String,
  include_log_counts~ : Bool,
) -> Array[Json] {
  let records = []
  let seen : Map[String, Bool] = {}
  if book_root != "" {
    for
      record in mooncode_durable_session_listing_records(
        book_root,
        include_log_counts~,
      ) {
      let session_id = mooncode_json_string(record, "session_id", default="")
      if session_id != "" {
        seen[session_id] = true
      }
      records.push(record)
    }
  }
  for binding in self.mooncode_sessions.values() {
    if mooncode_listing_root_matches(book_root, binding.book_root) &&
      !seen.contains(binding.session_id) {
      records.push(
        mooncode_session_listing_record_from_parts(
          binding.session_id,
          binding.book_root,
          Some(binding),
          mooncode_session_snapshot(binding),
          source="memory",
          include_log_counts~,
        ),
      )
    }
  }
  records
}

///|
fn mooncode_listing_root_matches(
  requested_root : String,
  book_root : String,
) -> Bool {
  requested_root == "" ||
  requested_root == book_root ||
  mooncode_sessions_root(requested_root) == mooncode_sessions_root(book_root)
}

///|
async fn Daemon::mooncode_session_record(
  self : Daemon,
  session_id : String,
  book_root : String,
) -> Json? {
  match self.mooncode_sessions.get(session_id) {
    Some(binding) if mooncode_listing_root_matches(book_root, binding.book_root) =>
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
    let session_book_root = mooncode_json_string(
      snapshot,
      "book_root",
      default=book_root,
    )
    Some(
      mooncode_session_record_from_parts(
        session_id,
        session_book_root,
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

///|
async fn MoonCodeSessionBinding::restore_first_user_prompt(
  self : MoonCodeSessionBinding,
) -> Unit {
  if self.first_user_prompt != "" || self.book_root == "" {
    return
  }
  let journal = mooncode_read_session_journal(self.book_root, self.session_id)
  for entry in mooncode_journal_entries(journal, mooncode_journal_command()) {
    self.remember_first_user_prompt(
      mooncode_json_object_field_or_empty(entry, "command"),
    )
    if self.first_user_prompt != "" {
      return
    }
  }
}

///|
fn MoonCodeSessionBinding::remember_workspace(
  self : MoonCodeSessionBinding,
  body : Json,
) -> Unit {
  let packet = mooncode_json_object_field_or_empty(body, "packet")
  let workspace_id = mooncode_json_string(
    packet,
    "workspace_id",
    default=mooncode_json_string(body, "workspace_id", default=""),
  )
  let workspace_name = mooncode_json_string(
    packet,
    "workspace_name",
    default=mooncode_json_string(body, "workspace_name", default=""),
  )
  if workspace_id != "" {
    self.workspace_id = workspace_id
  }
  if workspace_name != "" {
    self.workspace_name = workspace_name
  }
}
