///|
/// Strict parser and session-gate audit ledger:
/// Recovery coverage required here: dot-path rejection, symlink rejection, and exact no-mutation snapshots.
/// These regressions must compare the complete production snapshot before and after every rejected request.
/// - Calls into the persistent session gate are async.
/// - Exact object schemas reject omitted, extension, usage, and client-owned state fields.
/// - Policy: turn_limit is required; null is unbounded None, while exact nonnegative Int32 values are preserved in Some.
/// - Budget and requirements shape failures are tested independently from protocol validity.
/// - Security audit defects: dot aliases and following snapshot/directory symlinks could bypass identity/kind checks.
/// - Evidence audit defect: rejection tests did not prove the active store, fixture bytes/entries, and journal were unchanged.
/// - Recovery history: the first repair turn exhausted its bounded planner after fixing production; a follow-up also exhausted inspection looking for read_link. Direct kind/exists/count APIs now complete the evidence without reading link targets.
fn goal_api_body(turn_limit : Json) -> Json {
  {
    "protocol": "mooncode.v1",
    "session_id": "session",
    "goal_id": "goal",
    "objective": "  Ship it  ",
    "budget": {
      "token_limit": Json::null(),
      "turn_limit": turn_limit,
      "wall_time_limit": Json::null(),
    },
    "requirements": [{ "id": "r1", "criterion": "  passes  " }],
  }
}

///|
fn goal_api_rejected(body : Json, path? : String = "session") -> Bool {
  try {
    ignore(mooncode_parse_goal_put_request(body, path))
    false
  } catch {
    InvalidGoalRequest(_) => true
  }
}

///|
test "mooncode_goal_api: valid limits preserve exact values" {
  let unbounded = mooncode_parse_goal_put_request(
    goal_api_body(Json::null()),
    "session",
  )
  assert_eq(unbounded.budget.turn_limit, None)

  for limit in [0, 7, 2147483647] {
    let request = mooncode_parse_goal_put_request(
      goal_api_body(limit.to_json()),
      "session",
    )
    assert_eq(request.objective, "Ship it")
    assert_eq(request.requirements[0].criterion, "passes")
    assert_eq(request.budget.turn_limit, Some(limit))
    assert_eq(request.budget.tokens_used, 0)
    assert_eq(request.budget.turns_used, 0)
    assert_eq(request.budget.wall_time_used, 0)
    assert_true(request.requirements[0].state == Unproven)
    assert_eq(request.requirements[0].evidence_refs.length(), 0)
  }
}

///|
test "mooncode_goal_api: turn_limit policy rejects invalid values" {
  for
    value in [
      (-1 : Json),
      (1.5 : Json),
      (2147483648 : Json),
      ("7" : Json),
      (true : Json),
    ] {
    assert_true(goal_api_rejected(goal_api_body(value)))
  }
}

///|
test "mooncode_goal_api: isolated container shape rejection" {
  let body = goal_api_body((7).to_json())
  let top = match body {
    Object(top) => top
    _ => abort("fixture")
  }
  top["budget"] = (7 : Json)
  assert_true(goal_api_rejected(body))

  let body = goal_api_body((7).to_json())
  let top = match body {
    Object(top) => top
    _ => abort("fixture")
  }
  top["requirements"] = ({ "id": "r1", "criterion": "ok" } : Json)
  assert_true(goal_api_rejected(body))
}

///|
test "mooncode_goal_api: exact schemas reject client state injection" {
  for field in ["tokens_used", "turns_used", "wall_time_used"] {
    let body = goal_api_body((7).to_json())
    let top = match body {
      Object(top) => top
      _ => abort("fixture")
    }
    top[field] = (0 : Json)
    assert_true(goal_api_rejected(body))

    let body = goal_api_body((7).to_json())
    let top = match body {
      Object(top) => top
      _ => abort("fixture")
    }
    let budget = match top.get("budget") {
      Some(Object(budget)) => budget
      _ => abort("fixture")
    }
    budget[field] = (0 : Json)
    assert_true(goal_api_rejected(body))
  }
  for field in ["state", "evidence", "evidence_refs"] {
    let body = goal_api_body((7).to_json())
    let top = match body {
      Object(top) => top
      _ => abort("fixture")
    }
    let requirements = match top.get("requirements") {
      Some(Array(requirements)) => requirements
      _ => abort("fixture")
    }
    let requirement = match requirements[0] {
      Object(requirement) => requirement
      _ => abort("fixture")
    }
    requirement[field] = Json::null()
    assert_true(goal_api_rejected(body))
  }
}

///|
test "mooncode_goal_api: isolated scalar identity and text rejection" {
  for field in ["session_id", "goal_id", "objective"] {
    let body = goal_api_body((7).to_json())
    let top = match body {
      Object(top) => top
      _ => abort("fixture")
    }
    top[field] = (7 : Json)
    assert_true(goal_api_rejected(body))
  }
  for field in ["id", "criterion"] {
    let body = goal_api_body((7).to_json())
    let top = match body {
      Object(top) => top
      _ => abort("fixture")
    }
    let requirements = match top.get("requirements") {
      Some(Array(requirements)) => requirements
      _ => abort("fixture")
    }
    let requirement = match requirements[0] {
      Object(requirement) => requirement
      _ => abort("fixture")
    }
    requirement[field] = (7 : Json)
    assert_true(goal_api_rejected(body))
  }
  for value in ["", " session", "session "] {
    let body = goal_api_body((7).to_json())
    let top = match body {
      Object(top) => top
      _ => abort("fixture")
    }
    top["session_id"] = value.to_json()
    assert_true(goal_api_rejected(body, path=value))
  }
  for value in ["", " r1", "r1 "] {
    let body = goal_api_body((7).to_json())
    let top = match body {
      Object(top) => top
      _ => abort("fixture")
    }
    let requirements = match top.get("requirements") {
      Some(Array(requirements)) => requirements
      _ => abort("fixture")
    }
    let requirement = match requirements[0] {
      Object(requirement) => requirement
      _ => abort("fixture")
    }
    requirement["id"] = value.to_json()
    assert_true(goal_api_rejected(body))
  }
}

///|
test "mooncode_goal_api: every budget key is required" {
  for field in ["token_limit", "turn_limit", "wall_time_limit"] {
    let body = goal_api_body((7).to_json())
    let top = match body {
      Object(top) => top
      _ => abort("fixture")
    }
    let budget = match top.get("budget") {
      Some(Object(budget)) => budget
      _ => abort("fixture")
    }
    budget.remove(field)
    assert_true(goal_api_rejected(body))
  }
}

///|
fn goal_gate_snapshot(session_id : String, root : String) -> Json {
  let binding = MoonCodeSessionBinding::{
    session_id,
    book_root: root,
    workspace_id: "book-code-lab",
    workspace_name: "Code Lab",
    model: "",
    command_count: 2,
    first_user_prompt: "Build a durable MoonCode tool",
    custom_title: "",
    last_command_id: "cmd-2",
    last_updated: @clock.Timestamp::from_ms(42L),
    runtime_service_running: false,
    runtime_service_task: None,
    active_command_id: "",
    events: @broadcast.Broadcast::new(),
  }
  mooncode_session_snapshot(binding)
}

///|
fn goal_gate_dir(root : String, id : String, archived : Bool) -> String {
  mooncode_session_dir_by_safe_id(root, mooncode_safe_session_id(id), archived~)
}

///|
async fn goal_gate_write_snapshot(
  root : String,
  id : String,
  archived : Bool,
  snapshot : Json,
) -> Unit {
  let dir = goal_gate_dir(root, id, archived)
  @fsx.make_directory(dir, recursive=true, exists_ok=true)
  @fsx.write_to_file(dir + "/session.json", snapshot.stringify())
}

///|
async fn goal_gate_path_observation(path : String) -> (Bool, Int) {
  let exists = @fsx.exists(path)
  let count = if exists { @fsx.list_directory(path).length() } else { 0 }
  (exists, count)
}

///|
async fn assert_goal_gate_path_observation(
  path : String,
  before : (Bool, Int),
) -> Unit {
  assert_eq(@fsx.exists(path), before.0)
  if before.0 {
    assert_eq(@fsx.list_directory(path).length(), before.1)
  }
}

///|
async test "mooncode_goal_api: active session gate validates exact snapshot identity" {
  @fsx.with_temporary_directory("moonclaw-goal-gate-XXXXXX", async fn(root) {
    let id = "exact-session"
    goal_gate_write_snapshot(root, id, false, goal_gate_snapshot(id, root))
    assert_eq(mooncode_goal_require_active_session(id, root), root)
  })
}

///|
async test "mooncode_goal_api: dot aliases reject without storage" {
  @fsx.with_temporary_directory("moonclaw-goal-dot-aliases-XXXXXX", async fn(
    root,
  ) {
    for session_id in [".", ".."] {
      try {
        ignore(mooncode_goal_require_active_session(session_id, root))
        abort("expected invalid goal session query")
      } catch {
        InvalidGoalSessionQuery => ()
        _ => abort("unexpected goal session query error")
      }
      assert_false(@fsx.exists(mooncode_session_journal_path(root, session_id)))
    }
    assert_false(@fsx.exists(mooncode_sessions_root(root)))
  })
}

///|
async test "mooncode_goal_api: active session gate rejects invalid query without writes" {
  @fsx.with_temporary_directory("moonclaw-goal-gate-XXXXXX", async fn(root) {
    let sentinel = root + "/sentinel"
    @fsx.write_to_file(sentinel, "unchanged")
    for pair in [("", root), (" padded ", root), ("id", ""), ("id", " " + root)] {
      let sessions_root = mooncode_sessions_root(pair.1)
      let before = goal_gate_path_observation(sessions_root)
      try {
        ignore(mooncode_goal_require_active_session(pair.0, pair.1))
        abort("gate accepted invalid query")
      } catch {
        InvalidGoalSessionQuery => ()
        _ => abort("wrong gate error")
      }
      assert_goal_gate_path_observation(sessions_root, before)
    }
    assert_true(@fsx.exists(sentinel))
    assert_eq(@fsx.read_file(sentinel), "unchanged")
    assert_false(@fsx.exists(mooncode_sessions_root(root)))
    assert_false(@fsx.exists(mooncode_session_journal_path(root, "id")))
  })
}

///|
async fn goal_gate_assert_fixture_unchanged(
  root : String,
  id : String,
  archived : Bool,
  expected_count : Int,
  expected_bytes : String,
) -> Unit {
  let dir = goal_gate_dir(root, id, archived)
  let entries = @fsx.list_directory(dir)
  assert_eq(entries.length(), expected_count)
  assert_eq(@fsx.read_file(dir + "/session.json"), expected_bytes)
  assert_false(@fsx.exists(mooncode_session_journal_path(root, id)))
}

///|
async test "mooncode_goal_api: active session gate rejects absent archived and missing file" {
  @fsx.with_temporary_directory("moonclaw-goal-gate-XXXXXX", async fn(root) {
    let id = "absent"
    try {
      ignore(mooncode_goal_require_active_session(id, root))
      abort("accepted absent session")
    } catch {
      GoalSessionAbsentOrMismatch => ()
      _ => abort("wrong gate error")
    }
    assert_false(@fsx.exists(mooncode_sessions_root(root)))
    assert_false(@fsx.exists(mooncode_session_journal_path(root, id)))
    goal_gate_write_snapshot(root, id, true, goal_gate_snapshot(id, root))
    let archived_dir = goal_gate_dir(root, id, true)
    let archived_bytes = @fsx.read_file(archived_dir + "/session.json")
    let archived_count = @fsx.list_directory(archived_dir).length()
    try {
      ignore(mooncode_goal_require_active_session(id, root))
      abort("accepted archived session")
    } catch {
      GoalSessionAbsentOrMismatch => ()
      _ => abort("wrong gate error")
    }
    goal_gate_assert_fixture_unchanged(
      root, id, true, archived_count, archived_bytes,
    )
    assert_false(@fsx.exists(mooncode_sessions_root(root)))
    let active = goal_gate_dir(root, id, false)
    @fsx.make_directory(active, recursive=true, exists_ok=true)
    assert_eq(@fsx.list_directory(active).length(), 0)
    try {
      ignore(mooncode_goal_require_active_session(id, root))
      abort("accepted missing snapshot")
    } catch {
      GoalSessionAbsentOrMismatch => ()
      _ => abort("wrong gate error")
    }
    assert_eq(@fsx.list_directory(active).length(), 0)
    assert_false(@fsx.exists(mooncode_session_journal_path(root, id)))
  })
}

///|
async test "mooncode_goal_api: active session gate distinguishes corrupt snapshot" {
  @fsx.with_temporary_directory("moonclaw-goal-gate-XXXXXX", async fn(root) {
    let id = "corrupt"
    let dir = goal_gate_dir(root, id, false)
    @fsx.make_directory(dir, recursive=true, exists_ok=true)
    let fixture_path = dir + "/session.json"
    let invalid = "{\"broken\":"
    let parse_failed = try {
      ignore(@json.parse(invalid))
      false
    } catch {
      _ => true
    }
    assert_true(parse_failed)
    @fsx.write_to_file(fixture_path, invalid)
    let before_count = @fsx.list_directory(dir).length()
    assert_true(@fsx.read_file(fixture_path) == invalid)
    assert_true(@fsx.exists(dir))
    assert_true(@fsx.exists(fixture_path))
    assert_true(@fs.kind(dir, follow_symlink=false) == Directory)
    assert_true(@fs.kind(fixture_path, follow_symlink=false) == Regular)
    try {
      ignore(mooncode_goal_require_active_session(id, root))
      abort("accepted corrupt snapshot")
    } catch {
      GoalSessionCorrupt => ()
      _ => abort("wrong gate error")
    }
    goal_gate_assert_fixture_unchanged(root, id, false, before_count, invalid)
  })
}

///|
async test "mooncode_goal_api: active session gate rejects every identity mismatch" {
  @fsx.with_temporary_directory("moonclaw-goal-gate-XXXXXX", async fn(root) {
    let id = "identity"
    for
      pair in [
        ("kind", "wrong"),
        ("protocol", "wrong"),
        ("owner", "wrong"),
        ("session_id", "wrong"),
        ("book_root", root + "/wrong"),
      ] {
      let snapshot = goal_gate_snapshot(id, root)
      let object = match snapshot {
        Object(object) => object
        _ => abort("fixture")
      }
      object[pair.0] = pair.1.to_json()
      goal_gate_write_snapshot(root, id, false, snapshot)
      let dir = goal_gate_dir(root, id, false)
      let before_bytes = @fsx.read_file(dir + "/session.json")
      let before_count = @fsx.list_directory(dir).length()
      try {
        ignore(mooncode_goal_require_active_session(id, root))
        abort("accepted identity mismatch")
      } catch {
        GoalSessionAbsentOrMismatch => ()
        _ => abort("wrong gate error")
      }
      goal_gate_assert_fixture_unchanged(
        root, id, false, before_count, before_bytes,
      )
    }
  })
}

///|
async test "mooncode_goal_api: active directory and snapshot dangling symlinks are read-only corruption" {
  @fsx.with_temporary_directory("moonclaw-goal-dangling-XXXXXX", async fn(
    root,
  ) {
    for pair in [("dangling-dir", true), ("dangling-file", false)] {
      let id = pair.0
      let active = goal_gate_dir(root, id, false)
      let container = if pair.1 { mooncode_sessions_root(root) } else { active }
      @fsx.make_directory(container, recursive=true, exists_ok=true)
      let missing_path = root + "/missing-" + id
      let link_path = if pair.1 { active } else { active + "/session.json" }
      @fs.symlink(target=missing_path, link_path)
      assert_eq(@fs.kind(link_path, follow_symlink=false), SymLink)
      assert_false(@fsx.exists(missing_path))
      let count = @fsx.list_directory(container).length()
      try {
        ignore(mooncode_goal_require_active_session(id, root))
        abort("dangling symlink must be corrupt")
      } catch {
        GoalSessionCorrupt => ()
        _ => abort("unexpected dangling symlink error")
      }
      assert_eq(@fsx.list_directory(container).length(), count)
      assert_eq(@fs.kind(link_path, follow_symlink=false), SymLink)
      assert_false(@fsx.exists(missing_path))
      assert_false(@fsx.exists(mooncode_session_journal_path(root, id)))
    }
  })
}

///|
async test "mooncode_goal_api: active session gate rejects snapshot and directory symlinks" {
  @fsx.with_temporary_directory("moonclaw-goal-symlink-XXXXXX", async fn(root) {
    let snapshot_id = "snapshot-link"
    let archived_snapshot_path = goal_gate_dir(root, snapshot_id, true) +
      "/session.json"
    goal_gate_write_snapshot(
      root,
      snapshot_id,
      true,
      goal_gate_snapshot(snapshot_id, root),
    )
    let archived_snapshot_bytes = @fsx.read_file(archived_snapshot_path)
    let active_dir = goal_gate_dir(root, snapshot_id, false)
    @fsx.make_directory(active_dir, recursive=true, exists_ok=true)
    let active_snapshot_path = active_dir + "/session.json"
    @fs.symlink(target=archived_snapshot_path, active_snapshot_path)
    assert_eq(@fs.kind(active_snapshot_path, follow_symlink=false), SymLink)
    let active_snapshot_count = @fsx.list_directory(active_dir).length()
    let archived_snapshot_count = @fsx.list_directory(
      goal_gate_dir(root, snapshot_id, true),
    ).length()
    try {
      goal_gate_snapshot(snapshot_id, root) |> ignore
      ignore(mooncode_goal_require_active_session(snapshot_id, root))
      abort("snapshot symlink must be corrupt")
    } catch {
      GoalSessionCorrupt => ()
      _ => abort("unexpected snapshot symlink error")
    }
    assert_eq(@fsx.read_file(archived_snapshot_path), archived_snapshot_bytes)
    assert_eq(@fsx.list_directory(active_dir).length(), active_snapshot_count)
    assert_eq(
      @fsx.list_directory(goal_gate_dir(root, snapshot_id, true)).length(),
      archived_snapshot_count,
    )
    assert_eq(@fs.kind(active_snapshot_path, follow_symlink=false), SymLink)
    assert_false(@fsx.exists(mooncode_session_journal_path(root, snapshot_id)))

    let directory_id = "directory-link"
    let archived_dir = goal_gate_dir(root, directory_id, true)
    let archived_directory_snapshot_path = archived_dir + "/session.json"
    goal_gate_write_snapshot(
      root,
      directory_id,
      true,
      goal_gate_snapshot(directory_id, root),
    )
    let archived_directory_snapshot_bytes = @fsx.read_file(
      archived_directory_snapshot_path,
    )
    let active_directory = goal_gate_dir(root, directory_id, false)
    @fsx.make_directory(
      mooncode_sessions_root(root),
      recursive=true,
      exists_ok=true,
    )
    @fs.symlink(target=archived_dir, active_directory)
    assert_eq(@fs.kind(active_directory, follow_symlink=false), SymLink)
    let active_parent = mooncode_sessions_root(root)
    let active_directory_count = @fsx.list_directory(active_parent).length()
    let archived_directory_count = @fsx.list_directory(archived_dir).length()
    try {
      ignore(mooncode_goal_require_active_session(directory_id, root))
      abort("directory symlink must be corrupt")
    } catch {
      GoalSessionCorrupt => ()
      _ => abort("unexpected directory symlink error")
    }
    assert_eq(
      @fsx.read_file(archived_directory_snapshot_path),
      archived_directory_snapshot_bytes,
    )
    assert_eq(
      @fsx.list_directory(active_parent).length(),
      active_directory_count,
    )
    assert_eq(
      @fsx.list_directory(archived_dir).length(),
      archived_directory_count,
    )
    assert_eq(@fs.kind(active_directory, follow_symlink=false), SymLink)
    assert_false(@fsx.exists(mooncode_session_journal_path(root, directory_id)))
  })
}

///|
async test "mooncode_goal_api: safe id collision requires exact requested identity" {
  @fsx.with_temporary_directory("moonclaw-goal-gate-XXXXXX", async fn(root) {
    let requested = "a/b"
    let collision = "a:b"
    assert_eq(
      mooncode_safe_session_id(requested),
      mooncode_safe_session_id(collision),
    )
    goal_gate_write_snapshot(
      root,
      requested,
      false,
      goal_gate_snapshot(collision, root),
    )
    let dir = goal_gate_dir(root, requested, false)
    let before_bytes = @fsx.read_file(dir + "/session.json")
    let before_count = @fsx.list_directory(dir).length()
    try {
      ignore(mooncode_goal_require_active_session(requested, root))
      abort("accepted safe-id collision")
    } catch {
      GoalSessionAbsentOrMismatch => ()
      _ => abort("wrong gate error")
    }
    goal_gate_assert_fixture_unchanged(
      root, requested, false, before_count, before_bytes,
    )
  })
}
