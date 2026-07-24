///|
/// Focused internal API compile ledger: production/routes/ledger remain untouched. Compiler
/// signature drift found here should be transferred to the later ledger slice.
fn goal_internal_assert_error(
  response : MoonCodeGoalApiResponse,
  status : Int,
  code : String,
) -> Unit raise {
  assert_eq(response.status_code, status)
  let body = match response.body {
    Object(body) => body
    _ => abort("error body must be an object")
  }
  assert_eq(body.length(), 4)
  for key in ["kind", "protocol", "owner", "error"] {
    assert_true(body.contains(key))
  }
  assert_eq(body["kind"], ("mooncode-goal-error" : Json))
  assert_eq(body["protocol"], ("mooncode.v1" : Json))
  assert_eq(body["owner"], ("moonclaw" : Json))
  assert_eq(body["error"], code.to_json())
}

///|
test "mooncode_goal_api_internal: checked epoch boundaries are exact" {
  assert_eq(goal_api_checked_epoch_seconds(-1L), None)
  assert_eq(goal_api_checked_epoch_seconds(0L), Some(0L))
  assert_eq(goal_api_checked_epoch_seconds(2147483648L), Some(2147483648L))
  assert_eq(
    goal_api_checked_epoch_seconds(9223372036854775807L),
    Some(9223372036854775807L),
  )
}

///|
fn goal_internal_assert_redacted(body : Json) -> Unit raise {
  let wrapper = match body {
    Object(wrapper) => wrapper
    _ => abort("goal response must be an object")
  }
  assert_eq(wrapper.length(), 4)
  for key in ["kind", "protocol", "owner", "goal"] {
    assert_true(wrapper.contains(key))
  }
  assert_eq(wrapper["kind"], ("mooncode-goal-status" : Json))
  assert_eq(wrapper["protocol"], ("mooncode.v1" : Json))
  assert_eq(wrapper["owner"], ("moonclaw" : Json))
  let goal = match wrapper["goal"] {
    Object(goal) => goal
    _ => abort("goal must be an object")
  }
  assert_eq(goal.length(), 12)
  for
    key in [
      "schema_version", "goal_id", "session_id", "status", "run_state", "run_id",
      "revision", "current_goal_turn", "continuation_count", "budget", "requirements",
      "convergence",
    ] {
    assert_true(goal.contains(key))
  }
  let budget = match goal["budget"] {
    Object(budget) => budget
    _ => abort("budget must be an object")
  }
  assert_eq(budget.length(), 9)
  for
    key in [
      "token_limit", "turn_limit", "wall_time_limit", "tokens_used", "turns_used",
      "wall_time_used", "tokens_remaining", "turns_remaining", "wall_time_remaining",
    ] {
    assert_true(budget.contains(key))
  }
  let requirements = match goal["requirements"] {
    Object(requirements) => requirements
    _ => abort("requirements summary must be an object")
  }
  assert_eq(requirements.length(), 4)
  for key in ["total", "proven", "unproven", "contested"] {
    assert_true(requirements.contains(key))
  }
}

///|
async test "mooncode_goal_api_internal: lifecycle is exact and durable" {
  @fsx.with_temporary_directory("moonclaw-goal-internal-XXXXXX", async fn(
    root,
  ) {
    let id = "session"
    let journal = mooncode_session_journal_path(root, id)
    goal_gate_write_snapshot(root, id, false, goal_gate_snapshot(id, root))
    let missing = mooncode_goal_api_get_internal(root, id)
    goal_internal_assert_error(missing, 404, "goal_not_found")
    assert_false(@fsx.exists(journal))

    let created = mooncode_goal_api_put_internal(
      root,
      id,
      goal_api_body((7).to_json()),
      9007199254740993L,
    )
    assert_eq(created.status_code, 201)
    goal_internal_assert_redacted(created.body)
    let journal_bytes = @fsx.read_file(journal)
    assert_eq(
      mooncode_replay_goal(root, id).unwrap().created_at,
      9007199254740993L,
    )

    let retry = mooncode_goal_api_put_internal(
      root,
      id,
      goal_api_body((7).to_json()),
      9223372036854775807L,
    )
    assert_eq(retry.status_code, 200)
    assert_eq(retry.body, created.body)
    assert_eq(@fsx.read_file(journal), journal_bytes)

    let fetched = mooncode_goal_api_get_internal(root, id)
    assert_eq(fetched.status_code, 200)
    assert_eq(fetched.body, retry.body)
    assert_eq(@fsx.read_file(journal), journal_bytes)

    let changed = goal_api_body((7).to_json())
    let changed_object = match changed {
      Object(object) => object
      _ => abort("fixture")
    }
    changed_object["objective"] = ("Different" : Json)
    let conflict = mooncode_goal_api_put_internal(root, id, changed, 1L)
    goal_internal_assert_error(conflict, 409, "goal_conflict")
    assert_eq(@fsx.read_file(journal), journal_bytes)
  })
}

///|
async test "mooncode_goal_api_internal: clock and parse failures create no journal" {
  @fsx.with_temporary_directory("moonclaw-goal-errors-XXXXXX", async fn(root) {
    let active = "active"
    goal_gate_write_snapshot(
      root,
      active,
      false,
      goal_gate_snapshot(active, root),
    )
    let clock_body = goal_api_body((7).to_json())
    let clock_object = match clock_body {
      Object(object) => object
      _ => abort("fixture")
    }
    clock_object["session_id"] = active.to_json()
    let clock_error = mooncode_goal_api_put_internal(
      root, active, clock_body, -1L,
    )
    goal_internal_assert_error(clock_error, 500, "goal_clock_out_of_range")
    assert_false(@fsx.exists(mooncode_session_journal_path(root, active)))

    let absent = "absent"
    let malformed = mooncode_goal_api_put_internal(
      root,
      absent,
      ({ "broken": true } : Json),
      0L,
    )
    goal_internal_assert_error(malformed, 400, "invalid_goal_request")
    assert_false(@fsx.exists(mooncode_session_journal_path(root, absent)))
    assert_false(@fsx.exists(goal_gate_dir(root, absent, false)))
  })
}
