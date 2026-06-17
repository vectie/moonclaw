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
      "protocol": mooncode_protocol_version(),
      "session_id": binding.session_id,
      "command_id": mooncode_command_id(body),
      "created_at": self.clock.now(),
      "web_search": mooncode_command_web_search(body),
      "command": body,
    },
  )
  for event in events {
    self.mooncode_persist_event(binding, event)
  }
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
