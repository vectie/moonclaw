///|
pub(all) struct RobotPolicyDecision {
  decision_id : String
  status : String
  owner : String
  work_id : String
  kind : String
  http_method : String
  route : String
  target_route : String
  title : String
  reason : String
  physical_execution_allowed : Bool
  message : String
} derive(Debug, Eq, ToJson, FromJson)

///|
fn string_field(json : Json, key : String) -> String {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
fn bool_field(json : Json, key : String) -> Bool {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(value) => @json.from_json(value) catch { _ => false }
        None => false
      }
    _ => false
  }
}

///|
fn object_field(json : Json, key : String) -> Json {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(Object(_) as value) => value
        _ => {}
      }
    _ => {}
  }
}

///|
fn context_body(payload : Json) -> Json {
  let inner = object_field(payload, "context")
  if inner == {} {
    payload
  } else {
    inner
  }
}

///|
fn next_work_item(context : Json) -> Json {
  let queue = object_field(context, "work_queue")
  match object_field(queue, "next_item") {
    Object(object) as value if object.length() > 0 => value
    _ => {}
  }
}

///|
fn gateway(context : Json) -> Json {
  object_field(context, "gateway")
}

///|
fn operator_kind(kind : String) -> Bool {
  match kind {
    "start-runtime"
    | "review-evidence"
    | "calibrate-runtime"
    | "repair-dataset"
    | "review-policy-safety"
    | "approve-policy-proposal"
    | "review-policy-proposal"
    | "review-maintenance-message"
    | "review-task-message"
    | "review-command-message"
    | "approve-command-message"
    | "execute-command-message" => true
    _ => false
  }
}

///|
fn decision_id(prefix : String, kind : String, now_ms : Int64) -> String {
  "\{prefix}-\{kind}-\{now_ms}"
  .replace(old="/", new="-")
  .replace(old=":", new="-")
  .replace(old=" ", new="-")
}

///|
fn work_decision(item : Json, now_ms : Int64) -> RobotPolicyDecision {
  let kind = string_field(item, "kind")
  let owner = if operator_kind(kind) { "operator" } else { "moonclaw" }
  let target = string_field(item, "target_path")
  {
    decision_id: decision_id("robot-policy-work", kind, now_ms),
    status: if owner == "operator" {
      "needs-operator"
    } else {
      "route-selected"
    },
    owner,
    work_id: string_field(item, "work_id"),
    kind,
    http_method: if owner == "operator" {
      "GET"
    } else {
      "POST"
    },
    route: if owner == "operator" {
      target
    } else {
      target
    },
    target_route: target,
    title: string_field(item, "title"),
    reason: string_field(item, "reason"),
    physical_execution_allowed: false,
    message: if owner == "operator" {
      "Operator action is required before MoonClaw can continue."
    } else {
      "MoonClaw selected the explicit Moonrobo route for this work item."
    },
  }
}

///|
fn ready_decision(context : Json, now_ms : Int64) -> RobotPolicyDecision {
  let status = gateway(context)
  let route = string_field(status, "next_route")
  let title = string_field(status, "next_title")
  {
    decision_id: decision_id("robot-policy-gateway", route, now_ms),
    status: "route-selected",
    owner: "moonclaw",
    work_id: "",
    kind: string_field(status, "status"),
    http_method: string_field(status, "next_method"),
    route,
    target_route: route,
    title,
    reason: "Gateway status selected the next Moonrobo route.",
    physical_execution_allowed: bool_field(status, "physical_execution_allowed"),
    message: "MoonClaw selected the gateway next route from Moonrobo context.",
  }
}

///|
fn idle_decision(now_ms : Int64) -> RobotPolicyDecision {
  {
    decision_id: decision_id("robot-policy-idle", "idle", now_ms),
    status: "idle",
    owner: "moontown",
    work_id: "",
    kind: "idle",
    http_method: "POST",
    route: "/api/moonrobo/ask",
    target_route: "/api/moonrobo/ask",
    title: "Ask Robo",
    reason: "No queued robot work is present in Moonrobo context.",
    physical_execution_allowed: false,
    message: "Robot policy is idle; ask for another task.",
  }
}

///|
pub fn select_route_from_context(
  payload : Json,
  now_ms? : Int64 = 0L,
) -> RobotPolicyDecision {
  let context = context_body(payload)
  let item = next_work_item(context)
  match item {
    Object(object) if object.length() > 0 => work_decision(item, now_ms)
    _ => {
      let status = gateway(context)
      if bool_field(status, "can_submit_gateway_command") &&
        string_field(status, "next_route") != "" {
        ready_decision(context, now_ms)
      } else {
        idle_decision(now_ms)
      }
    }
  }
}

///|
pub fn select_route_from_context_text(
  payload : String,
  now_ms? : Int64 = 0L,
) -> Result[RobotPolicyDecision, String] {
  let json = @json.parse(payload) catch {
    error => return Err("failed to parse Moonrobo context JSON: \{error}")
  }
  Ok(select_route_from_context(json, now_ms~))
}
