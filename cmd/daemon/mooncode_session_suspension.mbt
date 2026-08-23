///|
const MOONCODE_SESSION_SUSPENSION_CONTRACT : String = "mooncode.session-suspension.v1"

///|
const MOONCODE_SESSION_SUSPENSION_MAX_DEPTH : Int = 32

///|
const MOONCODE_SESSION_SUSPENSION_MAX_SESSIONS : Int = 256

///|
let mooncode_session_suspension_requests : Map[String, Bool] = Map([])

///|
fn mooncode_session_suspension_key(
  book_root : String,
  session_id : String,
) -> String {
  mooncode_goal_runtime_sha256_hex(book_root + "\n" + session_id)
}

///|
fn mooncode_session_suspension_requested(
  book_root : String,
  session_id : String,
) -> Bool {
  mooncode_session_suspension_requests.contains(
    mooncode_session_suspension_key(book_root, session_id),
  )
}

///|
async fn mooncode_collect_session_descendants(
  book_root : String,
  session_id : String,
  depth : Int,
  visited : Map[String, Bool],
  sessions : Array[Json],
) -> Unit {
  if depth > MOONCODE_SESSION_SUSPENSION_MAX_DEPTH {
    raise InvalidJournal(
      "MoonCode worker lineage exceeds the suspension depth policy",
    )
  }
  if sessions.length() >= MOONCODE_SESSION_SUSPENSION_MAX_SESSIONS {
    raise InvalidJournal(
      "MoonCode worker lineage exceeds the suspension size policy",
    )
  }
  let key = mooncode_session_suspension_key(book_root, session_id)
  if visited.contains(key) {
    return
  }
  visited[key] = true
  sessions.push({
    "session_id": session_id,
    "book_root": book_root,
    "depth": depth,
  })
  for worker in mooncode_worker_records(book_root, session_id) {
    let child_session_id = mooncode_json_string(
      worker,
      "child_session_id",
      default="",
    )
    let child_book_root = mooncode_json_string(
      worker,
      "child_book_root",
      default="",
    )
    if child_session_id != "" && child_book_root != "" {
      mooncode_collect_session_descendants(
        child_book_root,
        child_session_id,
        depth + 1,
        visited,
        sessions,
      )
    }
  }
}

///|
async fn mooncode_session_tree(
  book_root : String,
  session_id : String,
) -> Array[Json] {
  let sessions : Array[Json] = []
  mooncode_collect_session_descendants(
    book_root,
    session_id,
    0,
    Map([]),
    sessions,
  )
  sessions
}

///|
async fn Daemon::mooncode_cancel_session_runtime(
  self : Daemon,
  session_id : String,
) -> Bool {
  match self.mooncode_sessions.get(session_id) {
    Some(binding) if binding.runtime_service_running => {
      match binding.runtime_service_task {
        Some(task) => {
          task.cancel()
          let _ = task.wait() catch { _ => () }
          binding.runtime_service_task = None
        }
        None => ()
      }
      binding.runtime_service_running = false
      binding.active_command_id = ""
      true
    }
    _ => false
  }
}

///|
async fn Daemon::mooncode_suspend_session_node(
  self : Daemon,
  session : Json,
  operation_id : String,
  descendant_count : Int,
) -> Json {
  let session_id = mooncode_json_string(session, "session_id", default="")
  let book_root = mooncode_json_string(session, "book_root", default="")
  let lifecycle_gate = mooncode_open_session_lifecycle_gate(
    book_root, session_id,
  )
  defer lifecycle_gate.close()
  lifecycle_gate.lock(Exclusive)
  defer lifecycle_gate.unlock()
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Exclusive)
  defer session_lock.unlock()
  let state = mooncode_session_state_locked(book_root, session_id)
  match state {
    "suspended" =>
      return {
        "session_id": session_id,
        "book_root": book_root,
        "state": "suspended",
        "changed": false,
      }
    "active" | "suspending" => ()
    "archived" | "deleted" =>
      return {
        "session_id": session_id,
        "book_root": book_root,
        "state": state,
        "changed": false,
      }
    "new" =>
      return {
        "session_id": session_id,
        "book_root": book_root,
        "state": "missing",
        "changed": false,
      }
    other =>
      raise InvalidJournal(
        "MoonCode session `\{session_id}` cannot suspend from lifecycle state `\{other}`",
      )
  }
  mooncode_write_session_state_locked(book_root, session_id, "suspending")
  let now = self.clock.now()
  ignore(
    mooncode_append_session_journal_once_locked(
      book_root,
      session_id,
      mooncode_journal_event(),
      {
        "id": "suspend:\{operation_id}:\{mooncode_safe_session_id(session_id)}",
        "kind": "session.suspended",
        "event": "session.suspended",
        "contract": MOONCODE_SESSION_SUSPENSION_CONTRACT,
        "session_id": session_id,
        "command_id": "",
        "lane": "session",
        "status": "suspended",
        "state": "suspended",
        "created_at": now,
        "descendant_count": descendant_count,
        "detail": "Runtime work was cancelled and this session was sealed against new commands.",
      },
      require_active=false,
    ),
  )
  mooncode_write_session_state_locked(book_root, session_id, "suspended")
  {
    "session_id": session_id,
    "book_root": book_root,
    "state": "suspended",
    "changed": true,
  }
}

///|
async fn Daemon::mooncode_suspend_session_tree(
  self : Daemon,
  session_id : String,
  book_root : String,
) -> Json {
  let sessions = mooncode_session_tree(book_root, session_id)
  for session in sessions {
    mooncode_session_suspension_requests[mooncode_session_suspension_key(
      mooncode_json_string(session, "book_root", default=""),
      mooncode_json_string(session, "session_id", default=""),
    )] = true
  }
  defer (for session in sessions {
    mooncode_session_suspension_requests.remove(
      mooncode_session_suspension_key(
        mooncode_json_string(session, "book_root", default=""),
        mooncode_json_string(session, "session_id", default=""),
      ),
    )
  })
  let cancelled : Map[String, Bool] = Map([])
  for session in sessions {
    let current_id = mooncode_json_string(session, "session_id", default="")
    cancelled[current_id] = self.mooncode_cancel_session_runtime(current_id)
  }
  let operation_id = self.uuid.v4().to_string()
  let suspended_sessions : Array[Json] = []
  let mut index = sessions.length() - 1
  while index >= 0 {
    let session = sessions[index]
    let current_id = mooncode_json_string(session, "session_id", default="")
    let result = self.mooncode_suspend_session_node(
      session,
      operation_id,
      if index == 0 {
        sessions.length() - 1
      } else {
        0
      },
    )
    suspended_sessions.push(
      mooncode_json_object_with_field(
        result,
        "runtime_cancelled",
        cancelled.get(current_id).unwrap_or(false).to_json(),
      ),
    )
    index -= 1
  }
  {
    "kind": "mooncode-session-lifecycle-result",
    "contract": MOONCODE_SESSION_SUSPENSION_CONTRACT,
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "action": "suspend",
    "session_id": session_id,
    "suspended": true,
    "descendant_count": (sessions.length() - 1).max(0),
    "sessions": Json::array(suspended_sessions),
  }
}

///|
async fn Daemon::mooncode_resume_session(
  self : Daemon,
  session_id : String,
  book_root : String,
) -> Json {
  let lifecycle_gate = mooncode_open_session_lifecycle_gate(
    book_root, session_id,
  )
  defer lifecycle_gate.close()
  lifecycle_gate.lock(Exclusive)
  defer lifecycle_gate.unlock()
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Exclusive)
  defer session_lock.unlock()
  let state = mooncode_session_state_locked(book_root, session_id)
  if state != "suspended" && state != "suspending" && state != "active" {
    raise mooncode_session_management_error(
      409,
      "Conflict",
      "MoonCode session cannot resume from lifecycle state `\{state}`",
      session_id,
    )
  }
  if state != "active" {
    mooncode_write_session_state_locked(book_root, session_id, "resuming")
    ignore(
      mooncode_append_session_journal_once_locked(
        book_root,
        session_id,
        mooncode_journal_event(),
        {
          "id": "resume:\{self.uuid.v4()}:\{mooncode_safe_session_id(session_id)}",
          "kind": "session.resumed",
          "event": "session.resumed",
          "contract": MOONCODE_SESSION_SUSPENSION_CONTRACT,
          "session_id": session_id,
          "command_id": "",
          "lane": "session",
          "status": "active",
          "state": "active",
          "created_at": self.clock.now(),
          "detail": "The parent session may accept new commands; descendants remain suspended until explicitly resumed.",
        },
        require_active=false,
      ),
    )
    mooncode_write_session_state_locked(book_root, session_id, "active")
  }
  {
    "kind": "mooncode-session-lifecycle-result",
    "contract": MOONCODE_SESSION_SUSPENSION_CONTRACT,
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "action": "resume",
    "session_id": session_id,
    "suspended": false,
    "descendants_remain_suspended": true,
  }
}

///|
async fn mooncode_require_descendants_sealed(
  book_root : String,
  session_id : String,
) -> Unit {
  let sessions = mooncode_session_tree(book_root, session_id)
  for index in 1..<sessions.length() {
    let child = sessions[index]
    let child_id = mooncode_json_string(child, "session_id", default="")
    let child_root = mooncode_json_string(child, "book_root", default="")
    let state = mooncode_session_state_locked(child_root, child_id)
    if state != "suspended" && state != "archived" && state != "deleted" {
      raise mooncode_session_management_error(
        409,
        "Conflict",
        "MoonCode descendant `\{child_id}` is not sealed; suspend the parent before changing its storage",
        session_id,
      )
    }
  }
}
