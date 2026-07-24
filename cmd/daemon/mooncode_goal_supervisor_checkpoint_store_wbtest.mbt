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
