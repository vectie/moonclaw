///|
struct HttpTextResponse {
  status : Int
  body : String
} derive(Debug, Eq, ToJson, FromJson)

///|
struct RobotPolicyRunOutput {
  decision : @policy.RobotPolicyDecision
  invoked : Bool
  invocation : HttpTextResponse?
  message : String
} derive(Debug, Eq, ToJson, FromJson)

///|
fn usage() -> Unit {
  println("MoonClaw Robot Policy")
  println("")
  println("Usage:")
  println("  moon run cmd/robot_policy -- <moonrobo-context.json>")
  println("  moon run cmd/robot_policy -- --url <moonrobo-base-url> [--invoke]")
  println("")
  println("Reads Moonrobo /api/moonclaw/context and prints the MoonClaw-owned")
  println("route decision as JSON. With --invoke, MoonClaw calls the selected")
  println("non-physical Moonrobo route and prints the downstream response.")
}

///|
fn error_json(message : String) -> Json {
  { "status": Json::string("error"), "message": Json::string(message) }.to_json()
}

///|
fn print_error(message : String) -> Unit {
  println(error_json(message).stringify(indent=2))
}

///|
fn trim_base_url(base : String) -> String {
  let trimmed = base.trim().to_owned()
  trimmed.trim_end(chars="/").to_owned()
}

///|
fn join_url(base : String, route : String) -> String {
  if route.has_prefix("http://") || route.has_prefix("https://") {
    route
  } else {
    let clean = trim_base_url(base)
    if route.has_prefix("/") {
      "\{clean}\{route}"
    } else {
      "\{clean}/\{route}"
    }
  }
}

///|
async fn get_text(url : String) -> Result[HttpTextResponse, String] {
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
async fn post_empty_json(url : String) -> Result[HttpTextResponse, String] {
  let (response, data) = @http.post(url, "{}") catch {
    error => return Err("POST \{url} failed: \{error}")
  }
  let body = data.text()
  Ok({ status: response.code, body })
}

///|
async fn invoke_decision(
  base_url : String,
  decision : @policy.RobotPolicyDecision,
) -> Result[HttpTextResponse, String] {
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
  let url = join_url(base_url, decision.route)
  match decision.http_method {
    "GET" => get_text(url)
    "POST" => post_empty_json(url)
    route_method => Err("unsupported Moonrobo route method \{route_method}")
  }
}

///|
fn print_decision_from_text(text : String) -> Unit {
  match @policy.select_route_from_context_text(text) {
    Ok(decision) => println(decision.to_json().stringify(indent=2))
    Err(message) => print_error(message)
  }
}

///|
async fn run_live(base_url : String, invoke : Bool) -> Unit {
  let context = match get_text(join_url(base_url, "/api/moonclaw/context")) {
    Ok(response) => response.body
    Err(message) => {
      print_error(message)
      return
    }
  }
  let decision = match @policy.select_route_from_context_text(context) {
    Ok(decision) => decision
    Err(message) => {
      print_error(message)
      return
    }
  }
  if !invoke {
    println(decision.to_json().stringify(indent=2))
    return
  }
  let invocation = match invoke_decision(base_url, decision) {
    Ok(response) => Some(response)
    Err(message) => {
      println(
        { decision, invoked: false, invocation: None, message }
        .to_json()
        .stringify(indent=2),
      )
      return
    }
  }
  println(
    {
      decision,
      invoked: true,
      invocation,
      message: "MoonClaw invoked the selected Moonrobo route.",
    }
    .to_json()
    .stringify(indent=2),
  )
}

///|
async fn main {
  let args = @os.args()
  match args[:] {
    [_bin, "--help"] | [_bin, "-h"] => usage()
    [_bin, "--url", base_url] => run_live(base_url, false)
    [_bin, "--url", base_url, "--invoke"] => run_live(base_url, true)
    [_bin, path] => {
      let text = @fsx.read_file(path) catch {
        error => {
          print_error("failed to read Moonrobo context file: \{error}")
          return
        }
      }
      print_decision_from_text(text)
    }
    _ => usage()
  }
}
