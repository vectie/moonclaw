///|
const MOONCODE_RESPONSES_TRANSPORT_CONTRACT : String = "moonclaw.responses-transport.v1"

///|
fn mooncode_runtime_responses_transport_enabled(command : Json) -> Bool {
  mooncode_json_bool(
    mooncode_json_object_field_or_empty(command, "payload"),
    "planner_responses_transport",
    default=false,
  )
}

///|
fn mooncode_runtime_responses_chat_fallback_enabled(command : Json) -> Bool {
  mooncode_runtime_responses_transport_enabled(command) &&
  mooncode_json_bool(
    mooncode_json_object_field_or_empty(command, "payload"),
    "planner_responses_chat_fallback",
    default=false,
  )
}

///|
fn mooncode_runtime_responses_prompt_cache_mode(command : Json) -> String? {
  match
    mooncode_json_string(
      mooncode_json_object_field_or_empty(command, "payload"),
      "planner_prompt_cache_mode",
      default="",
    ) {
    "implicit" => Some("implicit")
    "explicit" => Some("explicit")
    _ => None
  }
}

///|
fn mooncode_runtime_responses_prompt_cache_ttl(command : Json) -> String? {
  match
    mooncode_json_string(
      mooncode_json_object_field_or_empty(command, "payload"),
      "planner_prompt_cache_ttl",
      default="",
    ) {
    "30m" => Some("30m")
    "24h" => Some("24h")
    _ => None
  }
}

///|
fn mooncode_runtime_responses_prompt_cache_key(command : Json) -> String? {
  let session_id = mooncode_json_string(command, "session_id", default="")
    .trim()
    .to_owned()
  if session_id == "" {
    None
  } else {
    Some("moonclaw-session:\{session_id}")
  }
}

///|
fn mooncode_runtime_responses_transport_name(command : Json) -> String {
  if mooncode_runtime_responses_transport_enabled(command) {
    "responses"
  } else {
    "chat_completions"
  }
}

///|
async fn mooncode_runtime_dispatch_model_request(
  model : @model.Model,
  request : @openai.Request,
  command : Json,
  timeout_ms~ : Int?,
) -> (@openai.ChatCompletion, String) {
  if !mooncode_runtime_responses_transport_enabled(command) {
    return (
      @openai.chat(
        model~,
        request,
        extra_body=mooncode_runtime_turn_model_extra_body(model, command),
        timeout_ms~,
      ),
      "chat_completions",
    )
  }
  let result = Some(
    @openai.responses_chat(
      model~,
      request,
      prompt_cache_key?=mooncode_runtime_responses_prompt_cache_key(command),
      prompt_cache_mode?=mooncode_runtime_responses_prompt_cache_mode(command),
      prompt_cache_ttl?=mooncode_runtime_responses_prompt_cache_ttl(command),
      timeout_ms~,
    ),
  ) catch {
    error =>
      if mooncode_runtime_responses_chat_fallback_enabled(command) &&
        @openai.error_class(error) == "permanent_http" {
        None
      } else {
        raise error
      }
  }
  match result {
    Some(completion) => (completion, "responses")
    None =>
      (
        @openai.chat(
          model~,
          request,
          extra_body=mooncode_runtime_turn_model_extra_body(model, command),
          timeout_ms~,
        ),
        "chat_fallback",
      )
  }
}
