///|
pub(all) struct NativeCapabilityEndpoints {
  capabilities : String
  session_list : String
  session_listing : String
  session_show : String
  session_commands : String
  session_turns : String
  runtime_control : String
  runtime_claim : String
  stream : String
  runtime_turn : String
  runtime_loop : String
  runtime_service : String
  runtime_events : String
  tool_exec : String
  eval_report : String
  package_result : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn native_capability_endpoints() -> NativeCapabilityEndpoints {
  {
    capabilities: "/v1/code/capabilities",
    session_list: "/v1/code/sessions?book_root=<path>",
    session_listing: "/v1/code/sessions?book_root=<path>&format=listing",
    session_show: "/v1/code/sessions/<id>?book_root=<path>",
    session_commands: "/v1/code/sessions/<id>/commands",
    session_turns: "/v1/code/sessions/<id>/turns",
    runtime_control: "/v1/code/sessions/<id>/runtime-control?book_root=<path>",
    runtime_claim: "/v1/code/sessions/<id>/runtime-claim?book_root=<path>",
    stream: "/v1/code/sessions/<id>/stream?book_root=<path>&format=jsonl|sse&since=<n>&wait_ms=<ms>&poll_ms=<ms>",
    runtime_turn: "/v1/code/sessions/<id>/runtime-turn?book_root=<path>",
    runtime_loop: "/v1/code/sessions/<id>/runtime-loop?book_root=<path>",
    runtime_service: "/v1/code/sessions/<id>/runtime-service?book_root=<path>",
    runtime_events: "/v1/code/sessions/<id>/runtime-events?book_root=<path>",
    tool_exec: "/v1/code/sessions/<id>/tool-exec?book_root=<path>",
    eval_report: "/v1/code/sessions/<id>/eval-report?book_root=<path>",
    package_result: "/v1/code/sessions/<id>/package-result?book_root=<path>",
  }
}

///|
pub fn NativeCapabilityEndpoints::required_endpoints(
  self : NativeCapabilityEndpoints,
) -> Array[String] {
  [
    self.capabilities,
    self.session_list,
    self.session_listing,
    self.session_show,
    self.session_commands,
    self.session_turns,
    self.runtime_control,
    self.runtime_claim,
    self.stream,
    self.runtime_turn,
    self.runtime_loop,
    self.runtime_service,
    self.runtime_events,
    self.tool_exec,
    self.eval_report,
    self.package_result,
  ]
}

///|
pub fn native_capability_target_description() -> String {
  let endpoints = native_capability_required_endpoints()
  if endpoints.length() == 0 {
    ""
  } else if endpoints.length() == 1 {
    endpoints[0]
  } else {
    let first = endpoints[0]
    let rest : Array[String] = []
    for i in 1..<endpoints.length() {
      rest.push(endpoints[i])
    }
    first + " plus " + rest.join(", ")
  }
}

///|
pub fn native_endpoint_component(value : String) -> String {
  let pieces : Array[String] = []
  for byte in @encoding/utf8.encode(value) {
    if native_endpoint_unreserved_byte(byte) {
      pieces.push(byte.to_char().to_string())
    } else {
      pieces.push(native_endpoint_percent_encoded_byte(byte))
    }
  }
  pieces.join("")
}

///|
fn native_endpoint_unreserved_byte(byte : Byte) -> Bool {
  (byte >= b'a' && byte <= b'z') ||
  (byte >= b'A' && byte <= b'Z') ||
  (byte >= b'0' && byte <= b'9') ||
  byte == b'-' ||
  byte == b'_' ||
  byte == b'.' ||
  byte == b'~'
}

///|
fn native_endpoint_percent_encoded_byte(byte : Byte) -> String {
  let value = byte.to_int()
  "%" +
  native_endpoint_hex_digit(value / 16) +
  native_endpoint_hex_digit(value % 16)
}

///|
fn native_endpoint_hex_digit(value : Int) -> String {
  match value {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "A"
    11 => "B"
    12 => "C"
    13 => "D"
    14 => "E"
    _ => "F"
  }
}

///|
fn native_endpoint_path(segments : Array[String]) -> String {
  let encoded : Array[String] = []
  for segment in segments {
    encoded.push(native_endpoint_component(segment))
  }
  "/" + encoded.join("/")
}

///|
fn native_endpoint_query(query : Array[(String, String)]) -> String {
  let fields : Array[String] = []
  for field in query {
    let (key, value) = field
    fields.push(
      native_endpoint_component(key) + "=" + native_endpoint_component(value),
    )
  }
  fields.join("&")
}

///|
fn native_endpoint_url(
  segments : Array[String],
  query? : Array[(String, String)] = [],
) -> String {
  let path = native_endpoint_path(segments)
  if query.length() == 0 {
    path
  } else {
    path + "?" + native_endpoint_query(query)
  }
}

///|
pub fn native_capabilities_endpoint() -> String {
  native_endpoint_url(["v1", "code", "capabilities"])
}

///|
pub fn native_session_list_endpoint(book_root : String) -> String {
  native_endpoint_url(["v1", "code", "sessions"], query=[
    ("book_root", book_root),
  ])
}

///|
pub fn native_session_listing_endpoint(book_root : String) -> String {
  native_endpoint_url(["v1", "code", "sessions"], query=[
    ("book_root", book_root),
    ("format", "listing"),
  ])
}

///|
pub fn native_session_show_endpoint(
  session_id : String,
  book_root : String,
) -> String {
  native_endpoint_url(["v1", "code", "sessions", session_id], query=[
    ("book_root", book_root),
  ])
}

///|
pub fn native_session_commands_endpoint(session_id : String) -> String {
  native_endpoint_url(["v1", "code", "sessions", session_id, "commands"])
}

///|
pub fn native_session_turns_endpoint(session_id : String) -> String {
  native_endpoint_url(["v1", "code", "sessions", session_id, "turns"])
}

///|
pub fn native_runtime_control_endpoint(
  session_id : String,
  book_root : String,
) -> String {
  native_endpoint_url(
    ["v1", "code", "sessions", session_id, "runtime-control"],
    query=[("book_root", book_root)],
  )
}

///|
pub fn native_runtime_claim_endpoint(
  session_id : String,
  book_root : String,
) -> String {
  native_endpoint_url(["v1", "code", "sessions", session_id, "runtime-claim"], query=[
    ("book_root", book_root),
  ])
}

///|
pub fn native_stream_endpoint(
  session_id : String,
  book_root : String,
  format : String,
  since : Int,
  wait_ms? : Int = 0,
  poll_ms? : Int = 100,
) -> String {
  native_endpoint_url(["v1", "code", "sessions", session_id, "stream"], query=[
    ("book_root", book_root),
    ("format", format),
    ("since", "\{since}"),
    ("wait_ms", "\{wait_ms}"),
    ("poll_ms", "\{poll_ms}"),
  ])
}

///|
pub fn native_runtime_turn_endpoint(
  session_id : String,
  book_root : String,
) -> String {
  native_endpoint_url(["v1", "code", "sessions", session_id, "runtime-turn"], query=[
    ("book_root", book_root),
  ])
}

///|
pub fn native_runtime_loop_endpoint(
  session_id : String,
  book_root : String,
) -> String {
  native_endpoint_url(["v1", "code", "sessions", session_id, "runtime-loop"], query=[
    ("book_root", book_root),
  ])
}

///|
pub fn native_runtime_service_endpoint(
  session_id : String,
  book_root : String,
) -> String {
  native_endpoint_url(
    ["v1", "code", "sessions", session_id, "runtime-service"],
    query=[("book_root", book_root)],
  )
}

///|
pub fn native_runtime_events_endpoint(
  session_id : String,
  book_root : String,
) -> String {
  native_endpoint_url(
    ["v1", "code", "sessions", session_id, "runtime-events"],
    query=[("book_root", book_root)],
  )
}

///|
pub fn native_tool_exec_endpoint(
  session_id : String,
  book_root : String,
) -> String {
  native_endpoint_url(["v1", "code", "sessions", session_id, "tool-exec"], query=[
    ("book_root", book_root),
  ])
}

///|
pub fn native_eval_report_endpoint(
  session_id : String,
  book_root : String,
) -> String {
  native_endpoint_url(["v1", "code", "sessions", session_id, "eval-report"], query=[
    ("book_root", book_root),
  ])
}

///|
pub fn native_package_result_endpoint(
  session_id : String,
  book_root : String,
) -> String {
  native_endpoint_url(
    ["v1", "code", "sessions", session_id, "package-result"],
    query=[("book_root", book_root)],
  )
}
