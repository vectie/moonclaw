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
async test "mooncode stable session lock serializes append storage and archive" {
  @moonclaw_fsx.with_temporary_directory("moonclaw-session-lock-XXXXXX", book_root => {
    let session_id = "session-lock"
    let daemon = mooncode_control_test_daemon(book_root)
    mooncode_management_test_create_session(daemon, book_root, session_id)
    let session_lock = mooncode_open_session_lock(book_root, session_id)
    session_lock.lock(Exclusive)
    @async.with_task_group(group => {
      let archive = group.spawn(() => {
        daemon.mooncode_manage_session_response(session_id, {
          "action": "archive",
          "book_root": book_root,
        })
      })
      @async.sleep(25)
      assert_true(archive.try_wait() is None)
      session_lock.unlock()
      let result = archive.wait()
      assert_true(mooncode_json_bool(result, "archived", default=false))
    })
    session_lock.close()
    assert_false(@fsx.exists(mooncode_session_dir(book_root, session_id)))
    assert_true(
      @fsx.exists(
        mooncode_session_dir_by_safe_id(
          book_root,
          mooncode_safe_session_id(session_id),
          archived=true,
        ),
      ),
    )
  })
}

///|
async test "mooncode lifecycle retries recover interrupted transition markers" {
  @moonclaw_fsx.with_temporary_directory(
    "moonclaw-session-transition-recovery-XXXXXX",
    book_root => {
      let session_id = "session-transition-recovery"
      let daemon = mooncode_control_test_daemon(book_root)
      mooncode_management_test_create_session(daemon, book_root, session_id)
      let session_lock = mooncode_open_session_lock(book_root, session_id)
      session_lock.lock(Exclusive)
      mooncode_write_session_state_locked(book_root, session_id, "archiving")
      session_lock.unlock()
      session_lock.close()
      assert_true(
        mooncode_append_session_journal_once(
          book_root,
          session_id,
          mooncode_journal_event(),
          {
            "id": "recovered-active",
            "command_id": "cmd-1",
            "created_at": "2026-07-15T00:03:00Z",
          },
        ),
      )
      assert_true(
        @fsx.read_file(mooncode_session_state_path(book_root, session_id)).has_suffix(
          "active\n",
        ),
      )
      ignore(
        daemon.mooncode_manage_session_response(session_id, {
          "action": "archive",
          "book_root": book_root,
        }),
      )
      let restore_lock = mooncode_open_session_lock(book_root, session_id)
      restore_lock.lock(Exclusive)
      mooncode_write_session_state_locked(book_root, session_id, "restoring")
      restore_lock.unlock()
      restore_lock.close()
      ignore(
        daemon.mooncode_manage_session_response(session_id, {
          "action": "restore",
          "book_root": book_root,
        }),
      )
      let delete_lock = mooncode_open_session_lock(book_root, session_id)
      delete_lock.lock(Exclusive)
      mooncode_write_session_state_locked(book_root, session_id, "deleting")
      delete_lock.unlock()
      delete_lock.close()
      ignore(
        daemon.mooncode_manage_session_response(session_id, {
          "action": "delete",
          "book_root": book_root,
        }),
      )
      assert_true(
        @fsx.read_file(mooncode_session_state_path(book_root, session_id)).has_suffix(
          "deleted\n",
        ),
      )
    },
  )
}

///|
async test "mooncode lifecycle reader ignores and next writer repairs torn marker suffix" {
  @moonclaw_fsx.with_temporary_directory(
    "moonclaw-session-marker-tail-XXXXXX",
    book_root => {
      let session_id = "session-marker-tail"
      let daemon = mooncode_control_test_daemon(book_root)
      mooncode_management_test_create_session(daemon, book_root, session_id)
      let marker = mooncode_session_state_path(book_root, session_id)
      let marker_file = @fs.open(
        marker,
        mode=ReadWrite,
        append=false,
        create_mode=OpenExisting,
      )
      marker_file.lock(Exclusive)
      let position = marker_file.size()
      marker_file.write_at(b"archiv", position~)
      marker_file.sync()
      marker_file.unlock()
      marker_file.close()
      let session_lock = mooncode_open_session_lock(book_root, session_id)
      session_lock.lock(Shared)
      assert_eq(mooncode_session_state_locked(book_root, session_id), "active")
      session_lock.unlock()
      session_lock.close()
      ignore(
        daemon.mooncode_manage_session_response(session_id, {
          "action": "archive",
          "book_root": book_root,
        }),
      )
      let marker_content = @fsx.read_file(marker)
      assert_false(marker_content.contains("archivarchiving"))
      assert_true(marker_content.has_suffix("archived\n"))
    },
  )
}

///|
async test "mooncode lifecycle reader streams committed history and ignores raw torn bytes" {
  @moonclaw_fsx.with_temporary_directory(
    "moonclaw-session-state-stream-XXXXXX",
    book_root => {
      let marker = mooncode_session_state_path(
        book_root, "session-state-stream",
      )
      @fsx.make_directory(
        @pathx.dirname(marker),
        recursive=true,
        exists_ok=true,
      )
      let file = @fs.open(
        marker,
        mode=ReadWrite,
        append=false,
        create_mode=CreateOrTruncate,
        permission=0o644,
      )
      let mut position = 0L
      for _ in 0..<8192 {
        file.write_at(b"active\n", position~)
        position += 7L
      }
      file.write_at(b"archived\n", position~)
      position += 9L
      file.write_at(Bytes::from_array([0xe2, 0x82]), position~)
      file.sync()
      file.close()
      assert_eq(mooncode_session_stored_state_locked(marker), "archived")
      @fsx.write_to_file(marker, "active\ninvalid\nrestor")
      let invalid_committed_state_rejected = try {
        ignore(mooncode_session_stored_state_locked(marker))
        false
      } catch {
        InvalidJournal(_) => true
        _ => false
      }
      assert_true(invalid_committed_state_rejected)
    },
  )
}

///|
async test "mooncode runtime lifecycle gate blocks archive for active work" {
  @moonclaw_fsx.with_temporary_directory(
    "moonclaw-session-runtime-gate-XXXXXX",
    book_root => {
      let session_id = "session-runtime-gate"
      let daemon = mooncode_control_test_daemon(book_root)
      mooncode_management_test_create_session(daemon, book_root, session_id)
      let lifecycle_gate = mooncode_open_session_lifecycle_gate(
        book_root, session_id,
      )
      lifecycle_gate.lock(Shared)
      @async.with_task_group(group => {
        let archive = group.spawn(() => {
          daemon.mooncode_manage_session_response(session_id, {
            "action": "archive",
            "book_root": book_root,
          })
        })
        @async.sleep(25)
        assert_true(archive.try_wait() is None)
        lifecycle_gate.unlock()
        let result = archive.wait()
        assert_true(mooncode_json_bool(result, "archived", default=false))
      })
      lifecycle_gate.close()
      assert_false(@fsx.exists(mooncode_session_dir(book_root, session_id)))
    },
  )
}

///|
async test "mooncode stable projection lock omits a session moved while waiting" {
  @moonclaw_fsx.with_temporary_directory(
    "moonclaw-session-projection-lock-XXXXXX",
    book_root => {
      let session_id = "session-projection-lock"
      let safe_session_id = mooncode_safe_session_id(session_id)
      let daemon = mooncode_control_test_daemon(book_root)
      mooncode_management_test_create_session(daemon, book_root, session_id)
      let session_lock = mooncode_open_session_lock(book_root, session_id)
      session_lock.lock(Exclusive)
      @async.with_task_group(group => {
        let durable_projection = group.spawn(() => {
          mooncode_durable_session_record_by_safe_id(book_root, safe_session_id)
        })
        let direct_projection = group.spawn(() => {
          daemon.mooncode_session_record(session_id, book_root)
        })
        @async.sleep(25)
        assert_true(durable_projection.try_wait() is None)
        assert_true(direct_projection.try_wait() is None)
        mooncode_write_session_state_locked(book_root, session_id, "archiving")
        mooncode_move_session_record(
          book_root,
          safe_session_id,
          from_archived=false,
        )
        mooncode_write_session_state_locked(book_root, session_id, "archived")
        session_lock.unlock()
        assert_true(durable_projection.wait() is None)
        assert_true(direct_projection.wait() is None)
      })
      session_lock.close()
      assert_false(@fsx.exists(mooncode_session_dir(book_root, session_id)))
      assert_true(
        mooncode_durable_session_listing_record_by_safe_id(
          book_root,
          safe_session_id,
          archived=true,
          include_log_counts=true,
        )
        is Some(_),
      )
    },
  )
}

///|
async test "transaction seeded append state survives ordinary append and persist" {
  @moonclaw_fsx.with_temporary_directory(
    "moonclaw-session-append-state-XXXXXX",
    book_root => {
      let session_id = "session-append-state"
      let daemon = mooncode_control_test_daemon(book_root)
      mooncode_management_test_create_session(daemon, book_root, session_id)
      let binding = daemon.mooncode_binding_for_session(session_id)
      let journal_path = mooncode_session_journal_path(book_root, session_id)
      ignore(
        mooncode_session_journal_transaction(book_root, session_id, fn(_) {
          NoAppend(())
        }),
      )
      let canonical_path = @fs.realpath(journal_path)
      mooncode_journal_append_scan_count_reset(canonical_path)
      assert_true(
        mooncode_append_session_journal_once(
          book_root,
          session_id,
          mooncode_journal_event(),
          {
            "id": "persisted-event",
            "kind": "append-state-test",
            "command_id": "cmd-1",
            "created_at": "2026-07-15T00:01:00Z",
          },
        ),
      )
      assert_eq(mooncode_journal_append_scan_count_get(canonical_path), 0)
      daemon.mooncode_persist_session(binding)
      assert_eq(mooncode_journal_append_scan_count_get(canonical_path), 0)
      let warm_snapshot = @json.parse(
        @fsx.read_file(mooncode_session_snapshot_path(book_root, session_id)),
      )
      assert_eq(
        mooncode_json_string(warm_snapshot, "journal_sequence", default=""),
        "2",
      )
      mooncode_journal_append_cache_clear()
      daemon.mooncode_persist_session(binding)
      assert_eq(mooncode_journal_append_scan_count_get(canonical_path), 1)
      let cold_snapshot = @json.parse(
        @fsx.read_file(mooncode_session_snapshot_path(book_root, session_id)),
      )
      assert_eq(
        mooncode_json_string(cold_snapshot, "journal_sequence", default=""),
        "2",
      )
      daemon.mooncode_persist_session(binding)
      assert_eq(mooncode_journal_append_scan_count_get(canonical_path), 1)
    },
  )
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

///|
async test "mooncode lifecycle markers prevent archived and deleted resurrection" {
  @moonclaw_fsx.with_temporary_directory("moonclaw-session-state-XXXXXX", book_root => {
    let session_id = "session-state"
    let daemon = mooncode_control_test_daemon(book_root)
    mooncode_management_test_create_session(daemon, book_root, session_id)
    let binding = daemon.mooncode_binding_for_session(session_id)
    assert_true(
      @fsx.read_file(mooncode_session_state_path(book_root, session_id)).has_suffix(
        "active\n",
      ),
    )
    ignore(
      daemon.mooncode_manage_session_response(session_id, {
        "action": "archive",
        "book_root": book_root,
      }),
    )
    assert_true(
      @fsx.read_file(mooncode_session_state_path(book_root, session_id)).has_suffix(
        "archived\n",
      ),
    )
    let append_after_archive_rejected = try {
      ignore(
        mooncode_append_session_journal_once(
          book_root,
          session_id,
          mooncode_journal_event(),
          {
            "id": "post-archive",
            "command_id": "cmd-1",
            "created_at": "2026-07-15T00:01:00Z",
          },
        ),
      )
      false
    } catch {
      InvalidJournal(_) => true
      _ => false
    }
    assert_true(append_after_archive_rejected)
    let persist_after_archive_rejected = try {
      daemon.mooncode_persist_session(binding)
      false
    } catch {
      InvalidJournal(_) => true
      _ => false
    }
    assert_true(persist_after_archive_rejected)
    assert_false(@fsx.exists(mooncode_session_dir(book_root, session_id)))
    ignore(
      daemon.mooncode_manage_session_response(session_id, {
        "action": "restore",
        "book_root": book_root,
      }),
    )
    assert_true(
      @fsx.read_file(mooncode_session_state_path(book_root, session_id)).has_suffix(
        "active\n",
      ),
    )
    ignore(
      daemon.mooncode_manage_session_response(session_id, {
        "action": "delete",
        "book_root": book_root,
      }),
    )
    assert_true(
      @fsx.read_file(mooncode_session_state_path(book_root, session_id)).has_suffix(
        "deleted\n",
      ),
    )
    let append_after_delete_rejected = try {
      ignore(
        mooncode_append_session_journal_once(
          book_root,
          session_id,
          mooncode_journal_event(),
          {
            "id": "post-delete",
            "command_id": "cmd-1",
            "created_at": "2026-07-15T00:02:00Z",
          },
        ),
      )
      false
    } catch {
      InvalidJournal(_) => true
      _ => false
    }
    assert_true(append_after_delete_rejected)
    assert_false(@fsx.exists(mooncode_session_dir(book_root, session_id)))
  })
}
