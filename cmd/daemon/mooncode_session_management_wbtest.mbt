///|
async fn mooncode_management_test_create_session(
  daemon : Daemon,
  book_root : String,
  session_id : String,
) -> Unit {
  let binding = daemon.mooncode_binding_for_session(session_id)
  binding.book_root = book_root
  binding.workspace_id = "book-code-lab"
  binding.workspace_name = "Code Lab"
  binding.command_count = 1
  binding.first_user_prompt = "Build a durable tool"
  binding.last_command_id = "cmd-1"
  binding.last_updated = @clock.Timestamp::from_ms(100L)
  @fsx.make_directory(
    mooncode_session_dir(book_root, session_id),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    mooncode_session_snapshot_path(book_root, session_id),
    mooncode_session_snapshot(binding).stringify(),
  )
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": "cmd-1",
      "client_turn_id": "client-1",
      "created_at": "2026-07-15T00:00:00Z",
      "command": {
        "command": "prompt",
        "text": "Build a durable tool",
        "packet": { "client_turn_id": "client-1" },
      },
    },
  )
}

///|
async test "mooncode session lifecycle is durable and preserves book content" {
  @moonclaw_fsx.with_temporary_directory("moonclaw-session-lifecycle-XXXXXX", book_root => {
    let session_id = "session/lifecycle:1"
    let book_file = @pathx.join(book_root, "chapter.mbt")
    @fsx.write_to_file(book_file, "fn chapter() -> Int { 1 }")
    let daemon = mooncode_control_test_daemon(book_root)
    mooncode_management_test_create_session(daemon, book_root, session_id)
    let renamed = daemon.mooncode_manage_session_response(session_id, {
      "action": "rename",
      "book_root": book_root,
      "title": "Durable lifecycle",
    })
    assert_eq(
      mooncode_json_string(renamed, "title", default=""),
      "Durable lifecycle",
    )
    let journal = mooncode_read_session_journal(book_root, session_id)
    let events = mooncode_journal_entries(journal, mooncode_journal_event())
    let rename_events = events.filter(event => {
      mooncode_json_string(event, "kind", default="") ==
      mooncode_session_rename_event_kind()
    })
    assert_eq(rename_events.length(), 1)
    let rename_event_id = mooncode_json_string(
      rename_events[0],
      "id",
      default="",
    )
    assert_true(rename_event_id.has_prefix("mooncode-session-rename-"))
    assert_false(rename_event_id.contains("{self.uuid.v4()}"))
    let restarted = mooncode_control_test_daemon(book_root)
    let restarted_records = restarted.mooncode_session_listing_records(
      book_root,
      include_log_counts=true,
    )
    assert_eq(restarted_records.length(), 1)
    assert_eq(
      mooncode_json_string(
        mooncode_session_listing_row(restarted_records[0]),
        "title",
        default="",
      ),
      "Durable lifecycle",
    )
    let archived = restarted.mooncode_manage_session_response(session_id, {
      "action": "archive",
      "book_root": book_root,
    })
    assert_true(mooncode_json_bool(archived, "archived", default=false))
    assert_eq(
      restarted
      .mooncode_session_listing_records(book_root, include_log_counts=true)
      .length(),
      0,
    )
    let archived_records = restarted.mooncode_archived_session_listing_records(
      book_root,
      include_log_counts=true,
    )
    assert_eq(archived_records.length(), 1)
    let archived_row = mooncode_session_listing_row(archived_records[0])
    assert_true(mooncode_json_bool(archived_row, "archived", default=false))
    assert_eq(
      mooncode_json_string(archived_row, "title", default=""),
      "Durable lifecycle",
    )
    assert_eq(@fsx.read_file(book_file), "fn chapter() -> Int { 1 }")
    let restored = restarted.mooncode_manage_session_response(session_id, {
      "action": "restore",
      "book_root": book_root,
    })
    assert_false(mooncode_json_bool(restored, "archived", default=true))
    assert_eq(
      restarted
      .mooncode_session_listing_records(book_root, include_log_counts=true)
      .length(),
      1,
    )
    let deleted = restarted.mooncode_manage_session_response(session_id, {
      "action": "delete",
      "book_root": book_root,
    })
    assert_true(mooncode_json_bool(deleted, "deleted", default=false))
    assert_eq(
      restarted
      .mooncode_session_listing_records(book_root, include_log_counts=true)
      .length(),
      0,
    )
    assert_eq(
      restarted
      .mooncode_archived_session_listing_records(
        book_root,
        include_log_counts=true,
      )
      .length(),
      0,
    )
    assert_eq(@fsx.read_file(book_file), "fn chapter() -> Int { 1 }")
  })
}

///|
async test "mooncode session lifecycle refuses storage changes while running" {
  @moonclaw_fsx.with_temporary_directory("moonclaw-session-running-XXXXXX", book_root => {
    let session_id = "session-running"
    let daemon = mooncode_control_test_daemon(book_root)
    mooncode_management_test_create_session(daemon, book_root, session_id)
    let binding = daemon.mooncode_binding_for_session(session_id)
    binding.runtime_service_running = true
    let mut rejected = false
    ignore(
      daemon.mooncode_manage_session_response(session_id, {
        "action": "archive",
        "book_root": book_root,
      }) catch {
        _ => {
          rejected = true
          Json::object({})
        }
      },
    )
    assert_true(rejected)
    assert_true(@fsx.exists(mooncode_session_dir(book_root, session_id)))
  })
}
