///|
pub fn command_action_contract_id() -> String {
  "mooncode-command-actions.v1"
}

///|
pub fn command_prompt() -> String {
  "prompt"
}

///|
pub fn command_steer() -> String {
  "steer"
}

///|
pub fn command_run_tests() -> String {
  "run_tests"
}

///|
pub fn command_run_build() -> String {
  "run_build"
}

///|
pub fn command_run_eval() -> String {
  "run_eval"
}

///|
pub fn command_package() -> String {
  "package"
}

///|
pub fn command_commit() -> String {
  "commit"
}

///|
pub fn command_accept() -> String {
  "accept"
}

///|
pub fn command_reject() -> String {
  "reject"
}

///|
pub fn command_approve_tool() -> String {
  "approve_tool"
}

///|
pub fn command_reject_tool() -> String {
  "reject_tool"
}

///|
pub fn command_apply_patch() -> String {
  "apply_patch"
}

///|
pub fn command_revert_patch() -> String {
  "revert_patch"
}

///|
pub fn command_cancel() -> String {
  "cancel"
}

///|
pub fn command_note() -> String {
  "note"
}

///|
pub fn command_turn_actions() -> Array[String] {
  [command_prompt(), command_steer(), command_cancel()]
}

///|
pub fn command_advertised_actions() -> Array[String] {
  [
    command_prompt(),
    command_steer(),
    command_run_tests(),
    command_run_build(),
    command_run_eval(),
    command_package(),
    command_commit(),
    command_accept(),
    command_reject(),
    command_approve_tool(),
    command_reject_tool(),
    command_apply_patch(),
    command_revert_patch(),
    command_cancel(),
  ]
}

///|
pub fn command_supported_actions() -> Array[String] {
  let actions = command_advertised_actions()
  actions.push(command_note())
  actions
}

///|
pub fn command_action_contract_json() -> Json {
  {
    "kind": "mooncode-command-action-contract",
    "protocol": protocol_version(),
    "contract_id": command_action_contract_id(),
    "turn_actions": command_turn_actions(),
    "advertised_actions": command_advertised_actions(),
    "supported_actions": command_supported_actions(),
  }
}
