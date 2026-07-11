///|
struct HttpTextResponse {
  status : Int
  body : String
} derive(Debug, Eq, ToJson, FromJson)

///|
struct RobotRoutineRunOutput {
  plan : @routine.RobotRoutinePlan
  invoked : Bool
  invocation : HttpTextResponse?
  message : String
} derive(Debug, Eq, ToJson, FromJson)

///|
fn usage() -> Unit {
  println("MoonClaw Robot Routine")
  println("")
  println("Usage:")
  println("  moon run cmd/robot_routine -- <moonrobo-context.json>")
  println(
    "  moon run cmd/robot_routine -- --url <moonrobo-base-url> [--invoke]",
  )
  println("")
  println("Reads MoonRobo /api/moonclaw/context and prints the MoonClaw-owned")
  println("routine plan as JSON, including MoonClaw-authored request bodies.")
  println("With --invoke, MoonClaw calls only the next non-physical")
  println("MoonClaw-owned routine step and prints the downstream response.")
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
async fn post_json(
  url : String,
  body : String,
) -> Result[HttpTextResponse, String] {
  let (response, data) = @http.post(url, body) catch {
    error => return Err("POST \{url} failed: \{error}")
  }
  let body = data.text()
  Ok({ status: response.code, body })
}

///|
async fn invoke_step(
  base_url : String,
  step : @routine.RobotRoutineStep,
) -> Result[HttpTextResponse, String] {
  if step.owner != "moonclaw" {
    return Err("MoonClaw cannot invoke a routine step owned by \{step.owner}")
  }
  if step.physical_execution_allowed {
    return Err(
      "selected routine step allows physical execution; explicit safety-gated invocation is not implemented yet",
    )
  }
  let url = join_url(base_url, step.route)
  match step.http_method {
    "GET" => get_text(url)
    "POST" => post_json(url, step.request_body)
    route_method => Err("unsupported MoonRobo route method \{route_method}")
  }
}

///|
fn print_plan_from_text(text : String) -> Unit {
  match @routine.plan_routine_from_context_text(text) {
    Ok(plan) => println(plan.to_json().stringify(indent=2))
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
  let plan = match @routine.plan_routine_from_context_text(context) {
    Ok(plan) => plan
    Err(message) => {
      print_error(message)
      return
    }
  }
  if !invoke {
    println(plan.to_json().stringify(indent=2))
    return
  }
  let step = match plan.next_step {
    Some(step) => step
    None => {
      println(
        {
          plan,
          invoked: false,
          invocation: None,
          message: "MoonClaw robot routine has no next step to invoke.",
        }
        .to_json()
        .stringify(indent=2),
      )
      return
    }
  }
  let invocation = match invoke_step(base_url, step) {
    Ok(response) => Some(response)
    Err(message) => {
      println(
        { plan, invoked: false, invocation: None, message }
        .to_json()
        .stringify(indent=2),
      )
      return
    }
  }
  println(
    {
      plan,
      invoked: true,
      invocation,
      message: "MoonClaw invoked the next robot routine step.",
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
          print_error("failed to read MoonRobo context file: \{error}")
          return
        }
      }
      print_plan_from_text(text)
    }
    _ => usage()
  }
}
