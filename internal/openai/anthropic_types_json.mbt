///|
pub impl ToJson for AnthropicRequest with to_json(self : AnthropicRequest) -> Json {
  let obj : Map[String, Json] = {
    "model": Json::string(self.model),
    "max_tokens": self.max_tokens.to_json(),
    "messages": self.messages.to_json(),
  }
  if self.system is Some(system) {
    obj["system"] = Json::string(system)
  }
  if self.tools is Some(tools) {
    obj["tools"] = tools.to_json()
  }
  if self.stream is Some(stream) {
    obj["stream"] = stream.to_json()
  }
  Json::object(obj)
}

///|
pub impl ToJson for AnthropicMessage with to_json(self : AnthropicMessage) -> Json {
  let obj : Map[String, Json] = {
    "role": Json::string(self.role),
    "content": self.content.to_json(),
  }
  Json::object(obj)
}

///|
pub impl ToJson for AnthropicContent with to_json(self : AnthropicContent) -> Json {
  match self {
    Text(text) => Json::string(text)
    Blocks(blocks) => blocks.to_json()
  }
}

///|
pub impl ToJson for AnthropicBlock with to_json(self : AnthropicBlock) -> Json {
  let obj : Map[String, Json] = { "type": Json::string(self.type_) }
  if self.text is Some(text) {
    obj["text"] = Json::string(text)
  }
  Json::object(obj)
}

///|
pub impl ToJson for AnthropicTool with to_json(self : AnthropicTool) -> Json {
  let obj : Map[String, Json] = { "name": Json::string(self.name) }
  if self.description is Some(desc) {
    obj["description"] = Json::string(desc)
  }
  obj["input_schema"] = self.input_schema
  Json::object(obj)
}
