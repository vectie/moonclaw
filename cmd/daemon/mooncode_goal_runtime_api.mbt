///|
priv struct MoonCodeGoalRuntimePutRequest {
  session_id : String
  goal_id : String
  objective : String
  criteria : Array[MoonCodeGoalRuntimeStoredCriterion]
}

///|
priv struct MoonCodeGoalRuntimeApiResponse {
  status_code : Int
  body : Json
}

///|
fn mooncode_goal_runtime_api_response(
  status_code : Int,
  body : Json,
) -> MoonCodeGoalRuntimeApiResponse {
  { status_code, body }
}

///|
fn mooncode_goal_runtime_api_error(
  status_code : Int,
  code : String,
) -> MoonCodeGoalRuntimeApiResponse {
  mooncode_goal_runtime_api_response(status_code, {
    "kind": "mooncode-goal-runtime-error",
    "protocol": mooncode_goal_runtime_protocol_v1,
    "owner": "moonclaw",
    "contract": mooncode_goal_runtime_contract_v1,
    "error": code,
  })
}

///|
fn mooncode_goal_runtime_parse_put_request(
  body : Json,
  path_session_id : String,
) -> MoonCodeGoalRuntimePutRequest raise MoonCodeGoalRuntimeCodecError {
  let object = mooncode_goal_runtime_exact_object(
    body,
    ["protocol", "contract", "session_id", "goal_id", "objective", "criteria"],
    "goal runtime request",
  )
  if mooncode_goal_runtime_checked_string(object, "protocol") !=
    mooncode_goal_runtime_protocol_v1 {
    mooncode_goal_runtime_fail("unsupported protocol")
  }
  if mooncode_goal_runtime_checked_string(object, "contract") !=
    mooncode_goal_runtime_contract_v1 {
    mooncode_goal_runtime_fail("unsupported contract")
  }
  let session_id = mooncode_goal_runtime_checked_string(object, "session_id")
  if !mooncode_goal_runtime_canonical(session_id) ||
    session_id != path_session_id {
    mooncode_goal_runtime_fail("session mismatch")
  }
  let goal_id = mooncode_goal_runtime_checked_string(object, "goal_id")
  let objective = mooncode_goal_runtime_checked_string(object, "objective")
  if !mooncode_goal_runtime_canonical(goal_id) ||
    !mooncode_goal_runtime_canonical(objective) {
    mooncode_goal_runtime_fail("invalid goal identity")
  }
  let criteria_json = mooncode_goal_runtime_checked_array(object, "criteria")
  if criteria_json.is_empty() {
    mooncode_goal_runtime_fail("criteria must not be empty")
  }
  let criteria : Array[MoonCodeGoalRuntimeStoredCriterion] = []
  let ids : Array[String] = []
  let texts : Array[String] = []
  for item in criteria_json {
    let criterion = mooncode_goal_runtime_exact_object(
      item,
      ["id", "criterion"],
      "goal runtime criterion",
    )
    let id = mooncode_goal_runtime_checked_string(criterion, "id")
    let text = mooncode_goal_runtime_checked_string(criterion, "criterion")
    if !mooncode_goal_runtime_canonical(id) ||
      !mooncode_goal_runtime_canonical(text) ||
      ids.any(fn(value) { value == id }) ||
      texts.any(fn(value) { value == text }) {
      mooncode_goal_runtime_fail("invalid or duplicate criterion")
    }
    ids.push(id)
    texts.push(text)
    criteria.push({ id, criterion: text })
  }
  { session_id, goal_id, objective, criteria }
}

///|
fn mooncode_goal_runtime_state_from_scan(
  scan : MoonCodeGoalRuntimeScan,
) -> @mooncode_core.GoalRuntimeState raise MoonCodeGoalRuntimeStoreError {
  guard scan.genesis is Some(genesis_entry) &&
    genesis_entry.carrier.record is Genesis(genesis) else {
    mooncode_goal_runtime_store_corrupt("runtime status has no genesis")
  }
  let criterion_ids = genesis.criteria.map(fn(item) { item.id })
  let mut state = @mooncode_core.new_goal_runtime_state()
  for entry in scan.events {
    guard entry.carrier.record is Event(value) else {
      mooncode_goal_runtime_store_corrupt(
        "runtime event index contains genesis",
      )
    }
    match value.event {
      PlannerDecision(_, Achieved(_, evidence)) => {
        if evidence.length() != criterion_ids.length() {
          mooncode_goal_runtime_store_corrupt(
            "achieved evidence does not cover every genesis criterion",
          )
        }
        for criterion_id in criterion_ids {
          if !evidence.any(fn(item) { item.criterion == criterion_id }) {
            mooncode_goal_runtime_store_corrupt(
              "achieved evidence does not match genesis criteria",
            )
          }
        }
      }
      _ => ()
    }
    let before = @mooncode_core.goal_runtime_handled_count(state)
    let next = @mooncode_core.reduce_goal_runtime(state, value.event)
    if @mooncode_core.goal_runtime_handled_count(next) != before + 1 {
      mooncode_goal_runtime_store_corrupt(
        "unique runtime event was not accepted by the reducer",
      )
    }
    state = next
  }
  state
}

///|
#warnings("-unused_value")
fn mooncode_goal_runtime_status_response(
  scan : MoonCodeGoalRuntimeScan,
  status_code? : Int = 200,
) -> MoonCodeGoalRuntimeApiResponse raise {
  guard scan.genesis is Some(entry) else {
    return mooncode_goal_runtime_api_error(404, "goal_runtime_not_found")
  }
  guard entry.carrier.record is Genesis(genesis) else {
    mooncode_goal_runtime_fail("indexed genesis is not genesis")
  }
  let canonical = encode_mooncode_goal_runtime_genesis(genesis)
  let genesis_json = @json.parse(canonical) catch {
    _ => mooncode_goal_runtime_fail("canonical genesis is invalid JSON")
  }
  mooncode_goal_runtime_api_response(status_code, {
    "kind": "mooncode-goal-runtime-status",
    "protocol": mooncode_goal_runtime_protocol_v1,
    "owner": "moonclaw",
    "contract": mooncode_goal_runtime_contract_v1,
    "session_id": genesis.session_id,
    "goal_id": genesis.goal_id,
    "cursor": scan.cursor.text(),
    "genesis": genesis_json,
    "status": @mooncode_core.goal_runtime_status_json(
      mooncode_goal_runtime_state_from_scan(scan),
    ),
  })
}
