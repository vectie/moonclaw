///|
pub fn conversation_ownership_contract_id() -> String {
  "mooncode-conversation-ownership.v1"
}

///|
pub fn conversation_ownership_contract_kind() -> String {
  "mooncode-conversation-ownership-contract"
}

///|
pub fn conversation_ownership_contract_json() -> Json {
  {
    "kind": conversation_ownership_contract_kind(),
    "protocol": protocol_version(),
    "contract_id": conversation_ownership_contract_id(),
    "conversation_contract_id": conversation_contract_id(),
    "owner": {
      "projection": "mooncode",
      "ui": "moondesk",
      "runtime": "moonclaw",
    },
    "visible_owner_rule": "Every visible progress, assistant, failure, abort, and recovery row must carry command_id, turn_id, client_turn_id, runtime_session_id, run_id, action, and event_id ownership fields.",
    "unowned_event_rule": "Unscoped runtime/progress/assistant/failure events are durable diagnostics only and must not attach to the latest active turn.",
    "control_rule": "Steer and cancel command evidence stays in folded control lifecycle projections unless MoonClaw emits command-scoped user-visible failure or abort evidence for the affected prompt turn.",
    "abort_rule": "runtime_aborted closes a visible chat turn only when it is scoped to a non-control command; cancel-scoped runtime_aborted settles the cancel lifecycle instead.",
  }
}
