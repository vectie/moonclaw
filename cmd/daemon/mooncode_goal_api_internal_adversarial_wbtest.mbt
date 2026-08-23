///|
/// Second focused adversarial slice for the internal goal API. These tests deliberately
/// preserve hostile journal bytes and assert parser precedence before any store access.
fn goal_adversarial_assert_error(
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
  let encoded = response.body.stringify()
  for
    field in [
      "objective", "criterion", "evidence", "approval_refs", "seen_ids", "blocker",
    ] {
    assert_false(encoded.contains(field))
  }
}

///|
async test "mooncode_goal_api_internal adversarial: invalid UTF-8 journal is immutable" {
  @fsx.with_temporary_directory("moonclaw-goal-invalid-utf8-XXXXXX", async fn(
    root,
  ) {
    let id = "session"
    goal_gate_write_snapshot(root, id, false, goal_gate_snapshot(id, root))
    let journal = mooncode_session_journal_path(root, id)
    let body = goal_api_body((7).to_json())
    let created = mooncode_goal_api_put_internal(root, id, body, 1L)
    assert_eq(created.status_code, 201)
    @fs.write_file(journal, Bytes::from_array([0xff, 10]))
    let before = @fs.read_file(journal).binary()
    goal_adversarial_assert_error(
      mooncode_goal_api_get_internal(root, id),
      409,
      "goal_corrupt",
    )
    assert_eq(@fs.read_file(journal).binary(), before)
    goal_adversarial_assert_error(
      mooncode_goal_api_put_internal(root, id, body, 1L),
      409,
      "goal_corrupt",
    )
    assert_eq(@fs.read_file(journal).binary(), before)
  })
}

///|
async test "mooncode_goal_api_internal adversarial: complete and unterminated corrupt journals are immutable" {
  @fsx.with_temporary_directory("moonclaw-goal-corrupt-XXXXXX", async fn(root) {
    let id = "session"
    goal_gate_write_snapshot(root, id, false, goal_gate_snapshot(id, root))
    let journal = mooncode_session_journal_path(root, id)
    for bytes in ["not-json\n"] {
      @fsx.write_to_file(journal, bytes)
      let before = @fsx.read_file(journal)
      goal_adversarial_assert_error(
        mooncode_goal_api_get_internal(root, id),
        409,
        "goal_corrupt",
      )
      assert_eq(@fsx.read_file(journal), before)
      goal_adversarial_assert_error(
        mooncode_goal_api_put_internal(
          root,
          id,
          goal_api_body((7).to_json()),
          1L,
        ),
        409,
        "goal_corrupt",
      )
      assert_eq(@fsx.read_file(journal), before)
    }
  })
}

///|
async test "mooncode_goal_api_internal adversarial: sole unterminated genesis is ignored then repaired by PUT" {
  @fsx.with_temporary_directory("moonclaw-goal-tail-XXXXXX", async fn(root) {
    let id = "session"
    goal_gate_write_snapshot(root, id, false, goal_gate_snapshot(id, root))
    let journal = mooncode_session_journal_path(root, id)
    let created = mooncode_goal_api_put_internal(
      root,
      id,
      goal_api_body((7).to_json()),
      1L,
    )
    assert_eq(created.status_code, 201)
    let text = @fsx.read_file(journal)
    let unterminated = text.strip_suffix("\n").unwrap().to_owned()
    @fsx.write_to_file(journal, unterminated)
    let before = @fsx.read_file(journal)
    goal_adversarial_assert_error(
      mooncode_goal_api_get_internal(root, id),
      404,
      "goal_not_found",
    )
    assert_eq(@fsx.read_file(journal), before)
    let recreated = mooncode_goal_api_put_internal(
      root,
      id,
      goal_api_body((7).to_json()),
      1L,
    )
    assert_eq(recreated.status_code, 201)
    assert_true(@fsx.read_file(journal).has_suffix("\n"))
    let fetched = mooncode_goal_api_get_internal(root, id)
    assert_eq(fetched.status_code, 200)
    assert_eq(fetched.body, recreated.body)
  })
}

///|
async test "mooncode_goal_api_internal adversarial: torn suffix after committed goal is ignored and repaired by idempotent PUT" {
  @fsx.with_temporary_directory("moonclaw-goal-torn-tail-XXXXXX", async fn(
    root,
  ) {
    let id = "session"
    goal_gate_write_snapshot(root, id, false, goal_gate_snapshot(id, root))
    let journal = mooncode_session_journal_path(root, id)
    let body = goal_api_body((7).to_json())
    let created = mooncode_goal_api_put_internal(root, id, body, 1L)
    assert_eq(created.status_code, 201)
    let committed = @fsx.read_file(journal)
    let status = created.body
    @fsx.write_to_file(journal, committed + "{\"kind\":")

    let fetched = mooncode_goal_api_get_internal(root, id)
    assert_eq(fetched.status_code, 200)
    assert_eq(fetched.body, status)
    assert_eq(@fsx.read_file(journal), committed + "{\"kind\":")

    let repeated = mooncode_goal_api_put_internal(root, id, body, 1L)
    assert_eq(repeated.status_code, 200)
    assert_eq(repeated.body, status)
    let repaired = @fsx.read_file(journal)
    assert_true(repaired.has_suffix("\n"))
    assert_false(repaired.has_suffix("{\"kind\":"))

    let fetched_again = mooncode_goal_api_get_internal(root, id)
    assert_eq(fetched_again.status_code, 200)
    assert_eq(fetched_again.body, status)
  })
}

///|
async test "mooncode_goal_api_internal adversarial: malformed PUT wins and creates no journal" {
  @fsx.with_temporary_directory("moonclaw-goal-precedence-XXXXXX", async fn(
    root,
  ) {
    let bad : Json = { "protocol": "wrong" }
    let missing_journal = mooncode_session_journal_path(root, "missing")
    goal_adversarial_assert_error(
      mooncode_goal_api_put_internal(root, "missing", bad, 1L),
      400,
      "invalid_goal_request",
    )
    assert_false(@fsx.exists(missing_journal))

    let id = "corrupt"
    goal_gate_write_snapshot(root, id, false, goal_gate_snapshot(id, root))
    let journal = mooncode_session_journal_path(root, id)
    @fsx.write_to_file(journal, "not-json\n")
    let before = @fsx.read_file(journal)
    goal_adversarial_assert_error(
      mooncode_goal_api_put_internal(root, id, bad, 1L),
      400,
      "invalid_goal_request",
    )
    assert_eq(@fsx.read_file(journal), before)
  })
}
