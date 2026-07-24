///|
async test "checkpoint store records first checkpoint and retries idempotently" {
  @fsx.with_temporary_directory(
    "moonclaw-goal-supervisor-checkpoint-store-XXXXXX",
    async fn(root) {
      let session = "session"
      let goal = "goal"
      let owner = "owner"
      let lease_event_id = "lease-1"
      let checkpoint_event_id = "checkpoint-1"
      let budget = goal_store_test_budget()
      let requirements = goal_store_test_requirements()
      ignore(
        mooncode_create_goal(
          root,
          mooncode_protocol_version(),
          session,
          goal,
          "objective",
          10,
          budget,
          requirements,
        ),
      )
      let fence_token = match
        mooncode_goal_supervisor_lease_acquire(
          root, session, goal, owner, lease_event_id, 11, 21,
        ) {
        SupervisorLeaseAcquired(lease) => lease.fence_token
        _ => abort("expected supervisor lease acquisition")
      }
      let first = mooncode_goal_supervisor_checkpoint_record(
        root,
        session,
        goal,
        0,
        0,
        0,
        owner,
        lease_event_id,
        checkpoint_event_id,
        fence_token,
        21,
        2,
        None,
        None,
        None,
        12,
      )
      guard first is CheckpointRecorded(_) else {
        abort("expected checkpoint recording")
      }
      let records = mooncode_read_session_journal(root, session)
      inspect(records.length(), content="3")
      inspect(mooncode_json_int(records[2], "sequence", default=0), content="3")
      let journal_path = mooncode_session_journal_path(root, session)
      let before = @fsx.read_file(journal_path)
      let retry = mooncode_goal_supervisor_checkpoint_record(
        root,
        session,
        goal,
        0,
        0,
        0,
        owner,
        lease_event_id,
        checkpoint_event_id,
        fence_token,
        21,
        2,
        None,
        None,
        None,
        12,
      )
      guard retry is CheckpointIdempotent(_) else {
        abort("expected idempotent checkpoint retry")
      }
      let after = @fsx.read_file(journal_path)
      inspect(after == before, content="true")
    },
  )
}

///|
async test "checkpoint store rejects stale basis without changing journal" {
  @fsx.with_temporary_directory(
    "moonclaw-goal-supervisor-checkpoint-stale-basis-XXXXXX",
    async fn(root) {
      let session = "session"
      ignore(
        mooncode_create_goal(
          root,
          mooncode_protocol_version(),
          session,
          "goal",
          "objective",
          10,
          goal_store_test_budget(),
          goal_store_test_requirements(),
        ),
      )
      let fence_token = match
        mooncode_goal_supervisor_lease_acquire(
          root, session, "goal", "owner", "lease-1", 11, 21,
        ) {
        SupervisorLeaseAcquired(lease) => lease.fence_token
        _ => abort("expected supervisor lease acquisition")
      }
      let journal_path = mooncode_session_journal_path(root, session)
      let before = @fsx.read_file(journal_path)
      let result = mooncode_goal_supervisor_checkpoint_record(
        root,
        session,
        "goal",
        0,
        0,
        0,
        "owner",
        "lease-1",
        "checkpoint-stale-basis",
        fence_token,
        21,
        1,
        None,
        None,
        None,
        12,
      )
      guard result is CheckpointConflict else {
        abort("expected stale checkpoint basis conflict")
      }
      let after = @fsx.read_file(journal_path)
      inspect(after == before, content="true")
    },
  )
}

///|
async test "checkpoint store rejects changed retry with same event id" {
  @fsx.with_temporary_directory(
    "moonclaw-goal-supervisor-checkpoint-changed-retry-XXXXXX",
    async fn(root) {
      let session = "session"
      ignore(
        mooncode_create_goal(
          root,
          mooncode_protocol_version(),
          session,
          "goal",
          "objective",
          10,
          goal_store_test_budget(),
          goal_store_test_requirements(),
        ),
      )
      let fence_token = match
        mooncode_goal_supervisor_lease_acquire(
          root, session, "goal", "owner", "lease-1", 11, 21,
        ) {
        SupervisorLeaseAcquired(lease) => lease.fence_token
        _ => abort("expected supervisor lease acquisition")
      }
      let first = mooncode_goal_supervisor_checkpoint_record(
        root,
        session,
        "goal",
        0,
        0,
        0,
        "owner",
        "lease-1",
        "checkpoint-1",
        fence_token,
        21,
        2,
        None,
        None,
        None,
        12,
      )
      guard first is CheckpointRecorded(_) else {
        abort("expected initial checkpoint recording")
      }
      let journal_path = mooncode_session_journal_path(root, session)
      let before = @fsx.read_file(journal_path)
      let retry = mooncode_goal_supervisor_checkpoint_record(
        root,
        session,
        "goal",
        0,
        0,
        0,
        "owner",
        "lease-1",
        "checkpoint-1",
        fence_token,
        21,
        2,
        None,
        None,
        None,
        13,
      )
      guard retry is CheckpointConflict else {
        abort("expected changed checkpoint retry conflict")
      }
      let after = @fsx.read_file(journal_path)
      inspect(after == before, content="true")
    },
  )
}

///|
async test "checkpoint store blocks ambiguous terminal-linked checkpoint" {
  @fsx.with_temporary_directory(
    "moonclaw-goal-supervisor-checkpoint-terminal-linked-XXXXXX",
    async fn(root) {
      let session = "session"
      ignore(
        mooncode_create_goal(
          root,
          mooncode_protocol_version(),
          session,
          "goal",
          "objective",
          10,
          goal_store_test_budget(),
          goal_store_test_requirements(),
        ),
      )
      let fence_token = match
        mooncode_goal_supervisor_lease_acquire(
          root, session, "goal", "owner", "lease-1", 11, 21,
        ) {
        SupervisorLeaseAcquired(lease) => lease.fence_token
        _ => abort("expected supervisor lease acquisition")
      }
      let journal_path = mooncode_session_journal_path(root, session)
      let before = @fsx.read_file(journal_path)
      let result = mooncode_goal_supervisor_checkpoint_record(
        root,
        session,
        "goal",
        0,
        0,
        0,
        "owner",
        "lease-1",
        "checkpoint-terminal-linked",
        fence_token,
        21,
        2,
        Some("command-1"),
        Some("claim-1"),
        Some("receipt-1"),
        12,
      )
      guard result is CheckpointBlockedAmbiguous else {
        abort("expected ambiguous terminal-linked checkpoint block")
      }
      let after = @fsx.read_file(journal_path)
      inspect(after == before, content="true")
    },
  )
}

///|
async test "checkpoint store rejects ordinary event ID collision without changing journal" {
  @fsx.with_temporary_directory(
    "moonclaw-goal-supervisor-checkpoint-ordinary-collision-XXXXXX",
    async fn(root) {
      let session = "session"
      ignore(
        mooncode_create_goal(
          root,
          mooncode_protocol_version(),
          session,
          "goal",
          "objective",
          10,
          goal_store_test_budget(),
          goal_store_test_requirements(),
        ),
      )
      let fence_token = match
        mooncode_goal_supervisor_lease_acquire(
          root, session, "goal", "owner", "lease-1", 11, 21,
        ) {
        SupervisorLeaseAcquired(lease) => lease.fence_token
        _ => abort("expected supervisor lease acquisition")
      }
      let applied = mooncode_apply_goal_event(
        root,
        session,
        "goal",
        @mooncode_core.goal_event_to_json(
          @mooncode_core.RequirementUpdated(
            "ordinary-event",
            12,
            "r1",
            @mooncode_core.Proven,
            ["evidence:r1"],
          ),
        ),
      )
      guard applied is GoalMutationApplied else {
        abort("expected goal mutation applied")
      }
      let replayed = mooncode_replay_goal(root, session).unwrap()
      let journal_path = mooncode_session_journal_path(root, session)
      let before = @fsx.read_file(journal_path)
      let result = mooncode_goal_supervisor_checkpoint_record(
        root,
        session,
        "goal",
        replayed.run_id,
        replayed.revision,
        replayed.current_goal_turn,
        "owner",
        "lease-1",
        "ordinary-event",
        fence_token,
        21,
        3,
        None,
        None,
        None,
        13,
      )
      guard result is CheckpointConflict else {
        abort("expected checkpoint conflict")
      }
      let after = @fsx.read_file(journal_path)
      inspect(after == before, content="true")
    },
  )
}

///|
async test "checkpoint store concurrent unique checkpoint IDs at same basis linearize once" {
  @fsx.with_temporary_directory(
    "moonclaw-goal-supervisor-checkpoint-concurrent-XXXXXX",
    async fn(root) {
      let session = "session"
      ignore(
        mooncode_create_goal(
          root,
          mooncode_protocol_version(),
          session,
          "goal",
          "objective",
          10,
          goal_store_test_budget(),
          goal_store_test_requirements(),
        ),
      )
      let fence_token = match
        mooncode_goal_supervisor_lease_acquire(
          root, session, "goal", "owner", "lease-1", 11, 21,
        ) {
        SupervisorLeaseAcquired(lease) => lease.fence_token
        _ => abort("expected supervisor lease acquisition")
      }
      let mut recorded = 0
      let mut conflicts = 0
      @async.with_task_group(async fn(group) {
        let tasks = Array::new(capacity=16)
        for i in 0..<16 {
          tasks.push(
            group.spawn(async fn() {
              mooncode_goal_supervisor_checkpoint_record(
                root,
                session,
                "goal",
                0,
                0,
                0,
                "owner",
                "lease-1",
                "checkpoint-\{i}",
                fence_token,
                21,
                2,
                None,
                None,
                None,
                12,
              )
            }),
          )
        }
        for task in tasks {
          match task.wait() {
            CheckpointRecorded(_) => recorded += 1
            CheckpointConflict => conflicts += 1
            _ => abort("expected recorded or conflict")
          }
        }
      })
      assert_eq(recorded, 1)
      assert_eq(conflicts, 15)
      let records = mooncode_read_session_journal(root, session)
      assert_eq(records.length(), 3)
      assert_eq(mooncode_json_int(records[2], "sequence", default=0), 3)
    },
  )
}
