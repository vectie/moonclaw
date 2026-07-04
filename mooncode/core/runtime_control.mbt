///|
pub fn runtime_control_contract_id() -> String {
  "mooncode-runtime-control.v1"
}

///|
pub fn runtime_control_contract_kind() -> String {
  "mooncode-runtime-control-contract"
}

///|
pub fn runtime_control_state_kind() -> String {
  "mooncode-runtime-control-state"
}

///|
pub fn runtime_control_scheduler_boundary_unit() -> String {
  "native-runtime-scheduler-boundary"
}

///|
pub fn runtime_control_status_pending() -> String {
  "pending"
}

///|
pub fn runtime_control_status_running() -> String {
  "running"
}

///|
pub fn runtime_control_status_runtime_started() -> String {
  "runtime-started"
}

///|
pub fn runtime_control_status_completed() -> String {
  "completed"
}

///|
pub fn runtime_control_status_failed() -> String {
  "failed"
}

///|
pub fn runtime_control_status_blocked_invalid() -> String {
  "blocked-invalid"
}

///|
pub fn runtime_control_status_blocked_tool_authorization() -> String {
  "blocked-tool-authorization"
}

///|
pub fn runtime_control_status_blocked_missing_proof() -> String {
  "blocked-missing-proof"
}

///|
pub fn runtime_control_active_statuses() -> Array[String] {
  [runtime_control_status_running(), runtime_control_status_runtime_started()]
}

///|
pub fn runtime_control_terminal_statuses() -> Array[String] {
  [runtime_control_status_completed(), runtime_control_status_failed()]
}

///|
pub fn runtime_control_blocked_statuses() -> Array[String] {
  [
    runtime_control_status_blocked_invalid(),
    runtime_control_status_blocked_tool_authorization(),
    runtime_control_status_blocked_missing_proof(),
  ]
}

///|
pub fn runtime_control_effect_start_turn() -> String {
  "start-turn"
}

///|
pub fn runtime_control_effect_active_turn() -> String {
  "active-turn"
}

///|
pub fn runtime_control_effect_queue_turn() -> String {
  "queue-turn"
}

///|
pub fn runtime_control_effect_deliver_steer() -> String {
  "deliver-steer"
}

///|
pub fn runtime_control_effect_queue_steer() -> String {
  "queue-steer"
}

///|
pub fn runtime_control_effect_defer_steer() -> String {
  "defer-steer"
}

///|
pub fn runtime_control_effect_cancel_active() -> String {
  "cancel-active"
}

///|
pub fn runtime_control_effect_withdraw_pending() -> String {
  "withdraw-pending"
}

///|
pub fn runtime_control_effect_drop_cancel() -> String {
  "drop-cancel"
}

///|
pub fn runtime_control_effect_record_note() -> String {
  "record-note"
}

///|
pub fn runtime_control_effect_wait_for_proof() -> String {
  "wait-for-proof"
}

///|
pub fn runtime_control_effect_blocked() -> String {
  "blocked"
}

///|
pub fn runtime_control_effect_already_completed() -> String {
  "already-completed"
}

///|
pub fn runtime_control_effect_failed() -> String {
  "failed"
}

///|
pub fn runtime_control_effects() -> Array[String] {
  [
    runtime_control_effect_start_turn(),
    runtime_control_effect_active_turn(),
    runtime_control_effect_queue_turn(),
    runtime_control_effect_deliver_steer(),
    runtime_control_effect_queue_steer(),
    runtime_control_effect_defer_steer(),
    runtime_control_effect_cancel_active(),
    runtime_control_effect_withdraw_pending(),
    runtime_control_effect_drop_cancel(),
    runtime_control_effect_record_note(),
    runtime_control_effect_wait_for_proof(),
    runtime_control_effect_blocked(),
    runtime_control_effect_already_completed(),
    runtime_control_effect_failed(),
  ]
}

///|
pub fn runtime_control_target_state_active() -> String {
  "active"
}

///|
pub fn runtime_control_target_state_pending() -> String {
  "pending"
}

///|
pub fn runtime_control_target_state_idle() -> String {
  "idle"
}

///|
pub fn runtime_control_target_state_recorded() -> String {
  "recorded"
}

///|
pub fn runtime_control_target_state_terminal() -> String {
  "terminal"
}

///|
pub fn runtime_control_target_state_blocked() -> String {
  "blocked"
}

///|
pub fn runtime_control_target_states() -> Array[String] {
  [
    runtime_control_target_state_active(),
    runtime_control_target_state_pending(),
    runtime_control_target_state_idle(),
    runtime_control_target_state_recorded(),
    runtime_control_target_state_terminal(),
    runtime_control_target_state_blocked(),
  ]
}

///|
pub fn runtime_control_action_starts_turn(action : String) -> Bool {
  action != command_steer() &&
  action != command_cancel() &&
  action != command_note()
}

///|
pub fn runtime_control_status_is_pending(status : String) -> Bool {
  status == runtime_control_status_pending()
}

///|
pub fn runtime_control_status_is_active(status : String) -> Bool {
  runtime_control_active_statuses().contains(status)
}

///|
pub fn runtime_control_status_is_terminal(status : String) -> Bool {
  runtime_control_terminal_statuses().contains(status)
}

///|
pub fn runtime_control_status_is_blocked(status : String) -> Bool {
  runtime_control_blocked_statuses().contains(status)
}

///|
pub fn runtime_control_effect_allows_turn(effect : String) -> Bool {
  effect == runtime_control_effect_start_turn() ||
  effect == runtime_control_effect_active_turn() ||
  effect == runtime_control_effect_deliver_steer() ||
  effect == runtime_control_effect_queue_steer() ||
  effect == runtime_control_effect_cancel_active() ||
  effect == runtime_control_effect_withdraw_pending() ||
  effect == runtime_control_effect_queue_turn()
}

///|
pub fn runtime_control_effect_is_terminal(effect : String) -> Bool {
  effect == runtime_control_effect_already_completed() ||
  effect == runtime_control_effect_failed() ||
  effect == runtime_control_effect_blocked()
}

///|
pub fn runtime_control_settlement_required(
  action : String,
  effect : String,
) -> Bool {
  (action == command_steer() || action == command_cancel()) &&
  !runtime_control_effect_is_terminal(effect)
}

///|
pub fn runtime_control_settlement_events(
  action : String,
  effect : String,
) -> Array[String] {
  if action == command_steer() {
    if effect == runtime_control_effect_defer_steer() {
      [runtime_event_steer_deferred()]
    } else {
      [runtime_event_steer_applied(), runtime_event_steer_dropped()]
    }
  } else if action == command_cancel() {
    if effect == runtime_control_effect_drop_cancel() {
      [runtime_event_cancel_dropped()]
    } else {
      [runtime_event_runtime_aborted(), runtime_event_cancel_dropped()]
    }
  } else {
    []
  }
}

///|
pub fn runtime_control_contract_json() -> Json {
  {
    "kind": runtime_control_contract_kind(),
    "protocol": protocol_version(),
    "contract_id": runtime_control_contract_id(),
    "owner": "mooncode",
    "runtime_owner": "moonclaw",
    "reference": "mooncode/runtime-control",
    "command_action_contract_id": command_action_contract_id(),
    "event_name_contract_id": runtime_event_name_contract_id(),
    "conversation_contract_id": conversation_contract_id(),
    "conversation_ownership_contract_id": conversation_ownership_contract_id(),
    "rule": "A MoonCode runtime consumes one ordered command queue. Prompt and command actions start turns, steer targets the active turn, next pending turn, or defers into the next future turn, and cancel targets the active turn or withdraws the next pending turn.",
    "turn_starting_actions": "all supported actions except steer, cancel, and note",
    "active_statuses": runtime_control_active_statuses(),
    "terminal_statuses": runtime_control_terminal_statuses(),
    "blocked_statuses": runtime_control_blocked_statuses(),
    "protocol_effects": runtime_control_effects(),
    "target_states": runtime_control_target_states(),
    "boundary": {
      "ui": "Moondesk records commands and renders decisions.",
      "runtime": "MoonClaw enforces runtime control before executing tools.",
      "store": "commands.jsonl, runtime-commands.jsonl, runtime-receipts.jsonl, and events.jsonl remain append-only.",
    },
    "settlement_boundary": {
      "unit": runtime_control_scheduler_boundary_unit(),
      "rule": "Steer and cancel commands are durable control evidence. They do not fabricate chat rows or pretend to interrupt a running tool; MoonClaw settles them when the native runtime reaches a scheduler boundary or emits a real abort event.",
      "steer_events": runtime_control_settlement_events(
        command_steer(),
        runtime_control_effect_queue_steer(),
      ),
      "deferred_steer_events": runtime_control_settlement_events(
        command_steer(),
        runtime_control_effect_defer_steer(),
      ),
      "cancel_events": runtime_control_settlement_events(
        command_cancel(),
        runtime_control_effect_cancel_active(),
      ),
      "dropped_cancel_events": runtime_control_settlement_events(
        command_cancel(),
        runtime_control_effect_drop_cancel(),
      ),
    },
    "turn_ownership": conversation_ownership_contract_json(),
  }
}
