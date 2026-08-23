///|
#warnings("-unused_value-unused_constructor")
priv enum MoonCodeGoalHttpRoute {
  GoalGet
  GoalPut
  GoalMethodNotAllowed
  NotGoalRoute
} derive(Debug, Eq)

///|
fn mooncode_goal_http_allow() -> String {
  "GET, PUT"
}

///|
async fn mooncode_write_goal_http_response(
  w : @httpx.ResponseWriter,
  response : MoonCodeGoalApiResponse,
) -> Unit {
  w.header().set("Content-Type", "application/json")
  w.write_header(response.status_code)
  w.write(response.body.stringify(indent=2))
}

///|
#warnings("-unused_value")
fn mooncode_goal_http_route(
  method_ : String,
  segments : Array[String],
) -> MoonCodeGoalHttpRoute {
  match (method_, segments) {
    ("GET", ["", "v1", "code", "sessions", _, "goal"]) => GoalGet
    ("PUT", ["", "v1", "code", "sessions", _, "goal"]) => GoalPut
    (_, ["", "v1", "code", "sessions", _, "goal"]) => GoalMethodNotAllowed
    _ => NotGoalRoute
  }
}

///|
#warnings("-unused_value")
fn mooncode_parse_goal_http_body(text : String) -> Result[Json, String] {
  Ok(@json.parse(text)) catch {
    _ => Err("invalid_json")
  }
}

///|
#warnings("-unused_value")
async fn Daemon::mooncode_goal_get(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let response = mooncode_goal_api_get_internal(
    mooncode_request_book_root(r),
    session_id.to_owned(),
  )
  mooncode_write_goal_http_response(w, response)
}

///|
#warnings("-unused_value")
async fn Daemon::mooncode_goal_put(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  // Parse before consulting session state so malformed JSON is deterministic.
  let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
  let body : Json = reader.read() catch {
    _ => {
      mooncode_write_goal_http_response(w, goal_api_error(400, "invalid_json"))
      return
    }
  }
  let response = mooncode_goal_api_put_internal(
    mooncode_request_book_root(r),
    session_id.to_owned(),
    body,
    self.clock.now().truncate_to_s(),
  )
  mooncode_write_goal_http_response(w, response)
}

///|
#warnings("-unused_value")
async fn Daemon::mooncode_goal_method_not_allowed(
  self : Daemon,
  w : @httpx.ResponseWriter,
) -> Unit {
  w.header().set("Allow", mooncode_goal_http_allow())
  mooncode_write_goal_http_response(
    w,
    goal_api_error(405, "method_not_allowed"),
  )
}
