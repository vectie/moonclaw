///|
pub struct AnthropicRequest {
  model : String
  max_tokens : Int32
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
  input_tokens : Int32
  output_tokens : Int32
} derive(FromJson, Debug)

///|
pub struct AnthropicStreamEvent {
  type_ : String
  index : Int32?
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

///|
pub extend AnthropicResponse with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend AnthropicResponse with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AnthropicContentBlock with @moonbitlang/core/json.FromJson::{
  from_json,
}

///|
pub extend AnthropicContentBlock with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AnthropicUsage with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend AnthropicUsage with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AnthropicStreamEvent with @moonbitlang/core/json.FromJson::{
  from_json,
}

///|
pub extend AnthropicStreamEvent with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AnthropicDelta with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend AnthropicDelta with @moonbitlang/core/debug.Debug::{to_repr}
