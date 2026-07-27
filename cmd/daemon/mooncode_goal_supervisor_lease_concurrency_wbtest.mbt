///|
async test "mooncode_goal_supervisor_lease: concurrent initial acquire linearizes once" {
  @fsx.with_temporary_directory(
    "moonclaw-goal-supervisor-concurrent-initial-XXXXXX",
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
      let mut acquired = 0
      let mut conflicts = 0
      @async.with_task_group(async fn(group) {
        let tasks = Array::new(capacity=16)
        for i in 0..<16 {
          tasks.push(
            group.spawn(async fn() {
              mooncode_goal_supervisor_lease_acquire(
                root,
                session_id,
                "goal",
                "owner-\{i}",
                "lease-\{i}",
                11,
                21,
              )
            }),
          )
        }
        for task in tasks {
          match task.wait() {
            SupervisorLeaseAcquired(lease) => {
              assert_eq(lease.fence_token, 1)
              acquired += 1
            }
            SupervisorLeaseConflict(_) => conflicts += 1
            _ => abort("expected acquired or conflict")
          }
        }
      })
      assert_eq(acquired, 1)
      assert_eq(conflicts, 15)
      let records = mooncode_read_session_journal(root, session_id)
      let goal = mooncode_replay_goal_records_detailed(records, session_id).unwrap().current
      let (_, maximum_fence) = mooncode_goal_supervisor_lease_replay(
        records, goal,
      )
      assert_eq(maximum_fence, 1)
    },
  )
}

///|
async test "mooncode_goal_supervisor_lease: concurrent takeover linearizes once" {
  @fsx.with_temporary_directory(
    "moonclaw-goal-supervisor-concurrent-takeover-XXXXXX",
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
      ignore(
        mooncode_goal_supervisor_lease_acquire(
          root, session_id, "goal", "owner-initial", "lease-initial", 11, 21,
        ),
      )
      let mut acquired = 0
      let mut conflicts = 0
      @async.with_task_group(async fn(group) {
        let tasks = Array::new(capacity=16)
        for i in 0..<16 {
          tasks.push(
            group.spawn(async fn() {
              mooncode_goal_supervisor_lease_acquire(
                root,
                session_id,
                "goal",
                "owner-\{i}",
                "takeover-\{i}",
                21,
                31,
              )
            }),
          )
        }
        for task in tasks {
          match task.wait() {
            SupervisorLeaseAcquired(lease) => {
              assert_eq(lease.fence_token, 2)
              acquired += 1
            }
            SupervisorLeaseConflict(_) => conflicts += 1
            _ => abort("expected acquired or conflict")
          }
        }
      })
      assert_eq(acquired, 1)
      assert_eq(conflicts, 15)
      let records = mooncode_read_session_journal(root, session_id)
      let goal = mooncode_replay_goal_records_detailed(records, session_id).unwrap().current
      let (_, maximum_fence) = mooncode_goal_supervisor_lease_replay(
        records, goal,
      )
      assert_eq(maximum_fence, 2)
    },
  )
}

///|
async test "mooncode_goal_supervisor_lease: generic append cannot bypass validation" {
  @fsx.with_temporary_directory("moonclaw-goal-supervisor-bypass-XXXXXX", async fn(
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
    let path = mooncode_session_journal_path(root, session_id)
    let before = @fsx.read_file(path)
    let payload : Json = {
      "id": "bypass",
      "kind": "mooncode.goal.supervisor.fake.v1",
      "recorded_at": 11,
    }
    let mut rejected = false
    ignore(
      mooncode_append_session_journal_once(
        root,
        session_id,
        mooncode_journal_event(),
        payload,
      ),
    ) catch {
      InvalidJournal(_) => rejected = true
      _ => ()
    }
    assert_true(rejected)
    assert_eq(@fsx.read_file(path), before)
  })
}
