///|
pub fn model_planner_evidence_contract_id() -> String {
  "mooncode-model-planner-evidence.v1"
}

///|
pub fn model_planner_evidence_contract_kind() -> String {
  "mooncode-model-planner-evidence-contract"
}

///|
pub fn model_planner_evidence_report_kind() -> String {
  "mooncode-model-planner-evidence-report"
}

///|
pub fn model_planner_mode_model_tool_calls() -> String {
  "model-tool-calls"
}

///|
pub fn model_planner_status_pending() -> String {
  "pending"
}

///|
pub fn model_planner_status_service_started() -> String {
  "service-started"
}

///|
pub fn model_planner_status_running() -> String {
  "running"
}

///|
pub fn model_planner_status_satisfied() -> String {
  "satisfied"
}

///|
pub fn model_planner_status_planner_failed() -> String {
  "planner-failed"
}

///|
pub fn model_planner_status_contract_failed() -> String {
  "contract-failed"
}

///|
pub fn model_planner_status_no_model_planned_commands() -> String {
  "no-model-planned-commands"
}

///|
pub fn model_planner_missing_evidence_reason() -> String {
  "missing-model-planner-evidence-after-turn-start"
}

///|
pub fn model_planner_stray_evidence_reason() -> String {
  "planner-evidence-without-model-command"
}

///|
pub fn model_planner_command_actions() -> Array[String] {
  [command_prompt(), command_steer(), command_package()]
}

///|
pub fn model_planner_command_action_is_supported(action : String) -> Bool {
  model_planner_command_actions().contains(action)
}

///|
pub fn model_planner_command_event_kinds() -> Array[String] {
  [
    for action in model_planner_command_actions() => "command.\{action}"
  ]
}

///|
pub fn model_planner_command_event_kind_is_supported(kind : String) -> Bool {
  model_planner_command_event_kinds().contains(kind)
}

///|
pub fn model_planner_planner_event_kinds() -> Array[String] {
  [
    runtime_event_planner_started(),
    runtime_event_planner_selected(),
    runtime_event_planner_failed(),
  ]
}

///|
pub fn model_planner_terminal_event_kinds() -> Array[String] {
  [
    runtime_event_turn_finished(),
    runtime_event_runtime_finished(),
    runtime_event_command_error(),
    runtime_event_turn_failed(),
    runtime_event_max_steps_exhausted(),
    runtime_event_runtime_unavailable(),
  ]
}

///|
pub fn model_planner_event_is_planner_evidence(
  kind : String,
  planner_mode : String,
) -> Bool {
  model_planner_planner_event_kinds().contains(kind) ||
  planner_mode == model_planner_mode_model_tool_calls()
}

///|
pub fn model_planner_status_is_running(status : String) -> Bool {
  status == model_planner_status_running() ||
  status == model_planner_status_service_started()
}

///|
pub fn model_planner_status_is_contract_failure(status : String) -> Bool {
  status == model_planner_status_contract_failed()
}

///|
pub fn model_planner_contract_failure_rule() -> String {
  "MoonClaw started the model-planned turn but did not emit runtime.planner_started, runtime.planner_selected, model planner reasoning, model-planned tool calls, or runtime.planner_failed."
}

///|
pub fn model_planner_queued_rule() -> String {
  "The command is queued. The UI must not show a working state until MoonClaw emits command-scoped runtime evidence."
}

///|
pub fn model_planner_working_evidence_rule() -> String {
  "The visible working state is backed by command-scoped MoonClaw planner/runtime evidence."
}

///|
pub fn model_planner_evidence_contract_json() -> Json {
  {
    "kind": model_planner_evidence_contract_kind(),
    "protocol": protocol_version(),
    "contract_id": model_planner_evidence_contract_id(),
    "owner": {
      "runtime": "moonclaw",
      "projection": "mooncode",
      "ui": "moondesk",
    },
    "model_planned_actions": model_planner_command_actions(),
    "model_planned_command_kinds": model_planner_command_event_kinds(),
    "planner_event_kinds": model_planner_planner_event_kinds(),
    "terminal_event_kinds": model_planner_terminal_event_kinds(),
    "model_planner_mode": model_planner_mode_model_tool_calls(),
    "statuses": [
      model_planner_status_pending(),
      model_planner_status_service_started(),
      model_planner_status_running(),
      model_planner_status_satisfied(),
      model_planner_status_planner_failed(),
      model_planner_status_contract_failed(),
      model_planner_status_no_model_planned_commands(),
    ],
    "problem_reasons": [
      model_planner_missing_evidence_reason(),
      model_planner_stray_evidence_reason(),
    ],
    "model_planned_command_rule": "A prompt, steer, or package command with a selected model and no explicit runtime_tool_calls is model-planned.",
    "working_signal_rule": "MoonDesk may show active work only after command-scoped MoonClaw evidence exists: runtime.turn_started, runtime.planner_started, planner reasoning, planner-selected tool calls, assistant output, or command-scoped failure.",
    "required_sequence": [
      "command.prompt/command.steer/command.package",
      runtime_event_service_started(),
      runtime_event_turn_started(),
      "runtime.planner_started or runtime.planner_failed",
      "runtime.planner_selected plus planner reasoning/tool calls, or runtime.planner_failed",
      "tool result evidence when tools run",
      "assistant response, runtime.turn_finished, or command-scoped failure",
    ],
    "contract_failure_rule": "Once a model-planned turn has runtime.turn_started, missing planner evidence is a runtime contract failure instead of a UI thinking state.",
    "command_action_contract_id": command_action_contract_id(),
    "event_name_contract_id": runtime_event_name_contract_id(),
    "runtime_tool_contract_id": runtime_tool_contract_id(),
  }
}
