///|
fn mooncode_json_string(json : Json, key : String, default~ : String) -> String {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(String(value)) => value
        _ => default
      }
    _ => default
  }
}

///|
fn mooncode_json_bool(json : Json, key : String, default~ : Bool) -> Bool {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(value) => @json.from_json(value) catch { _ => default }
        None => default
      }
    _ => default
  }
}

///|
fn mooncode_json_array_items(json : Json, key : String) -> Array[Json] {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(Array(items)) => items
        _ => []
      }
    _ => []
  }
}

///|
fn mooncode_json_object_field_or_empty(json : Json, key : String) -> Json {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(Object(_) as value) => value
        _ => Json::object({})
      }
    _ => Json::object({})
  }
}
