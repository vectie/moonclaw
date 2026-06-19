///|
test "mooncode session listing uses live last_updated without sidecar mtime" {
  let listing = mooncode_session_listing_row({
    "kind": "mooncode-session-record",
    "session_id": "session-live",
    "book_root": "/tmp/moonbook",
    "live_binding_ready": true,
    "last_updated": Json::number(77.0, repr="77"),
    "snapshot": { "first_user_prompt": "  first user request\nsecond line" },
    "source": "memory",
  })
  guard listing is { "updated_at_ms": Number(value, repr=Some("77")), .. } else {
    fail("expected exact live updated_at_ms")
  }
  assert_eq(value.to_int64(), 77L)
}

///|
test "mooncode session list format rejects unsupported values before response" {
  assert_true(mooncode_session_list_format_error("") is None)
  assert_true(mooncode_session_list_format_error("json") is None)
  assert_true(mooncode_session_list_format_error("listing") is None)
  guard mooncode_session_list_format_error("yaml") is Some(payload) else {
    fail("expected unsupported format payload")
  }
  assert_eq(
    mooncode_json_string(payload, "error", default=""),
    "unsupported MoonCode session list format",
  )
  assert_eq(mooncode_json_string(payload, "format", default=""), "yaml")
  guard payload is { "allowed_formats": Array(formats), .. } else {
    fail("expected allowed_formats array")
  }
  assert_eq(formats.length(), 2)
}

///|
test "mooncode compact session listing row is minimal json contract" {
  let listing = mooncode_compact_session_listing_row({
    "kind": "mooncode-session-record",
    "session_id": "session-live",
    "book_root": "/tmp/moonbook",
    "live_binding_ready": true,
    "last_updated": Json::number(77.0, repr="77"),
    "snapshot": {
      "first_user_prompt": "  first user request\nsecond line",
      "last_text": "  build a tool\nthen run tests",
      "last_command_id": "cmd-1",
    },
  })
  assert_eq(mooncode_json_string(listing, "id", default=""), "session-live")
  assert_eq(
    mooncode_json_string(listing, "title", default=""),
    "first user request",
  )
  guard listing
    is {
      "updated_at_ms": Number(value, repr=Some("77")),
      "workspace_root"? : None,
      "session_url"? : None,
      ..
    } else {
    fail("expected minimal MoonCode compact listing row")
  }
  assert_eq(value.to_int64(), 77L)
}

///|
test "mooncode compact session listing title has no rich fallback" {
  let listing = mooncode_compact_session_listing_row({
    "kind": "mooncode-session-record",
    "session_id": "session-no-prompt",
    "last_updated": Json::number(77.0, repr="77"),
    "snapshot": {
      "last_text": "fallback text should stay out of json mode",
      "last_command_id": "cmd-fallback",
    },
  })
  assert_eq(mooncode_json_string(listing, "title", default="missing"), "")
}

///|
test "mooncode compact session listing title is untruncated first line" {
  let long_line = "x".repeat(128)
  let listing = mooncode_compact_session_listing_row({
    "kind": "mooncode-session-record",
    "session_id": "session-long-title",
    "last_updated": Json::number(77.0, repr="77"),
    "snapshot": {
      "first_user_prompt": long_line + "\nsecond line",
      "last_text": "fallback",
    },
  })
  let title = mooncode_json_string(listing, "title", default="")
  assert_eq(title.char_length(), 128)
  assert_eq(title, long_line)
}

///|
test "mooncode compact session listing title trims the first line" {
  let listing = mooncode_compact_session_listing_row({
    "kind": "mooncode-session-record",
    "session_id": "session-spaced-title",
    "last_updated": Json::number(77.0, repr="77"),
    "snapshot": {
      "first_user_prompt": "  first user request  \nsecond line",
      "last_text": "fallback",
    },
  })
  assert_eq(
    mooncode_json_string(listing, "title", default=""),
    "first user request",
  )
}

///|
async test "mooncode binding remembers first prompt once for session picker title" {
  let binding = MoonCodeSessionBinding::{
    session_id: "session-title",
    task_id: @uuid.nil,
    book_root: "/tmp/moonbook",
    command_count: 0,
    first_user_prompt: "",
    last_command_id: "",
    last_updated: @clock.Timestamp::from_ms(1L),
    persisted_task_event_count: 0,
    events: @broadcast.Broadcast::new(),
  }
  binding.remember_first_user_prompt({
    "command": "prompt",
    "text": "  first user request\nwith context",
  })
  binding.remember_first_user_prompt({
    "command": "prompt",
    "text": "second request should not rename session",
  })
  let listing = mooncode_compact_session_listing_row(
    mooncode_session_record_from_parts(
      "session-title",
      "/tmp/moonbook",
      Some(binding),
      Some(mooncode_session_snapshot(binding)),
      source="memory",
    ),
  )
  assert_eq(
    mooncode_json_string(listing, "title", default=""),
    "first user request",
  )
}

///|
test "mooncode session listing rows sort newest first with undated rows last" {
  let rows : Array[Json] = [
    {
      "id": "older",
      "title": "Older",
      "updated_at_ms": Json::number(10.0, repr="10"),
    },
    { "id": "missing", "title": "Missing", "updated_at_ms": null },
    {
      "id": "newer",
      "title": "Newer",
      "updated_at_ms": Json::number(20.0, repr="20"),
    },
  ]
  rows.sort_by(mooncode_compare_session_listing_rows)
  assert_eq(mooncode_json_string(rows[0], "id", default=""), "newer")
  assert_eq(mooncode_json_string(rows[1], "id", default=""), "older")
  assert_eq(mooncode_json_string(rows[2], "id", default=""), "missing")
}
