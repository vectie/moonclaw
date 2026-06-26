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
    command_count: 2,
    first_user_prompt: "Build a durable MoonCode tool",
    last_command_id: "cmd-2",
    last_updated: @clock.Timestamp::from_ms(42L),
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
  mooncode_append_jsonl(
    mooncode_commands_path(binding.book_root, binding.session_id),
    { "kind": "mooncode-command", "command_id": "cmd-1" },
  )
  mooncode_append_jsonl(
    mooncode_runtime_receipts_path(binding.book_root, binding.session_id),
    { "kind": mooncode_kind_runtime_receipt(), "command_id": "cmd-1" },
  )
  mooncode_append_jsonl(
    mooncode_events_path(binding.book_root, binding.session_id),
    { "kind": "assistant_delta", "command_id": "cmd-1" },
  )
  let snapshot = @fsx.read_file(session_path)
  assert_true(snapshot.contains("\"owner\":\"moonclaw\""))
  assert_true(snapshot.contains(".moonclaw/mooncode/sessions/session_demo_1"))
  assert_true(
    @fsx.read_file(
      mooncode_commands_path(binding.book_root, binding.session_id),
    ).contains("\"mooncode-command\""),
  )
  assert_true(
    @fsx.read_file(
      mooncode_runtime_receipts_path(binding.book_root, binding.session_id),
    ).contains("\"mooncode.runtime-receipt\""),
  )
  assert_true(
    @fsx.read_file(mooncode_events_path(binding.book_root, binding.session_id)).contains(
      "\"assistant_delta\"",
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
    command_count: 1,
    first_user_prompt: "Resume this MoonCode session",
    last_command_id: "cmd-resume",
    last_updated: @clock.Timestamp::from_ms(77L),
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
  mooncode_append_jsonl(
    mooncode_commands_path(binding.book_root, binding.session_id),
    { "kind": "mooncode-command", "command_id": "cmd-resume" },
  )
  mooncode_append_jsonl(
    mooncode_events_path(binding.book_root, binding.session_id),
    { "kind": "assistant_delta", "command_id": "cmd-resume" },
  )
  mooncode_append_jsonl(
    mooncode_package_results_path(binding.book_root, binding.session_id),
    { "kind": "mooncode-package-result", "command_id": "cmd-resume" },
  )
  mooncode_append_jsonl(
    mooncode_runtime_receipts_path(binding.book_root, binding.session_id),
    { "kind": mooncode_kind_runtime_receipt(), "command_id": "cmd-resume" },
  )
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
    command_count: 1,
    first_user_prompt: "Create an executable tool",
    last_command_id: "cmd-life",
    last_updated: @clock.Timestamp::from_ms(88L),
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
  mooncode_append_jsonl(
    mooncode_commands_path(binding.book_root, binding.session_id),
    {
      "kind": "mooncode-command",
      "command": "prompt",
      "command_id": "cmd-life",
    },
  )
  mooncode_append_jsonl(
    mooncode_runtime_receipts_path(binding.book_root, binding.session_id),
    {
      "kind": mooncode_kind_runtime_receipt(),
      "command_id": "cmd-life",
      "status": "runtime-completed",
    },
  )
  mooncode_append_jsonl(
    mooncode_events_path(binding.book_root, binding.session_id),
    {
      "kind": "tool.write",
      "lane": "diff",
      "command_id": "cmd-life",
      "path": "tools/demo/main.mbt",
    },
  )
  mooncode_append_jsonl(
    mooncode_events_path(binding.book_root, binding.session_id),
    {
      "event": mooncode_event_test_result(),
      "lane": "test",
      "status": "passed",
      "command_id": "cmd-life",
    },
  )
  mooncode_append_jsonl(
    mooncode_events_path(binding.book_root, binding.session_id),
    { "kind": "receipt.accept", "lane": "review", "command_id": "cmd-life" },
  )
  mooncode_append_jsonl(
    mooncode_events_path(binding.book_root, binding.session_id),
    {
      "event": mooncode_event_package_verified(),
      "lane": "artifact",
      "command_id": "cmd-life",
    },
  )
  mooncode_append_jsonl(
    mooncode_package_results_path(binding.book_root, binding.session_id),
    {
      "kind": "mooncode-package-result",
      "event": mooncode_event_package_verified(),
      "command_id": "cmd-life",
    },
  )
  mooncode_append_jsonl(
    mooncode_book_results_path(binding.book_root, binding.session_id),
    {
      "kind": "mooncode-book-result",
      "requires_review": false,
      "event_type": "knowledge_accepted",
      "command_id": "cmd-life",
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
  assert_false(lifecycle.stringify().contains("Moondesk"))
  assert_false(lifecycle.stringify().contains("Rabbita"))
  let listing = mooncode_session_listing_row(record)
  assert_true(mooncode_json_bool(listing, "lifecycle_ready", default=false))
  assert_eq(
    mooncode_json_string(listing, "lifecycle_status", default=""),
    "complete",
  )
}
