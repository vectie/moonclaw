///|
async test "16 concurrent supervised claimers append exactly one receipt" {
  @fsx.with_temporary_directory("goal-runtime-claim-concurrent-XXXXXX", async fn(
    root,
  ) {
    ignore(
      mooncode_create_goal(
        root,
        mooncode_protocol_version(),
        "session",
        "goal",
        "objective",
        10,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ),
    )
    let fence = match
      mooncode_goal_supervisor_lease_acquire(
        root, "session", "goal", "owner", "lease-1", 11, 21,
      ) {
      SupervisorLeaseAcquired(lease) => lease.fence_token
      _ => fail("expected lease acquisition")
    }
    guard mooncode_goal_supervisor_checkpoint_record(
        root,
        "session",
        "goal",
        0,
        0,
        0,
        "owner",
        "lease-1",
        "checkpoint-1",
        fence,
        21,
        2,
        None,
        None,
        None,
        12,
      )
      is CheckpointRecorded(_) else {
      fail("expected checkpoint recording")
    }
    ignore(
      mooncode_append_session_journal(
        root,
        "session",
        mooncode_journal_command(),
        {
          "kind": "mooncode-command",
          "protocol": mooncode_protocol_version(),
          "session_id": "session",
          "command_id": "cmd-atomic",
          "created_at": 13,
          "command": {
            "protocol": mooncode_protocol_version(),
            "session_id": "session",
            "book_root": root,
            "command": "prompt",
            "packet": { "command_id": "cmd-atomic" },
          },
        },
      ),
    )
    let tasks = Array::makei(16, fn(i) {
      async fn() {
        mooncode_goal_supervisor_runtime_claim_record(
          root,
          "session",
          "goal",
          0,
          "owner",
          "lease-1",
          "checkpoint-1",
          "claim-\{i}",
          "consumer-\{i}",
          fence,
          21,
          13,
        )
      }
    })
    let outcomes = @async.all(tasks)
    let mut recorded = 0
    let mut blocked = 0
    for outcome in outcomes {
      match outcome {
        Recorded(_) => recorded += 1
        BlockedAmbiguous(_) => blocked += 1
        _ => fail("unexpected concurrent runtime claim outcome")
      }
    }
    assert_eq(recorded, 1)
    assert_eq(blocked, 15)
    let journal = mooncode_read_session_journal(root, "session")
    let receipts = mooncode_journal_entries(
      journal,
      mooncode_journal_runtime_receipt(),
    )
    assert_eq(receipts.length(), 1)
    assert_eq(
      mooncode_json_string(receipts[0], "status", default=""),
      "runtime-claimed",
    )
  })
}

///|
async test "mismatched nested command id is blocked without mutation" {
  @fsx.with_temporary_directory("goal-runtime-claim-mismatch-XXXXXX", async fn(
    root,
  ) {
    ignore(
      mooncode_create_goal(
        root,
        mooncode_protocol_version(),
        "session",
        "goal",
        "objective",
        10,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ),
    )
    let fence = match
      mooncode_goal_supervisor_lease_acquire(
        root, "session", "goal", "owner", "lease-1", 11, 21,
      ) {
      SupervisorLeaseAcquired(lease) => lease.fence_token
      _ => fail("expected lease acquisition")
    }
    guard mooncode_goal_supervisor_checkpoint_record(
        root,
        "session",
        "goal",
        0,
        0,
        0,
        "owner",
        "lease-1",
        "checkpoint-1",
        fence,
        21,
        2,
        None,
        None,
        None,
        12,
      )
      is CheckpointRecorded(_) else {
      fail("expected checkpoint recording")
    }
    ignore(
      mooncode_append_session_journal(
        root,
        "session",
        mooncode_journal_command(),
        {
          "kind": "mooncode-command",
          "protocol": mooncode_protocol_version(),
          "session_id": "session",
          "command_id": "cmd-outer",
          "created_at": 13,
          "command": {
            "protocol": mooncode_protocol_version(),
            "session_id": "session",
            "book_root": root,
            "command": "prompt",
            "packet": { "command_id": "cmd-inner" },
          },
        },
      ),
    )
    let journal_path = mooncode_session_journal_path(root, "session")
    let before = @fsx.read_file(journal_path)
    guard mooncode_goal_supervisor_runtime_claim_record(
        root, "session", "goal", 0, "owner", "lease-1", "checkpoint-1", "claim-mismatch",
        "consumer-1", fence, 21, 13,
      )
      is BlockedAmbiguous(_) else {
      fail("expected ambiguous runtime claim")
    }
    assert_eq(
      mooncode_read_session_journal(root, "session")
      .filter(fn(record) {
        mooncode_json_string(record, "record_kind", default="") ==
        mooncode_journal_runtime_receipt()
      })
      .length(),
      0,
    )
    assert_eq(@fsx.read_file(journal_path), before)
  })
}

///|
async test "supervised runtime claim is recorded, idempotent, and conflict-safe" {
  @fsx.with_temporary_directory("goal-runtime-claim-XXXXXX", async fn(root) {
    ignore(
      mooncode_create_goal(
        root,
        mooncode_protocol_version(),
        "session",
        "goal",
        "objective",
        10,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ),
    )
    let fence = match
      mooncode_goal_supervisor_lease_acquire(
        root, "session", "goal", "owner", "lease-1", 11, 21,
      ) {
      SupervisorLeaseAcquired(lease) => lease.fence_token
      _ => fail("expected lease acquisition")
    }
    guard mooncode_goal_supervisor_checkpoint_record(
        root,
        "session",
        "goal",
        0,
        0,
        0,
        "owner",
        "lease-1",
        "checkpoint-1",
        fence,
        21,
        2,
        None,
        None,
        None,
        12,
      )
      is CheckpointRecorded(_) else {
      fail("expected checkpoint recording")
    }
    ignore(
      mooncode_append_session_journal(
        root,
        "session",
        mooncode_journal_command(),
        {
          "kind": "mooncode-command",
          "protocol": mooncode_protocol_version(),
          "session_id": "session",
          "command_id": "cmd-1",
          "created_at": 13,
          "command": {
            "protocol": mooncode_protocol_version(),
            "session_id": "session",
            "book_root": root,
            "command": "prompt",
            "packet": { "command_id": "cmd-1" },
          },
        },
      ),
    )
    let first = mooncode_goal_supervisor_runtime_claim_record(
      root, "session", "goal", 0, "owner", "lease-1", "checkpoint-1", "claim-1",
      "consumer-1", fence, 21, 13,
    )
    match first {
      Recorded(payload) => {
        assert_eq(
          mooncode_json_string(payload, "command_id", default=""),
          "cmd-1",
        )
        assert_eq(mooncode_json_string(payload, "book_root", default=""), root)
        assert_eq(mooncode_json_int(payload, "basis_sequence", default=-1), 4)
      }
      _ => fail("expected recorded runtime claim")
    }
    assert_eq(
      mooncode_read_session_journal(root, "session")
      .filter(fn(record) {
        mooncode_json_string(record, "record_kind", default="") ==
        mooncode_journal_runtime_receipt()
      })
      .length(),
      1,
    )
    let journal_path = mooncode_session_journal_path(root, "session")
    let before = @fsx.read_file(journal_path)
    guard mooncode_goal_supervisor_runtime_claim_record(
        root, "session", "goal", 0, "owner", "lease-1", "checkpoint-1", "claim-1",
        "consumer-1", fence, 21, 13,
      )
      is Idempotent(_) else {
      fail("expected idempotent runtime claim")
    }
    assert_eq(@fsx.read_file(journal_path), before)
    guard mooncode_goal_supervisor_runtime_claim_record(
        root, "session", "goal", 0, "owner", "lease-1", "checkpoint-1", "claim-1",
        "consumer-2", fence, 21, 13,
      )
      is Conflict(_) else {
      fail("expected conflicting runtime claim")
    }
    assert_eq(@fsx.read_file(journal_path), before)
    ignore(
      mooncode_append_session_journal(
        root,
        "session",
        mooncode_journal_runtime_receipt(),
        {
          "kind": "moonclaw",
          "protocol": mooncode_protocol_version(),
          "session_id": "session",
          "status": "runtime-completed",
          "runtime_mode": "moonclaw-native-runtime-turn",
          "consumer_id": "consumer-1",
          "command_id": "cmd-1",
          "claim_id": "claim-1",
          "completed_at": 14,
        },
      ),
    )
    let completed_before = @fsx.read_file(journal_path)
    guard mooncode_goal_supervisor_runtime_claim_record(
        root, "session", "goal", 0, "owner", "lease-1", "checkpoint-1", "claim-1",
        "consumer-1", fence, 21, 13,
      )
      is BlockedAmbiguous(_) else {
      fail("expected completed runtime claim to be blocked as ambiguous")
    }
    assert_eq(@fsx.read_file(journal_path), completed_before)
    match
      mooncode_goal_supervisor_lease_acquire(
        root, "session", "goal", "owner-2", "lease-2", 21, 31,
      ) {
      SupervisorLeaseAcquired(lease) => assert_eq(lease.fence_token, 2)
      _ => fail("expected second lease acquisition")
    }
    let second_lease_before = @fsx.read_file(journal_path)
    guard mooncode_goal_supervisor_runtime_claim_record(
        root, "session", "goal", 0, "owner", "lease-1", "checkpoint-1", "claim-1",
        "consumer-1", fence, 21, 13,
      )
      is Conflict(_) else {
      fail("expected old-fence runtime claim conflict")
    }
    assert_eq(@fsx.read_file(journal_path), second_lease_before)
  })
}

///|
async test "forged runtime claim lineage blocks ambiguous exact retry without mutation" {
  @fsx.with_temporary_directory("goal-runtime-claim-forged-XXXXXX", async fn(
    root,
  ) {
    ignore(
      mooncode_create_goal(
        root,
        mooncode_protocol_version(),
        "session",
        "goal",
        "objective",
        10,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ),
    )
    let fence = match
      mooncode_goal_supervisor_lease_acquire(
        root, "session", "goal", "owner", "lease-1", 11, 21,
      ) {
      SupervisorLeaseAcquired(lease) => lease.fence_token
      _ => fail("expected lease acquisition")
    }
    guard mooncode_goal_supervisor_checkpoint_record(
        root,
        "session",
        "goal",
        0,
        0,
        0,
        "owner",
        "lease-1",
        "checkpoint-1",
        fence,
        21,
        2,
        None,
        None,
        None,
        12,
      )
      is CheckpointRecorded(_) else {
      fail("expected checkpoint recording")
    }
    ignore(
      mooncode_append_session_journal(
        root,
        "session",
        mooncode_journal_runtime_receipt(),
        {
          "kind": mooncode_kind_runtime_receipt(),
          "protocol": mooncode_protocol_version(),
          "owner": "moonclaw",
          "runtime_mode": "moonclaw-native-runtime-claim",
          "status": "runtime-claimed",
          "book_root": root,
          "session_id": "session",
          "goal_id": "goal",
          "goal_run_id": 0,
          "owner_id": "owner",
          "acquisition_event_id": "lease-1",
          "checkpoint_event_id": "checkpoint-1",
          "claim_id": "claim-forged",
          "consumer_id": "consumer-1",
          "fence_token": fence,
          "expected_lease_expires_at": 21,
          "claimed_at": 13,
          "basis_sequence": 3,
          "command_id": "fake-command",
          "command_entry": {
            "kind": "mooncode-command",
            "protocol": mooncode_protocol_version(),
            "session_id": "session",
            "command_id": "fake-command",
            "created_at": 13,
            "command": {
              "protocol": mooncode_protocol_version(),
              "session_id": "session",
              "book_root": root,
              "command": "prompt",
              "packet": { "command_id": "fake-command" },
            },
          },
          "command": {
            "protocol": mooncode_protocol_version(),
            "session_id": "session",
            "book_root": root,
            "command": "prompt",
            "packet": { "command_id": "fake-command" },
          },
        },
      ),
    )
    let journal_path = mooncode_session_journal_path(root, "session")
    let before = @fsx.read_file(journal_path)
    guard mooncode_goal_supervisor_runtime_claim_record(
        root, "session", "goal", 0, "owner", "lease-1", "checkpoint-1", "claim-forged",
        "consumer-1", fence, 21, 13,
      )
      is BlockedAmbiguous(_) else {
      fail("expected forged-lineage exact retry to be blocked as ambiguous")
    }
    assert_eq(@fsx.read_file(journal_path), before)
  })
}

///|
async test "supervised runtime claim preserves exact Int64 timestamps above 2^53" {
  @fsx.with_temporary_directory("goal-runtime-claim-int64-XXXXXX", async fn(
    root,
  ) {
    let acquired_at : Int64 = 9007199254740993
    let checkpointed_at : Int64 = 9007199254740994
    let claimed_at : Int64 = 9007199254740995
    let lease_expires_at : Int64 = 9007199254741993
    ignore(
      mooncode_create_goal(
        root,
        mooncode_protocol_version(),
        "session",
        "goal",
        "objective",
        acquired_at - 1,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ),
    )
    let fence = match
      mooncode_goal_supervisor_lease_acquire(
        root, "session", "goal", "owner", "lease-int64", acquired_at, lease_expires_at,
      ) {
      SupervisorLeaseAcquired(lease) => lease.fence_token
      _ => fail("expected lease acquisition")
    }
    guard mooncode_goal_supervisor_checkpoint_record(
        root,
        "session",
        "goal",
        0,
        0,
        0,
        "owner",
        "lease-int64",
        "checkpoint-int64",
        fence,
        lease_expires_at,
        2,
        None,
        None,
        None,
        checkpointed_at,
      )
      is CheckpointRecorded(_) else {
      fail("expected checkpoint recording")
    }
    ignore(
      mooncode_append_session_journal(
        root,
        "session",
        mooncode_journal_command(),
        {
          "kind": "mooncode-command",
          "protocol": mooncode_protocol_version(),
          "session_id": "session",
          "command_id": "cmd-int64",
          "created_at": 13,
          "command": {
            "protocol": mooncode_protocol_version(),
            "session_id": "session",
            "book_root": root,
            "command": "prompt",
            "packet": { "command_id": "cmd-int64" },
          },
        },
      ),
    )
    let first = mooncode_goal_supervisor_runtime_claim_record(
      root, "session", "goal", 0, "owner", "lease-int64", "checkpoint-int64", "claim-int64",
      "consumer-int64", fence, lease_expires_at, claimed_at,
    )
    let payload = match first {
      Recorded(payload) => payload
      _ => fail("expected recorded runtime claim")
    }
    assert_eq(
      goal_json_int64(payload, "expected_lease_expires_at"),
      lease_expires_at,
    )
    assert_eq(goal_json_int64(payload, "claimed_at"), claimed_at)
    let encoded = payload.stringify()
    assert_true(
      encoded.contains("\"expected_lease_expires_at\":9007199254741993"),
    )
    assert_true(encoded.contains("\"claimed_at\":9007199254740995"))
    guard mooncode_goal_supervisor_runtime_claim_record(
        root, "session", "goal", 0, "owner", "lease-int64", "checkpoint-int64", "claim-int64",
        "consumer-int64", fence, lease_expires_at, claimed_at,
      )
      is Idempotent(_) else {
      fail("expected exact Int64 retry to be idempotent")
    }
  })
}

///|
test "runtime claim optional timestamp matching is strict and non-raising" {
  let legacy : Json = { "claimed_at": Json::number(13.0) }
  assert_eq(
    mooncode_goal_supervisor_runtime_claim_optional_int64(legacy, "claimed_at"),
    Some(13),
  )
  let malformed : Json = { "claimed_at": "13" }
  assert_eq(
    mooncode_goal_supervisor_runtime_claim_optional_int64(
      malformed, "claimed_at",
    ),
    None,
  )
  assert_eq(
    mooncode_goal_supervisor_runtime_claim_optional_int64(
      malformed, "expected_lease_expires_at",
    ),
    None,
  )
}

///|
async test "malformed existing runtime claim timestamp yields safe conflict" {
  @fsx.with_temporary_directory("goal-runtime-claim-malformed-time-XXXXXX", async fn(
    root,
  ) {
    ignore(
      mooncode_create_goal(
        root,
        mooncode_protocol_version(),
        "session",
        "goal",
        "objective",
        10,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ),
    )
    let fence = match
      mooncode_goal_supervisor_lease_acquire(
        root, "session", "goal", "owner", "lease-1", 11, 21,
      ) {
      SupervisorLeaseAcquired(lease) => lease.fence_token
      _ => fail("expected lease acquisition")
    }
    guard mooncode_goal_supervisor_checkpoint_record(
        root,
        "session",
        "goal",
        0,
        0,
        0,
        "owner",
        "lease-1",
        "checkpoint-1",
        fence,
        21,
        2,
        None,
        None,
        None,
        12,
      )
      is CheckpointRecorded(_) else {
      fail("expected checkpoint recording")
    }
    ignore(
      mooncode_append_session_journal(
        root,
        "session",
        mooncode_journal_command(),
        {
          "kind": "mooncode-command",
          "protocol": mooncode_protocol_version(),
          "session_id": "session",
          "command_id": "cmd-malformed-time",
          "created_at": 13,
          "command": {
            "protocol": mooncode_protocol_version(),
            "session_id": "session",
            "book_root": root,
            "command": "prompt",
            "packet": { "command_id": "cmd-malformed-time" },
          },
        },
      ),
    )
    let records = mooncode_read_session_journal(root, "session")
    let commands = mooncode_journal_entries(records, mooncode_journal_command())
    guard commands.length() == 1 else { fail("expected one durable command") }
    let command_entry = commands[0]
    let command = mooncode_json_object_field_or_empty(command_entry, "command")
    ignore(
      mooncode_append_session_journal(
        root,
        "session",
        mooncode_journal_runtime_receipt(),
        {
          "kind": mooncode_kind_runtime_receipt(),
          "protocol": mooncode_protocol_version(),
          "owner": "moonclaw",
          "runtime_mode": "moonclaw-native-runtime-claim",
          "status": "runtime-claimed",
          "book_root": root,
          "session_id": "session",
          "goal_id": "goal",
          "goal_run_id": 0,
          "owner_id": "owner",
          "acquisition_event_id": "lease-1",
          "checkpoint_event_id": "checkpoint-1",
          "claim_id": "claim-malformed-time",
          "consumer_id": "consumer-1",
          "fence_token": fence,
          "expected_lease_expires_at": "invalid",
          "claimed_at": Json::number(13.0),
          "basis_sequence": mooncode_journal_last_sequence(records),
          "command_id": "cmd-malformed-time",
          "command": command,
          "command_entry": command_entry,
        },
      ),
    )
    let journal_path = mooncode_session_journal_path(root, "session")
    let before = @fsx.read_file(journal_path)
    guard mooncode_goal_supervisor_runtime_claim_record(
        root, "session", "goal", 0, "owner", "lease-1", "checkpoint-1", "claim-malformed-time",
        "consumer-1", fence, 21, 13,
      )
      is Conflict(_) else {
      fail("expected malformed timestamp conflict")
    }
    assert_eq(@fsx.read_file(journal_path), before)
  })
}
