///|
priv struct MoonDeskPromotionItem {
  source_relative : String
  destination_relative : String
} derive(Eq, ToJson, @json.FromJson)

///|
#warnings("-unused_value")
priv struct MoonDeskPromotionRequest {
  protocol_version : Int
  instance_id : String
  request_id : String
  workspace_id : String
  retention_id : String
  approval_digest : String
  command_digest : String
  items : Array[MoonDeskPromotionItem]
} derive(Eq, ToJson, @json.FromJson)

///|
priv struct MoonFortPromotionError {
  code : String
  message : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
fn moondesk_promotion_safe_digest(value : String) -> Bool {
  value.length() == 64 &&
  value.all(character => {
    character.is_ascii_digit() || (character >= 'a' && character <= 'f')
  })
}

///|
fn moondesk_promotion_safe_relative_path(value : String) -> Bool {
  value.length() >= 1 &&
  value.length() <= 4_096 &&
  !value.has_prefix("/") &&
  !value.has_suffix("/") &&
  !value.contains("//") &&
  !value.contains("\u{0}") &&
  !value.split("/").any(component => component == "." || component == "..")
}

///|
fn moondesk_promotion_parse_request(
  json : Json,
) -> MoonDeskPromotionRequest raise {
  let request : MoonDeskPromotionRequest = @json.from_json(json) catch {
    _ => fail("invalid typed promotion request")
  }
  guard request.protocol_version == 1 &&
    recovery_safe_id(request.request_id) &&
    request.retention_id.length() >= 1 &&
    request.retention_id.length() <= 128 &&
    request.retention_id.all(character => {
      character.is_ascii_alphabetic() ||
      character.is_ascii_digit() ||
      character == '-' ||
      character == '_'
    }) &&
    moondesk_promotion_safe_digest(request.approval_digest) &&
    moondesk_promotion_safe_digest(request.command_digest) &&
    request.items.length() == 1 &&
    request.items.all(item => {
      moondesk_promotion_safe_relative_path(item.source_relative) &&
      moondesk_promotion_safe_relative_path(item.destination_relative)
    }) else {
    fail("invalid typed promotion request")
  }
  let sources : Map[String, Bool] = Map([])
  let destinations : Map[String, Bool] = Map([])
  for item in request.items {
    guard !sources.contains(item.source_relative) &&
      !destinations.contains(item.destination_relative) else {
      fail("duplicate promotion mapping")
    }
    sources[item.source_relative] = true
    destinations[item.destination_relative] = true
  }
  request
}
