///|
fn supervisor_lease_test_envelope(id : String, payload : Json) -> Json raise {
  {
    "record_kind": mooncode_journal_event(),
    "record_id": mooncode_journal_goal_event() + ":" + id,
    "session_id": "session",
    "recorded_at": goal_json_int(payload, "recorded_at"),
    "payload": payload,
  }
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
      125,
      135,
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
      SupervisorLeaseConflict(lease) => assert_eq(lease.owner_id, "owner-a")
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
