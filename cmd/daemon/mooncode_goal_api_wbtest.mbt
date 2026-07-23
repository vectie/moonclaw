///|
/// Strict parser audit ledger:
/// - Exact object schemas reject omitted, extension, usage, and client-owned state fields.
/// - Policy: turn_limit is required, non-null, exact nonnegative Int32; parsed values are preserved in Some.
/// - Budget and requirements shape failures are tested independently from protocol validity.
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
    _ => abort("unexpected goal parser error")
  }
}

///|
test "mooncode_goal_api: valid limits preserve exact values" {
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
    assert_true(request.requirements[0].state == @mooncode_core.Unproven)
    assert_eq(request.requirements[0].evidence_refs.length(), 0)
  }
}

///|
test "mooncode_goal_api: turn_limit policy rejects invalid values" {
  for
    value in [
      Json::null(),
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
