///|
pub fn native_command_contract_id() -> String {
  "mooncode-native-command-execution.v1"
}

///|
pub fn native_command_execution_contract_json() -> Json {
  {
    "kind": "mooncode-native-command-execution-contract",
    "protocol": protocol_version(),
    "contract_id": native_command_contract_id(),
    "runtime_owner": "moonclaw",
    "ui_owner": "moondesk",
    "artifact_owner": "moonbook",
    "supported_actions": command_supported_actions(),
    "event_sink": "POST /api/mooncode/sessions/<session-id>/runtime-events",
    "eval_report_sink": "POST /api/mooncode/sessions/<session-id>/eval-report",
    "ack_sink": "POST /api/mooncode/sessions/<session-id>/runtime-replay",
    "claim_sink": "POST /api/mooncode/sessions/<session-id>/runtime-claim",
  }
}
