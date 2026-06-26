///|
pub(all) struct RobotRoutineDecision {
  decision_id : String
  status : String
  owner : String
  work_id : String
  kind : String
  http_method : String
  route : String
  request_body : String
  target_route : String
  title : String
  reason : String
  physical_execution_allowed : Bool
  message : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RobotRoutineStep {
  step_id : String
  order : Int
  kind : String
  owner : String
  status : String
  http_method : String
  route : String
  request_body : String
  reason : String
  physical_execution_allowed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RobotRoutinePlan {
  plan_id : String
  status : String
  owner : String
  step_count : Int
  steps : Array[RobotRoutineStep]
  next_step : RobotRoutineStep?
  decision : RobotRoutineDecision
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
  let queue = object_field(context, "platform_queue")
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
fn tool_registry(context : Json) -> Json {
  object_field(context, "tool_registry")
}

///|
fn task_intent(context : Json) -> Json {
  object_field(context, "task_intent")
}

///|
fn live_readiness(payload : Json) -> Json {
  object_field(payload, "live_readiness")
}

///|
fn robot_id(context : Json) -> String {
  string_field(context, "robot_id")
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
fn unsupported_aggregate_kind(kind : String) -> Bool {
  kind == "run-live-exercise"
}

///|
fn route_segment_matches(template : String, route : String) -> Bool {
  if template.has_prefix("{") && template.has_suffix("}") {
    route != ""
  } else {
    template == route
  }
}

///|
fn registered_route_template_matches(template : String, route : String) -> Bool {
  if template == route {
    return true
  }
  let template_parts = template.split("/").to_array()
  let route_parts = route.split("/").to_array()
  if template_parts.length() != route_parts.length() {
    return false
  }
  for i in 0..<template_parts.length() {
    if !route_segment_matches(
        template_parts[i].to_owned(),
        route_parts[i].to_owned(),
      ) {
      return false
    }
  }
  true
}

///|
fn route_registered_for_moonclaw(
  context : Json,
  http_method : String,
  route : String,
) -> Bool {
  if http_method == "" || route == "" {
    return false
  }
  match tool_registry(context) {
    Object(registry) =>
      match registry.get("providers") {
        Some(Array(providers)) =>
          for provider in providers {
            guard provider is Object(provider_object) else { continue }
            match provider_object.get("capabilities") {
              Some(Array(capabilities)) =>
                for capability in capabilities {
                  guard capability is Object(_) else { continue }
                  if string_field(capability, "http_method") == http_method &&
                    registered_route_template_matches(
                      string_field(capability, "route"),
                      route,
                    ) &&
                    !bool_field(capability, "physical_execution_allowed") {
                    return true
                  }
                }
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  false
}

///|
fn decision_id(prefix : String, kind : String, now_ms : Int64) -> String {
  "\{prefix}-\{kind}-\{now_ms}"
  .replace(old="/", new="-")
  .replace(old=":", new="-")
  .replace(old=" ", new="-")
}

///|
fn gateway_command_goal(item : Json, context : Json) -> String {
  let task = task_intent(context)
  let goal = string_field(task, "goal")
  if bool_field(task, "has_task") && goal != "" {
    goal
  } else {
    let reason = string_field(item, "reason")
    if reason != "" {
      reason
    } else {
      let title = string_field(item, "title")
      if title != "" {
        title
      } else {
        let status = string_field(gateway(context), "status")
        if status != "" {
          "Continue the Moonrobo robot routine from gateway status \{status}."
        } else {
          "Continue the Moonrobo robot routine from MoonClaw routine state."
        }
      }
    }
  }
}

///|
fn gateway_command_body(item : Json, context : Json, now_ms : Int64) -> String {
  {
    "command_id": Json::string(
      decision_id(
        "moonclaw-gateway-command",
        string_field(item, "kind"),
        now_ms,
      ),
    ),
    "robot_id": Json::string(robot_id(context)),
    "requested_by": {
      "kind": Json::string("moontown"),
      "id": Json::string("moonclaw"),
    },
    "goal": Json::string(gateway_command_goal(item, context)),
    "now_ms": now_ms.to_json(),
    "remember": true.to_json(),
  }
  .to_json()
  .stringify()
}

///|
fn task_goal(context : Json) -> String {
  let task = task_intent(context)
  let goal = string_field(task, "goal")
  if bool_field(task, "has_task") && goal != "" {
    goal
  } else {
    "Continue the Moonrobo robot routine from MoonClaw routine state."
  }
}

///|
fn task_message_id(context : Json, now_ms : Int64) -> String {
  let task = task_intent(context)
  let message_id = string_field(task, "message_id")
  if message_id != "" {
    message_id
  } else {
    decision_id("moonclaw-message", robot_id(context), now_ms)
  }
}

///|
fn task_message_body(context : Json, now_ms : Int64) -> Json {
  {
    "message_id": Json::string(task_message_id(context, now_ms)),
    "robot_id": Json::string(robot_id(context)),
    "requested_by": {
      "kind": Json::string("moontown"),
      "id": Json::string("moonclaw"),
    },
    "message": Json::string(task_goal(context)),
    "now_ms": now_ms.to_json(),
  }.to_json()
}

///|
fn proof_session_body(context : Json, now_ms : Int64) -> String {
  {
    "session_id": Json::string(
      decision_id("moonclaw-proof-session", robot_id(context), now_ms),
    ),
    "task_message": task_message_body(context, now_ms),
    "iterations": (3).to_json(),
    "max_steps": (8).to_json(),
    "bootstrap": true.to_json(),
    "stop_when_ready": true.to_json(),
  }
  .to_json()
  .stringify()
}

///|
fn route_request_body(item : Json, context : Json, now_ms : Int64) -> String {
  if string_field(item, "target_path") == "/api/moonrobo/gateway/command" {
    gateway_command_body(item, context, now_ms)
  } else if string_field(item, "target_path") == "/api/moonrobo/proof-session" {
    proof_session_body(context, now_ms)
  } else {
    "{}"
  }
}

///|
fn registry_blocker_decision(
  kind : String,
  target : String,
  http_method : String,
  title : String,
  reason : String,
  now_ms : Int64,
) -> RobotRoutineDecision {
  {
    decision_id: decision_id("robot-routine-unregistered-route", kind, now_ms),
    status: "needs-operator",
    owner: "operator",
    work_id: "",
    kind,
    http_method: "GET",
    route: "/api/tools/registry",
    request_body: "",
    target_route: target,
    title: if title == "" {
      "Register Moonrobo tool route"
    } else {
      title
    },
    reason: if reason == "" {
      "MoonClaw will not invoke unregistered Moonrobo route \{http_method} \{target}."
    } else {
      "\{reason}; route \{http_method} \{target} is not registered as a bounded Moonrobo tool."
    },
    physical_execution_allowed: false,
    message: "MoonClaw blocked an unregistered Moonrobo routine target; update the Moonrobo tool registry or choose a registered route.",
  }
}

///|
fn work_decision(
  item : Json,
  context : Json,
  now_ms : Int64,
) -> RobotRoutineDecision {
  let kind = string_field(item, "kind")
  let owner = if operator_kind(kind) { "operator" } else { "moonclaw" }
  let target = string_field(item, "target_path")
  let http_method = if owner == "operator" { "GET" } else { "POST" }
  if owner == "moonclaw" &&
    !route_registered_for_moonclaw(context, http_method, target) {
    return registry_blocker_decision(
      kind,
      target,
      http_method,
      string_field(item, "title"),
      string_field(item, "reason"),
      now_ms,
    )
  }
  {
    decision_id: decision_id("robot-routine-work", kind, now_ms),
    status: if owner == "operator" {
      "needs-operator"
    } else {
      "route-selected"
    },
    owner,
    work_id: string_field(item, "work_id"),
    kind,
    http_method,
    route: if owner == "operator" {
      target
    } else {
      target
    },
    request_body: if owner == "operator" {
      ""
    } else {
      route_request_body(item, context, now_ms)
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
fn ready_decision(context : Json, now_ms : Int64) -> RobotRoutineDecision {
  let status = gateway(context)
  let route = string_field(status, "next_route")
  let title = string_field(status, "next_title")
  let http_method = string_field(status, "next_method")
  let kind = if route == "/api/moonrobo/gateway/command" {
    "submit-gateway-command"
  } else {
    string_field(status, "status")
  }
  if !route_registered_for_moonclaw(context, http_method, route) {
    return registry_blocker_decision(
      kind, route, http_method, title, "Gateway status selected the next Moonrobo route.",
      now_ms,
    )
  }
  let item = {
    "kind": Json::string(kind),
    "target_path": Json::string(route),
    "title": Json::string(title),
    "reason": Json::string("Gateway status selected the next Moonrobo route."),
  }.to_json()
  {
    decision_id: decision_id("robot-routine-gateway", kind, now_ms),
    status: "route-selected",
    owner: "moonclaw",
    work_id: "",
    kind,
    http_method,
    route,
    request_body: route_request_body(item, context, now_ms),
    target_route: route,
    title,
    reason: "Gateway status selected the next Moonrobo route.",
    physical_execution_allowed: bool_field(status, "physical_execution_allowed"),
    message: "MoonClaw selected the gateway next route from Moonrobo context.",
  }
}

///|
fn idle_decision(now_ms : Int64) -> RobotRoutineDecision {
  {
    decision_id: decision_id("robot-routine-idle", "idle", now_ms),
    status: "idle",
    owner: "moontown",
    work_id: "",
    kind: "idle",
    http_method: "POST",
    route: "/api/moonrobo/ask",
    request_body: "",
    target_route: "/api/moonrobo/ask",
    title: "Ask Robo",
    reason: "No queued robot work is present in Moonrobo context.",
    physical_execution_allowed: false,
    message: "Robot routine is idle; ask for another task.",
  }
}

///|
fn select_route_from_context(
  payload : Json,
  now_ms? : Int64 = 0L,
) -> RobotRoutineDecision {
  let context = context_body(payload)
  let item = next_work_item(context)
  match item {
    Object(object) if object.length() > 0 &&
      !unsupported_aggregate_kind(string_field(item, "kind")) =>
      work_decision(item, context, now_ms)
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
fn routine_step(
  step_id : String,
  order : Int,
  kind : String,
  owner : String,
  status : String,
  http_method : String,
  route : String,
  request_body : String,
  reason : String,
  physical_execution_allowed? : Bool = false,
) -> RobotRoutineStep {
  {
    step_id,
    order,
    kind,
    owner,
    status,
    http_method,
    route,
    request_body,
    reason,
    physical_execution_allowed,
  }
}

///|
fn validation_step(order : Int) -> RobotRoutineStep {
  routine_step(
    "routine-step-runtime-validation",
    order,
    "validate-runtime",
    "moonclaw",
    "pending",
    "POST",
    "/api/runtime/validation/session",
    { "sample_count": 3 }.to_json().stringify(),
    "Collect repeated runtime validation before robot command or proof work.",
  )
}

///|
fn gateway_step(
  context : Json,
  now_ms : Int64,
  order : Int,
) -> RobotRoutineStep {
  let item = {
    "kind": Json::string("submit-gateway-command"),
    "reason": Json::string(
      "MoonClaw routine selected the next gateway command.",
    ),
    "title": Json::string("Submit gateway command"),
  }.to_json()
  routine_step(
    "routine-step-gateway-command",
    order,
    "submit-gateway-command",
    "moonclaw",
    "pending",
    "POST",
    "/api/moonrobo/gateway/command",
    gateway_command_body(item, context, now_ms),
    "Submit the MoonClaw-authored robot command through Moonrobo ingress.",
  )
}

///|
fn proof_step(context : Json, now_ms : Int64, order : Int) -> RobotRoutineStep {
  routine_step(
    "routine-step-proof-session",
    order,
    "run-proof-session",
    "moonclaw",
    "pending",
    "POST",
    "/api/moonrobo/proof-session",
    proof_session_body(context, now_ms),
    "Run bounded proof attempts after validation and gateway command evidence.",
  )
}

///|
fn feedback_step(order : Int) -> RobotRoutineStep {
  routine_step(
    "routine-step-bind-feedback", order, "bind-execution-feedback", "operator", "needs-evidence",
    "POST", "/api/moonrobo/executions/feedback", "", "Bind matched physical/runtime feedback once real execution telemetry is available.",
  )
}

///|
fn memory_step(order : Int) -> RobotRoutineStep {
  routine_step(
    "routine-step-remember", order, "remember-robot-context", "moonclaw", "pending",
    "POST", "/api/moonbook/remember", "{}", "Persist MoonBook memory after the current robot evidence changes.",
  )
}

///|
fn append_selected_route_step(
  steps : Array[RobotRoutineStep],
  decision : RobotRoutineDecision,
) -> Unit {
  if decision.status == "route-selected" &&
    decision.owner == "moonclaw" &&
    decision.route != "" {
    steps.push(
      routine_step(
        "routine-step-selected-route",
        steps.length() + 1,
        decision.kind,
        decision.owner,
        "selected",
        decision.http_method,
        decision.route,
        decision.request_body,
        decision.reason,
        physical_execution_allowed=decision.physical_execution_allowed,
      ),
    )
  }
}

///|
fn append_remainder_steps(
  steps : Array[RobotRoutineStep],
  payload : Json,
  context : Json,
  now_ms : Int64,
) -> Unit {
  let readiness = live_readiness(payload)
  let status = string_field(readiness, "status")
  if status == "needs-runtime-validation" {
    if !steps.any(step => step.route == "/api/runtime/validation/session") {
      steps.push(validation_step(steps.length() + 1))
    }
    return
  }
  if status == "needs-calibration" {
    steps.push(
      routine_step(
        "routine-step-runtime-calibration",
        steps.length() + 1,
        "calibrate-runtime",
        "operator",
        "needs-operator",
        "GET",
        "/api/moonclaw/runtime-calibration/latest",
        "",
        "Resolve runtime calibration before MoonClaw continues robot routine work.",
      ),
    )
    return
  }
  if bool_field(readiness, "can_submit_gateway_command") &&
    !steps.any(step => step.route == "/api/moonrobo/gateway/command") {
    steps.push(gateway_step(context, now_ms, steps.length() + 1))
  }
  if bool_field(readiness, "can_run_proof_session") &&
    !steps.any(step => step.route == "/api/moonrobo/proof-session") {
    steps.push(proof_step(context, now_ms, steps.length() + 1))
  }
  if !bool_field(readiness, "proof_session_feedback_closed") {
    steps.push(feedback_step(steps.length() + 1))
  }
  steps.push(memory_step(steps.length() + 1))
}

///|
fn plan_status(steps : Array[RobotRoutineStep]) -> String {
  if steps.is_empty() {
    "idle"
  } else if steps[0].owner == "operator" {
    "needs-operator"
  } else {
    "ready"
  }
}

///|
fn plan_message(status : String) -> String {
  match status {
    "idle" => "MoonClaw robot routine is idle; ask Robo for another task."
    "needs-operator" =>
      "MoonClaw robot routine needs operator evidence before continuing."
    _ =>
      "MoonClaw planned the explicit robot routine route sequence from Moonrobo context."
  }
}

///|
pub fn plan_routine_from_context(
  payload : Json,
  now_ms? : Int64 = 0L,
) -> RobotRoutinePlan {
  let context = context_body(payload)
  let decision = select_route_from_context(payload, now_ms~)
  let steps : Array[RobotRoutineStep] = []
  append_selected_route_step(steps, decision)
  append_remainder_steps(steps, payload, context, now_ms)
  let status = plan_status(steps)
  {
    plan_id: decision_id("robot-routine-plan", robot_id(context), now_ms),
    status,
    owner: if status == "needs-operator" {
      "operator"
    } else if status == "idle" {
      "moontown"
    } else {
      "moonclaw"
    },
    step_count: steps.length(),
    steps,
    next_step: if steps.is_empty() {
      None
    } else {
      Some(steps[0])
    },
    decision,
    message: plan_message(status),
  }
}

///|
pub fn plan_routine_from_context_text(
  payload : String,
  now_ms? : Int64 = 0L,
) -> Result[RobotRoutinePlan, String] {
  let json = @json.parse(payload) catch {
    error => return Err("failed to parse Moonrobo context JSON: \{error}")
  }
  Ok(plan_routine_from_context(json, now_ms~))
}
