///|
pub fn protocol_version() -> String {
  "mooncode.v1"
}

///|
fn product_id() -> String {
  "mooncode"
}

///|
pub fn conversation_contract_id() -> String {
  "moonsuite-conversation.v3"
}

///|
pub fn session_snapshot_contract_id() -> String {
  "mooncode-session-snapshot.v2"
}

///|
pub fn session_record_contract_id() -> String {
  "mooncode-session-record.v2"
}

///|
pub fn session_listing_contract_id() -> String {
  "mooncode-session-listing.v2"
}

///|
pub fn conversation_kind() -> String {
  @conversation.conversation_kind(product_id=product_id())
}

///|
pub fn conversation_turn_kind() -> String {
  @conversation.turn_kind(product_id=product_id())
}

///|
pub fn conversation_message_roles() -> Array[String] {
  ["user", "work", "assistant"]
}

///|
pub fn conversation_turn_required_fields() -> Array[String] {
  [
    "kind", "turn_id", "client_turn_id", "command_id", "ordinal", "status", "user",
    "work", "assistant",
  ]
}

///|
pub fn conversation_contract_json() -> Json {
  {
    "kind": "moonsuite-conversation-contract",
    "protocol": protocol_version(),
    "contract_id": conversation_contract_id(),
    "product_id": product_id(),
    "conversation_kind": conversation_kind(),
    "turn_kind": conversation_turn_kind(),
    "conversation_required_fields": [
      "contract_id", "session_id", "revision", "last_sequence", "turns",
    ],
    "sequence_encoding": "canonical nonnegative decimal JSON string",
    "sequence_fields": ["revision", "last_sequence"],
    "sequence_rules": [
      "revision equals last_sequence for a complete journal projection", "sequence values compare by arbitrary-precision decimal magnitude",
      "sequence values never decrease across authoritative replay",
    ],
    "journal_write_contract_id": journal_contract_id(),
    "journal_read_contract_ids": journal_read_contract_ids(),
    "watch_write_contract": conversation_watch_exact_contract_json(),
    "watch_read_contract_ids": conversation_watch_read_contract_ids(),
    "turn_required_fields": conversation_turn_required_fields(),
    "slot_required_fields": ["item_id", "status"],
    "work_required_fields": ["item_id", "status", "summary", "steps", "live"],
    "work_step_kinds": [
      "thought", "context", "tool", "edit", "test", "artifact", "status",
    ],
    "turn_order": conversation_message_roles(),
    "identity_fields": ["turn_id", "client_turn_id", "command_id", "ordinal"],
    "ownership": {
      "durable_owner": "mooncode",
      "projection_owner": "moonclaw",
      "ui_owner": "moondesk",
      "contract_owner": "mooncode",
      "base_contract_owner": "moonlib",
    },
  }
}

///|
pub fn native_capability_contract_id() -> String {
  "mooncode-native-capability-surface.v2"
}

///|
pub fn native_capability_required_endpoints() -> Array[String] {
  native_capability_endpoints().required_endpoints()
}

///|
pub fn native_capability_required_tools() -> Array[String] {
  runtime_tool_native_required_tools()
}

///|
pub fn native_command_body_required_fields() -> Array[String] {
  ["protocol", "session_id", "book_root", "packet"]
}

///|
pub fn native_command_body_supported_fields() -> Array[String] {
  [
    "protocol", "command", "text", "model", "session_id", "book_root", "context_path",
    "payload", "packet", "execution_plan", "tool_authorization", "tool_contract",
    "result_contract", "owner", "web_search", "runtime_tool_calls", "deferred_steering",
    "content_parts", "model_workspace",
  ]
}

///|
pub fn native_command_body_field_is_supported(name : String) -> Bool {
  native_command_body_supported_fields().contains(name)
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
    "idle_semantics": "When live_wait_ms is zero, runtime-loop preserves immediate idle behavior; when positive, it polls the authoritative session journal until a claimable command record appears or the wait budget expires.",
  }
}

///|
pub fn native_capability_stream_options() -> Json {
  {
    "stream_contract_id": "mooncode-stream.v2",
    "since_encoding": "canonical nonnegative decimal text",
    "sequence_encoding": "canonical nonnegative decimal JSON string",
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
    "snapshot_semantics": "When wait_ms is zero, stream preserves immediate replay behavior; when positive, it polls journal.jsonl until an event record with a sequence newer than since appears or the wait budget expires.",
  }
}

///|
fn native_capability_surface_fingerprint_source() -> String {
  let required_endpoints = native_capability_required_endpoints().join("\n")
  let required_tools = native_capability_required_tools().join("\n")
  let supported_runtime_tools = runtime_tool_names().join("\n")
  let supported_event_lanes = event_lanes().join("\n")
  let supported_runtime_events = runtime_event_names().join("\n")
  let supported_command_actions = command_supported_actions().join("\n")
  let native_command_contract = native_command_execution_contract_json().stringify()
  let command_body_required_fields = native_command_body_required_fields().join(
    "\n",
  )
  let command_body_supported_fields = native_command_body_supported_fields().join(
    "\n",
  )
  let loop_options = native_capability_runtime_loop_options().stringify()
  let stream_options = native_capability_stream_options().stringify()
  [
    "kind=mooncode-native-capability-surface",
    "component=mooncode",
    "protocol=\{protocol_version()}",
    "capability_contract_id=\{native_capability_contract_id()}",
    "conversation_contract_id=\{conversation_contract_id()}",
    "conversation_watch_write_contract_id=\{conversation_watch_exact_contract_id()}",
    "conversation_watch_read_contract_ids=\{conversation_watch_read_contract_ids().join(",")}",
    "journal_write_contract_id=\{journal_contract_id()}",
    "journal_read_contract_ids=\{journal_read_contract_ids().join(",")}",
    "session_snapshot_contract_id=\{session_snapshot_contract_id()}",
    "session_record_contract_id=\{session_record_contract_id()}",
    "session_listing_contract_id=\{session_listing_contract_id()}",
    "runtime_tool_contract_id=\{runtime_tool_contract_id()}",
    "runtime_tool_names=\{supported_runtime_tools}",
    "event_lane_contract_id=\{event_lane_contract_id()}",
    "event_lanes=\{supported_event_lanes}",
    "runtime_event_name_contract_id=\{runtime_event_name_contract_id()}",
    "runtime_event_names=\{supported_runtime_events}",
    "native_event_projection_contract_id=\{native_event_projection_contract_id()}",
    "model_planner_evidence_contract_id=\{model_planner_evidence_contract_id()}",
    "conversation_ownership_contract_id=\{conversation_ownership_contract_id()}",
    "runtime_control_contract_id=\{runtime_control_contract_id()}",
    "runtime_consumer_contract_id=\{runtime_consumer_contract_id()}",
    "command_action_contract_id=\{command_action_contract_id()}",
    "native_command_contract_id=\{native_command_contract_id()}",
    "native_command_contract=\{native_command_contract}",
    "command_actions=\{supported_command_actions}",
    "required_endpoints=\{required_endpoints}",
    "required_tools=\{required_tools}",
    "command_body_required_fields=\{command_body_required_fields}",
    "command_body_supported_fields=\{command_body_supported_fields}",
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
    "conversation_contract": conversation_contract_json(),
    "conversation_watch_write_contract": conversation_watch_exact_contract_json(),
    "conversation_watch_read_contract_ids": conversation_watch_read_contract_ids(),
    "journal_write_contract_id": journal_contract_id(),
    "journal_read_contract_ids": journal_read_contract_ids(),
    "session_contracts": {
      "snapshot": session_snapshot_contract_id(),
      "record": session_record_contract_id(),
      "listing": session_listing_contract_id(),
    },
    "event_lane_contract": event_lane_contract_json(),
    "runtime_event_name_contract": runtime_event_name_contract_json(),
    "native_event_projection_contract": native_event_projection_contract_json(),
    "model_planner_evidence_contract": model_planner_evidence_contract_json(),
    "conversation_ownership_contract": conversation_ownership_contract_json(),
    "runtime_control_contract": runtime_control_contract_json(),
    "runtime_consumer_contract": runtime_consumer_contract_json("<id>"),
    "command_action_contract": command_action_contract_json(),
    "native_command_execution_contract": native_command_execution_contract_json(),
    "runtime_tool_contract": runtime_tool_contract_json(),
    "runtime_tool_call_contract": runtime_tool_call_contract_json(),
    "required_endpoints": native_capability_required_endpoints(),
    "required_tools": native_capability_required_tools(),
    "command_body_required_fields": native_command_body_required_fields(),
    "command_body_supported_fields": native_command_body_supported_fields(),
    "runtime_loop_options": native_capability_runtime_loop_options(),
    "stream_options": native_capability_stream_options(),
  }
}

///|
pub fn standalone_boundary_json() -> Json {
  {
    "kind": "mooncode-standalone-boundary",
    "protocol": protocol_version(),
    "core_package": "mooncode/core",
    "projection_component": "mooncode.projection",
    "host_component": "book.host",
    "runtime_component": "moonclaw.standalone-runtime",
    "runtime_substrate": "moonclaw.shared-runtime",
    "lanes": [
      {
        "id": "mooncode-coding-lane",
        "owner": "mooncode",
        "responsibility": "Executable-book coding turns, diffs, tests, packages, and proof artifacts over the shared MoonClaw runtime substrate.",
      },
      {
        "id": "book-workflow-lane",
        "owner": "book-host",
        "responsibility": "Human-language book edits and review workflows that may call MoonClaw by protocol without becoming the coding lane.",
      },
      {
        "id": "moonclaw-task-lane",
        "owner": "moonclaw",
        "responsibility": "Generic bounded background jobs kept separate from MoonCode sessions.",
      },
    ],
    "roles": [
      {
        "id": "mooncode-core",
        "owner": "mooncode",
        "responsibility": "Stable protocol ids, native MoonCode capability surface, standalone boundary, and cross-project contracts without host, UI, or runtime implementation dependencies.",
      },
      {
        "id": "mooncode-projection",
        "owner": "host-shell",
        "responsibility": "Book-scoped command, event, stream, review, runtime, test, package, and eval projections used by a host shell.",
      },
      {
        "id": "book-host",
        "owner": "host-shell",
        "responsibility": "HTTP or local routes plus MoonBook file persistence for wiki/reviews/mooncode and durable MoonCode session sidecars.",
      },
      {
        "id": "moonclaw-standalone-runtime",
        "owner": "moonclaw",
        "responsibility": "Standalone shared runtime substrate for agent sessions, model calls, tool execution, cancellation, event streams, durable coding sessions, tests/builds, package result production, and generic task jobs.",
      },
    ],
    "rules": [
      "mooncode/core must contain only stable protocol and capability contracts",
      "projection components may import mooncode/core but must remain UI-free", "host components may persist and route MoonCode records but must not own the coding runtime loop",
      "MoonClaw must remain usable as a standalone agent runtime outside MoonDesk",
      "MoonCode, book workflows, and generic tasks share MoonClaw runtime primitives but keep separate typed protocols",
      "runtime engines must own tool execution and runtime sessions behind the MoonCode contract",
    ],
  }
}
