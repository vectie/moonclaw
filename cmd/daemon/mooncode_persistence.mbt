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
        "planner_mode": if mooncode_runtime_turn_explicit_tool_calls(body)
          .length() > 0 {
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
  let journal = mooncode_read_session_journal(
    binding.book_root,
    binding.session_id,
  )
  mooncode_write_locked_file(
    mooncode_session_snapshot_path(binding.book_root, binding.session_id),
    mooncode_session_snapshot(
      binding,
      journal_sequence=mooncode_journal_last_sequence(journal),
    ).stringify(indent=2),
  )
}
