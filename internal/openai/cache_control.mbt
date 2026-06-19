///|
/// Cache directives for individual content parts.
pub(all) enum CacheControl {
  Ephemeral
}

///|
pub impl ToJson for CacheControl with fn to_json(self : CacheControl) -> Json {
  match self {
    Ephemeral => { "type": "ephemeral" }
  }
}

///|
impl @json.FromJson for CacheControl with fn from_json(
  json : Json,
  json_path : @json.JsonPath,
) -> CacheControl {
  guard json is Object(json) else {
    raise JsonDecodeError((json_path, "Expected an object"))
  }
  guard json.get("type") is Some(String(type_)) else {
    raise JsonDecodeError((json_path, "Missing 'type' field"))
  }
  match type_ {
    "ephemeral" => Ephemeral
    _ =>
      raise JsonDecodeError((json_path, "Unknown cache control type: \{type_}"))
  }
}
