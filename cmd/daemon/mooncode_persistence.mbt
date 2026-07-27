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
  ignore(
    mooncode_append_session_journal(
      binding.book_root,
      binding.session_id,
      mooncode_journal_command(),
      {
        "kind": "mooncode-command",
        "protocol": mooncode_protocol_version(),
        "session_id": binding.session_id,
        "command_id": mooncode_command_id(body),
        "created_at": self.clock.now(),
        "web_search": mooncode_command_web_search(body),
        "planner_mode": if mooncode_runtime_turn_explicit_tool_calls(body).length() >
          0 {
          "explicit-tool-calls"
        } else {
          ""
        },
        "command": body,
      },
    ),
  )
  for event in events {
    self.mooncode_persist_event(binding, event)
  }
  self.mooncode_persist_session(binding)
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
  ignore(
    mooncode_append_session_journal(
      binding.book_root,
      binding.session_id,
      mooncode_journal_event(),
      event,
    ),
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
  let session_lock = mooncode_open_session_lock(
    binding.book_root,
    binding.session_id,
  )
  defer session_lock.close()
  session_lock.lock(Exclusive)
  defer session_lock.unlock()
  mooncode_require_active_session_state_locked(
    binding.book_root,
    binding.session_id,
  )
  let journal = mooncode_read_session_journal_path(
    mooncode_session_journal_path(binding.book_root, binding.session_id),
    binding.session_id,
  )
  let snapshot_path = mooncode_session_snapshot_path(
    binding.book_root,
    binding.session_id,
  )
  mooncode_write_locked_file(
    snapshot_path,
    mooncode_session_snapshot(
      binding,
      journal_sequence=mooncode_journal_last_sequence_exact(journal),
    ).stringify(indent=2),
  )
  mooncode_sync_journal_directories(
    mooncode_journal_commit_directories(snapshot_path),
  )
}
