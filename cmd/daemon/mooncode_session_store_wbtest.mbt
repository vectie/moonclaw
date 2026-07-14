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
    book_root,
    workspace_id: "book-code-lab",
    workspace_name: "Code Lab",
    command_count: 2,
    first_user_prompt: "Build a durable MoonCode tool",
    last_command_id: "cmd-2",
    last_updated: @clock.Timestamp::from_ms(42L),
    runtime_service_running: false,
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
  mooncode_append_session_journal(
    binding.book_root,
    binding.session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "command_id": "cmd-1",
      "created_at": "2026-07-15T00:00:00Z",
    },
  )
  mooncode_append_session_journal(
    binding.book_root,
    binding.session_id,
    mooncode_journal_runtime_receipt(),
    {
      "kind": mooncode_kind_runtime_receipt(),
      "command_id": "cmd-1",
      "completed_at": "2026-07-15T00:00:01Z",
    },
  )
  mooncode_append_session_journal(
    binding.book_root,
    binding.session_id,
    mooncode_journal_event(),
    {
      "kind": "assistant_delta",
      "command_id": "cmd-1",
      "created_at": "2026-07-15T00:00:02Z",
    },
  )
  let snapshot = @fsx.read_file(session_path)
  assert_true(snapshot.contains("\"owner\":\"moonclaw\""))
  assert_true(
    snapshot.contains(
      ".moonsuite/products/moonclaw/mooncode/sessions/session_demo_1",
    ),
  )
  assert_true(
    @fsx.read_file(
      mooncode_session_journal_path(binding.book_root, binding.session_id),
    ).contains("\"mooncode-command\""),
  )
  assert_true(
    @fsx.read_file(
      mooncode_session_journal_path(binding.book_root, binding.session_id),
    ).contains("\"mooncode.runtime-receipt\""),
  )
  assert_true(
    @fsx.read_file(
      mooncode_session_journal_path(binding.book_root, binding.session_id),
    ).contains("\"assistant_delta\""),
  )
}

///|
test "mooncode durable sessions derive product home from workspace roots" {
  let suite_root = @pathx.join(@os.tmpdir(), "moonclaw-mooncode-suite")
  let book_root = suite_root |> @pathx.join("books/research")
  let standalone_root = @pathx.join(@os.tmpdir(), "moonclaw-standalone-book")
  assert_eq(
    mooncode_sessions_root(standalone_root),
    standalone_root
    |> @pathx.join(".moonsuite/products/moonclaw/mooncode/sessions"),
  )
  assert_eq(
    mooncode_sessions_root(book_root),
    suite_root |> @pathx.join(".moonsuite/products/moonclaw/mooncode/sessions"),
  )
  assert_eq(
    mooncode_session_snapshot_path(book_root, "session/demo:1"),
    suite_root
    |> @pathx.join(
      ".moonsuite/products/moonclaw/mooncode/sessions/session_demo_1/session.json",
    ),
  )
}

///|
async test "mooncode durable sidecars list and show without live binding" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-sidecar-list-XXXXXX"),
  )
  let binding = MoonCodeSessionBinding::{
    session_id: "session/resume:1",
    book_root,
    workspace_id: "book-code-lab",
    workspace_name: "Code Lab",
    command_count: 1,
    first_user_prompt: "Resume this MoonCode session",
    last_command_id: "cmd-resume",
    last_updated: @clock.Timestamp::from_ms(77L),
    runtime_service_running: false,
    events: @broadcast.Broadcast::new(),
  }
  @fsx.make_directory(
    mooncode_session_dir(binding.book_root, binding.session_id),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    mooncode_session_snapshot_path(binding.book_root, binding.session_id),
    mooncode_session_snapshot(binding).stringify(),
  )
  mooncode_append_session_journal(
    binding.book_root,
    binding.session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "command_id": "cmd-resume",
      "created_at": "2026-07-15T00:01:00Z",
    },
  )
  mooncode_append_session_journal(
    binding.book_root,
    binding.session_id,
    mooncode_journal_event(),
    {
      "kind": "assistant_delta",
      "command_id": "cmd-resume",
      "created_at": "2026-07-15T00:01:01Z",
    },
  )
  mooncode_append_session_journal(
    binding.book_root,
    binding.session_id,
    mooncode_journal_package_result(),
    {
      "kind": "mooncode-package-result",
      "command_id": "cmd-resume",
      "created_at": "2026-07-15T00:01:02Z",
    },
  )
  mooncode_append_session_journal(
    binding.book_root,
    binding.session_id,
    mooncode_journal_runtime_receipt(),
    {
      "kind": mooncode_kind_runtime_receipt(),
      "command_id": "cmd-resume",
      "completed_at": "2026-07-15T00:01:03Z",
    },
  )
  let listing_records = mooncode_durable_session_listing_records(book_root)
  assert_eq(listing_records.length(), 1)
  let listing_record = listing_records[0]
  assert_eq(
    mooncode_json_string(listing_record, "kind", default=""),
    "mooncode-session-listing-record",
  )
  assert_eq(
    mooncode_json_int(listing_record, "command_log_count", default=0),
    1,
  )
  assert_eq(
    mooncode_json_int(listing_record, "runtime_receipt_log_count", default=0),
    1,
  )
  assert_eq(mooncode_json_int(listing_record, "event_log_count", default=0), 1)
  assert_eq(
    mooncode_json_int(listing_record, "package_result_log_count", default=0),
    1,
  )
  let compact_records = mooncode_durable_session_listing_records(
    book_root,
    include_log_counts=false,
  )
  assert_eq(compact_records.length(), 1)
  assert_eq(
    mooncode_json_int(compact_records[0], "command_log_count", default=0),
    1,
  )
  assert_eq(
    mooncode_json_int(compact_records[0], "event_log_count", default=-1),
    0,
  )
  assert_eq(
    mooncode_json_int(
      compact_records[0],
      "runtime_receipt_log_count",
      default=-1,
    ),
    0,
  )
  assert_false(listing_record.stringify().contains("mooncode_conversation"))
  assert_false(listing_record.stringify().contains("executable_book_lifecycle"))
  let lightweight_listing = mooncode_session_listing_row(listing_record)
  assert_eq(
    mooncode_json_string(lightweight_listing, "title", default=""),
    "Resume this MoonCode session",
  )
  assert_eq(mooncode_json_int(lightweight_listing, "event_count", default=0), 1)
  let records = mooncode_durable_session_records(book_root)
  assert_eq(records.length(), 1)
  let record = records[0]
  assert_eq(
    mooncode_json_string(record, "kind", default=""),
    "mooncode-session-record",
  )
  assert_eq(
    mooncode_json_string(record, "session_id", default=""),
    "session/resume:1",
  )
  assert_eq(mooncode_json_string(record, "resume_state", default=""), "durable")
  let text = record.stringify()
  assert_true(text.contains("\"command_log_count\":1"))
  assert_true(text.contains("\"runtime_receipt_log_count\":1"))
  assert_true(text.contains("\"event_log_count\":1"))
  assert_true(text.contains("\"package_result_log_count\":1"))
  assert_true(text.contains("\"live_binding_ready\":false"))
  let lifecycle = mooncode_json_object_field_or_empty(
    record, "executable_book_lifecycle",
  )
  assert_eq(
    mooncode_json_string(lifecycle, "kind", default=""),
    "mooncode-executable-book-lifecycle-report",
  )
  assert_eq(
    mooncode_json_string(lifecycle, "contract_id", default=""),
    mooncode_executable_book_lifecycle_contract_id(),
  )
  assert_false(mooncode_json_bool(lifecycle, "ready", default=true))
  assert_eq(
    mooncode_json_string(lifecycle, "first_blocker_id", default=""),
    "edit_code",
  )
  let listing = mooncode_session_listing_row(record)
  assert_eq(mooncode_json_string(listing, "id", default=""), "session/resume:1")
  assert_eq(mooncode_json_string(listing, "status", default=""), "durable")
  guard listing is { "updated_at_ms": Number(stamp, ..), .. } else {
    fail("expected durable listing updated_at_ms")
  }
  assert_true(stamp > 0.0)
  assert_eq(
    mooncode_json_string(listing, "workspace_root", default=""),
    book_root,
  )
  assert_eq(
    mooncode_json_string(listing, "last_command_id", default=""),
    "cmd-resume",
  )
  assert_eq(mooncode_json_int(listing, "command_count", default=0), 1)
  assert_eq(mooncode_json_int(listing, "event_count", default=0), 1)
  assert_eq(mooncode_json_int(listing, "package_result_count", default=0), 1)
  assert_eq(
    mooncode_json_string(listing, "lifecycle_status", default=""),
    "blocked",
  )
  assert_eq(
    mooncode_json_string(listing, "lifecycle_first_blocker_id", default=""),
    "edit_code",
  )
  assert_true(
    mooncode_json_string(listing, "stream_url", default="").contains(
      "format=jsonl",
    ),
  )
}

///|
async test "mooncode durable session record exposes canonical conversation" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-conversation-XXXXXX"),
  )
  let session_id = "session/conversation:1"
  @fsx.make_directory(
    mooncode_session_dir(book_root, session_id),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    mooncode_session_snapshot_path(book_root, session_id),
    (
      {
        "kind": "mooncode-session-snapshot",
        "protocol": mooncode_protocol_version(),
        "owner": "moonclaw",
        "session_id": session_id,
        "book_root": book_root,
      } : Json).stringify(),
  )
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": "cmd-chat-1",
      "created_at": "2026-07-07T00:00:00Z",
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "book_root": book_root,
        "command": "prompt",
        "packet": {
          "command_id": "cmd-chat-1",
          "client_turn_id": "client-chat-1",
          "message": "hey",
        },
      },
    },
  )
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_event(),
    {
      "id": "reasoning-1",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": "cmd-chat-1",
      "lane": "runtime",
      "kind": "reasoning_delta",
      "event": "reasoning_delta",
      "status": "running",
      "detail": "Planner step selected a finish tool call.",
      "created_at": "2026-07-07T00:00:01Z",
    },
  )
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_event(),
    {
      "id": "finish-call-1",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": "cmd-chat-1",
      "lane": "review",
      "kind": mooncode_event_tool_call(),
      "event": mooncode_event_tool_call(),
      "tool": "finish",
      "status": "running",
      "detail": "{ \"answer\": \"wrong source\" }",
      "created_at": "2026-07-07T00:00:02Z",
    },
  )
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_event(),
    {
      "id": "finish-1",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": "cmd-chat-1",
      "lane": "review",
      "kind": "finish",
      "event": "finish",
      "tool": "finish",
      "status": "done",
      "detail": "finished",
      "tool_result": {
        "tool": "finish",
        "ok": true,
        "output": "hello reply",
        "metadata": { "answer": "hello reply" },
      },
      "created_at": "2026-07-07T00:00:03Z",
    },
  )
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_runtime_receipt(),
    {
      "kind": mooncode_kind_runtime_receipt(),
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command_id": "cmd-chat-1",
      "status": "runtime-completed",
      "completed_at": "2026-07-07T00:00:04Z",
      "execution": {
        "tool_results": [
          {
            "tool": "finish",
            "ok": true,
            "output": "hello reply",
            "metadata": { "answer": "hello reply" },
          },
        ],
      },
    },
  )
  let records = mooncode_durable_session_records(book_root)
  assert_eq(records.length(), 1)
  let conversation = mooncode_json_object_field_or_empty(
    records[0],
    "mooncode_conversation",
  )
  assert_eq(
    mooncode_json_string(conversation, "kind", default=""),
    @mooncode_core.conversation_kind(),
  )
  assert_eq(
    mooncode_json_string(conversation, "contract_id", default=""),
    "moonsuite-conversation.v2",
  )
  assert_eq(mooncode_json_int(conversation, "revision", default=0), 5)
  assert_eq(mooncode_json_int(conversation, "last_sequence", default=0), 5)
  assert_eq(mooncode_json_int(conversation, "turn_count", default=0), 1)
  let turns = mooncode_json_array_items(conversation, "turns")
  assert_eq(turns.length(), 1)
  let turn = turns[0]
  assert_eq(mooncode_json_string(turn, "command_id", default=""), "cmd-chat-1")
  assert_eq(
    mooncode_json_string(turn, "client_turn_id", default=""),
    "client-chat-1",
  )
  assert_eq(mooncode_json_string(turn, "status", default=""), "done")
  assert_eq(mooncode_json_int(turn, "ordinal", default=-1), 0)
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(turn, "user"),
      "content",
      default="",
    ),
    "hey",
  )
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(turn, "assistant"),
      "content",
      default="",
    ),
    "hello reply",
  )
  assert_eq(mooncode_json_array_items(turn, "progress").length(), 0)
  let work = mooncode_json_object_field_or_empty(turn, "work")
  assert_eq(
    mooncode_json_string(work, "item_id", default=""),
    "turn:cmd-chat-1:work",
  )
  assert_eq(mooncode_json_string(work, "status", default=""), "done")
  assert_eq(mooncode_json_array_items(work, "steps").length(), 1)
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(turn, "user"),
      "item_id",
      default="",
    ),
    "turn:cmd-chat-1:user",
  )
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(turn, "assistant"),
      "item_id",
      default="",
    ),
    "turn:cmd-chat-1:assistant",
  )
}

///|
async test "mooncode durable lifecycle completes from book-local evidence" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-lifecycle-XXXXXX"),
  )
  let binding = MoonCodeSessionBinding::{
    session_id: "session/lifecycle:1",
    book_root,
    workspace_id: "book-code-lab",
    workspace_name: "Code Lab",
    command_count: 1,
    first_user_prompt: "Create an executable tool",
    last_command_id: "cmd-life",
    last_updated: @clock.Timestamp::from_ms(88L),
    runtime_service_running: false,
    events: @broadcast.Broadcast::new(),
  }
  @fsx.make_directory(
    mooncode_session_dir(binding.book_root, binding.session_id),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    mooncode_session_snapshot_path(binding.book_root, binding.session_id),
    mooncode_session_snapshot(binding).stringify(),
  )
  mooncode_append_session_journal(
    binding.book_root,
    binding.session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "command": "prompt",
      "command_id": "cmd-life",
      "created_at": "2026-07-15T00:02:00Z",
    },
  )
  mooncode_append_session_journal(
    binding.book_root,
    binding.session_id,
    mooncode_journal_runtime_receipt(),
    {
      "kind": mooncode_kind_runtime_receipt(),
      "command_id": "cmd-life",
      "status": "runtime-completed",
      "completed_at": "2026-07-15T00:02:01Z",
    },
  )
  mooncode_append_session_journal(
    binding.book_root,
    binding.session_id,
    mooncode_journal_event(),
    {
      "kind": "tool.write",
      "lane": "diff",
      "command_id": "cmd-life",
      "path": "tools/demo/main.mbt",
      "created_at": "2026-07-15T00:02:02Z",
    },
  )
  mooncode_append_session_journal(
    binding.book_root,
    binding.session_id,
    mooncode_journal_event(),
    {
      "event": mooncode_event_test_result(),
      "lane": "test",
      "status": "passed",
      "command_id": "cmd-life",
      "created_at": "2026-07-15T00:02:03Z",
    },
  )
  mooncode_append_session_journal(
    binding.book_root,
    binding.session_id,
    mooncode_journal_event(),
    {
      "kind": "receipt.accept",
      "lane": "review",
      "command_id": "cmd-life",
      "created_at": "2026-07-15T00:02:04Z",
    },
  )
  mooncode_append_session_journal(
    binding.book_root,
    binding.session_id,
    mooncode_journal_event(),
    {
      "event": mooncode_event_package_verified(),
      "lane": "artifact",
      "command_id": "cmd-life",
      "created_at": "2026-07-15T00:02:05Z",
    },
  )
  mooncode_append_session_journal(
    binding.book_root,
    binding.session_id,
    mooncode_journal_package_result(),
    {
      "kind": "mooncode-package-result",
      "event": mooncode_event_package_verified(),
      "command_id": "cmd-life",
      "created_at": "2026-07-15T00:02:06Z",
    },
  )
  mooncode_append_session_journal(
    binding.book_root,
    binding.session_id,
    mooncode_journal_book_result(),
    {
      "kind": "mooncode-book-result",
      "requires_review": false,
      "event_type": "knowledge_accepted",
      "command_id": "cmd-life",
      "created_at": "2026-07-15T00:02:07Z",
    },
  )
  let record = mooncode_session_record_from_parts(
    binding.session_id,
    binding.book_root,
    None,
    Some(mooncode_load_session_snapshot(binding.book_root, binding.session_id)),
    source="sidecar",
  )
  let lifecycle = mooncode_json_object_field_or_empty(
    record, "executable_book_lifecycle",
  )
  assert_true(mooncode_json_bool(lifecycle, "ready", default=false))
  assert_eq(mooncode_json_string(lifecycle, "status", default=""), "complete")
  assert_eq(
    mooncode_json_int(lifecycle, "completed_step_count", default=0),
    mooncode_executable_book_lifecycle_steps().length(),
  )
  assert_eq(
    mooncode_json_string(lifecycle, "first_blocker_id", default="x"),
    "",
  )
  assert_false(lifecycle.stringify().contains("MoonDesk"))
  assert_false(lifecycle.stringify().contains("Rabbita"))
  let listing = mooncode_session_listing_row(record)
  assert_true(mooncode_json_bool(listing, "lifecycle_ready", default=false))
  assert_eq(
    mooncode_json_string(listing, "lifecycle_status", default=""),
    "complete",
  )
}

///|
async test "mooncode journal preserves one thousand contiguous records" (
  t : @test.Test,
) {
  ignore(t)
  let root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-journal-volume-XXXXXX"),
  )
  let session_id = "session-volume"
  for index in 0..<1000 {
    mooncode_append_session_journal(
      root,
      session_id,
      mooncode_journal_event(),
      {
        "id": "event-\{index}",
        "command_id": "command-volume",
        "created_at": "timestamp-\{index}",
        "index": index,
      },
    ) catch {
      error => fail("append failed at record \{index}: \{error}")
    }
  }
  let records = mooncode_read_session_journal(root, session_id)
  assert_eq(records.length(), 1000)
  for index, record in records {
    assert_eq(mooncode_json_int(record, "sequence", default=0), index + 1)
  }
  let events = mooncode_journal_entries(records, mooncode_journal_event())
  assert_eq(mooncode_json_int(events[0], "index", default=-1), 0)
  assert_eq(mooncode_json_int(events[999], "index", default=-1), 999)
  assert_true(
    @fsx.read_file(mooncode_session_journal_path(root, session_id)).has_suffix(
      "\n",
    ),
  )
}

///|
async test "mooncode journal serializes concurrent cross-lane writers" (
  t : @test.Test,
) {
  ignore(t)
  let root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-journal-concurrent-XXXXXX"),
  )
  let session_id = "session-concurrent"
  @async.with_task_group(group => {
    let tasks = []
    for index in 0..<64 {
      let record_kind = if index % 3 == 0 {
        mooncode_journal_command()
      } else if index % 3 == 1 {
        mooncode_journal_event()
      } else {
        mooncode_journal_package_result()
      }
      tasks.push(
        group.spawn(() => {
          mooncode_append_session_journal(root, session_id, record_kind, {
            "id": "record-\{index}",
            "command_id": "command-\{index}",
            "created_at": "timestamp-\{index}",
            "index": index,
          })
        }),
      )
    }
    for task in tasks {
      task.wait()
    }
  })
  let records = mooncode_read_session_journal(root, session_id)
  assert_eq(records.length(), 64)
  let seen = Array::make(64, false)
  for sequence, record in records {
    assert_eq(mooncode_json_int(record, "sequence", default=0), sequence + 1)
    let payload = mooncode_json_object_field_or_empty(record, "payload")
    let index = mooncode_json_int(payload, "index", default=-1)
    assert_true(index >= 0 && index < seen.length())
    assert_false(seen[index])
    seen[index] = true
  }
  for present in seen {
    assert_true(present)
  }
}

///|
async test "mooncode journal repairs only a torn final record" (t : @test.Test) {
  ignore(t)
  let root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-journal-torn-XXXXXX"),
  )
  let session_id = "session-torn"
  mooncode_append_session_journal(root, session_id, mooncode_journal_event(), {
    "id": "event-1",
    "command_id": "command-torn",
    "created_at": "timestamp-1",
    "index": 1,
  })
  let path = mooncode_session_journal_path(root, session_id)
  let valid_prefix = @fsx.read_file(path)
  @fsx.write_to_file(path, valid_prefix + "{\"kind\":")
  mooncode_append_session_journal(root, session_id, mooncode_journal_event(), {
    "id": "event-2",
    "command_id": "command-torn",
    "created_at": "timestamp-2",
    "index": 2,
  })
  let records = mooncode_read_session_journal(root, session_id)
  assert_eq(records.length(), 2)
  assert_eq(mooncode_json_int(records[0], "sequence", default=0), 1)
  assert_eq(mooncode_json_int(records[1], "sequence", default=0), 2)
  assert_true(@fsx.read_file(path).has_suffix("\n"))
}

///|
async test "mooncode journal makes duplicate delivery idempotent" (
  t : @test.Test,
) {
  ignore(t)
  let root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-journal-dedup-XXXXXX"),
  )
  let session_id = "session-dedup"
  let first : Json = {
    "id": "event-stable",
    "command_id": "command-dedup",
    "created_at": "2026-07-15T00:03:00Z",
    "detail": "one delivery",
  }
  mooncode_append_session_journal(
    root,
    session_id,
    mooncode_journal_event(),
    first,
  )
  mooncode_append_session_journal(
    root,
    session_id,
    mooncode_journal_event(),
    first,
  )
  mooncode_append_session_journal(root, session_id, mooncode_journal_event(), {
    "id": "event-next",
    "command_id": "command-dedup",
    "created_at": "2026-07-15T00:03:01Z",
  })
  let records = mooncode_read_session_journal(root, session_id)
  assert_eq(records.length(), 2)
  assert_eq(mooncode_json_int(records[0], "sequence", default=0), 1)
  assert_eq(mooncode_json_int(records[1], "sequence", default=0), 2)
}

///|
async test "mooncode journal rejects complete corruption and sequence gaps" (
  t : @test.Test,
) {
  ignore(t)
  let root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-journal-invalid-XXXXXX"),
  )
  let corrupt_session = "session-corrupt-line"
  mooncode_append_session_journal(
    root,
    corrupt_session,
    mooncode_journal_event(),
    {
      "id": "event-valid",
      "command_id": "command-invalid",
      "created_at": "2026-07-15T00:04:00Z",
    },
  )
  let corrupt_path = mooncode_session_journal_path(root, corrupt_session)
  let valid_prefix = @fsx.read_file(corrupt_path)
  @fsx.write_to_file(
    corrupt_path,
    valid_prefix + "{\"kind\":\"not-a-journal-record\"}\n",
  )
  let rejected_corruption = try {
    ignore(mooncode_read_session_journal(root, corrupt_session))
    false
  } catch {
    InvalidJournal(_) => true
    _ => false
  }
  assert_true(rejected_corruption)
  let gap_session = "session-sequence-gap"
  mooncode_append_session_journal(root, gap_session, mooncode_journal_event(), {
    "id": "event-before-gap",
    "command_id": "command-gap",
    "created_at": "2026-07-15T00:05:00Z",
  })
  let gap_path = mooncode_session_journal_path(root, gap_session)
  let gap_record = @moonlib_conversation.journal_record(
    session_id=gap_session,
    sequence=3,
    record_id="event:event-after-gap",
    record_kind=mooncode_journal_event(),
    command_id="command-gap",
    client_turn_id="",
    recorded_at="2026-07-15T00:05:01Z",
    payload={
      "id": "event-after-gap",
      "command_id": "command-gap",
      "created_at": "2026-07-15T00:05:01Z",
    },
  )
  @fsx.write_to_file(
    gap_path,
    @fsx.read_file(gap_path) + gap_record.stringify() + "\n",
  )
  let rejected_gap = try {
    ignore(mooncode_read_session_journal(root, gap_session))
    false
  } catch {
    InvalidJournal(_) => true
    _ => false
  }
  assert_true(rejected_gap)
}

///|
async test "mooncode journal rebuilds conversation after snapshot corruption" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-journal-recovery-XXXXXX"),
  )
  let session_id = "session/recovery"
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "session_id": session_id,
      "command_id": "command-recovery",
      "created_at": "2026-07-15T00:06:00Z",
      "command": {
        "session_id": session_id,
        "book_root": book_root,
        "command": "prompt",
        "packet": {
          "command_id": "command-recovery",
          "client_turn_id": "client-recovery",
          "message": "recover this turn",
        },
      },
    },
  )
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_runtime_receipt(),
    {
      "kind": mooncode_kind_runtime_receipt(),
      "session_id": session_id,
      "command_id": "command-recovery",
      "status": "runtime-completed",
      "completed_at": "2026-07-15T00:06:01Z",
      "execution": {
        "tool_results": [
          {
            "tool": "finish",
            "ok": true,
            "output": "recovered reply",
            "metadata": { "answer": "recovered reply" },
          },
        ],
      },
    },
  )
  @fsx.write_to_file(
    mooncode_session_snapshot_path(book_root, session_id),
    "{\"kind\":",
  )
  let record = mooncode_session_record_from_parts(
    session_id,
    book_root,
    None,
    Some(mooncode_load_session_snapshot(book_root, session_id)),
    source="recovery-test",
  )
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(record, "snapshot"),
      "load_status",
      default="",
    ),
    "invalid-json",
  )
  let conversation = mooncode_json_object_field_or_empty(
    record, "mooncode_conversation",
  )
  assert_eq(mooncode_json_int(conversation, "revision", default=0), 2)
  assert_eq(mooncode_json_int(conversation, "last_sequence", default=0), 2)
  let turn = mooncode_json_array_items(conversation, "turns")[0]
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(turn, "assistant"),
      "content",
      default="",
    ),
    "recovered reply",
  )
}

///|
async test "mooncode canonical conversation replay is deterministic" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-replay-XXXXXX"),
  )
  let session_id = "session/replay:1"
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_command(),
    {
      "kind": "mooncode-command",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": "cmd-replay-1",
      "created_at": "2026-07-10T00:00:00Z",
      "command": {
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "book_root": book_root,
        "command": "prompt",
        "packet": {
          "command_id": "cmd-replay-1",
          "client_turn_id": "client-replay-1",
          "message": "verify deterministic replay",
        },
      },
    },
  )
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_event(),
    {
      "id": "reasoning-replay-1",
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "command_id": "cmd-replay-1",
      "lane": "runtime",
      "kind": "reasoning_delta",
      "event": "reasoning_delta",
      "status": "running",
      "detail": "Inspecting the requested behavior.",
      "created_at": "2026-07-10T00:00:01Z",
    },
  )
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_runtime_receipt(),
    {
      "kind": mooncode_kind_runtime_receipt(),
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command_id": "cmd-replay-1",
      "status": "runtime-completed",
      "completed_at": "2026-07-10T00:00:02Z",
      "execution": {
        "tool_results": [
          {
            "tool": "finish",
            "ok": true,
            "output": "deterministic reply",
            "metadata": { "answer": "deterministic reply" },
          },
        ],
      },
    },
  )
  let first = mooncode_session_record_from_parts(
    session_id,
    book_root,
    None,
    None,
    source="sidecar",
  )
  let baseline = mooncode_json_object_field_or_empty(
    first, "mooncode_conversation",
  ).stringify()
  assert_eq(
    mooncode_json_int(
      mooncode_json_object_field_or_empty(first, "mooncode_conversation"),
      "revision",
      default=0,
    ),
    3,
  )
  for _ in 0..<100 {
    let replay = mooncode_session_record_from_parts(
      session_id,
      book_root,
      None,
      None,
      source="sidecar",
    )
    assert_eq(
      mooncode_json_object_field_or_empty(replay, "mooncode_conversation").stringify(),
      baseline,
    )
  }
}

///|
test "mooncode session binding keeps its first MoonBook root" {
  let binding = MoonCodeSessionBinding::{
    session_id: "session/root-lock",
    book_root: "",
    workspace_id: "",
    workspace_name: "",
    command_count: 0,
    first_user_prompt: "",
    last_command_id: "",
    last_updated: @clock.Timestamp::from_ms(1L),
    runtime_service_running: false,
    events: @broadcast.Broadcast::new(),
  }
  assert_true(binding.bind_book_root("/tmp/moonsuite/books/code-lab"))
  assert_true(binding.bind_book_root("/tmp/moonsuite/books/code-lab"))
  assert_false(binding.bind_book_root("/tmp/moonsuite"))
  assert_eq(binding.book_root, "/tmp/moonsuite/books/code-lab")
}

///|
test "canonical conversation hides control commands and explains failed work" {
  let prompt : Json = {
    "command_id": "cmd-prompt",
    "created_at": "2026-07-10T00:00:00Z",
    "command": {
      "command": "prompt",
      "text": "Read the project",
      "packet": {
        "command_id": "cmd-prompt",
        "client_turn_id": "client-prompt",
        "workspace_id": "code-lab",
        "workspace_name": "Code Lab",
      },
    },
  }
  let steer : Json = {
    "command_id": "cmd-steer",
    "created_at": "2026-07-10T00:00:01Z",
    "command": {
      "command": "steer",
      "text": "Use the README",
      "packet": { "command_id": "cmd-steer" },
    },
  }
  let failed : Json = {
    "id": "event-failed",
    "command_id": "cmd-prompt",
    "kind": "runtime.turn_finished",
    "status": "failed",
    "created_at": "2026-07-10T00:00:02Z",
  }
  let conversation = mooncode_session_conversation(
    { "session_id": "session-failed", "book_root": "/tmp/book" },
    [prompt, steer],
    [],
    [failed],
    journal_sequence=3,
  )
  assert_eq(mooncode_json_int(conversation, "turn_count", default=0), 1)
  assert_eq(
    mooncode_json_string(conversation, "workspace_id", default=""),
    "code-lab",
  )
  assert_eq(
    mooncode_json_string(conversation, "workspace_name", default=""),
    "Code Lab",
  )
  let turns = mooncode_json_array_items(conversation, "turns")
  assert_eq(
    mooncode_json_string(turns[0], "command_id", default=""),
    "cmd-prompt",
  )
  let assistant = mooncode_json_object_field_or_empty(turns[0], "assistant")
  assert_true(
    mooncode_json_string(assistant, "content", default="").contains(
      "could not complete this request",
    ),
  )
  assert_eq(mooncode_json_string(assistant, "status", default=""), "failed")
}

///|
test "canonical queued turn does not claim that runtime work started" {
  let prompt : Json = {
    "command_id": "cmd-queued",
    "created_at": "2026-07-14T00:00:00Z",
    "command": {
      "command": "prompt",
      "text": "Inspect the project",
      "packet": {
        "command_id": "cmd-queued",
        "client_turn_id": "client-queued",
      },
    },
  }
  let conversation = mooncode_session_conversation(
    { "session_id": "session-queued", "book_root": "/tmp/book" },
    [prompt],
    [],
    journal_sequence=1,
    [],
  )
  let turns = mooncode_json_array_items(conversation, "turns")
  assert_eq(turns.length(), 1)
  assert_eq(mooncode_json_string(turns[0], "status", default=""), "queued")
  assert_eq(
    mooncode_json_object_field_or_empty(turns[0], "work").stringify(),
    "{}",
  )
}

///|
test "read tools remain context steps even when runtime lane is diff" {
  let event : Json = {
    "id": "read-failed",
    "command_id": "cmd-read",
    "kind": "tool_result",
    "event": "tool_result",
    "lane": "diff",
    "tool": "read",
    "path": "README.md",
    "status": "failed",
  }
  assert_eq(mooncode_conversation_work_step_kind(event), "context")
  assert_eq(
    mooncode_conversation_progress_title(event),
    "Could not check context",
  )
  assert_eq(
    mooncode_conversation_progress_detail(event),
    "Could not read `README.md`.",
  )
}

///|
test "canonical work keeps review evidence on the matching file step" {
  let command : Json = {
    "command_id": "cmd-evidence",
    "created_at": "2026-07-15T00:00:00Z",
    "command": {
      "command": "prompt",
      "text": "Update two files",
      "packet": {
        "command_id": "cmd-evidence",
        "client_turn_id": "client-evidence",
      },
    },
  }
  let write_a : Json = {
    "id": "write-a-start",
    "command_id": "cmd-evidence",
    "kind": "tool_call",
    "event": "tool_call",
    "lane": "diff",
    "tool": "write",
    "tool_call_id": "write-a",
    "path": "src/a.mbt",
    "status": "running",
  }
  let write_b : Json = {
    "id": "write-b-start",
    "command_id": "cmd-evidence",
    "kind": "tool_call",
    "event": "tool_call",
    "lane": "diff",
    "tool": "write",
    "tool_call_id": "write-b",
    "path": "src/b.mbt",
    "status": "running",
  }
  let result_a : Json = {
    "id": "write-a-result",
    "command_id": "cmd-evidence",
    "kind": "tool_result",
    "event": "tool_result",
    "lane": "diff",
    "tool": "write",
    "path": "src/a.mbt",
    "diff": "--- a/src/a.mbt\n+++ b/src/a.mbt\n-old\n+new\n",
    "status": "done",
    "tool_result": {
      "output": "updated a",
      "metadata": { "path": "src/a.mbt", "status": 0, "truncated": false },
    },
  }
  let conversation = mooncode_session_conversation(
    { "session_id": "session-evidence" },
    [command],
    [],
    [write_a, write_b, result_a],
    journal_sequence=4,
  )
  let turn = mooncode_json_array_items(conversation, "turns")[0]
  let steps = mooncode_json_array_items(
    mooncode_json_object_field_or_empty(turn, "work"),
    "steps",
  )
  assert_eq(steps.length(), 2)
  assert_eq(mooncode_json_string(steps[0], "status", default=""), "done")
  assert_eq(mooncode_json_string(steps[1], "status", default=""), "running")
  let evidence = mooncode_json_object_field_or_empty(steps[0], "evidence")
  assert_eq(mooncode_json_string(evidence, "kind", default=""), "edit")
  assert_eq(mooncode_json_string(evidence, "state", default=""), "applied")
  assert_eq(mooncode_json_string(evidence, "path", default=""), "src/a.mbt")
  assert_true(
    mooncode_json_string(evidence, "diff", default="").contains("+new"),
  )
  assert_eq(mooncode_json_string(evidence, "output", default=""), "updated a")
  assert_eq(mooncode_json_int(evidence, "exit_code", default=-1), 0)
}

///|
test "planner lifecycle projects as one user-facing thought without failure" {
  let command : Json = {
    "command_id": "cmd-plan",
    "created_at": "2026-07-10T00:00:00Z",
    "command": {
      "command": "prompt",
      "text": "Read README.md",
      "packet": { "command_id": "cmd-plan", "client_turn_id": "client-plan" },
    },
  }
  let started : Json = {
    "id": "planner-started",
    "command_id": "cmd-plan",
    "kind": "runtime.planner_started",
    "status": "running",
    "created_at": "2026-07-10T00:00:01Z",
  }
  let fallback : Json = {
    "id": "planner-fallback",
    "command_id": "cmd-plan",
    "kind": "runtime.planner_failed",
    "status": "failed",
    "created_at": "2026-07-10T00:00:02Z",
  }
  let conversation = mooncode_session_conversation(
    { "session_id": "session-plan" },
    [command],
    [],
    [started, fallback],
    journal_sequence=3,
  )
  let turns = mooncode_json_array_items(conversation, "turns")
  assert_eq(turns.length(), 1)
  assert_eq(mooncode_json_string(turns[0], "status", default=""), "running")
  let work = mooncode_json_object_field_or_empty(turns[0], "work")
  let steps = mooncode_json_array_items(work, "steps")
  assert_eq(steps.length(), 1)
  assert_eq(mooncode_json_string(steps[0], "kind", default=""), "thought")
  assert_eq(
    mooncode_json_string(steps[0], "title", default=""),
    "Using a local plan",
  )
  assert_eq(mooncode_json_string(steps[0], "status", default=""), "done")
  assert_eq(mooncode_json_object_field_or_empty(work, "live").stringify(), "{}")
  assert_eq(
    mooncode_json_object_field_or_empty(turns[0], "assistant").stringify(),
    "{}",
  )
}

///|
test "terminal events settle running work steps" {
  let command : Json = {
    "command_id": "cmd-settle",
    "created_at": "2026-07-10T00:00:00Z",
    "command": {
      "command": "prompt",
      "text": "Read README.md",
      "packet": { "command_id": "cmd-settle" },
    },
  }
  let started : Json = {
    "id": "turn-started",
    "command_id": "cmd-settle",
    "kind": "runtime.turn_started",
    "status": "running",
    "created_at": "2026-07-10T00:00:01Z",
  }
  let finished : Json = {
    "id": "turn-finished",
    "command_id": "cmd-settle",
    "kind": "runtime.turn_finished",
    "status": "done",
    "created_at": "2026-07-10T00:00:02Z",
  }
  let conversation = mooncode_session_conversation(
    { "session_id": "session-settle" },
    [command],
    [],
    [started, finished],
    journal_sequence=3,
  )
  let turn = mooncode_json_array_items(conversation, "turns")[0]
  let steps = mooncode_json_array_items(
    mooncode_json_object_field_or_empty(turn, "work"),
    "steps",
  )
  assert_eq(steps.length(), 1)
  assert_eq(mooncode_json_string(steps[0], "status", default=""), "done")
}
