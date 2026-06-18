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
    "/v1/mooncode/sessions/<id>/stream?book_root=<path>&format=jsonl|sse&since=<n>&wait_ms=<ms>&poll_ms=<ms>",
    "/v1/mooncode/sessions/<id>/runtime-dispatch?book_root=<path>", "/v1/mooncode/sessions/<id>/runtime-turn?book_root=<path>",
    "/v1/mooncode/sessions/<id>/runtime-loop?book_root=<path>", "/v1/mooncode/sessions/<id>/runtime-service?book_root=<path>",
    "/v1/mooncode/sessions/<id>/runtime-events?book_root=<path>", "/v1/mooncode/sessions/<id>/tool-exec?book_root=<path>",
    "/v1/mooncode/sessions/<id>/eval-report?book_root=<path>", "/v1/mooncode/sessions/<id>/package-result?book_root=<path>",
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
pub fn native_capability_runtime_loop_options() -> Json {
  {
    "live_wait_ms": {
      "default": 0,
      "min": 0,
      "max": 30000,
      "purpose": "Opt-in bounded wait for new prompt, steer, or cancel commands before the native runtime loop returns idle.",
    },
    "poll_ms": {
      "default": 250,
      "min": 25,
      "max": 2000,
      "purpose": "Polling interval while live_wait_ms is active.",
    },
    "idle_semantics": "When live_wait_ms is zero, runtime-loop preserves immediate idle behavior; when positive, it polls commands.jsonl until a claimable command appears or the wait budget expires.",
  }
}

///|
pub fn native_capability_stream_options() -> Json {
  {
    "wait_ms": {
      "default": 0,
      "min": 0,
      "max": 30000,
      "purpose": "Opt-in bounded long-poll wait for new durable MoonCode events after the requested stream sequence.",
    },
    "poll_ms": {
      "default": 100,
      "min": 25,
      "max": 2000,
      "purpose": "Polling interval while wait_ms is active.",
    },
    "snapshot_semantics": "When wait_ms is zero, stream preserves immediate replay behavior; when positive, it polls events.jsonl until a sequence newer than since appears or the wait budget expires.",
  }
}

///|
fn native_capability_surface_fingerprint_source() -> String {
  let required_endpoints = native_capability_required_endpoints().join("\n")
  let required_tools = native_capability_required_tools().join("\n")
  let loop_options = native_capability_runtime_loop_options().stringify()
  let stream_options = native_capability_stream_options().stringify()
  [
    "kind=mooncode-native-capability-surface",
    "component=mooncode",
    "protocol=\{protocol_version()}",
    "capability_contract_id=\{native_capability_contract_id()}",
    "required_endpoints=\{required_endpoints}",
    "required_tools=\{required_tools}",
    "runtime_loop_options=\{loop_options}",
    "stream_options=\{stream_options}",
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
    "runtime_loop_options": native_capability_runtime_loop_options(),
    "stream_options": native_capability_stream_options(),
  }
}

///|
pub fn extraction_boundary_json() -> Json {
  {
    "kind": "mooncode-extraction-boundary",
    "protocol": protocol_version(),
    "portable_core_package": "vectie/moondesk/mooncode/core",
    "moondesk_projection_package": "vectie/moondesk/internal/mooncode",
    "moonwiki_host_package": "vectie/moondesk/internal/moonwiki",
    "future_standalone_package": "mooncode",
    "roles": [
      {
        "id": "portable-core",
        "package": "mooncode/core",
        "owner": "mooncode",
        "responsibility": "Stable protocol ids, native MoonCode capability surface, extraction boundary, and cross-repo contracts that MoonClaw or standalone MoonCode can share without Moondesk UI dependencies.",
      },
      {
        "id": "moondesk-projection",
        "package": "internal/mooncode",
        "owner": "moondesk",
        "responsibility": "Book-scoped command, event, stream, review, runtime, test, package, and eval projections used by the Moondesk UI and HTTP adapter.",
      },
      {
        "id": "moonwiki-host",
        "package": "internal/moonwiki",
        "owner": "moonwiki",
        "responsibility": "HTTP routes and MoonBook file persistence for wiki/reviews/mooncode and .moontown/mooncode-sessions sidecars.",
      },
      {
        "id": "runtime-engine",
        "package": "../moonclaw",
        "owner": "moonclaw",
        "responsibility": "Typed agent loop, model calls, tool execution, durable coding sessions, streaming events, tests/builds, and package result production.",
      },
    ],
    "rules": [
      "mooncode/core must not import internal/mooncode or internal/moonwiki", "internal/mooncode may import mooncode/core but should remain UI-free",
      "internal/moonwiki may persist and route MoonCode records but must not own the coding agent loop",
      "MoonClaw or standalone mooncode must own tool execution and runtime sessions",
    ],
  }
}
