///|
pub impl ToJson for AnthropicRequest with fn to_json(self : AnthropicRequest) -> Json {
  let obj : Map[String, Json] = {
    "model": Json::string(self.model),
    "max_tokens": Json(self.max_tokens),
    "messages": Json(self.messages),
  }
  if self.system is Some(system) {
    obj["system"] = Json::string(system)
  }
  if self.tools is Some(tools) {
    obj["tools"] = Json(tools)
  }
  if self.stream is Some(stream) {
    obj["stream"] = Json(stream)
  }
  Json::object(obj)
}

///|
pub impl ToJson for AnthropicMessage with fn to_json(self : AnthropicMessage) -> Json {
  let obj : Map[String, Json] = {
    "role": Json::string(self.role),
    "content": self.content.to_json(),
  }
  Json::object(obj)
}

///|
pub impl ToJson for AnthropicContent with fn to_json(self : AnthropicContent) -> Json {
  match self {
    Text(text) => Json::string(text)
    Blocks(blocks) => Json(blocks)
  }
}

///|
pub impl ToJson for AnthropicBlock with fn to_json(self : AnthropicBlock) -> Json {
  let obj : Map[String, Json] = { "type": Json::string(self.type_) }
  if self.text is Some(text) {
    obj["text"] = Json::string(text)
  }
  Json::object(obj)
}

///|
pub impl ToJson for AnthropicTool with fn to_json(self : AnthropicTool) -> Json {
  let obj : Map[String, Json] = { "name": Json::string(self.name) }
  if self.description is Some(desc) {
    obj["description"] = Json::string(desc)
  }
  obj["input_schema"] = self.input_schema
  Json::object(obj)
}

///|
pub extend AnthropicRequest with ToJson::{to_json}

///|
pub extend AnthropicMessage with ToJson::{to_json}

///|
pub extend AnthropicContent with ToJson::{to_json}

///|
pub extend AnthropicBlock with ToJson::{to_json}

///|
pub extend AnthropicTool with ToJson::{to_json}
