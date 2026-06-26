///|
struct RobotPolicyGatewayRequest {
  moonrobo_url : String
  now_ms : Int64?
} derive(Debug, Eq, ToJson)

///|
struct RobotPolicyHttpTextResponse {
  status : Int
  body : String
} derive(Debug, Eq, ToJson, FromJson)

///|
struct RobotPolicyGatewayResponse {
  decision : @robot_policy.RobotPolicyDecision
  invoked : Bool
  invocation : RobotPolicyHttpTextResponse?
  message : String
} derive(Debug, Eq, ToJson, FromJson)

///|
fn robot_policy_error(code : String, message : String) -> Json {
  { "error": { "code": code, "message": message } }.to_json()
}

///|
fn robot_policy_trim_base_url(base : String) -> String {
  let trimmed = base.trim().to_owned()
  trimmed.trim_end(chars="/").to_owned()
}

///|
fn robot_policy_join_url(base : String, route : String) -> String {
  if route.has_prefix("http://") || route.has_prefix("https://") {
    route
  } else {
    let clean = robot_policy_trim_base_url(base)
    if route.has_prefix("/") {
      "\{clean}\{route}"
    } else {
      "\{clean}/\{route}"
    }
  }
}

///|
fn robot_policy_decode_request_text(
  text : String,
) -> Result[RobotPolicyGatewayRequest, String] {
  let json = @json.parse(text) catch {
    error => return Err("invalid JSON: \{error}")
  }
  guard json is Object(object) else {
    return Err("request body must be a JSON object")
  }
  let moonrobo_url = match object.get("moonrobo_url") {
    Some(String(value)) => value
    _ => return Err("moonrobo_url is required")
  }
  if moonrobo_url.trim() == "" {
    return Err("moonrobo_url is required")
  }
  let now_ms = match object.get("now_ms") {
    Some(Number(value, ..)) => Some(value.to_int64())
    Some(String(value)) =>
      Some(
        @string.parse_int64(value) catch {
          _ => return Err("now_ms must be an integer millisecond timestamp")
        },
      )
    Some(_) => return Err("now_ms must be an integer millisecond timestamp")
    None => None
  }
  Ok({ moonrobo_url, now_ms })
}

///|
fn robot_policy_now_ms(params : RobotPolicyGatewayRequest) -> Int64 {
  match params.now_ms {
    Some(now_ms) => now_ms
    None => current_time_ms().to_int64()
  }
}

///|
async fn robot_policy_read_request(
  r : @httpx.RequestReader,
) -> RobotPolicyGatewayRequest {
  let body = r.body.read_all().binary()
  let text : String = @encoding/utf8.decode(body) catch {
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_utf8",
          "message": "Invalid UTF-8 in request body",
        },
      })
  }
  match robot_policy_decode_request_text(text) {
    Ok(params) => params
    Err(message) =>
      raise json_error(
        400,
        "BadRequest",
        robot_policy_error("invalid_params", message),
      )
  }
}

///|
async fn robot_policy_get_text(
  url : String,
) -> Result[RobotPolicyHttpTextResponse, String] {
  let (response, data) = @http.get(url) catch {
    error => return Err("GET \{url} failed: \{error}")
  }
  let body = data.text()
  guard response.code is (200..=299) else {
    return Err("GET \{url} returned \{response.code}: \{body}")
  }
  Ok({ status: response.code, body })
}

///|
async fn robot_policy_post_json(
  url : String,
  body : String,
) -> Result[RobotPolicyHttpTextResponse, String] {
  let (response, data) = @http.post(url, body) catch {
    error => return Err("POST \{url} failed: \{error}")
  }
  Ok({ status: response.code, body: data.text() })
}

///|
async fn robot_policy_fetch_context(
  base_url : String,
) -> Result[String, String] {
  match
    robot_policy_get_text(
      robot_policy_join_url(base_url, "/api/moonclaw/context"),
    ) {
    Ok(response) => Ok(response.body)
    Err(message) => Err(message)
  }
}

///|
async fn robot_policy_invoke_decision(
  base_url : String,
  decision : @robot_policy.RobotPolicyDecision,
) -> Result[RobotPolicyHttpTextResponse, String] {
  if decision.owner != "moonclaw" {
    return Err("MoonClaw cannot invoke a decision owned by \{decision.owner}")
  }
  if decision.status != "route-selected" {
    return Err("MoonClaw cannot invoke decision status \{decision.status}")
  }
  if decision.physical_execution_allowed {
    return Err(
      "selected route allows physical execution; explicit safety-gated invocation is not implemented yet",
    )
  }
  let url = robot_policy_join_url(base_url, decision.route)
  match decision.http_method {
    "GET" => robot_policy_get_text(url)
    "POST" => robot_policy_post_json(url, decision.request_body)
    route_method => Err("unsupported Moonrobo route method \{route_method}")
  }
}

///|
async fn Gateway::select_robot_policy(
  self : Gateway,
  r : @httpx.RequestReader,
  invoke : Bool,
) -> RobotPolicyGatewayResponse {
  ignore(self)
  let params = robot_policy_read_request(r)
  let base_url = robot_policy_trim_base_url(params.moonrobo_url)
  let context = match robot_policy_fetch_context(base_url) {
    Ok(context) => context
    Err(message) =>
      raise json_error(
        502,
        "BadGateway",
        robot_policy_error("moonrobo_context_unavailable", message),
      )
  }
  let decision = match
    @robot_policy.select_route_from_context_text(
      context,
      now_ms=robot_policy_now_ms(params),
    ) {
    Ok(decision) => decision
    Err(message) =>
      raise json_error(
        422,
        "UnprocessableEntity",
        robot_policy_error("robot_policy_failed", message),
      )
  }
  if !invoke {
    return {
      decision,
      invoked: false,
      invocation: None,
      message: "MoonClaw selected the robot policy route from Moonrobo context.",
    }
  }
  let invocation = match robot_policy_invoke_decision(base_url, decision) {
    Ok(response) => response
    Err(message) =>
      raise json_error(
        409,
        "Conflict",
        robot_policy_error("robot_policy_invocation_blocked", message),
      )
  }
  {
    decision,
    invoked: true,
    invocation: Some(invocation),
    message: "MoonClaw invoked the selected Moonrobo route.",
  }
}

///|
async fn Gateway::handle_robot_policy(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let response = self.select_robot_policy(r, false)
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(response.to_json().stringify())
}

///|
async fn Gateway::handle_robot_policy_invoke(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let response = self.select_robot_policy(r, true)
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(response.to_json().stringify())
}
