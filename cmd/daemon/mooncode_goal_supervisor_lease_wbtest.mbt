///|
fn supervisor_lease_test_envelope(id : String, payload : Json) -> Json raise {
  {
    "record_kind": mooncode_journal_event(),
    "record_id": mooncode_journal_goal_event() + ":" + id,
    "session_id": "session",
    "recorded_at": goal_json_int64_value(
      goal_json_int64(payload, "recorded_at"),
    ),
    "payload": payload,
  }
}

///|
test "supervisor lease timestamps round-trip exactly above 2^53" {
  let recorded_at : Int64 = 9007199254740993
  let lease_expires_at : Int64 = 9007199254741993
  let payload = mooncode_goal_supervisor_lease_v1(
    "lease-int64",
    mooncode_protocol_version(),
    "session",
    "goal",
    0,
    "owner",
    recorded_at,
    lease_expires_at,
    1,
  )
  let encoded = payload.stringify()
  assert_true(encoded.contains("\"recorded_at\":9007199254740993"))
  assert_true(encoded.contains("\"lease_expires_at\":9007199254741993"))
  let decoded = mooncode_goal_supervisor_lease_decode(
    supervisor_lease_test_envelope("lease-int64", payload),
  )
  assert_eq(decoded.recorded_at, recorded_at)
  assert_eq(decoded.lease_expires_at, lease_expires_at)
}

///|
test "supervisor lease decoder accepts legacy repr-less small timestamps" {
  let payload : Json = {
    "id": "lease-legacy",
    "kind": mooncode_goal_supervisor_lease_v1_kind(),
    "protocol": mooncode_protocol_version(),
    "session_id": "session",
    "goal_id": "goal",
    "goal_run_id": 0,
    "owner_id": "owner",
    "recorded_at": Json::number(124.0),
    "lease_expires_at": Json::number(134.0),
    "fence_token": 1,
  }
  let envelope : Json = {
    "record_kind": mooncode_journal_event(),
    "record_id": "event:lease-legacy",
    "session_id": "session",
    "recorded_at": Json::number(124.0),
    "payload": payload,
  }
  let decoded = mooncode_goal_supervisor_lease_decode(envelope)
  assert_eq(decoded.recorded_at, 124)
  assert_eq(decoded.lease_expires_at, 134)
}

///|
test "mooncode_goal_supervisor_lease: replay duplicate identity and fence ordering" {
  let genesis = goal_store_replay_genesis()
  let goal = mooncode_replay_goal_records([genesis], "session").unwrap()
  let lease_a = supervisor_lease_test_envelope(
    "lease-a",
    mooncode_goal_supervisor_lease_v1(
      "lease-a",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner-a",
      124,
      134,
      1,
    ),
  )
  let lease_b = supervisor_lease_test_envelope(
    "lease-b",
    mooncode_goal_supervisor_lease_v1(
      "lease-b",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner-b",
      134,
      144,
      2,
    ),
  )
  let (current, maximum_fence) = mooncode_goal_supervisor_lease_replay(
    [genesis, lease_a, lease_b, lease_a],
    goal,
  )
  assert_eq(maximum_fence, 2)
  match current {
    Some(lease) => assert_eq(lease.owner_id, "owner-b")
    None => abort("expected current supervisor lease B")
  }

  let conflicting_a = supervisor_lease_test_envelope(
    "lease-a",
    mooncode_goal_supervisor_lease_v1(
      "lease-a",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner-a",
      124,
      135,
      1,
    ),
  )
  let mut conflict_rejected = false
  ignore(
    mooncode_goal_supervisor_lease_replay(
      [genesis, lease_a, lease_b, conflicting_a],
      goal,
    ),
  ) catch {
    InvalidGoalGenesis(_) => conflict_rejected = true
    _ => ()
  }
  assert_true(conflict_rejected)

  let lease_c = supervisor_lease_test_envelope(
    "lease-c",
    mooncode_goal_supervisor_lease_v1(
      "lease-c",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner-c",
      126,
      136,
      3,
    ),
  )
  let mut gap_rejected = false
  ignore(
    mooncode_goal_supervisor_lease_replay([genesis, lease_a, lease_c], goal),
  ) catch {
    InvalidGoalGenesis(_) => gap_rejected = true
    _ => ()
  }
  assert_true(gap_rejected)
}

///|
test "mooncode_goal_supervisor_lease: single-active lineage replay" {
  let genesis = goal_store_replay_genesis()
  let goal_from_genesis = mooncode_replay_goal_records([genesis], "session").unwrap()
  let final_goal = { ..goal_from_genesis, run_id: 1 }
  let run_0 = supervisor_lease_test_envelope(
    "lease-run-0",
    mooncode_goal_supervisor_lease_v1(
      "lease-run-0",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner-run-0",
      10,
      20,
      1,
    ),
  )
  let (current, maximum_fence) = mooncode_goal_supervisor_lease_replay(
    [genesis, run_0],
    final_goal,
  )
  match current {
    Some(lease) => {
      assert_eq(lease.goal_run_id, 0)
      assert_eq(lease.fence_token, 1)
    }
    None => abort("expected run-0 supervisor lease")
  }
  assert_eq(maximum_fence, 1)

  let early_run_1 = supervisor_lease_test_envelope(
    "lease-run-1-early",
    mooncode_goal_supervisor_lease_v1(
      "lease-run-1-early",
      mooncode_protocol_version(),
      "session",
      "goal",
      1,
      "owner-run-1",
      19,
      29,
      2,
    ),
  )
  let mut early_takeover_rejected = false
  ignore(
    mooncode_goal_supervisor_lease_replay(
      [genesis, run_0, early_run_1],
      final_goal,
    ),
  ) catch {
    InvalidGoalGenesis(_) => early_takeover_rejected = true
    _ => ()
  }
  assert_true(early_takeover_rejected)

  let run_1 = supervisor_lease_test_envelope(
    "lease-run-1",
    mooncode_goal_supervisor_lease_v1(
      "lease-run-1",
      mooncode_protocol_version(),
      "session",
      "goal",
      1,
      "owner-run-1",
      20,
      30,
      2,
    ),
  )
  let (current, maximum_fence) = mooncode_goal_supervisor_lease_replay(
    [genesis, run_0, run_1],
    final_goal,
  )
  match current {
    Some(lease) => {
      assert_eq(lease.goal_run_id, 1)
      assert_eq(lease.fence_token, 2)
    }
    None => abort("expected run-1 supervisor lease")
  }
  assert_eq(maximum_fence, 2)
}

///|
/// Focused durable supervisor-lease acquisition coverage.
async test "mooncode_goal_supervisor_lease: first acquisition is durable" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    ignore(
      mooncode_create_goal(
        root,
        mooncode_protocol_version(),
        session_id,
        "goal",
        "objective",
        10,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ),
    )
    let result = mooncode_goal_supervisor_lease_acquire(
      root, session_id, "goal", "owner", "lease-1", 11, 21,
    )
    match result {
      SupervisorLeaseAcquired(lease) => {
        assert_eq(lease.fence_token, 1)
        assert_eq(lease.recorded_at, 11)
        let records = mooncode_read_session_journal(root, session_id)
        let goal = mooncode_replay_goal_records_detailed(records, session_id).unwrap().current
        let (current, maximum_fence) = mooncode_goal_supervisor_lease_replay(
          records, goal,
        )
        assert_true(current == Some(lease))
        assert_eq(maximum_fence, lease.fence_token)
      }
      _ => abort("expected SupervisorLeaseAcquired supervisor lease")
    }
  })
}

///|
async test "mooncode_goal_supervisor_lease: exact retry is idempotent and byte stable" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    ignore(
      mooncode_create_goal(
        root,
        mooncode_protocol_version(),
        session_id,
        "goal",
        "objective",
        10,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ),
    )
    ignore(
      mooncode_goal_supervisor_lease_acquire(
        root, session_id, "goal", "owner", "lease-1", 11, 21,
      ),
    )
    let path = mooncode_session_journal_path(root, session_id)
    let before = @fsx.read_file(path)
    match
      mooncode_goal_supervisor_lease_acquire(
        root, session_id, "goal", "owner", "lease-1", 11, 21,
      ) {
      SupervisorLeaseIdempotent(_) => ()
      _ =>
        abort("expected SupervisorLeaseIdempotent supervisor lease acquisition")
    }
    let after = @fsx.read_file(path)
    assert_true(before == after)
  })
}

///|
async test "mooncode_goal_supervisor_lease: active conflict is byte stable" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    ignore(
      mooncode_create_goal(
        root,
        mooncode_protocol_version(),
        session_id,
        "goal",
        "objective",
        10,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ),
    )
    ignore(
      mooncode_goal_supervisor_lease_acquire(
        root, session_id, "goal", "owner-a", "lease-1", 11, 21,
      ),
    )
    let path = mooncode_session_journal_path(root, session_id)
    let before = @fsx.read_file(path)
    match
      mooncode_goal_supervisor_lease_acquire(
        root, session_id, "goal", "owner-b", "lease-2", 12, 22,
      ) {
      SupervisorLeaseConflict(lease) =>
        assert_eq(lease.unwrap().owner_id, "owner-a")
      _ =>
        abort("expected SupervisorLeaseConflict supervisor lease acquisition")
    }
    let after = @fsx.read_file(path)
    assert_true(before == after)
  })
}

///|
async test "mooncode_goal_supervisor_lease: expiry permits durable takeover" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    ignore(
      mooncode_create_goal(
        root,
        mooncode_protocol_version(),
        session_id,
        "goal",
        "objective",
        10,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ),
    )
    ignore(
      mooncode_goal_supervisor_lease_acquire(
        root, session_id, "goal", "owner-a", "lease-1", 11, 21,
      ),
    )
    match
      mooncode_goal_supervisor_lease_acquire(
        root, session_id, "goal", "owner-b", "lease-2", 21, 31,
      ) {
      SupervisorLeaseAcquired(lease) => {
        assert_eq(lease.fence_token, 2)
        assert_eq(lease.owner_id, "owner-b")
        assert_eq(lease.recorded_at, 21)
        let records = mooncode_read_session_journal(root, session_id)
        let goal = mooncode_replay_goal_records_detailed(records, session_id).unwrap().current
        let (current, maximum_fence) = mooncode_goal_supervisor_lease_replay(
          records, goal,
        )
        assert_true(current == Some(lease))
        assert_eq(maximum_fence, 2)
      }
      _ => abort("expected SupervisorLeaseAcquired supervisor lease takeover")
    }
  })
}

///|
async test "mooncode_goal_supervisor_lease: historical exact retry is stable after takeover" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    ignore(
      mooncode_create_goal(
        root,
        mooncode_protocol_version(),
        session_id,
        "goal",
        "objective",
        10,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ),
    )
    ignore(
      mooncode_goal_supervisor_lease_acquire(
        root, session_id, "goal", "owner-a", "lease-1", 11, 21,
      ),
    )
    ignore(
      mooncode_goal_supervisor_lease_acquire(
        root, session_id, "goal", "owner-b", "lease-2", 21, 31,
      ),
    )
    let path = mooncode_session_journal_path(root, session_id)
    let before = @fsx.read_file(path)
    match
      mooncode_goal_supervisor_lease_acquire(
        root, session_id, "goal", "owner-a", "lease-1", 11, 21,
      ) {
      SupervisorLeaseIdempotent(_) => ()
      _ => abort("expected historical SupervisorLeaseIdempotent")
    }
    assert_true(before == @fsx.read_file(path))
  })
}

///|
async test "mooncode_goal_supervisor_lease: historical changed intent conflicts after takeover" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    ignore(
      mooncode_create_goal(
        root,
        mooncode_protocol_version(),
        session_id,
        "goal",
        "objective",
        10,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ),
    )
    ignore(
      mooncode_goal_supervisor_lease_acquire(
        root, session_id, "goal", "owner-a", "lease-1", 11, 21,
      ),
    )
    ignore(
      mooncode_goal_supervisor_lease_acquire(
        root, session_id, "goal", "owner-b", "lease-2", 21, 31,
      ),
    )
    let path = mooncode_session_journal_path(root, session_id)
    let before = @fsx.read_file(path)
    match
      mooncode_goal_supervisor_lease_acquire(
        root, session_id, "goal", "changed", "lease-1", 11, 21,
      ) {
      SupervisorLeaseConflict(_) => ()
      _ => abort("expected historical SupervisorLeaseConflict")
    }
    assert_true(before == @fsx.read_file(path))
  })
}

///|
async test "mooncode_goal_supervisor_lease: missing goal is rejected without journal" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-XXXXXX", async fn(
    root,
  ) {
    let session_id = "session"
    try {
      ignore(
        mooncode_goal_supervisor_lease_acquire(
          root, session_id, "goal", "owner", "lease-1", 11, 21,
        ),
      )
      abort("expected InvalidGoalGenesis")
    } catch {
      InvalidGoalGenesis(_) => ()
      _ => abort("expected InvalidGoalGenesis")
    }
    assert_false(@fsx.exists(mooncode_session_journal_path(root, session_id)))
  })
}

///|
/// Pure replay coverage for renewal and malformed lineage rejection.
test "mooncode_goal_supervisor_lease: pure replay renewal and rejection validation" {
  let genesis = goal_store_replay_genesis()
  let goal = mooncode_replay_goal_records([genesis], "session").unwrap()
  let lease_a = supervisor_lease_test_envelope(
    "lease-a",
    mooncode_goal_supervisor_lease_v1(
      "lease-a",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner-a",
      10,
      20,
      1,
    ),
  )
  let renew_a = supervisor_lease_test_envelope(
    "renew-a",
    mooncode_goal_supervisor_lease_renewed_v1(
      "renew-a",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner-a",
      15,
      20,
      30,
      1,
      "lease-a",
    ),
  )
  let (current, maximum_fence) = mooncode_goal_supervisor_lease_replay(
    [genesis, lease_a, renew_a, lease_a, renew_a],
    goal,
  )
  assert_eq(maximum_fence, 1)
  match current {
    Some(lease) => assert_eq(lease.lease_expires_at, 30)
    None => abort("expected renewed supervisor lease")
  }

  let takeover = supervisor_lease_test_envelope(
    "lease-b",
    mooncode_goal_supervisor_lease_v1(
      "lease-b",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner-b",
      19,
      29,
      2,
    ),
  )
  let mut takeover_rejected = false
  ignore(
    mooncode_goal_supervisor_lease_replay([genesis, lease_a, takeover], goal),
  ) catch {
    InvalidGoalGenesis(_) => takeover_rejected = true
    _ => ()
  }
  assert_true(takeover_rejected)

  let stale_renewal = supervisor_lease_test_envelope(
    "renew-stale",
    mooncode_goal_supervisor_lease_renewed_v1(
      "renew-stale",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner-a",
      15,
      19,
      30,
      1,
      "lease-a",
    ),
  )
  let mut stale_rejected = false
  ignore(
    mooncode_goal_supervisor_lease_replay(
      [genesis, lease_a, stale_renewal],
      goal,
    ),
  ) catch {
    InvalidGoalGenesis(_) => stale_rejected = true
    _ => ()
  }
  assert_true(stale_rejected)

  let reused_id_renewal = supervisor_lease_test_envelope(
    "lease-a",
    mooncode_goal_supervisor_lease_renewed_v1(
      "lease-a",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner-a",
      15,
      20,
      30,
      1,
      "lease-a",
    ),
  )
  let mut cross_kind_duplicate_rejected = false
  ignore(
    mooncode_goal_supervisor_lease_replay(
      [genesis, lease_a, reused_id_renewal],
      goal,
    ),
  ) catch {
    InvalidGoalGenesis(_) => cross_kind_duplicate_rejected = true
    _ => ()
  }
  assert_true(cross_kind_duplicate_rejected)
}

///|
test "mooncode_goal_supervisor_lease: detailed replay rejects invalid lease lineage" {
  let genesis = goal_store_replay_genesis()
  let lease_a = supervisor_lease_test_envelope(
    "detailed-lease-a",
    mooncode_goal_supervisor_lease_v1(
      "detailed-lease-a",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner-a",
      10,
      20,
      1,
    ),
  )
  let renewal_without_acquisition = supervisor_lease_test_envelope(
    "detailed-renew-orphan",
    mooncode_goal_supervisor_lease_renewed_v1(
      "detailed-renew-orphan",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner-a",
      15,
      20,
      30,
      1,
      "detailed-lease-a",
    ),
  )
  let stale_expiry_renewal = supervisor_lease_test_envelope(
    "detailed-renew-stale",
    mooncode_goal_supervisor_lease_renewed_v1(
      "detailed-renew-stale",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner-a",
      15,
      19,
      30,
      1,
      "detailed-lease-a",
    ),
  )
  let early_fence2_takeover = supervisor_lease_test_envelope(
    "detailed-lease-b",
    mooncode_goal_supervisor_lease_v1(
      "detailed-lease-b",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner-b",
      19,
      29,
      2,
    ),
  )
  for
    records in [
      [genesis, renewal_without_acquisition],
      [genesis, lease_a, stale_expiry_renewal],
      [genesis, lease_a, early_fence2_takeover],
    ] {
    try {
      ignore(mooncode_replay_goal_records_detailed(records, "session"))
      abort("expected InvalidGoalGenesis")
    } catch {
      InvalidGoalGenesis(_) => ()
      _ => abort("expected InvalidGoalGenesis")
    }
  }
}
