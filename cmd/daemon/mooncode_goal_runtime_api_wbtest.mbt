///|
fn goal_runtime_test_body(session_id : String) -> Json {
  {
    "protocol": "mooncode.v1",
    "contract": "mooncode-goal-runtime.v1",
    "session_id": session_id,
    "goal_id": "goal-runtime",
    "objective": "Continue until the criteria are proven",
    "criteria": [
      { "id": "criterion-1", "criterion": "native proof exists" },
      { "id": "criterion-2", "criterion": "tests pass" },
    ],
  }
}

///|
fn goal_runtime_test_error(
  response : MoonCodeGoalRuntimeApiResponse,
  status : Int,
  code : String,
) -> Unit raise {
  assert_eq(response.status_code, status)
  let body = match response.body {
    Object(body) => body
    _ => abort("runtime error must be object")
  }
  assert_eq(body.length(), 5)
  assert_eq(body["kind"], ("mooncode-goal-runtime-error" : Json))
  assert_eq(body["protocol"], ("mooncode.v1" : Json))
  assert_eq(body["owner"], ("moonclaw" : Json))
  assert_eq(body["contract"], ("mooncode-goal-runtime.v1" : Json))
  assert_eq(body["error"], code.to_json())
}

///|
test "goal-runtime request is strict and rejects aggregate policy" {
  let parsed = mooncode_goal_runtime_parse_put_request(
    goal_runtime_test_body("session"),
    "session",
  )
  assert_eq(parsed.session_id, "session")
  assert_eq(parsed.criteria.length(), 2)
  for
    field in [
      "max_turns", "token_budget", "deadline", "planner_max_steps", "max_loc", "max_operations",
    ] {
    let body = goal_runtime_test_body("session")
    guard body is Object(fields) else { abort("fixture") }
    fields[field] = 1
    let rejected = try {
      ignore(mooncode_goal_runtime_parse_put_request(body, "session"))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
}

///|
test "goal-runtime HTTP route is exact" {
  let path = ["", "v1", "code", "sessions", "session", "goal-runtime"]
  assert_true(mooncode_goal_runtime_http_route("GET", path) is GoalRuntimeGet)
  assert_true(mooncode_goal_runtime_http_route("PUT", path) is GoalRuntimePut)
  assert_true(
    mooncode_goal_runtime_http_route("POST", path)
    is GoalRuntimeMethodNotAllowed,
  )
  assert_true(
    mooncode_goal_runtime_http_route("GET", [
      "", "v1", "code", "sessions", "session", "goal-runtime", "",
    ])
    is NotGoalRuntimeRoute,
  )
  assert_eq(mooncode_goal_runtime_http_allow(), "GET, PUT")
}

///|
async test "goal-runtime create retry read and conflict are durable" {
  @fsx.with_temporary_directory("moonclaw-goal-runtime-api-XXXXXX", async fn(
    root,
  ) {
    let id = "session"
    goal_gate_write_snapshot(root, id, false, goal_gate_snapshot(id, root))
    goal_runtime_test_error(
      mooncode_goal_runtime_api_get_internal(root, id),
      404,
      "goal_runtime_not_found",
    )
    let body = goal_runtime_test_body(id)
    let created = mooncode_goal_runtime_api_put_internal(root, id, body, 7L)
    assert_eq(created.status_code, 201)
    guard created.body is Object(created_body) else { abort("status") }
    assert_eq(created_body.length(), 9)
    assert_eq(created_body["cursor"], ("1" : Json))
    guard created_body["status"] is Object(status) else { abort("status") }
    assert_eq(status["terminal"], false)
    assert_eq(status["handled_count"], 0)
    let journal = mooncode_session_journal_path(root, id)
    let bytes = @fsx.read_file(journal)
    let retry = mooncode_goal_runtime_api_put_internal(root, id, body, 99L)
    assert_eq(retry.status_code, 200)
    assert_eq(retry.body, created.body)
    assert_eq(@fsx.read_file(journal), bytes)
    let fetched = mooncode_goal_runtime_api_get_internal(root, id)
    assert_eq(fetched.status_code, 200)
    assert_eq(fetched.body, created.body)
    let changed = goal_runtime_test_body(id)
    guard changed is Object(fields) else { abort("fixture") }
    fields["objective"] = ("different objective" : Json)
    goal_runtime_test_error(
      mooncode_goal_runtime_api_put_internal(root, id, changed, 100L),
      409,
      "goal_runtime_conflict",
    )
    assert_eq(@fsx.read_file(journal), bytes)
  })
}

///|
async test "legacy authority excludes goal-runtime creation" {
  @fsx.with_temporary_directory("moonclaw-goal-authority-legacy-XXXXXX", async fn(
    root,
  ) {
    let id = "session"
    goal_gate_write_snapshot(root, id, false, goal_gate_snapshot(id, root))
    assert_eq(
      mooncode_goal_api_put_internal(root, id, goal_api_body((7).to_json()), 1L).status_code,
      201,
    )
    let before = @fsx.read_file(mooncode_session_journal_path(root, id))
    goal_runtime_test_error(
      mooncode_goal_runtime_api_put_internal(
        root,
        id,
        goal_runtime_test_body(id),
        2L,
      ),
      409,
      "legacy_goal_incompatible",
    )
    assert_eq(@fsx.read_file(mooncode_session_journal_path(root, id)), before)
  })
}

///|
async test "goal-runtime authority excludes legacy creation" {
  @fsx.with_temporary_directory("moonclaw-goal-authority-runtime-XXXXXX", async fn(
    root,
  ) {
    let id = "session"
    goal_gate_write_snapshot(root, id, false, goal_gate_snapshot(id, root))
    assert_eq(
      mooncode_goal_runtime_api_put_internal(
        root,
        id,
        goal_runtime_test_body(id),
        1L,
      ).status_code,
      201,
    )
    let before = @fsx.read_file(mooncode_session_journal_path(root, id))
    let legacy = mooncode_goal_api_put_internal(
      root,
      id,
      goal_api_body((7).to_json()),
      2L,
    )
    assert_eq(legacy.status_code, 409)
    guard legacy.body is Object(error) else { abort("legacy error") }
    assert_eq(error["error"], ("goal_authority_conflict" : Json))
    assert_eq(@fsx.read_file(mooncode_session_journal_path(root, id)), before)
  })
}

///|
async test "goal-runtime validates request before absent session" {
  @fsx.with_temporary_directory("moonclaw-goal-runtime-precedence-XXXXXX", async fn(
    root,
  ) {
    goal_runtime_test_error(
      mooncode_goal_runtime_api_put_internal(
        root,
        "missing",
        ({ "max_turns": 1 } : Json),
        1L,
      ),
      400,
      "invalid_goal_runtime_request",
    )
    assert_false(@fsx.exists(mooncode_session_journal_path(root, "missing")))
  })
}

///|
async test "concurrent legacy and runtime creation choose exactly one authority" {
  @fsx.with_temporary_directory("moonclaw-goal-authority-race-XXXXXX", async fn(
    root,
  ) {
    let id = "session"
    goal_gate_write_snapshot(root, id, false, goal_gate_snapshot(id, root))
    @async.with_task_group(group => {
      let legacy_task = group.spawn(() => {
        mooncode_goal_api_put_internal(
          root,
          id,
          goal_api_body((7).to_json()),
          1L,
        )
      })
      let runtime_task = group.spawn(() => {
        mooncode_goal_runtime_api_put_internal(
          root,
          id,
          goal_runtime_test_body(id),
          1L,
        )
      })
      let legacy = legacy_task.wait()
      let runtime = runtime_task.wait()
      let created = (if legacy.status_code == 201 { 1 } else { 0 }) +
        (if runtime.status_code == 201 { 1 } else { 0 })
      let conflicted = (if legacy.status_code == 409 { 1 } else { 0 }) +
        (if runtime.status_code == 409 { 1 } else { 0 })
      assert_eq(created, 1)
      assert_eq(conflicted, 1)
    })
    let records = mooncode_read_session_journal(root, id)
    let authority = mooncode_goal_authority_snapshot(records, id)
    assert_false(mooncode_goal_authority_is_dual(authority))
    assert_true(
      (authority.legacy is Some(_)) != (authority.runtime.genesis is Some(_)),
    )
  })
}

///|
async test "handcrafted dual authority fails closed on both reads" {
  @fsx.with_temporary_directory("moonclaw-goal-authority-dual-XXXXXX", async fn(
    root,
  ) {
    let id = "session"
    goal_gate_write_snapshot(root, id, false, goal_gate_snapshot(id, root))
    assert_eq(
      mooncode_goal_api_put_internal(root, id, goal_api_body((7).to_json()), 1L).status_code,
      201,
    )
    let genesis = new_mooncode_goal_runtime_genesis(
      id,
      "goal-runtime",
      "Continue until the criteria are proven",
      [
        { id: "criterion-1", criterion: "native proof exists" },
        { id: "criterion-2", criterion: "tests pass" },
      ],
      2L,
    )
    let carrier = mooncode_goal_runtime_carrier_from_genesis(
      encode_mooncode_goal_runtime_genesis(genesis),
    )
    assert_true(
      mooncode_append_session_journal_once(
        root,
        id,
        mooncode_journal_event(),
        encode_mooncode_goal_runtime_carrier(carrier),
      ),
    )
    let legacy = mooncode_goal_api_get_internal(root, id)
    assert_eq(legacy.status_code, 409)
    guard legacy.body is Object(legacy_error) else { abort("legacy error") }
    assert_eq(legacy_error["error"], ("goal_authority_conflict" : Json))
    goal_runtime_test_error(
      mooncode_goal_runtime_api_get_internal(root, id),
      409,
      "goal_authority_conflict",
    )
  })
}

///|
fn goal_runtime_test_carrier_record(
  carrier : MoonCodeGoalRuntimeCarrier,
  sequence : Int,
) -> Json raise {
  scan_test_record(carrier, sequence)
}

///|
fn goal_runtime_test_status_rejected(records : Array[Json]) -> Bool {
  try {
    let scan = mooncode_goal_runtime_scan_records(records, "session-你好")
    ignore(mooncode_goal_runtime_status_response(scan))
    false
  } catch {
    MoonCodeGoalRuntimeStoreError::CorruptStore(_) => true
    MoonCodeGoalRuntimeStoreError::IdentityConflict(_, _, _) => true
    _ => false
  }
}

///|
test "runtime status rejects achieved evidence missing a genesis criterion" {
  let genesis = new_mooncode_goal_runtime_genesis(
    "session-你好",
    "goal-1",
    "objective",
    [
      { id: "criterion-1", criterion: "first" },
      { id: "criterion-2", criterion: "second" },
    ],
    1L,
  )
  let achieved = new_mooncode_goal_runtime_stored_event(
    "session-你好",
    "goal-1",
    PlannerDecision(
      "event-achieved",
      Achieved("done", [
        { criterion: "criterion-1", evidence_refs: ["proof-1"] },
      ]),
    ),
    2L,
  )
  assert_true(
    goal_runtime_test_status_rejected([
      goal_runtime_test_carrier_record(
        mooncode_goal_runtime_carrier_from_genesis(
          encode_mooncode_goal_runtime_genesis(genesis),
        ),
        1,
      ),
      goal_runtime_test_carrier_record(
        mooncode_goal_runtime_carrier_from_event(
          encode_mooncode_goal_runtime_stored_event(achieved),
        ),
        2,
      ),
    ]),
  )
}

///|
test "runtime status rejects a unique event after terminal settlement" {
  let genesis = scan_test_genesis(1L)
  let cancelled = new_mooncode_goal_runtime_stored_event(
    "session-你好",
    "goal-1",
    Cancelled("event-cancelled", "operator cancelled"),
    2L,
  )
  let after = new_mooncode_goal_runtime_stored_event(
    "session-你好",
    "goal-1",
    PhaseChanged("event-after", Running),
    3L,
  )
  assert_true(
    goal_runtime_test_status_rejected([
      goal_runtime_test_carrier_record(
        mooncode_goal_runtime_carrier_from_genesis(
          encode_mooncode_goal_runtime_genesis(genesis),
        ),
        1,
      ),
      goal_runtime_test_carrier_record(
        mooncode_goal_runtime_carrier_from_event(
          encode_mooncode_goal_runtime_stored_event(cancelled),
        ),
        2,
      ),
      goal_runtime_test_carrier_record(
        mooncode_goal_runtime_carrier_from_event(
          encode_mooncode_goal_runtime_stored_event(after),
        ),
        3,
      ),
    ]),
  )
}
