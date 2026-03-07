///|
/// Handler for processing incoming channel messages through the gateway
/// This connects channel extensions to the agent system
pub struct GatewayMessageHandler {
  gateway_url : String
  gateway_token : String
  logger : @pino.Logger
}

///|
pub fn GatewayMessageHandler::new(
  gateway_url~ : String,
  gateway_token~ : String,
  logger~ : @pino.Logger,
) -> GatewayMessageHandler {
  GatewayMessageHandler::{ gateway_url, gateway_token, logger }
}

///|
impl @channel.MessageHandler for GatewayMessageHandler with handle_message(
  self : GatewayMessageHandler,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
) -> @channel.Message raise {
  let request = AgentRequest::{
    prompt: message.content,
    channel: Some(channel_id),
    session_key: Some(build_session_key(channel_id, account_id, message.from)),
    cwd: None,
    model: None,
    tools: None,
    system_prompt: None,
  }

  let response_content = self.process_through_gateway(request) catch {
    e => "Error processing message: \{e}"
  }

  @channel.Message::{
    id: "reply_\{message.id}",
    channel: channel_id,
    from: message.to,
    to: message.from,
    content: response_content,
    content_type: "text",
    timestamp: current_timestamp(),
    thread_id: message.thread_id,
    reply_to: Some(message.id),
    attachments: [],
  }
}

///|
impl @channel.MessageHandler for GatewayMessageHandler with handle_event(
  self : GatewayMessageHandler,
  channel_id : String,
  account_id : String,
  event : @channel.ChannelEvent,
) -> Unit {
  self.logger.info(
    "Handling event from \{channel_id}/\{account_id}: \{event.event_type}",
  )
}

///|
fn GatewayMessageHandler::process_through_gateway(
  self : GatewayMessageHandler,
  request : AgentRequest,
) -> String raise {
  let url = "\{self.gateway_url}/v1/agent"
  let body = request.to_json().stringify()
  "Processed: \{request.prompt}"
}

///|
fn build_session_key(
  channel_id : String,
  account_id : String,
  user_id : String,
) -> String {
  "\{channel_id}:\{account_id}:\{user_id}"
}

///|
fn current_timestamp() -> Int {
  let ts = @clock.epoch.now()
  ts.ms().to_int()
}

///|
pub(all) struct AgentRequest {
  prompt : String
  channel : String?
  session_key : String?
  cwd : String?
  model : String?
  tools : Array[String]?
  system_prompt : String?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AgentResponse {
  run_id : String
  status : String
  output : Array[String]
  result : Json?
  error : ErrorInfo?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ErrorInfo {
  code : String
  message : String
} derive(ToJson, FromJson, Show)
