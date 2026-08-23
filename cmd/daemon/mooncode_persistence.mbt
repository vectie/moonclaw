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
  let journal_path = mooncode_session_journal_path(
    binding.book_root,
    binding.session_id,
  )
  let canonical_path = @fs.realpath(journal_path)
  let journal_file = @fs.open(
    journal_path,
    mode=ReadWrite,
    append=false,
    create_mode=OpenExisting,
  )
  defer journal_file.close()
  journal_file.lock(Exclusive)
  defer journal_file.unlock()
  mooncode_repair_journal_tail(journal_file)
  let committed_size = journal_file.size()
  let state = match mooncode_journal_append_states.get(canonical_path) {
    Some(state) if mooncode_journal_append_state_matches(
        state, journal_file, committed_size,
      ) => state
    _ => {
      mooncode_journal_append_states.remove(canonical_path)
      let rebuilt = mooncode_journal_scan_append_state(
        journal_file,
        binding.session_id,
      )
      mooncode_journal_append_scan_counts[canonical_path] = mooncode_journal_append_scan_count_get(
          canonical_path,
        ) +
        1
      mooncode_journal_append_states[canonical_path] = rebuilt
      rebuilt
    }
  }
  let snapshot_path = mooncode_session_snapshot_path(
    binding.book_root,
    binding.session_id,
  )
  mooncode_write_locked_file(
    snapshot_path,
    mooncode_session_snapshot(binding, journal_sequence=state.cursor).stringify(
      indent=2,
    ),
  )
  mooncode_sync_journal_directories(
    mooncode_journal_commit_directories(snapshot_path),
  )
}
