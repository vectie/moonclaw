///|
fn mooncode_claim_projection_command(
  book_root : String,
  session_id : String,
) -> Json {
  {
    "kind": "mooncode-command",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": "claim-projection-command",
    "created_at": "2026-10-02T00:00:00Z",
    "command": {
      "protocol": mooncode_protocol_version(),
      "session_id": session_id,
      "book_root": book_root,
      "command": "prompt",
      "packet": {
        "command_id": "claim-projection-command",
        "client_turn_id": "claim-projection-client",
        "message": "Keep the durable turn state accurate",
      },
    },
  }
}

///|
async fn mooncode_claim_projection_start(
  book_root : String,
  session_id : String,
) -> Json {
  let command = mooncode_claim_projection_command(book_root, session_id)
  mooncode_append_session_journal(
    book_root,
    session_id,
    mooncode_journal_command(),
    command,
  )
  let state = mooncode_runtime_claim_state_from_logs(
    session_id,
    book_root,
    [command],
    [],
    journal_path=mooncode_session_journal_path(book_root, session_id),
  )
  let receipts = mooncode_runtime_claim_receipts(
    session_id,
    book_root,
    state,
    { "consumer_id": "conversation-receipt-test" },
    now=@clock.Timestamp::from_ms(1_000L),
  )
  assert_eq(receipts.length(), 1)
  assert_eq(
    mooncode_json_string(receipts[0], "status", default=""),
    @mooncode_core.runtime_receipt_status_claimed(),
  )
  receipts[0]
}

///|
async fn mooncode_claim_projection_read(
  book_root : String,
  session_id : String,
) -> Json {
  let journal_path = mooncode_session_journal_path(book_root, session_id)
  let before = @fsx.read_file(journal_path)
  let record = mooncode_session_record_from_parts(
    session_id,
    book_root,
    None,
    None,
    source="claimed-projection-test",
  )
  let conversation = mooncode_json_object_field_or_empty(
    record, "mooncode_conversation",
  )
  // Rebuild from the durable journal without a live binding or a cached projection.
  for _ in 0..<3 {
    let reloaded = mooncode_session_record_from_parts(
      session_id,
      book_root,
      None,
      Some(mooncode_load_session_snapshot(book_root, session_id)),
      source="claimed-projection-reload",
    )
    assert_eq(
      mooncode_json_object_field_or_empty(reloaded, "mooncode_conversation").stringify(),
      conversation.stringify(),
    )
  }
  assert_eq(@fsx.read_file(journal_path), before)
  let turns = mooncode_json_array_items(conversation, "turns")
  assert_eq(turns.length(), 1)
  turns[0]
}

///|
fn mooncode_claim_projection_event(kind : String, status : String) -> Json {
  {
    "id": "claim-projection-" + kind,
    "session_id": "claim-projection-session",
    "command_id": "claim-projection-command",
    "kind": kind,
    "status": status,
    "created_at": "2026-10-02T00:00:02Z",
  }
}

///|
async test "durable claim leaves pending turn queued and preserves running live work" {
  let root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "mooncode-claim-live-XXXXXX"),
  )
  let session = "claim-projection-session"
  let claim = mooncode_claim_projection_start(root, session)
  let pending = mooncode_claim_projection_read(root, session)
  assert_eq(mooncode_json_string(pending, "status", default=""), "queued")
  mooncode_append_session_journal(
    root,
    session,
    mooncode_journal_runtime_receipt(),
    claim,
  )
  let claimed = mooncode_claim_projection_read(root, session)
  assert_eq(mooncode_json_string(claimed, "status", default=""), "queued")
  assert_eq(
    mooncode_json_object_field_or_empty(claimed, "assistant").stringify(),
    "{}",
  )
  mooncode_append_session_journal(
    root,
    session,
    mooncode_journal_event(),
    mooncode_claim_projection_event("runtime.planner_started", "running"),
  )
  let running = mooncode_claim_projection_read(root, session)
  assert_eq(mooncode_json_string(running, "status", default=""), "running")
  let live = mooncode_json_object_field_or_empty(
    mooncode_json_object_field_or_empty(running, "work"),
    "live",
  )
  assert_eq(
    mooncode_json_string(live, "title", default=""),
    "Planning next steps",
  )
  assert_eq(
    mooncode_json_string(live, "summary", default=""),
    "Choosing the tools needed for this request.",
  )
}

///|
async test "durable claim preserves approval waiting evidence" {
  let root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "mooncode-claim-approval-XXXXXX"),
  )
  let session = "claim-projection-session"
  let claim = mooncode_claim_projection_start(root, session)
  mooncode_append_session_journal(
    root,
    session,
    mooncode_journal_runtime_receipt(),
    claim,
  )
  let approval = mooncode_claim_projection_event(
      "tool.approval_requested", "waiting",
    )
    |> mooncode_json_object_with_field("state", "pending".to_json())
    |> mooncode_json_object_with_field(
      "approval_id",
      "approval-claim".to_json(),
    )
    |> mooncode_json_object_with_field("tool", "bash".to_json())
  mooncode_append_session_journal(
    root,
    session,
    mooncode_journal_event(),
    approval,
  )
  let checkpoint = mooncode_claim_projection_event(
      mooncode_runtime_continuation_kind(),
      "waiting",
    )
    |> mooncode_json_object_with_field("state", "awaiting-approval".to_json())
  mooncode_append_session_journal(
    root,
    session,
    mooncode_journal_event(),
    checkpoint,
  )
  let turn = mooncode_claim_projection_read(root, session)
  assert_eq(mooncode_json_string(turn, "status", default=""), "running")
  let steps = mooncode_json_array_items(
    mooncode_json_object_field_or_empty(turn, "work"),
    "steps",
  )
  assert_eq(steps.length(), 1)
  assert_eq(
    mooncode_json_string(steps[0], "title", default=""),
    "Approval needed",
  )
  let evidence = mooncode_json_object_field_or_empty(steps[0], "evidence")
  assert_eq(mooncode_json_string(evidence, "state", default=""), "pending")
  assert_eq(
    mooncode_json_string(evidence, "approval_id", default=""),
    "approval-claim",
  )
}

///|
async test "durable claim preserves paused planner and rejected finish projection" {
  for
    state in [
      "planner-quantum-paused", "planner-transport-paused", "planner-replan-paused",
    ] {
    let root = @fsx.mkdtemp(
      @pathx.join(@os.tmpdir(), "mooncode-claim-paused-XXXXXX"),
    )
    let session = "claim-projection-session"
    let claim = mooncode_claim_projection_start(root, session)
    mooncode_append_session_journal(
      root,
      session,
      mooncode_journal_runtime_receipt(),
      claim,
    )
    if state == "planner-replan-paused" {
      let answer = mooncode_claim_projection_event("finish", "done")
        |> mooncode_json_object_with_field(
          "content",
          "Rejected earlier answer".to_json(),
        )
      mooncode_append_session_journal(
        root,
        session,
        mooncode_journal_event(),
        answer,
      )
    }
    mooncode_append_session_journal(
      root,
      session,
      mooncode_journal_event(),
      mooncode_claim_projection_event("runtime.planner_started", "running"),
    )
    let checkpoint = mooncode_claim_projection_event(
        mooncode_runtime_continuation_kind(),
        "paused",
      )
      |> mooncode_json_object_with_field("state", state.to_json())
      |> mooncode_json_object_with_field(
        "finish_rejected",
        (state == "planner-replan-paused").to_json(),
      )
    mooncode_append_session_journal(
      root,
      session,
      mooncode_journal_event(),
      checkpoint,
    )
    let turn = mooncode_claim_projection_read(root, session)
    assert_eq(mooncode_json_string(turn, "status", default=""), "running")
    let live = mooncode_json_object_field_or_empty(
      mooncode_json_object_field_or_empty(turn, "work"),
      "live",
    )
    assert_eq(
      mooncode_json_string(live, "title", default=""),
      "Planning next steps",
    )
    assert_eq(
      mooncode_json_object_field_or_empty(turn, "assistant").stringify(),
      "{}",
    )
  }
}

///|
async test "older durable claim cannot override terminal event outcomes or assistant text" {
  for status in ["done", "failed", "cancelled"] {
    let root = @fsx.mkdtemp(
      @pathx.join(@os.tmpdir(), "mooncode-claim-terminal-event-XXXXXX"),
    )
    let session = "claim-projection-session"
    let claim = mooncode_claim_projection_start(root, session)
    mooncode_append_session_journal(
      root,
      session,
      mooncode_journal_runtime_receipt(),
      claim,
    )
    mooncode_append_session_journal(
      root,
      session,
      mooncode_journal_event(),
      mooncode_claim_projection_event("runtime.turn_started", "running"),
    )
    let delta = mooncode_claim_projection_event("assistant_delta", "running")
      |> mooncode_json_object_with_field(
        "content",
        "Existing assistant response".to_json(),
      )
    mooncode_append_session_journal(
      root,
      session,
      mooncode_journal_event(),
      delta,
    )
    mooncode_append_session_journal(
      root,
      session,
      mooncode_journal_event(),
      mooncode_claim_projection_event("runtime.turn_finished", status),
    )
    let turn = mooncode_claim_projection_read(root, session)
    assert_eq(mooncode_json_string(turn, "status", default=""), status)
    assert_eq(
      mooncode_conversation_message_content(
        mooncode_json_object_field_or_empty(turn, "assistant"),
      ),
      "Existing assistant response",
    )
    let work = mooncode_json_object_field_or_empty(turn, "work")
    assert_eq(
      mooncode_json_object_field_or_empty(work, "live").stringify(),
      "{}",
    )
    assert_eq(
      mooncode_json_string(
        mooncode_json_array_items(work, "steps")[0],
        "status",
        default="",
      ),
      status,
    )
  }
}

///|
async test "ordered claim and terminal receipts retain terminal answers usage and failures" {
  for
    (receipt_status, expected) in [
      ("runtime-completed", "done"),
      ("runtime-failed", "failed"),
      ("runtime-cancelled", "cancelled"),
    ] {
    let root = @fsx.mkdtemp(
      @pathx.join(@os.tmpdir(), "mooncode-claim-terminal-receipt-XXXXXX"),
    )
    let session = "claim-projection-session"
    let claim = mooncode_claim_projection_start(root, session)
    mooncode_append_session_journal(
      root,
      session,
      mooncode_journal_runtime_receipt(),
      claim,
    )
    mooncode_append_session_journal(
      root,
      session,
      mooncode_journal_event(),
      mooncode_claim_projection_event("runtime.planner_started", "running"),
    )
    let receipt : Json = {
      "kind": mooncode_kind_runtime_receipt(),
      "command_id": "claim-projection-command",
      "status": receipt_status,
      "completed_at": "2026-10-02T00:00:03Z",
      "execution": {
        "tool_results": [
          {
            "tool": "finish",
            "ok": true,
            "metadata": { "answer": "Durable final answer" },
          },
        ],
      },
      "planner_steps": [
        {
          "planner_metrics": {
            "usage_observed": true,
            "prompt_tokens": 12,
            "completion_tokens": 4,
            "cache_read_tokens": 3,
          },
        },
      ],
    }
    mooncode_append_session_journal(
      root,
      session,
      mooncode_journal_runtime_receipt(),
      receipt,
    )
    let turn = mooncode_claim_projection_read(root, session)
    assert_eq(mooncode_json_string(turn, "status", default=""), expected)
    assert_eq(
      mooncode_conversation_message_content(
        mooncode_json_object_field_or_empty(turn, "assistant"),
      ),
      "Durable final answer",
    )
    assert_eq(
      mooncode_json_int(
        mooncode_json_object_field_or_empty(turn, "usage"),
        "input_tokens",
        default=0,
      ),
      12,
    )
    assert_eq(
      mooncode_json_object_field_or_empty(
        mooncode_json_object_field_or_empty(turn, "work"),
        "live",
      ).stringify(),
      "{}",
    )
  }
}

///|
test "nonterminal receipt statuses cannot synthesize completion or clear work" {
  for
    status in [
      "",
      @mooncode_core.runtime_receipt_status_claimed(),
      @mooncode_core.runtime_receipt_status_proof_missing(),
      @mooncode_core.runtime_receipt_status_skipped(),
      @mooncode_core.runtime_receipt_status_missing(),
      @mooncode_core.runtime_receipt_status_recorded(),
      "unknown-receipt-status",
    ] {
    let commands = [
      mooncode_claim_projection_command(
        "/tmp/claim-projection", "claim-projection-session",
      ),
    ]
    let events = [
      mooncode_claim_projection_event("runtime.planner_started", "running"),
    ]
    let receipt : Json = {
      "command_id": "claim-projection-command",
      "status": status,
      "completed_at": "2026-10-02T00:00:04Z",
      "execution": {
        "tool_results": [
          {
            "tool": "finish",
            "ok": true,
            "metadata": { "answer": "Not a terminal answer" },
          },
        ],
      },
    }
    let baseline = mooncode_session_conversation(
      {},
      commands,
      [],
      events,
      journal_sequence=MoonCodeJournalSequence::zero(),
    )
    let actual = mooncode_session_conversation(
      {},
      commands,
      [receipt],
      events,
      journal_sequence=MoonCodeJournalSequence::zero(),
    )
    assert_eq(actual.stringify(), baseline.stringify())
  }
}

///|
test "recognized receipt status aliases retain completion failure and cancellation" {
  for
    (status, expected) in [
      (@mooncode_core.runtime_receipt_status_completed(), "done"),
      (@mooncode_core.runtime_receipt_status_accepted(), "done"),
      (@mooncode_core.runtime_receipt_status_acknowledged(), "done"),
      ("runtime-delivered", "done"),
      ("runtime-succeeded", "done"),
      ("runtime-finished", "done"),
      ("runtime-failed", "failed"),
      (@mooncode_core.runtime_receipt_status_failed(), "failed"),
      ("runtime-cancelled", "cancelled"),
    ] {
    let turns = mooncode_conversation_turns(
      [
        mooncode_claim_projection_command(
          "/tmp/claim-projection", "claim-projection-session",
        ),
      ],
      [{ "command_id": "claim-projection-command", "status": status }],
      [mooncode_claim_projection_event("runtime.planner_started", "running")],
    )
    assert_eq(turns[0].status, expected)
    assert_eq(turns[0].work_live.stringify(), "{}")
    if expected == "failed" {
      assert_true(
        mooncode_conversation_message_content(turns[0].assistant).contains(
          "could not complete",
        ),
      )
    }
  }
}

///|
test "claims preserve streaming assistant and terminal receipt keeps existing final answer" {
  let command = mooncode_claim_projection_command(
    "/tmp/claim-projection", "claim-projection-session",
  )
  let claim : Json = {
    "command_id": "claim-projection-command",
    "status": @mooncode_core.runtime_receipt_status_claimed(),
  }
  let delta = mooncode_claim_projection_event("assistant_delta", "running")
    |> mooncode_json_object_with_field(
      "content",
      "Existing assistant response".to_json(),
    )
  let streaming = mooncode_session_conversation(
    {},
    [command],
    [claim],
    [delta],
    journal_sequence=MoonCodeJournalSequence::zero(),
  )
  let streaming_turn = mooncode_json_array_items(streaming, "turns")[0]
  assert_eq(
    mooncode_json_string(streaming_turn, "status", default=""),
    "running",
  )
  let streaming_assistant = mooncode_json_object_field_or_empty(
    streaming_turn, "assistant",
  )
  assert_eq(
    mooncode_json_string(streaming_assistant, "status", default=""),
    "running",
  )
  assert_eq(
    mooncode_conversation_message_content(streaming_assistant),
    "Existing assistant response",
  )
  let receipt : Json = {
    "command_id": "claim-projection-command",
    "status": @mooncode_core.runtime_receipt_status_completed(),
    "execution": {
      "tool_results": [
        {
          "tool": "finish",
          "ok": true,
          "metadata": { "answer": "Conflicting receipt answer" },
        },
      ],
    },
  }
  let terminal_event = mooncode_claim_projection_event(
    "runtime.turn_finished", "done",
  )
  let complete = mooncode_session_conversation(
    {},
    [command],
    [claim, receipt],
    [delta, terminal_event],
    journal_sequence=MoonCodeJournalSequence::zero(),
  )
  let complete_turn = mooncode_json_array_items(complete, "turns")[0]
  assert_eq(mooncode_json_string(complete_turn, "status", default=""), "done")
  assert_eq(
    mooncode_conversation_message_content(
      mooncode_json_object_field_or_empty(complete_turn, "assistant"),
    ),
    "Existing assistant response",
  )
  assert_false(complete.stringify().contains("Conflicting receipt answer"))
}

///|
async test "claimed turn stays running for production planner narration before tool work" {
  let root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "mooncode-claim-narration-XXXXXX"),
  )
  let session = "claim-projection-session"
  let claim = mooncode_claim_projection_start(root, session)
  mooncode_append_session_journal(
    root,
    session,
    mooncode_journal_runtime_receipt(),
    claim,
  )
  let events = mooncode_runtime_turn_planner_progress_events(
    session,
    "claim-projection-command",
    {
      "planner_mode": "model",
      "model_response_message": {
        "content": "I will inspect README before making changes.",
      },
    },
    [{ "tool": "read", "arguments": { "path": "README.md" } }],
    step_index=0,
    now=@clock.Timestamp::from_ms(2_000L),
  )
  assert_eq(events.length(), 3)
  assert_eq(
    mooncode_json_string(events[1], "kind", default=""),
    "assistant_delta",
  )
  assert_eq(mooncode_json_string(events[1], "status", default=""), "running")
  for event in events {
    mooncode_append_session_journal(
      root,
      session,
      mooncode_journal_event(),
      event,
    )
  }
  let turn = mooncode_claim_projection_read(root, session)
  assert_eq(mooncode_json_string(turn, "status", default=""), "running")
  let assistant = mooncode_json_object_field_or_empty(turn, "assistant")
  assert_eq(mooncode_json_string(assistant, "status", default=""), "running")
  assert_eq(
    mooncode_conversation_message_content(assistant),
    "I will inspect README before making changes.",
  )
  let work = mooncode_json_object_field_or_empty(turn, "work")
  assert_eq(mooncode_json_string(work, "status", default=""), "running")
  assert_eq(mooncode_json_array_items(work, "steps").length(), 1)
}
