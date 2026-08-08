///|
/// Content parts supported in chat completion parameters.
pub enum ChatCompletionContentPartParam {
  Text(ChatCompletionContentPartTextParam)
  ImageUrl(ChatCompletionContentPartImageUrlParam)
}

///|
pub fn ChatCompletionContentPartParam::new(
  text~ : String,
  cache_control? : CacheControl,
) -> ChatCompletionContentPartParam {
  Text({ text, cache_control })
}

///|
pub impl ToJson for ChatCompletionContentPartParam with fn to_json(
  self : ChatCompletionContentPartParam,
) -> Json {
  match self {
    Text(param) => {
      let json : Map[String, Json] = { "type": "text", "text": param.text }
      if param.cache_control is Some(cache_control) {
        json["cache_control"] = cache_control.to_json()
      }
      Json::object(json)
    }
    ImageUrl(param) => {
      let image_url : Map[String, Json] = { "url": param.url }
      if param.detail is Some(detail) {
        image_url["detail"] = detail.to_json()
      }
      { "type": "image_url", "image_url": Json::object(image_url) }
    }
  }
}

///|
impl @json.FromJson for ChatCompletionContentPartParam with fn from_json(
  json : Json,
  json_path : @json.JsonPath,
) -> ChatCompletionContentPartParam raise {
  guard json is Object(json) else {
    raise JsonDecodeError((json_path, "Expected an object"))
  }
  guard json.get("type") is Some(String(type_)) else {
    raise JsonDecodeError((json_path, "Missing 'type' field"))
  }
  match type_ {
    "text" => {
      guard json.get("text") is Some(String(text)) else {
        raise JsonDecodeError((json_path, "Missing 'text' field"))
      }
      let cache_control = match json.get("cache_control") {
        None | Some(Null) => None
        Some(cache_control) => {
          let cache_control : CacheControl = @json.from_json(
            cache_control,
            path=json_path.add_key("cache_control"),
          )
          Some(cache_control)
        }
      }
      Text({ text, cache_control })
    }
    "image_url" => {
      guard json.get("image_url") is Some(Object(image_url)) else {
        raise JsonDecodeError((json_path, "Missing 'image_url' field"))
      }
      guard image_url.get("url") is Some(String(url)) else {
        raise JsonDecodeError((json_path, "Missing 'image_url.url' field"))
      }
      let detail = match image_url.get("detail") {
        None | Some(Null) => None
        Some(String(detail)) => Some(detail)
        Some(_) =>
          raise JsonDecodeError(
            (json_path, "Expected 'image_url.detail' to be a string"),
          )
      }
      ImageUrl({ url, detail })
    }
    _ =>
      raise JsonDecodeError((json_path, "Unknown content part type: \{type_}"))
  }
}
