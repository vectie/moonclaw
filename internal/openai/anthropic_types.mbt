///|
pub struct AnthropicRequest {
  model : String
  max_tokens : Int
  messages : Array[AnthropicMessage]
  system : String?
  tools : Array[AnthropicTool]?
  stream : Bool?
}

///|
pub struct AnthropicMessage {
  role : String
  content : AnthropicContent
}

///|
pub enum AnthropicContent {
  Text(String)
  Blocks(Array[AnthropicBlock])
}

///|
pub struct AnthropicBlock {
  type_ : String
  text : String?
}

///|
pub struct AnthropicTool {
  name : String
  description : String?
  input_schema : Json
}

///|
pub struct AnthropicResponse {
  id : String
  type_ : String
  role : String
  content : Array[AnthropicContentBlock]
  model : String
  stop_reason : String?
  stop_sequence : String?
  usage : AnthropicUsage
} derive(FromJson, Debug)

///|
pub struct AnthropicContentBlock {
  type_ : String
  text : String?
  name : String?
  input : Json?
  id : String?
} derive(FromJson, Debug)

///|
pub struct AnthropicUsage {
  input_tokens : Int
  output_tokens : Int
} derive(FromJson, Debug)

///|
pub struct AnthropicStreamEvent {
  type_ : String
  index : Int?
  delta : AnthropicDelta?
  content_block : AnthropicContentBlock?
  message : AnthropicResponse?
} derive(FromJson, Debug)

///|
pub struct AnthropicDelta {
  type_ : String?
  text : String?
  stop_reason : String?
} derive(FromJson, Debug)
