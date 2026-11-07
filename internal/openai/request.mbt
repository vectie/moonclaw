///|
/// Parameters accepted by the chat completion endpoint.
/// This is the request type
/// ```mbt no check
/// let uri = Uri::parse(url)
/// let client = @http.Client::connect(uri.host, protocol=uri.protocol, headers={
///   "Authorization": "Bearer \{model.api_key}",
///   "Content-Type": "application/json",
///   "Connection": "close",
/// })
/// defer client.close()
/// let response = client.post(uri.path, (request : ChatCompletionParam).to_json())
/// ```
pub struct Request {
  model : String
  messages : Array[ChatCompletionMessageParam]
  tools : Array[ChatCompletionToolParam]
  usage : CompletionUsageParam?
  user : String?
  max_tokens : Int32?
  temperature : Double?
  reasoning_effort : ChatCompletionReasoningEffort?
  response_format : ResponseFormat?
  stream : Bool?
  stream_options : ChatCompletionStreamOptionsParam?
  tool_choice : ChatCompletionToolChoice?
  parallel_tool_calls : Bool?
}

///|
pub impl ToJson for Request with fn to_json(self : Request) -> Json {
  let json : Map[String, Json] = {
    "model": Json::string(self.model),
    "messages": self.messages,
  }
  if !self.tools.is_empty() {
    json["tools"] = Json(self.tools)
  }
  if self.usage is Some(usage) {
    json["usage"] = ToJson::to_json(usage)
  }
  if self.user is Some(user) {
    json["user"] = Json::string(user)
  }
  if self.max_tokens is Some(max_tokens) {
    json["max_tokens"] = Json(max_tokens)
  }
  if self.temperature is Some(temperature) {
    json["temperature"] = Json(temperature)
  }
  if self.reasoning_effort is Some(reasoning_effort) {
    json["reasoning_effort"] = ToJson::to_json(reasoning_effort)
  }
  if self.response_format is Some(response_format) {
    json["response_format"] = response_format.to_json()
  }
  if self.stream is Some(stream) {
    json["stream"] = Json(stream)
  }
  if self.stream_options is Some(stream_options) {
    json["stream_options"] = stream_options.to_json()
  }
  if self.tool_choice is Some(tool_choice) {
    json["tool_choice"] = tool_choice.to_json()
  }
  if self.parallel_tool_calls is Some(parallel_tool_calls) {
    json["parallel_tool_calls"] = Json(parallel_tool_calls)
  }
  Json::object(json)
}

///|
pub extend Request with ToJson::{to_json}
