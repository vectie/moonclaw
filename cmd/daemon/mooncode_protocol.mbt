///|
fn mooncode_protocol_version() -> String {
  @mooncode_core.protocol_version()
}

///|
fn mooncode_native_capability_contract_id() -> String {
  @mooncode_core.native_capability_contract_id()
}

///|
fn mooncode_native_capability_required_endpoints() -> Array[String] {
  @mooncode_core.native_capability_required_endpoints()
}

///|
fn mooncode_native_capability_optional_endpoints() -> Array[String] {
  [
    "/v1/mooncode/sessions?book_root=<path>&format=listing", "/v1/mooncode/sessions/<id>/stream?book_root=<path>&format=jsonl|sse&since=<n>",
  ]
}

///|
fn mooncode_native_capability_endpoints() -> Array[String] {
  let endpoints = mooncode_native_capability_required_endpoints()
  for endpoint in mooncode_native_capability_optional_endpoints() {
    endpoints.push(endpoint)
  }
  endpoints
}

///|
fn mooncode_native_capability_tools() -> Array[String] {
  @mooncode_core.native_capability_required_tools()
}

///|
fn mooncode_native_capability_surface_fingerprint() -> String {
  @mooncode_core.native_capability_surface_fingerprint()
}

///|
fn mooncode_native_capability_surface_json() -> Json {
  {
    "kind": "mooncode-native-capability-surface",
    "component": "mooncode",
    "protocol": mooncode_protocol_version(),
    "capability_contract_id": mooncode_native_capability_contract_id(),
    "capability_surface_fingerprint": mooncode_native_capability_surface_fingerprint(),
    "required_endpoints": mooncode_native_capability_required_endpoints(),
    "optional_endpoints": mooncode_native_capability_optional_endpoints(),
    "advertised_endpoints": mooncode_native_capability_endpoints(),
    "required_tools": mooncode_native_capability_tools(),
  }
}

///|
fn mooncode_kind_runtime_turn() -> String {
  "mooncode-runtime-turn"
}

///|
fn mooncode_kind_runtime_turn_planner() -> String {
  "mooncode-runtime-turn-planner"
}

///|
fn mooncode_kind_runtime_dispatch() -> String {
  "mooncode.runtime-dispatch"
}

///|
fn mooncode_event_tool_call() -> String {
  "tool_call"
}

///|
fn mooncode_event_tool_result() -> String {
  "tool_result"
}

///|
fn mooncode_event_test_result() -> String {
  "test_result"
}

///|
fn mooncode_event_package_built() -> String {
  "package_built"
}

///|
fn mooncode_event_package_verified() -> String {
  "package_verified"
}

///|
fn mooncode_event_steer_applied() -> String {
  "steer_applied"
}

///|
fn mooncode_event_steer_dropped() -> String {
  "steer_dropped"
}

///|
fn mooncode_event_steer_deferred() -> String {
  "steer_deferred"
}

///|
fn mooncode_event_cancel_dropped() -> String {
  "cancel_dropped"
}

///|
fn mooncode_event_runtime_turn_finished() -> String {
  "runtime.turn_finished"
}

///|
fn mooncode_planner_mode_model_tool_calls() -> String {
  "model-tool-calls"
}

///|
fn mooncode_planner_mode_deterministic_fallback() -> String {
  "deterministic-fallback"
}

///|
fn mooncode_planner_mode_serve_scheduler_control() -> String {
  "serve-scheduler-control"
}
