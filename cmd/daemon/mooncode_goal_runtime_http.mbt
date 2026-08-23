///|
#warnings("-unused_constructor")
priv enum MoonCodeGoalRuntimeHttpRoute {
  GoalRuntimeGet
  GoalRuntimePut
  GoalRuntimeMethodNotAllowed
  NotGoalRuntimeRoute
}

///|
fn mooncode_goal_runtime_http_allow() -> String {
  "GET, PUT"
}

///|
async fn mooncode_write_goal_runtime_http_response(
  w : @httpx.ResponseWriter,
  response : MoonCodeGoalRuntimeApiResponse,
) -> Unit {
  w.header().set("Content-Type", "application/json")
  w.write_header(response.status_code)
  w.write(response.body.stringify(indent=2))
}

///|
async fn Daemon::mooncode_goal_runtime_get(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  ignore(self)
  let response = mooncode_goal_runtime_api_get_internal(
    mooncode_request_book_root(r),
    session_id.to_owned(),
  )
  mooncode_write_goal_runtime_http_response(w, response)
}

///|
async fn Daemon::mooncode_goal_runtime_put(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
  let body : Json = reader.read() catch {
    _ => {
      mooncode_write_goal_runtime_http_response(
        w,
        mooncode_goal_runtime_api_error(400, "invalid_json"),
      )
      return
    }
  }
  let response = mooncode_goal_runtime_api_put_internal(
    mooncode_request_book_root(r),
    session_id.to_owned(),
    body,
    self.clock.now().truncate_to_s(),
  )
  mooncode_write_goal_runtime_http_response(w, response)
}

///|
async fn Daemon::mooncode_goal_runtime_method_not_allowed(
  self : Daemon,
  w : @httpx.ResponseWriter,
) -> Unit {
  ignore(self)
  w.header().set("Allow", mooncode_goal_runtime_http_allow())
  mooncode_write_goal_runtime_http_response(
    w,
    mooncode_goal_runtime_api_error(405, "method_not_allowed"),
  )
}

///|
#warnings("-unused_value")
fn mooncode_goal_runtime_http_route(
  method_name : String,
  segments : Array[String],
) -> MoonCodeGoalRuntimeHttpRoute {
  match (method_name, segments) {
    ("GET", ["", "v1", "code", "sessions", _, "goal-runtime"]) => GoalRuntimeGet
    ("PUT", ["", "v1", "code", "sessions", _, "goal-runtime"]) => GoalRuntimePut
    (_, ["", "v1", "code", "sessions", _, "goal-runtime"]) =>
      GoalRuntimeMethodNotAllowed
    _ => NotGoalRuntimeRoute
  }
}
