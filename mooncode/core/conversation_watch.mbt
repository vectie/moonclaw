///|
pub fn conversation_watch_contract_id() -> String {
  @conversation.watch_contract_id()
}

///|
pub fn conversation_watch_kind() -> String {
  @conversation.watch_kind()
}

///|
pub fn conversation_watch_contract_json() -> Json {
  @conversation.watch_contract_json()
}

///|
/// Exact watch contract for conversation v3 arbitrary-precision cursors.
pub fn conversation_watch_exact_contract_id() -> String {
  "moonsuite-conversation-watch.v2"
}

///|
/// The exact v2 contract is current for writes; bounded MoonLib v1 remains
/// readable during migration.
pub fn conversation_watch_read_contract_ids() -> Array[String] {
  [conversation_watch_contract_id(), conversation_watch_exact_contract_id()]
}

///|
pub fn conversation_watch_exact_contract_json() -> Json {
  {
    "kind": "moonsuite-conversation-watch-contract",
    "contract_id": conversation_watch_exact_contract_id(),
    "required_fields": [
      "contract_id", "session_id", "revision", "next_sequence", "changed", "heartbeat",
      "terminal", "retry_after_ms", "snapshot",
    ],
    "cursor_encoding": "canonical nonnegative decimal JSON string",
    "resume_rule": "Resume with the last accepted revision and next_sequence; arbitrary-precision cursors may advance but never move backward.",
    "payload_rule": "Changed responses carry one canonical snapshot. Heartbeats carry no transcript rows, runtime events, or diagnostic records.",
    "contract_owner": "mooncode",
    "base_contract_owner": "moonlib",
  }
}

///|
pub fn conversation_watch_response_exact(
  session_id~ : String,
  revision~ : String,
  next_sequence~ : String,
  changed~ : Bool,
  heartbeat~ : Bool,
  terminal~ : Bool,
  retry_after_ms~ : Int,
  snapshot~ : Json,
) -> Json raise {
  require_exact_cursor("conversation watch revision", revision)
  require_exact_cursor("conversation watch next_sequence", next_sequence)
  {
    "kind": conversation_watch_kind(),
    "contract_id": conversation_watch_exact_contract_id(),
    "session_id": session_id,
    "revision": revision,
    "next_sequence": next_sequence,
    "changed": changed,
    "heartbeat": heartbeat,
    "terminal": terminal,
    "retry_after_ms": @conversation.watch_retry_after_ms_value(retry_after_ms),
    "snapshot": snapshot,
  }
}

///|
pub fn conversation_watch_response(
  session_id~ : String,
  revision~ : Int,
  next_sequence~ : Int,
  changed~ : Bool,
  heartbeat~ : Bool,
  terminal~ : Bool,
  retry_after_ms~ : Int,
  snapshot~ : Json,
) -> Json {
  @conversation.watch_response(
    session_id~,
    revision~,
    next_sequence~,
    changed~,
    heartbeat~,
    terminal~,
    retry_after_ms~,
    snapshot~,
  )
}
