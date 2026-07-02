///|
struct RobotRoutineGatewayRequest {
  moonrobo_url : String
  now_ms : Int64?
} derive(Debug, Eq, ToJson)

///|
struct RobotRoutineHttpTextResponse {
  status : Int
  body : String
} derive(Debug, Eq, ToJson, FromJson)

///|
struct RobotRoutineGatewayResponse {
  plan : @robot_routine.RobotRoutinePlan
  invoked : Bool
  invocation : RobotRoutineHttpTextResponse?
  message : String
} derive(Debug, Eq, ToJson, FromJson)

///|
struct RobotRoutineRunRecord {
  run_id : String
  moonrobo_url : String
  created_at_ms : Int64
  status : String
  invoked : Bool
  invocation : RobotRoutineHttpTextResponse?
  memory_refresh : RobotRoutineHttpTextResponse?
  context_before : Json
  context_after : Json
  plan : @robot_routine.RobotRoutinePlan
  record_path : String
  message : String
} derive(Debug, Eq, ToJson)

///|
struct RobotRoutineRunsResponse {
  runs : Array[RobotRoutineRunRecord]
  count : Int
} derive(Debug, Eq, ToJson)

///|
fn robot_routine_error(code : String, message : String) -> Json {
  { "error": { "code": code, "message": message } }.to_json()
}

///|
fn robot_routine_run_error(
  code : String,
  message : String,
  record : RobotRoutineRunRecord,
) -> Json {
  {
    "error": { "code": code, "message": message }.to_json(),
    "run": record.to_json(),
  }.to_json()
}

///|
fn robot_routine_string_field(
  object : Map[String, Json],
  key : String,
) -> Result[String, String] {
  match object.get(key) {
    Some(String(value)) => Ok(value)
    _ => Err("missing string field \{key}")
  }
}

///|
fn robot_routine_bool_field(
  object : Map[String, Json],
  key : String,
) -> Result[Bool, String] {
  match object.get(key) {
    Some(value) => {
      let decoded : Bool = @json.from_json(value) catch {
        error => return Err("invalid bool field \{key}: \{error}")
      }
      Ok(decoded)
    }
    None => Err("missing bool field \{key}")
  }
}

///|
fn robot_routine_i64_field(
  object : Map[String, Json],
  key : String,
) -> Result[Int64, String] {
  match object.get(key) {
    Some(Number(value, ..)) => Ok(value.to_int64())
    Some(String(value)) => {
      let decoded = @string.parse_int64(value) catch {
        error => return Err("invalid int64 field \{key}: \{error}")
      }
      Ok(decoded)
    }
    _ => Err("missing int64 field \{key}")
  }
}

///|
fn robot_routine_object_field(
  object : Map[String, Json],
  key : String,
) -> Result[Json, String] {
  match object.get(key) {
    Some(Object(_) as value) => Ok(value)
    _ => Err("missing object field \{key}")
  }
}

///|
fn robot_routine_optional_http_response_field(
  object : Map[String, Json],
  key : String,
) -> Result[RobotRoutineHttpTextResponse?, String] {
  match object.get(key) {
    Some(Object(_) as value) => {
      let response : RobotRoutineHttpTextResponse = @json.from_json(value) catch {
        error => return Err("invalid invocation field \{key}: \{error}")
      }
      Ok(Some(response))
    }
    Some(Null) => Ok(None)
    Some(_) => Err("invalid invocation field \{key}")
    None => Ok(None)
  }
}

///|
fn robot_routine_optional_json_field(
  object : Map[String, Json],
  key : String,
) -> Json {
  match object.get(key) {
    Some(value) => value
    None => Json::null()
  }
}

///|
fn robot_routine_run_record_from_json(
  json : Json,
) -> Result[RobotRoutineRunRecord, String] {
  guard json is Object(object) else {
    return Err("robot routine run record must be an object")
  }
  let plan_json = match robot_routine_object_field(object, "plan") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let plan : @robot_routine.RobotRoutinePlan = @json.from_json(plan_json) catch {
    error => return Err("invalid plan field: \{error}")
  }
  Ok({
    run_id: match robot_routine_string_field(object, "run_id") {
      Ok(value) => value
      Err(message) => return Err(message)
    },
    moonrobo_url: match robot_routine_string_field(object, "moonrobo_url") {
      Ok(value) => value
      Err(message) => return Err(message)
    },
    created_at_ms: match robot_routine_i64_field(object, "created_at_ms") {
      Ok(value) => value
      Err(message) => return Err(message)
    },
    status: match robot_routine_string_field(object, "status") {
      Ok(value) => value
      Err(message) => return Err(message)
    },
    invoked: match robot_routine_bool_field(object, "invoked") {
      Ok(value) => value
      Err(message) => return Err(message)
    },
    invocation: match
      robot_routine_optional_http_response_field(object, "invocation") {
      Ok(value) => value
      Err(message) => return Err(message)
    },
    memory_refresh: match
      robot_routine_optional_http_response_field(object, "memory_refresh") {
      Ok(value) => value
      Err(message) => return Err(message)
    },
    context_before: robot_routine_optional_json_field(object, "context_before"),
    context_after: robot_routine_optional_json_field(object, "context_after"),
    plan,
    record_path: match robot_routine_string_field(object, "record_path") {
      Ok(value) => value
      Err(message) => return Err(message)
    },
    message: match robot_routine_string_field(object, "message") {
      Ok(value) => value
      Err(message) => return Err(message)
    },
  })
}

///|
fn robot_routine_trim_base_url(base : String) -> String {
  let trimmed = base.trim().to_owned()
  trimmed.trim_end(chars="/").to_owned()
}

///|
fn robot_routine_join_url(base : String, route : String) -> String {
  if route.has_prefix("http://") || route.has_prefix("https://") {
    route
  } else {
    let clean = robot_routine_trim_base_url(base)
    if route.has_prefix("/") {
      "\{clean}\{route}"
    } else {
      "\{clean}/\{route}"
    }
  }
}

///|
fn robot_routine_runs_dir(root : String) -> String {
  @moonsuite.product_artifact_for_workspace_root(
    root, "moonclaw", "robot-routine-runs",
  )
}

///|
fn robot_routine_run_id(plan : @robot_routine.RobotRoutinePlan) -> String {
  "robot-routine-run-\{plan.plan_id}"
  .replace(old="/", new="-")
  .replace(old=":", new="-")
  .replace(old=" ", new="-")
}

///|
fn robot_routine_run_path(root : String, run_id : String) -> String {
  robot_routine_runs_dir(root) + "/\{run_id}.json"
}

///|
fn robot_routine_record_status(
  plan : @robot_routine.RobotRoutinePlan,
  invoked : Bool,
  invocation : RobotRoutineHttpTextResponse?,
  memory_refresh : RobotRoutineHttpTextResponse?,
) -> String {
  if invoked {
    match invocation {
      Some({ status: 200..=299, .. }) =>
        match memory_refresh {
          Some({ status: 200..=299, .. }) => "invoked-remembered"
          Some(_) => "memory-refresh-non-ok"
          None => "invoked"
        }
      Some(_) => "invoked-non-ok"
      None => "invoke-missing"
    }
  } else {
    plan.status
  }
}

///|
fn robot_routine_run_record(
  root : String,
  params : RobotRoutineGatewayRequest,
  plan : @robot_routine.RobotRoutinePlan,
  invoked : Bool,
  invocation : RobotRoutineHttpTextResponse?,
  memory_refresh? : RobotRoutineHttpTextResponse? = None,
  context_before? : Json = Json::null(),
  context_after? : Json = Json::null(),
  message : String,
  status? : String = "",
) -> RobotRoutineRunRecord {
  let run_id = robot_routine_run_id(plan)
  {
    run_id,
    moonrobo_url: robot_routine_trim_base_url(params.moonrobo_url),
    created_at_ms: robot_routine_now_ms(params),
    status: if status != "" {
      status
    } else {
      robot_routine_record_status(plan, invoked, invocation, memory_refresh)
    },
    invoked,
    invocation,
    memory_refresh,
    context_before,
    context_after,
    plan,
    record_path: robot_routine_run_path(root, run_id),
    message,
  }
}

///|
async fn write_robot_routine_run(
  root : String,
  record : RobotRoutineRunRecord,
) -> Result[Unit, String] {
  @fsx.make_directory(
    robot_routine_runs_dir(root),
    recursive=true,
    exists_ok=true,
  ) catch {
    error => return Err("failed to create robot routine run ledger: \{error}")
  }
  @fsx.write_to_file(record.record_path, record.to_json().stringify()) catch {
    error => return Err("failed to write robot routine run record: \{error}")
  }
  Ok(())
}

///|
async fn Gateway::persist_robot_routine_run_or_raise(
  self : Gateway,
  record : RobotRoutineRunRecord,
) -> Unit {
  match write_robot_routine_run(self.cwd, record) {
    Ok(_) => ()
    Err(message) =>
      raise json_error(
        500,
        "InternalServerError",
        robot_routine_error("robot_routine_ledger_failed", message),
      )
  }
}

///|
async fn read_robot_routine_run_path(
  path : String,
) -> Result[RobotRoutineRunRecord, String] {
  let text = @fsx.read_file(path) catch {
    error => return Err("failed to read robot routine run record: \{error}")
  }
  let json = @json.parse(text) catch {
    error => return Err("failed to parse robot routine run record: \{error}")
  }
  robot_routine_run_record_from_json(json)
}

///|
async fn read_robot_routine_run(
  root : String,
  run_id : String,
) -> Result[RobotRoutineRunRecord, String] {
  read_robot_routine_run_path(robot_routine_run_path(root, run_id))
}

///|
async fn list_robot_routine_runs(root : String) -> Array[RobotRoutineRunRecord] {
  let dir = robot_routine_runs_dir(root)
  if !(@fsx.exists(dir) catch { _ => false }) {
    return []
  }
  let records : Array[RobotRoutineRunRecord] = []
  let entries = @fsx.list_directory(dir) catch { _ => return records }
  for entry in entries {
    if !(entry.kind is Regular) || !entry.name.has_suffix(".json") {
      continue
    }
    match read_robot_routine_run_path(entry.path) {
      Ok(record) => records.push(record)
      Err(_) => ()
    }
  }
  records
}

///|
fn robot_routine_decode_request_text(
  text : String,
) -> Result[RobotRoutineGatewayRequest, String] {
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
fn robot_routine_now_ms(params : RobotRoutineGatewayRequest) -> Int64 {
  match params.now_ms {
    Some(now_ms) => now_ms
    None => current_time_ms().to_int64()
  }
}

///|
async fn robot_routine_read_request(
  r : @httpx.RequestReader,
) -> RobotRoutineGatewayRequest {
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
  match robot_routine_decode_request_text(text) {
    Ok(params) => params
    Err(message) =>
      raise json_error(
        400,
        "BadRequest",
        robot_routine_error("invalid_params", message),
      )
  }
}

///|
async fn robot_routine_get_text(
  url : String,
) -> Result[RobotRoutineHttpTextResponse, String] {
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
async fn robot_routine_post_json(
  url : String,
  body : String,
) -> Result[RobotRoutineHttpTextResponse, String] {
  let (response, data) = @http.post(url, body) catch {
    error => return Err("POST \{url} failed: \{error}")
  }
  Ok({ status: response.code, body: data.text() })
}

///|
async fn robot_routine_fetch_context(
  base_url : String,
) -> Result[String, String] {
  match
    robot_routine_get_text(
      robot_routine_join_url(base_url, "/api/moonclaw/context"),
    ) {
    Ok(response) => Ok(response.body)
    Err(message) => Err(message)
  }
}

///|
fn robot_routine_context_snapshot(context : String) -> Json {
  @json.parse(context) catch {
    _ => { "raw_context": context }.to_json()
  }
}

///|
async fn robot_routine_invoke_step(
  base_url : String,
  step : @robot_routine.RobotRoutineStep,
) -> Result[RobotRoutineHttpTextResponse, String] {
  if step.owner != "moonclaw" {
    return Err("MoonClaw cannot invoke a routine step owned by \{step.owner}")
  }
  if step.physical_execution_allowed {
    return Err(
      "selected routine step allows physical execution; explicit safety-gated invocation is not implemented yet",
    )
  }
  let url = robot_routine_join_url(base_url, step.route)
  match step.http_method {
    "GET" => robot_routine_get_text(url)
    "POST" => robot_routine_post_json(url, step.request_body)
    route_method => Err("unsupported Moonrobo route method \{route_method}")
  }
}

///|
async fn robot_routine_refresh_memory(
  base_url : String,
) -> Result[RobotRoutineHttpTextResponse, String] {
  robot_routine_post_json(
    robot_routine_join_url(base_url, "/api/moonbook/remember"),
    "{}",
  )
}

///|
fn robot_routine_plan_allows_memory_refresh(
  plan : @robot_routine.RobotRoutinePlan,
) -> Bool {
  plan.steps.any(step => {
    step.owner == "moonclaw" &&
    step.http_method == "POST" &&
    step.route == "/api/moonbook/remember"
  })
}

///|
async fn robot_routine_memory_refresh_after_invocation(
  base_url : String,
  plan : @robot_routine.RobotRoutinePlan,
  step : @robot_routine.RobotRoutineStep,
  invocation : RobotRoutineHttpTextResponse,
) -> Result[RobotRoutineHttpTextResponse, String] {
  if step.route == "/api/moonbook/remember" {
    Ok(invocation)
  } else if !robot_routine_plan_allows_memory_refresh(plan) {
    Err("MoonBook memory refresh is not registered for this robot routine plan")
  } else {
    robot_routine_refresh_memory(base_url)
  }
}

///|
async fn Gateway::select_robot_routine(
  self : Gateway,
  r : @httpx.RequestReader,
  invoke : Bool,
) -> RobotRoutineGatewayResponse {
  ignore(self)
  let params = robot_routine_read_request(r)
  let base_url = robot_routine_trim_base_url(params.moonrobo_url)
  let context = match robot_routine_fetch_context(base_url) {
    Ok(context) => context
    Err(message) =>
      raise json_error(
        502,
        "BadGateway",
        robot_routine_error("moonrobo_context_unavailable", message),
      )
  }
  let plan = match
    @robot_routine.plan_routine_from_context_text(
      context,
      now_ms=robot_routine_now_ms(params),
    ) {
    Ok(plan) => plan
    Err(message) =>
      raise json_error(
        422,
        "UnprocessableEntity",
        robot_routine_error("robot_routine_failed", message),
      )
  }
  if !invoke {
    return {
      plan,
      invoked: false,
      invocation: None,
      message: "MoonClaw planned the robot routine from Moonrobo context.",
    }
  }
  let step = match plan.next_step {
    Some(step) => step
    None =>
      raise json_error(
        409,
        "Conflict",
        robot_routine_error(
          "robot_routine_idle", "routine plan has no next step",
        ),
      )
  }
  let invocation = match robot_routine_invoke_step(base_url, step) {
    Ok(response) => response
    Err(message) =>
      raise json_error(
        409,
        "Conflict",
        robot_routine_error("robot_routine_invocation_blocked", message),
      )
  }
  {
    plan,
    invoked: true,
    invocation: Some(invocation),
    message: "MoonClaw invoked the next robot routine step.",
  }
}

///|
async fn Gateway::run_robot_routine(
  self : Gateway,
  r : @httpx.RequestReader,
) -> RobotRoutineRunRecord {
  let params = robot_routine_read_request(r)
  let base_url = robot_routine_trim_base_url(params.moonrobo_url)
  let context = match robot_routine_fetch_context(base_url) {
    Ok(context) => context
    Err(message) =>
      raise json_error(
        502,
        "BadGateway",
        robot_routine_error("moonrobo_context_unavailable", message),
      )
  }
  let context_before = robot_routine_context_snapshot(context)
  let plan = match
    @robot_routine.plan_routine_from_context_text(
      context,
      now_ms=robot_routine_now_ms(params),
    ) {
    Ok(plan) => plan
    Err(message) =>
      raise json_error(
        422,
        "UnprocessableEntity",
        robot_routine_error("robot_routine_failed", message),
      )
  }
  let step = match plan.next_step {
    Some(step) => step
    None => {
      let record = robot_routine_run_record(
        self.cwd,
        params,
        plan,
        false,
        None,
        context_before~,
        "MoonClaw persisted an idle robot routine run; ask Robo for another task.",
        status="idle",
      )
      self.persist_robot_routine_run_or_raise(record)
      raise json_error(
        409,
        "Conflict",
        robot_routine_run_error(
          "robot_routine_idle", "routine plan has no next step", record,
        ),
      )
    }
  }
  let invocation = match robot_routine_invoke_step(base_url, step) {
    Ok(response) => response
    Err(message) => {
      let status = if plan.status == "needs-operator" {
        "needs-operator"
      } else if step.physical_execution_allowed {
        "physical-execution-blocked"
      } else {
        "blocked"
      }
      let record = robot_routine_run_record(
        self.cwd,
        params,
        plan,
        false,
        None,
        context_before~,
        "MoonClaw persisted a blocked robot routine run: \{message}",
        status~,
      )
      self.persist_robot_routine_run_or_raise(record)
      raise json_error(
        409,
        "Conflict",
        robot_routine_run_error(
          "robot_routine_invocation_blocked", message, record,
        ),
      )
    }
  }
  let memory_refresh = match
    robot_routine_memory_refresh_after_invocation(
      base_url, plan, step, invocation,
    ) {
    Ok(response) => response
    Err(message) => {
      let record = robot_routine_run_record(
        self.cwd,
        params,
        plan,
        true,
        Some(invocation),
        context_before~,
        "MoonClaw invoked the robot routine step but could not refresh MoonBook memory: \{message}",
        status="memory-refresh-failed",
      )
      self.persist_robot_routine_run_or_raise(record)
      raise json_error(
        409,
        "Conflict",
        robot_routine_run_error(
          "robot_routine_memory_refresh_failed", message, record,
        ),
      )
    }
  }
  let context_after_text = match robot_routine_fetch_context(base_url) {
    Ok(context) => context
    Err(message) => {
      let record = robot_routine_run_record(
        self.cwd,
        params,
        plan,
        true,
        Some(invocation),
        memory_refresh=Some(memory_refresh),
        context_before~,
        "MoonClaw invoked the robot routine step and refreshed memory but could not read updated Moonrobo context: \{message}",
        status="context-refresh-failed",
      )
      self.persist_robot_routine_run_or_raise(record)
      raise json_error(
        409,
        "Conflict",
        robot_routine_run_error(
          "robot_routine_context_refresh_failed", message, record,
        ),
      )
    }
  }
  let context_after = robot_routine_context_snapshot(context_after_text)
  let record = robot_routine_run_record(
    self.cwd,
    params,
    plan,
    true,
    Some(invocation),
    memory_refresh=Some(memory_refresh),
    context_before~,
    context_after~,
    "MoonClaw planned, invoked, refreshed MoonBook memory, and persisted the robot routine run.",
  )
  self.persist_robot_routine_run_or_raise(record)
  record
}

///|
async fn Gateway::handle_robot_routine(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let response = self.select_robot_routine(r, false)
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(response.to_json().stringify())
}

///|
async fn Gateway::handle_robot_routine_invoke(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let response = self.select_robot_routine(r, true)
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(response.to_json().stringify())
}

///|
async fn Gateway::handle_robot_routine_run(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let response = self.run_robot_routine(r)
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(response.to_json().stringify())
}

///|
async fn Gateway::handle_list_robot_routine_runs(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let runs = list_robot_routine_runs(self.cwd)
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write({ runs, count: runs.length() }.to_json().stringify())
}

///|
async fn Gateway::handle_get_robot_routine_run(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  run_id : String,
) -> Unit {
  let record = match read_robot_routine_run(self.cwd, run_id) {
    Ok(record) => record
    Err(message) =>
      raise json_error(
        404,
        "NotFound",
        robot_routine_error("robot_routine_run_not_found", message),
      )
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(record.to_json().stringify())
}
