///|
fn field(json : Json, key : String) -> Json? {
  match json {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn text(json : Json, key : String, default~ : String = "") -> String {
  match field(json, key) {
    Some(String(value)) => value
    _ => default
  }
}

///|
fn flag(json : Json, key : String, default~ : Bool = false) -> Bool {
  match field(json, key) {
    Some(True) => true
    Some(False) => false
    _ => default
  }
}

///|
fn array(json : Json, key : String) -> Array[Json] {
  match field(json, key) {
    Some(Array(value)) => value
    _ => []
  }
}

///|
fn error(tool : String, message : String, metadata~ : Json = {}) -> Json {
  {
    "tool": tool,
    "ok": false,
    "is_error": true,
    "message": message,
    "output": "",
    "metadata": metadata,
  }
}

///|
fn redact_token(text : String, token : String) -> String {
  if token == "" {
    text
  } else {
    text.split(token).map(part => part.to_owned()).collect().join("[redacted]")
  }
}

///|
fn redact_response(value : Json, token : String) -> Json {
  match value {
    String(text) => Json(redact_token(text, token))
    Array(items) => Json(items.map(item => redact_response(item, token)))
    Object(fields) => {
      let sanitized : Map[String, Json] = Map([])
      for key, item in fields {
        sanitized[redact_token(key, token)] = redact_response(item, token)
      }
      Json(sanitized)
    }
    _ => value
  }
}
