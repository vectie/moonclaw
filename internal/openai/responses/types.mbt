///|
/// Types and JSON helpers for the OpenAI Responses API.
///
/// This is extracted from `oauth/codex` so that `internal/openai` owns the
/// request/stream item wire types.

///|
pub struct ResponsesRequest {
  model : String
  input : Array[ResponseInputItem]
  instructions : String
  tools : Array[Json]
  tool_choice : String
  reasoning_effort : String?
  reasoning_context : String?
  stream : Bool?
  store : Bool?
  previous_response_id : String?
  prompt_cache_key : String?
  prompt_cache_mode : String?
  prompt_cache_ttl : String?
  max_output_tokens : Int?
  parallel_tool_calls : Bool?
} derive(Debug)

///|
/// This is the minimal subset of Responses API content we currently need.
pub(all) enum ContentType {
  InputText
  OutputText
  Text
} derive(Debug)

///|
pub impl ToJson for ContentType with fn to_json(self : ContentType) -> Json {
  match self {
    InputText => "input_text"
    OutputText => "output_text"
    Text => "text"
  }
}

///|
pub impl @json.FromJson for ContentType with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ContentType raise @json.JsonDecodeError {
  guard json is String(s) else {
    raise JsonDecodeError((path, "ContentType: expected string"))
  }
  match s {
    "input_text" => InputText
    "output_text" => OutputText
    "text" => Text
    _ => raise JsonDecodeError((path, "ContentType: invalid value '\{s}'"))
  }
}

///|
pub struct ContentPart {
  type_ : ContentType
  text : String
} derive(Debug)

///|
pub fn ContentPart::new(type_~ : ContentType, text~ : String) -> ContentPart {
  { type_, text }
}

///|
pub impl ToJson for ContentPart with fn to_json(self : ContentPart) -> Json {
  { "type": self.type_, "text": self.text }
}

///|
pub impl @json.FromJson for ContentPart with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ContentPart raise @json.JsonDecodeError {
  guard json is Object(obj) else {
    raise JsonDecodeError((path, "ContentPart: expected object"))
  }
  let type_ : ContentType = match obj.get("type") {
    Some(v) => @json.from_json(v, path=path.add_key("type"))
    None => raise JsonDecodeError((path, "ContentPart: missing 'type'"))
  }
  let text : String = match obj.get("text") {
    Some(String(s)) => s
    Some(_) =>
      raise JsonDecodeError((path, "ContentPart: 'text' must be string"))
    None => raise JsonDecodeError((path, "ContentPart: missing 'text'"))
  }
  { type_, text }
}

///|
pub fn ResponsesRequest::new(
  model~ : String,
  input~ : Array[ResponseInputItem],
  instructions~ : String,
  tools? : Array[Json] = [],
  tool_choice? : String = "auto",
  reasoning_effort? : String,
  reasoning_context? : String,
  stream? : Bool,
  store? : Bool,
  previous_response_id? : String,
  prompt_cache_key? : String,
  prompt_cache_mode? : String,
  prompt_cache_ttl? : String,
  max_output_tokens? : Int,
  parallel_tool_calls? : Bool,
) -> ResponsesRequest {
  {
    model,
    input,
    instructions,
    tools,
    tool_choice,
    reasoning_effort,
    reasoning_context,
    stream,
    store,
    previous_response_id,
    prompt_cache_key,
    prompt_cache_mode,
    prompt_cache_ttl,
    max_output_tokens,
    parallel_tool_calls,
  }
}

///|
pub impl ToJson for ResponsesRequest with fn to_json(self : ResponsesRequest) -> Json {
  let obj = {
    "model": self.model.to_json(),
    "input": self.input.to_json(),
    "instructions": self.instructions.to_json(),
    "tools": self.tools.to_json(),
    "tool_choice": self.tool_choice.to_json(),
  }
  if self.stream is Some(v) {
    obj["stream"] = v.to_json()
  }
  if self.reasoning_effort is Some(_) || self.reasoning_context is Some(_) {
    let reasoning : Map[String, Json] = Map([])
    if self.reasoning_effort is Some(effort) {
      reasoning["effort"] = effort.to_json()
    }
    if self.reasoning_context is Some(context) {
      reasoning["context"] = context.to_json()
    }
    obj["reasoning"] = Json::object(reasoning)
  }
  if self.store is Some(v) {
    obj["store"] = v.to_json()
  }
  if self.previous_response_id is Some(id) {
    obj["previous_response_id"] = id.to_json()
  }
  if self.prompt_cache_key is Some(key) {
    obj["prompt_cache_key"] = key.to_json()
  }
  if self.prompt_cache_mode is Some(_) || self.prompt_cache_ttl is Some(_) {
    let options : Map[String, Json] = Map([])
    if self.prompt_cache_mode is Some(mode) {
      options["mode"] = mode.to_json()
    }
    if self.prompt_cache_ttl is Some(ttl) {
      options["ttl"] = ttl.to_json()
    }
    obj["prompt_cache_options"] = Json::object(options)
  }
  if self.max_output_tokens is Some(limit) {
    obj["max_output_tokens"] = limit.to_json()
  }
  if self.parallel_tool_calls is Some(enabled) {
    obj["parallel_tool_calls"] = enabled.to_json()
  }
  Json::object(obj)
}

///|
pub(all) enum ResponseInputItem {
  Message(role~ : String, content~ : Array[ContentPart])
  FunctionCall(call_id~ : String, name~ : String, arguments~ : String)
  FunctionCallOutput(call_id~ : String, output~ : String)
} derive(Debug)

///|
pub impl ToJson for ResponseInputItem with fn to_json(self : ResponseInputItem) -> Json {
  match self {
    Message(role~, content~) =>
      { "type": "message", "role": role, "content": content.to_json() }
    FunctionCall(call_id~, name~, arguments~) =>
      {
        "type": "function_call",
        "call_id": call_id,
        "name": name,
        "arguments": arguments,
      }
    FunctionCallOutput(call_id~, output~) =>
      { "type": "function_call_output", "call_id": call_id, "output": output }
  }
}

///|
pub(all) enum ResponseItem {
  Message(role~ : String, content~ : Array[ContentPart])
  FunctionCall(call_id~ : String, name~ : String, arguments~ : String)
} derive(Debug)

///|
pub impl @json.FromJson for ResponseItem with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ResponseItem raise @json.JsonDecodeError {
  guard json is Object(obj) else {
    raise JsonDecodeError((path, "ResponseItem: expected object"))
  }
  let type_ = match obj.get("type") {
    Some(String(s)) => s
    _ => raise JsonDecodeError((path, "ResponseItem: missing 'type'"))
  }
  match type_ {
    "message" => {
      let role = match obj.get("role") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "ResponseItem: missing 'role'"))
      }
      let content : Array[ContentPart] = match obj.get("content") {
        Some(content_json) =>
          @json.from_json(content_json, path=path.add_key("content"))
        None => []
      }
      Message(role~, content~)
    }
    "function_call" => {
      let call_id = match obj.get("call_id") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "ResponseItem: missing 'call_id'"))
      }
      let name = match obj.get("name") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "ResponseItem: missing 'name'"))
      }
      let arguments = match obj.get("arguments") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "ResponseItem: missing 'arguments'"))
      }
      FunctionCall(call_id~, name~, arguments~)
    }
    _ => raise JsonDecodeError((path, "ResponseItem: unknown type '\{type_}'"))
  }
}

///|
pub fn message_input(role~ : String, content~ : String) -> ResponseInputItem {
  Message(role~, content=[
    ContentPart::new(
      type_=if role == "user" { InputText } else { OutputText },
      text=content,
    ),
  ])
}

///|
pub fn function_call_output(
  call_id~ : String,
  output~ : String,
) -> ResponseInputItem {
  FunctionCallOutput(call_id~, output~)
}
