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
fn goal_api_turn_limit(json : Json) -> Int raise InvalidGoalRequest {
  match json {
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
      parsed
    }
    _ => {
      goal_api_fail("invalid turn_limit")
      0
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
      Some(value) => Some(goal_api_turn_limit(value))
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
