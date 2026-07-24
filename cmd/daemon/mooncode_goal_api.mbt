///|
/// Canonical, parser-only representation of a strict goal PUT request.
priv struct MoonCodeGoalPutRequest {
  session_id : String
  goal_id : String
  objective : String
  budget : @mooncode_core.GoalBudget
  requirements : Array[@mooncode_core.GoalRequirement]
}

///|
priv suberror InvalidGoalRequest {
  InvalidGoalRequest(String)
}

///|
/// Internal transport-neutral result used by the strict durable goal API.
/// Keeping this type private prevents this slice from declaring HTTP routes or endpoints.
priv struct MoonCodeGoalApiResponse {
  status_code : Int
  body : Json
}

///|
fn goal_api_response(status_code : Int, body : Json) -> MoonCodeGoalApiResponse {
  { status_code, body }
}

///|
fn goal_api_error(status_code : Int, code : String) -> MoonCodeGoalApiResponse {
  goal_api_response(status_code, {
    "kind": "mooncode-goal-error",
    "protocol": "mooncode.v1",
    "owner": "moonclaw",
    "error": code,
  })
}

///|
fn goal_api_status(goal : @mooncode_core.Goal) -> MoonCodeGoalApiResponse {
  goal_api_response(200, {
    "kind": "mooncode-goal-status",
    "protocol": "mooncode.v1",
    "owner": "moonclaw",
    "goal": @mooncode_core.goal_status_json(goal),
  })
}

///|
fn goal_api_created(goal : @mooncode_core.Goal) -> MoonCodeGoalApiResponse {
  let response = goal_api_status(goal)
  { status_code: 201, body: response.body }
}

///|
fn goal_api_checked_epoch_seconds(value : Int64) -> Int? {
  if value < 0L || value > 2147483647L {
    None
  } else {
    Some(value.to_int())
  }
}

///|
fn goal_api_fail(message : String) -> Unit raise InvalidGoalRequest {
  raise InvalidGoalRequest(message)
}

///|
fn goal_api_exact_object(
  json : Json,
  fields : Array[String],
  level : String,
) -> Map[String, Json] raise InvalidGoalRequest {
  match json {
    Object(object) => {
      if object.length() != fields.length() {
        goal_api_fail("invalid " + level + " fields")
      }
      for field in fields {
        if object.get(field) is None {
          goal_api_fail("invalid " + level + " fields")
        }
      }
      object
    }
    _ => {
      goal_api_fail(level + " must be an object")
      Map([])
    }
  }
}

///|
fn goal_api_string(
  object : Map[String, Json],
  field : String,
) -> String raise InvalidGoalRequest {
  match object.get(field) {
    Some(String(value)) => value
    _ => {
      goal_api_fail("invalid " + field)
      ""
    }
  }
}

///|
fn goal_api_id(
  value : String,
  field : String,
) -> String raise InvalidGoalRequest {
  if value.is_empty() || value.trim() != value {
    goal_api_fail("invalid " + field)
  }
  value
}

///|
fn goal_api_text(
  value : String,
  field : String,
) -> String raise InvalidGoalRequest {
  let value = value.trim()
  if value.is_empty() {
    goal_api_fail("invalid " + field)
  }
  value.to_string()
}

///|
fn goal_api_turn_limit(json : Json) -> Int? raise InvalidGoalRequest {
  match json {
    Null => None
    Number(value, ..) => {
      let parsed = goal_checked_int(value, "turn_limit") catch {
        _ => {
          goal_api_fail("invalid turn_limit")
          0
        }
      }
      if parsed < 0 {
        goal_api_fail("invalid turn_limit")
      }
      Some(parsed)
    }
    _ => {
      goal_api_fail("invalid turn_limit")
      None
    }
  }
}

///|
fn mooncode_parse_goal_put_request(
  body : Json,
  path_session_id : String,
) -> MoonCodeGoalPutRequest raise InvalidGoalRequest {
  try {
    let top = goal_api_exact_object(
      body,
      [
        "protocol", "session_id", "goal_id", "objective", "budget", "requirements",
      ],
      "request",
    )
    if goal_api_string(top, "protocol") != mooncode_protocol_version() {
      goal_api_fail("unsupported protocol")
    }
    let session_id = goal_api_id(
      goal_api_string(top, "session_id"),
      "session_id",
    )
    if session_id != path_session_id {
      goal_api_fail("session mismatch")
    }
    let goal_id = goal_api_id(goal_api_string(top, "goal_id"), "goal_id")
    let objective = goal_api_text(
      goal_api_string(top, "objective"),
      "objective",
    )
    let budget_json = match top.get("budget") {
      Some(v) => v
      None => Json::null()
    }
    let budget_object = goal_api_exact_object(
      budget_json,
      ["token_limit", "turn_limit", "wall_time_limit"],
      "budget",
    )
    match budget_object.get("token_limit") {
      Some(Null) => ()
      _ => goal_api_fail("token_limit must be null")
    }
    match budget_object.get("wall_time_limit") {
      Some(Null) => ()
      _ => goal_api_fail("wall_time_limit must be null")
    }
    let turn_limit = match budget_object.get("turn_limit") {
      Some(value) => goal_api_turn_limit(value)
      None => {
        goal_api_fail("invalid budget fields")
        None
      }
    }
    let items = match top.get("requirements") {
      Some(Array(items)) => items
      _ => {
        goal_api_fail("requirements must be an array")
        []
      }
    }
    if items.is_empty() {
      goal_api_fail("requirements must be nonempty")
    }
    let requirements : Array[@mooncode_core.GoalRequirement] = []
    let seen : Map[String, Bool] = Map([])
    for item in items {
      let requirement = goal_api_exact_object(
        item,
        ["id", "criterion"],
        "requirement",
      )
      let id = goal_api_id(goal_api_string(requirement, "id"), "requirement id")
      if seen.contains(id) {
        goal_api_fail("duplicate requirement id")
      }
      seen[id] = true
      requirements.push({
        id,
        criterion: goal_api_text(
          goal_api_string(requirement, "criterion"),
          "criterion",
        ),
        state: @mooncode_core.Unproven,
        evidence_refs: [],
      })
    }
    {
      session_id,
      goal_id,
      objective,
      budget: {
        token_limit: None,
        turn_limit,
        wall_time_limit: None,
        tokens_used: 0,
        turns_used: 0,
        wall_time_used: 0,
      },
      requirements,
    }
  } catch {
    InvalidGoalRequest(message) => raise InvalidGoalRequest(message)
    _ => raise InvalidGoalRequest("invalid goal request")
  }
}

///|
/// Value-free failures from the read-only durable-session gate.
priv suberror MoonCodeGoalSessionGateError {
  InvalidGoalSessionQuery
  GoalSessionAbsentOrMismatch
  GoalSessionCorrupt
}

///|
/// Validate an active durable session without invoking the binding or general
/// snapshot loaders. The returned root is the exact, canonical query root.
async fn mooncode_goal_require_active_session(
  session_id : String,
  book_root : String,
) -> String raise MoonCodeGoalSessionGateError {
  if session_id.is_empty() ||
    session_id.trim() != session_id ||
    book_root.is_empty() ||
    book_root.trim() != book_root {
    raise InvalidGoalSessionQuery
  }
  let safe_id = mooncode_safe_session_id(session_id)
  // Security boundary: reject dot aliases and any derived name that is not one
  // canonical path component before deriving a durable-session path.
  if session_id == "." ||
    session_id == ".." ||
    safe_id == "." ||
    safe_id == ".." ||
    @pathx.basename(safe_id) != safe_id {
    raise InvalidGoalSessionQuery
  }
  let session_dir = mooncode_session_dir_by_safe_id(
    book_root,
    safe_id,
    archived=false,
  )
  let snapshot_path = session_dir + "/session.json"
  // Non-following async kind probes map only genuine ENOENT to absence; every
  // present wrong kind and other stat failure is corrupt, including directory and
  // session.json symlinks.
  let dir_kind = @fs.kind(session_dir, follow_symlink=false) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() =>
      raise GoalSessionAbsentOrMismatch
    _ => raise GoalSessionCorrupt
  }
  if dir_kind != @fs.Directory {
    raise GoalSessionCorrupt
  }
  let snapshot_kind = @fs.kind(snapshot_path, follow_symlink=false) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() =>
      raise GoalSessionAbsentOrMismatch
    _ => raise GoalSessionCorrupt
  }
  if snapshot_kind != @fs.Regular {
    raise GoalSessionCorrupt
  }
  let text = @fsx.read_file(snapshot_path) catch {
    _ => raise GoalSessionCorrupt
  }
  let json = @json.parse(text) catch { _ => raise GoalSessionCorrupt }
  let object = match json {
    Object(object) => object
    _ => raise GoalSessionCorrupt
  }
  let exact = fn(field, expected) {
    match object.get(field) {
      Some(String(value)) => value == expected
      _ => false
    }
  }
  if !exact("kind", "mooncode-session-snapshot") ||
    !exact("protocol", "mooncode.v1") ||
    !exact("owner", "moonclaw") ||
    !exact("session_id", session_id) ||
    !exact("book_root", book_root) {
    raise GoalSessionAbsentOrMismatch
  }
  book_root
}
