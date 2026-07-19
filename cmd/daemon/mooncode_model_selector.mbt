///|
const MOONCODE_CODEX_GPT_5_6_SOL_ALIAS = "gpt-5.6-sol"

///|
const MOONCODE_CODEX_GPT_5_6_SOL_SELECTOR = "codex/gpt-5.6-sol"

///|
fn mooncode_runtime_model_selector(requested : String) -> String? {
  let selector = requested.trim().to_owned()
  if selector != requested {
    return None
  }
  if selector == MOONCODE_CODEX_GPT_5_6_SOL_ALIAS ||
    selector == MOONCODE_CODEX_GPT_5_6_SOL_SELECTOR {
    return Some(MOONCODE_CODEX_GPT_5_6_SOL_SELECTOR)
  }
  None
}

///|
fn mooncode_canonicalize_exact_model_alias(json : Json, key : String) -> Json {
  if mooncode_json_string(json, key, default="") ==
    MOONCODE_CODEX_GPT_5_6_SOL_ALIAS {
    mooncode_json_object_with_field(
      json,
      key,
      MOONCODE_CODEX_GPT_5_6_SOL_SELECTOR.to_json(),
    )
  } else {
    json
  }
}

///|
fn mooncode_canonicalize_model_container(json : Json) -> Json {
  let with_model = mooncode_canonicalize_exact_model_alias(json, "model")
  mooncode_canonicalize_exact_model_alias(with_model, "planner_model")
}

///|
fn mooncode_canonicalize_nested_model_container(
  json : Json,
  key : String,
) -> Json {
  match json {
    Object(fields) =>
      match fields.get(key) {
        Some(Object(_) as nested) =>
          mooncode_json_object_with_field(
            json,
            key,
            mooncode_canonicalize_model_container(nested),
          )
        _ => json
      }
    _ => json
  }
}

///|
fn mooncode_command_with_canonical_model_selector(command : Json) -> Json {
  let canonical = command
    |> mooncode_canonicalize_model_container
    |> mooncode_canonicalize_nested_model_container("payload")
  match canonical {
    Object(fields) =>
      match fields.get("packet") {
        Some(Object(_) as packet) => {
          let canonical_packet = packet
            |> mooncode_canonicalize_model_container
            |> mooncode_canonicalize_nested_model_container("payload")
          mooncode_json_object_with_field(canonical, "packet", canonical_packet)
        }
        _ => canonical
      }
    _ => canonical
  }
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
  let canonical = mooncode_command_with_canonical_model_selector(command)
  let inherited = if session_model != "" &&
    mooncode_command_inherits_session_model(canonical) {
    mooncode_json_object_with_field(canonical, "model", session_model.to_json())
  } else {
    canonical
  }
  inherited
}

///|
fn mooncode_runtime_turn_uses_exact_model(command : Json) -> Bool {
  mooncode_runtime_turn_requested_model(command) ==
  MOONCODE_CODEX_GPT_5_6_SOL_SELECTOR
}
