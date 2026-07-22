///|
fn mooncode_runtime_model_selector(requested : String) -> String? {
  let selector = requested.trim().to_owned()
  if selector == "" || selector != requested {
    return None
  }
  Some(selector)
}

///|
fn mooncode_command_inherits_session_model(command : Json) -> Bool {
  let action = mooncode_json_string(command, "command", default="prompt")
  (action == "prompt" || action == "package" || action == "steer") &&
  mooncode_runtime_turn_requested_model(command) == ""
}

///|
fn mooncode_command_with_session_model(
  command : Json,
  session_model : String,
) -> Json {
  let inherited = if session_model != "" &&
    mooncode_command_inherits_session_model(command) {
    mooncode_json_object_with_field(command, "model", session_model.to_json())
  } else {
    command
  }
  inherited
}
