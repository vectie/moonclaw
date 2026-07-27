///|
fn goal_adversarial_body_for(id : String, goal : Json) -> Json {
  let body = goal_api_body(goal)
  let fields = match body {
    Object(value) => value
    _ => abort("fixture")
  }
  fields["session_id"] = id.to_json()
  body
}

///|
async test "mooncode_goal_api_internal adversarial matrix: journal directory is immutable corruption" {
  @fsx.with_temporary_directory("moonclaw-goal-journal-directory-XXXXXX", async fn(
    root,
  ) {
    let id = "session"
    goal_gate_write_snapshot(root, id, false, goal_gate_snapshot(id, root))
    let journal = mooncode_session_journal_path(root, id)
    @fsx.make_directory(journal, recursive=true, exists_ok=true)
    let root_count = @fsx.list_directory(root).length()
    let sentinel = @pathx.join(journal, "sentinel")
    @fsx.write_to_file(sentinel, "sentinel-bytes")
    let sentinel_bytes = @fsx.read_file(sentinel)
    let journal_count = @fsx.list_directory(journal).length()
    goal_adversarial_assert_error(
      mooncode_goal_api_get_internal(root, id),
      409,
      "goal_corrupt",
    )
    goal_adversarial_assert_error(
      mooncode_goal_api_put_internal(root, id, goal_api_body((7).to_json()), 1L),
      409,
      "goal_corrupt",
    )
    assert_eq(@fs.kind(journal, follow_symlink=false), @fs.Directory)
    assert_eq(@fsx.read_file(sentinel), sentinel_bytes)
    assert_eq(@fsx.list_directory(root).length(), root_count)
    assert_eq(@fsx.list_directory(journal).length(), journal_count)
  })
}

///|
async test "mooncode_goal_api_internal adversarial matrix: journal symlink and target are immutable corruption" {
  @fsx.with_temporary_directory("moonclaw-goal-journal-symlink-XXXXXX", async fn(
    root,
  ) {
    let id = "session"
    goal_gate_write_snapshot(root, id, false, goal_gate_snapshot(id, root))
    let source = mooncode_session_journal_path(root, id)
    let target_dir = root + "/sentinel"
    @fsx.make_directory(target_dir, recursive=true, exists_ok=true)
    let target = target_dir + "/target"
    let sentinel = "sentinel-target-bytes"
    @fsx.write_to_file(target, sentinel)
    @fs.symlink(target~, source)
    let source_count = @fsx.list_directory(root).length()
    let target_count = @fsx.list_directory(target_dir).length()
    goal_adversarial_assert_error(
      mooncode_goal_api_get_internal(root, id),
      409,
      "goal_corrupt",
    )
    goal_adversarial_assert_error(
      mooncode_goal_api_put_internal(root, id, goal_api_body((7).to_json()), 1L),
      409,
      "goal_corrupt",
    )
    assert_eq(@fs.kind(source, follow_symlink=false), @fs.SymLink)
    assert_eq(@fsx.read_file(target), sentinel)
    assert_eq(@fsx.list_directory(root).length(), source_count)
    assert_eq(@fsx.list_directory(target_dir).length(), target_count)
  })
}

///|
async test "mooncode_goal_api_internal adversarial matrix: missing mismatch and corrupt sessions" {
  @fsx.with_temporary_directory("moonclaw-goal-session-matrix-XXXXXX", async fn(
    root,
  ) {
    let body = goal_api_body((7).to_json())
    goal_adversarial_assert_error(
      mooncode_goal_api_get_internal(root, "session"),
      404,
      "goal_session_not_found",
    )
    goal_adversarial_assert_error(
      mooncode_goal_api_put_internal(root, "session", body, 1L),
      404,
      "goal_session_not_found",
    )
    goal_gate_write_snapshot(
      root,
      "session",
      false,
      goal_gate_snapshot("other", root),
    )
    goal_adversarial_assert_error(
      mooncode_goal_api_get_internal(root, "session"),
      404,
      "goal_session_not_found",
    )
    goal_adversarial_assert_error(
      mooncode_goal_api_put_internal(root, "session", body, 1L),
      404,
      "goal_session_not_found",
    )
    let corrupt = "corrupt"
    let snapshot = mooncode_session_snapshot_path(root, corrupt)
    let snapshot_bytes = "null"
    goal_gate_write_snapshot(root, corrupt, false, Json::null())
    let snapshot_count = @fsx.list_directory(
      goal_gate_dir(root, corrupt, false),
    ).length()
    goal_adversarial_assert_error(
      mooncode_goal_api_get_internal(root, corrupt),
      409,
      "goal_session_corrupt",
    )
    goal_adversarial_assert_error(
      mooncode_goal_api_put_internal(
        root,
        corrupt,
        goal_adversarial_body_for(corrupt, (7).to_json()),
        1L,
      ),
      409,
      "goal_session_corrupt",
    )
    assert_eq(@fsx.read_file(snapshot), snapshot_bytes)
    assert_eq(
      @fsx.list_directory(goal_gate_dir(root, corrupt, false)).length(),
      snapshot_count,
    )
    assert_false(@fsx.exists(mooncode_session_journal_path(root, corrupt)))
  })
}

///|
async test "mooncode_goal_api_internal adversarial matrix: parser wins before session and journal" {
  @fsx.with_temporary_directory("moonclaw-goal-parser-first-XXXXXX", async fn(
    root,
  ) {
    let bad : Json = { "protocol": "wrong" }
    goal_adversarial_assert_error(
      mooncode_goal_api_put_internal(root, "missing", bad, 1L),
      400,
      "invalid_goal_request",
    )
    assert_false(@fsx.exists(mooncode_session_journal_path(root, "missing")))

    let corrupt_snapshot = "corrupt-snapshot"
    let snapshot_path = mooncode_session_snapshot_path(root, corrupt_snapshot)
    let snapshot_bytes = "null"
    goal_gate_write_snapshot(root, corrupt_snapshot, false, Json::null())
    let snapshot_count = @fsx.list_directory(
      goal_gate_dir(root, corrupt_snapshot, false),
    ).length()
    goal_adversarial_assert_error(
      mooncode_goal_api_put_internal(root, corrupt_snapshot, bad, 1L),
      400,
      "invalid_goal_request",
    )
    assert_eq(@fsx.read_file(snapshot_path), snapshot_bytes)
    assert_eq(
      @fsx.list_directory(goal_gate_dir(root, corrupt_snapshot, false)).length(),
      snapshot_count,
    )
    assert_false(
      @fsx.exists(mooncode_session_journal_path(root, corrupt_snapshot)),
    )

    let corrupt_journal = "corrupt-journal"
    let active_snapshot = goal_gate_snapshot(corrupt_journal, root)
    goal_gate_write_snapshot(root, corrupt_journal, false, active_snapshot)
    let journal_path = mooncode_session_journal_path(root, corrupt_journal)
    let journal_bytes = "corrupt-active-journal"
    @fsx.write_to_file(journal_path, journal_bytes)
    let active_dir = goal_gate_dir(root, corrupt_journal, false)
    let journal_count = @fsx.list_directory(active_dir).length()
    goal_adversarial_assert_error(
      mooncode_goal_api_put_internal(root, corrupt_journal, bad, 1L),
      400,
      "invalid_goal_request",
    )
    assert_eq(
      @fsx.read_file(mooncode_session_snapshot_path(root, corrupt_journal)),
      active_snapshot.stringify(),
    )
    assert_eq(@fsx.read_file(journal_path), journal_bytes)
    assert_eq(@fsx.list_directory(active_dir).length(), journal_count)
  })
}

///|
async test "mooncode_goal_api_internal adversarial matrix: exact nested fixture secrets are redacted" {
  @fsx.with_temporary_directory("moonclaw-goal-redaction-XXXXXX", async fn(
    root,
  ) {
    let id = "session"
    goal_gate_write_snapshot(root, id, false, goal_gate_snapshot(id, root))
    let body = goal_api_body((7).to_json())
    let top = match body {
      Object(value) => value
      _ => abort("fixture")
    }
    top["objective"] = ("OBJECTIVE_SECRET_7f3a" : Json)
    let requirements = match top["requirements"] {
      Array(value) => value
      _ => abort("fixture")
    }
    let requirement = match requirements[0] {
      Object(value) => value
      _ => abort("fixture")
    }
    requirement["id"] = ("REQUIREMENT_SECRET_8b4c" : Json)
    requirement["criterion"] = ("CRITERION_SECRET_9d5e" : Json)
    let response = mooncode_goal_api_put_internal(root, id, body, 1L)
    assert_eq(response.status_code, 201)
    let encoded = response.body.stringify()
    for
      secret in [
        "OBJECTIVE_SECRET_7f3a", "REQUIREMENT_SECRET_8b4c", "CRITERION_SECRET_9d5e",
      ] {
      assert_false(encoded.contains(secret))
    }
  })
}
