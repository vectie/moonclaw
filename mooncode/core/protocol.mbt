///|
pub fn protocol_version() -> String {
  "mooncode.v1"
}

///|
pub fn native_capability_contract_id() -> String {
  "mooncode-native-capability-surface.v1"
}

///|
pub fn native_capability_required_endpoints() -> Array[String] {
  [
    "/v1/mooncode/capabilities", "/v1/mooncode/sessions?book_root=<path>", "/v1/mooncode/sessions?book_root=<path>&format=json",
    "/v1/mooncode/sessions/<id>?book_root=<path>", "/v1/mooncode/sessions/<id>/commands",
    "/v1/mooncode/sessions/<id>/serve-scheduler?book_root=<path>", "/v1/mooncode/sessions/<id>/runtime-claim?book_root=<path>",
    "/v1/mooncode/sessions/<id>/runtime-dispatch?book_root=<path>", "/v1/mooncode/sessions/<id>/runtime-turn?book_root=<path>",
    "/v1/mooncode/sessions/<id>/runtime-loop?book_root=<path>", "/v1/mooncode/sessions/<id>/runtime-events?book_root=<path>",
    "/v1/mooncode/sessions/<id>/tool-exec?book_root=<path>", "/v1/mooncode/sessions/<id>/eval-report?book_root=<path>",
    "/v1/mooncode/sessions/<id>/package-result?book_root=<path>",
  ]
}

///|
pub fn native_capability_required_tools() -> Array[String] {
  [
    "read", "edit", "write", "apply_patch", "revert_patch", "shell", "moon_ide",
    "moon_cmd", "moon_check", "finish",
  ]
}

///|
fn native_capability_surface_fingerprint_source() -> String {
  let required_endpoints = native_capability_required_endpoints().join("\n")
  let required_tools = native_capability_required_tools().join("\n")
  [
    "kind=mooncode-native-capability-surface",
    "component=mooncode",
    "protocol=\{protocol_version()}",
    "capability_contract_id=\{native_capability_contract_id()}",
    "required_endpoints=\{required_endpoints}",
    "required_tools=\{required_tools}",
  ].join("\n")
}

///|
pub fn native_capability_surface_fingerprint() -> String {
  @crypto.bytes_to_hex_string(
    @crypto.sha256(
      @encoding/utf8.encode(native_capability_surface_fingerprint_source()).to_fixedarray(),
    ),
  )
}

///|
pub fn native_capability_surface_json() -> Json {
  {
    "kind": "mooncode-native-capability-surface",
    "component": "mooncode",
    "protocol": protocol_version(),
    "capability_contract_id": native_capability_contract_id(),
    "capability_surface_fingerprint": native_capability_surface_fingerprint(),
    "required_endpoints": native_capability_required_endpoints(),
    "required_tools": native_capability_required_tools(),
  }
}
