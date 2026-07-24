///|
async test "mooncode_goal_supervisor_renew: renewal id conflicts with acquisition at expiry" {
  @fsx.with_temporary_directory(
    "moonclaw-goal-supervisor-renew-acquire-id-XXXXXX",
    async fn(root) {
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
      let lease = match
        mooncode_goal_supervisor_lease_acquire(
          root, session_id, "goal", "owner", "lease-1", 11, 21,
        ) {
        SupervisorLeaseAcquired(lease) => lease
        _ => abort("expected initial supervisor lease")
      }
      match
        mooncode_goal_supervisor_lease_renew(
          root,
          session_id,
          "goal",
          "owner",
          "lease-1",
          "renew-1",
          lease.fence_token,
          21,
          12,
          31,
        ) {
        Renewed(renewal) => assert_eq(renewal.lease_expires_at, 31)
        _ => abort("expected Renewed")
      }
      let journal_path = mooncode_session_journal_path(root, session_id)
      let journal_before = @fsx.read_file(journal_path)
      match
        mooncode_goal_supervisor_lease_acquire(
          root, session_id, "goal", "next-owner", "renew-1", 31, 41,
        ) {
        SupervisorLeaseConflict(_) => ()
        _ => abort("expected SupervisorLeaseConflict")
      }
      assert_eq(@fsx.read_file(journal_path), journal_before)
    },
  )
}

///|
async test "mooncode_goal_supervisor_renew: ordinary goal event id conflicts with renewal" {
  @fsx.with_temporary_directory(
    "moonclaw-goal-supervisor-renew-goal-id-XXXXXX",
    async fn(root) {
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
      let lease = match
        mooncode_goal_supervisor_lease_acquire(
          root, session_id, "goal", "owner", "lease-1", 11, 21,
        ) {
        SupervisorLeaseAcquired(lease) => lease
        _ => abort("expected initial supervisor lease")
      }
      let event = @mooncode_core.RequirementUpdated(
        "ordinary-event",
        12,
        "r1",
        @mooncode_core.Proven,
        ["evidence:r1"],
      )
      match
        mooncode_apply_goal_event(
          root,
          session_id,
          "goal",
          @mooncode_core.goal_event_to_json(event),
        ) {
        GoalMutationApplied(_) => ()
        _ => abort("expected ordinary Goal event to apply")
      }
      let journal_path = mooncode_session_journal_path(root, session_id)
      let journal_before = @fsx.read_file(journal_path)
      match
        mooncode_goal_supervisor_lease_renew(
          root,
          session_id,
          "goal",
          "owner",
          "lease-1",
          "ordinary-event",
          lease.fence_token,
          21,
          13,
          31,
        ) {
        RenewalConflict(_) => ()
        _ => abort("expected RenewalConflict")
      }
      assert_eq(@fsx.read_file(journal_path), journal_before)
      match
        mooncode_goal_supervisor_lease_acquire(
          root, session_id, "goal", "next-owner", "ordinary-event", 21, 31,
        ) {
        SupervisorLeaseConflict(_) => ()
        _ => abort("expected SupervisorLeaseConflict")
      }
      assert_eq(@fsx.read_file(journal_path), journal_before)
    },
  )
}

///|
async test "mooncode_goal_supervisor_renew: durable idempotent conflict and stale lifecycle" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-renew-XXXXXX", async fn(
    root,
  ) {
    let protocol = mooncode_protocol_version()
    let session_id = "session"
    ignore(
      mooncode_create_goal(
        root,
        protocol,
        session_id,
        "goal",
        "objective",
        10,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ),
    )
    let acquired = mooncode_goal_supervisor_lease_acquire(
      root, session_id, "goal", "owner", "lease-1", 11, 21,
    )
    let lease = match acquired {
      SupervisorLeaseAcquired(lease) => lease
      _ => abort("expected initial supervisor lease")
    }
    let fence1 = lease.fence_token
    let renewed = mooncode_goal_supervisor_lease_renew(
      root, session_id, "goal", "owner", "lease-1", "renew-1", fence1, 21, 12, 31,
    )
    match renewed {
      Renewed(renewal) => assert_eq(renewal.lease_expires_at, 31)
      _ => abort("expected Renewed")
    }
    let journal_path = mooncode_session_journal_path(root, session_id)
    let bytes_after_first_renewal = @fsx.read_file(journal_path)
    match
      mooncode_goal_supervisor_lease_renew(
        root, session_id, "goal", "owner", "lease-1", "renew-1", fence1, 21, 12,
        31,
      ) {
      RenewalIdempotent(renewal) => assert_eq(renewal.lease_expires_at, 31)
      _ => abort("expected RenewalIdempotent")
    }
    assert_eq(@fsx.read_file(journal_path), bytes_after_first_renewal)
    match
      mooncode_goal_supervisor_lease_renew(
        root, session_id, "goal", "owner", "lease-1", "renew-1", fence1, 21, 12,
        32,
      ) {
      RenewalConflict(_) => ()
      _ => abort("expected conflicting renewal identity")
    }
    let second = mooncode_goal_supervisor_lease_renew(
      root, session_id, "goal", "owner", "lease-1", "renew-2", fence1, 31, 20, 41,
    )
    match second {
      Renewed(renewal) => assert_eq(renewal.lease_expires_at, 41)
      _ => abort("expected second Renewed")
    }
    let bytes_after_second_renewal = @fsx.read_file(journal_path)
    match
      mooncode_goal_supervisor_lease_renew(
        root, session_id, "goal", "owner", "lease-1", "renew-backdated", fence1,
        41, 19, 51,
      ) {
      RenewalConflict(_) => ()
      _ => abort("expected backdated renewal conflict")
    }
    assert_eq(@fsx.read_file(journal_path), bytes_after_second_renewal)
    match
      mooncode_goal_supervisor_lease_renew(
        root, session_id, "goal", "owner", "lease-1", "renew-1", fence1, 21, 12,
        31,
      ) {
      RenewalIdempotent(renewal) => assert_eq(renewal.lease_expires_at, 31)
      _ => abort("expected historical RenewalIdempotent")
    }
    assert_eq(@fsx.read_file(journal_path), bytes_after_second_renewal)
    match
      mooncode_goal_supervisor_lease_renew(
        root, session_id, "goal", "other", "lease-1", "stale-owner", fence1, 41,
        21, 51,
      ) {
      RenewalConflict(_) => ()
      _ => abort("expected owner conflict")
    }
    match
      mooncode_goal_supervisor_lease_renew(
        root,
        session_id,
        "goal",
        "owner",
        "lease-1",
        "stale-fence",
        fence1 + 1,
        41,
        21,
        51,
      ) {
      RenewalConflict(_) => ()
      _ => abort("expected fence conflict")
    }
    match
      mooncode_goal_supervisor_lease_renew(
        root, session_id, "goal", "owner", "lease-1", "stale-expected", fence1, 31,
        21, 51,
      ) {
      RenewalConflict(_) => ()
      _ => abort("expected stale expiry conflict")
    }
    let mut expired_rejected = false
    ignore(
      mooncode_goal_supervisor_lease_renew(
        root, session_id, "goal", "owner", "lease-1", "stale-now", fence1, 41, 41,
        51,
      ),
    ) catch {
      InvalidGoalGenesis(_) => expired_rejected = true
      _ => ()
    }
    assert_true(expired_rejected)
    assert_eq(@fsx.read_file(journal_path), bytes_after_second_renewal)
  })
}

///|
async test "mooncode_goal_supervisor_renew: 16 contenders linearize once" {
  @fsx.with_temporary_directory(
    "moonclaw-goal-supervisor-renew-concurrent-XXXXXX",
    async fn(root) {
      let protocol = mooncode_protocol_version()
      let session_id = "session"
      ignore(
        mooncode_create_goal(
          root,
          protocol,
          session_id,
          "goal",
          "objective",
          10,
          goal_store_test_budget(),
          goal_store_test_requirements(),
        ),
      )
      let acquired = mooncode_goal_supervisor_lease_acquire(
        root, session_id, "goal", "owner", "lease-1", 11, 21,
      )
      let lease = match acquired {
        SupervisorLeaseAcquired(lease) => lease
        _ => abort("expected initial supervisor lease")
      }
      let fence1 = lease.fence_token
      let mut renewed_count = 0
      let mut conflict_count = 0
      @async.with_task_group(async fn(group) {
        let tasks = Array::new(capacity=16)
        for i in 0..<16 {
          tasks.push(
            group.spawn(async fn() {
              mooncode_goal_supervisor_lease_renew(
                root,
                session_id,
                "goal",
                "owner",
                "lease-1",
                "renew-\{i}",
                fence1,
                21,
                12,
                31,
              )
            }),
          )
        }
        for task in tasks {
          match task.wait() {
            Renewed(_) => renewed_count += 1
            RenewalConflict(_) => conflict_count += 1
            _ => abort("unexpected renewal result")
          }
        }
      })
      assert_eq(renewed_count, 1)
      assert_eq(conflict_count, 15)
      let records = mooncode_read_session_journal(root, session_id)
      let replayed = mooncode_replay_goal_records_detailed(records, session_id).unwrap().current
      let (current, _) = mooncode_goal_supervisor_lease_replay(
        records, replayed,
      )
      let active = current.unwrap()
      assert_eq(active.fence_token, fence1)
      assert_eq(active.lease_expires_at, 31)
    },
  )
}
