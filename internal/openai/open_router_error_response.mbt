///|
#derive(ToJson)
pub struct OpenRouterErrorResponse {
  code : Int32
  message : String
  metadata : Json
}

///|
pub impl @json.FromJson for OpenRouterErrorResponse with fn from_json(
  json : Json,
  json_path : @json.JsonPath,
) -> OpenRouterErrorResponse {
  guard json is Object(json) else {
    raise JsonDecodeError((json_path, "Expected an object"))
  }
  let (code, code_label) = match json.get("code") {
    Some(Number(code, ..)) => (code.to_int(), "")
    Some(String(code)) => (502, code)
    _ => raise JsonDecodeError((json_path, "Missing 'code' field"))
  }
  guard json.get("message") is Some(String(raw_message)) else {
    raise JsonDecodeError((json_path, "Missing 'message' field"))
  }
  let message = if code_label != "" {
    "\{code_label}: \{raw_message}"
  } else {
    raw_message
  }
  let metadata = match json.get("metadata") {
    Some(metadata) => metadata
    None => Json::object(json)
  }
  { code, message, metadata, }
}

///|
pub extend OpenRouterErrorResponse with ToJson::{to_json}

///|
pub extend OpenRouterErrorResponse with @moonbitlang/core/json.FromJson::{
  from_json,
}
