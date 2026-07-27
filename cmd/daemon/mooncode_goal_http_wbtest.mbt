///|
test "mooncode goal HTTP contract: GET and PUT route shape" {
  assert_eq(
    mooncode_goal_http_route("GET", ["", "v1", "code", "sessions", "s", "goal"]),
    GoalGet,
  )
  assert_eq(
    mooncode_goal_http_route("PUT", ["", "v1", "code", "sessions", "s", "goal"]),
    GoalPut,
  )
}

///|
test "mooncode goal HTTP contract: unsupported method has exact Allow header" {
  assert_eq(
    mooncode_goal_http_route("POST", ["", "v1", "code", "sessions", "s", "goal"]),
    GoalMethodNotAllowed,
  )
  assert_eq(mooncode_goal_http_allow(), "GET, PUT")
}

///|
test "mooncode goal HTTP contract: malformed JSON is rejected before session lookup" {
  let result = mooncode_parse_goal_http_body("{")
  assert_eq(result, Err("invalid_json"))
}
