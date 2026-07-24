///|
fn lifecycle_assert_invalid(records : Array[Json]) -> Unit raise {
  let mut rejected = false
  ignore(mooncode_replay_goal_records_detailed(records, "session")) catch {
    InvalidGoalGenesis(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}

///|
fn lifecycle_lease(
  id : String,
  owner : String,
  recorded_at : Int,
  expires_at : Int,
  fence : Int,
) -> Json raise {
  supervisor_lease_test_envelope(
    id,
    mooncode_goal_supervisor_lease_v1(
      id,
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      owner,
      recorded_at,
      expires_at,
      fence,
    ),
  )
}

///|
fn lifecycle_renewal(
  id : String,
  owner : String,
  recorded_at : Int,
  expected_expiry : Int,
  expires_at : Int,
  fence : Int,
  acquisition_id : String,
) -> Json raise {
  supervisor_lease_test_envelope(
    id,
    mooncode_goal_supervisor_lease_renewed_v1(
      id,
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      owner,
      recorded_at,
      expected_expiry,
      expires_at,
      fence,
      acquisition_id,
    ),
  )
}

///|
test "mooncode goal supervisor lifecycle preflight rejects invalid histories" {
  let genesis = goal_store_replay_genesis()
  let lease = lifecycle_lease("lease-1", "owner", 124, 134, 1)
  lifecycle_assert_invalid([
    genesis,
    lifecycle_renewal("renew-orphan", "owner", 125, 134, 144, 1, "lease-1"),
  ])
  lifecycle_assert_invalid([
    genesis,
    lease,
    lifecycle_renewal("renew-stale", "owner", 135, 136, 146, 1, "lease-1"),
  ])
  lifecycle_assert_invalid([
    genesis,
    lease,
    lifecycle_lease("lease-2", "next-owner", 133, 143, 2),
  ])
}

///|
async test "mooncode goal supervisor lifecycle preflight preserves journal bytes" {
  @fsx.with_temporary_directory("mooncode-lifecycle-preflight-XXXXXX", async fn(
    directory,
  ) {
    ignore(
      mooncode_create_goal(
        directory,
        mooncode_protocol_version(),
        "session",
        "goal",
        "objective",
        123,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ),
    )
    let renewal = mooncode_goal_supervisor_lease_renewed_v1(
      "renew-orphan",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner",
      125,
      134,
      144,
      1,
      "lease-1",
    )
    mooncode_session_journal_transaction(directory, "session", fn(_) raise {
      Append(mooncode_journal_goal_event(), renewal, ())
    })
    let path = mooncode_session_journal_path(directory, "session")
    let before = @fsx.read_file(path)
    let event = goal_store_replay_requirement_event(
      126,
      "r1",
      @mooncode_core.Proven,
      ["evidence:r1"],
    )
    let mut rejected = false
    ignore(
      mooncode_apply_goal_event(
        directory,
        "session",
        "goal",
        @mooncode_core.goal_event_to_json(event),
      ),
    ) catch {
      InvalidGoalGenesis(_) => rejected = true
      _ => ()
    }
    assert_true(rejected)
    assert_eq(@fsx.read_file(path), before)
  })
}

///|
async test "mooncode goal supervisor lease conflicts preserve journal bytes" {
  @fsx.with_temporary_directory("mooncode-lifecycle-conflict-XXXXXX", async fn(
    directory,
  ) {
    ignore(
      mooncode_create_goal(
        directory,
        mooncode_protocol_version(),
        "session",
        "goal",
        "objective",
        10,
        goal_store_test_budget(),
        goal_store_test_requirements(),
      ),
    )
    let lease = mooncode_goal_supervisor_lease_v1(
      "lease-1",
      mooncode_protocol_version(),
      "session",
      "goal",
      0,
      "owner",
      11,
      21,
      1,
    )
    mooncode_session_journal_transaction(directory, "session", fn(_) raise {
      Append(mooncode_journal_goal_event(), lease, ())
    })
    let path = mooncode_session_journal_path(directory, "session")
    let before = @fsx.read_file(path)
    match
      mooncode_apply_goal_event(
        directory,
        "session",
        "goal",
        @mooncode_core.goal_event_to_json(
          @mooncode_core.RequirementUpdated(
            "lease-1",
            12,
            "r1",
            @mooncode_core.Proven,
            ["evidence:r1"],
          ),
        ),
      ) {
      GoalMutationConflict(_) => ()
      _ => abort("expected conflict")
    }
    assert_eq(@fsx.read_file(path), before)
  })
}
