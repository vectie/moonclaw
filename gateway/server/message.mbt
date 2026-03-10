///|
pub struct AgentMessage {
  message_id : String
  from_agent : String
  to_agent : String?
  topic : String
  payload : Json
  timestamp : Int
} derive(ToJson, FromJson, Show)

///|
pub fn agent_message(
  uuid~ : @uuid.Generator,
  from_agent~ : String,
  to_agent? : String,
  topic~ : String,
  payload~ : Json,
  timestamp~ : Int,
) -> AgentMessage {
  AgentMessage::{
    message_id: uuid.v4().to_string(),
    from_agent,
    to_agent,
    topic,
    payload,
    timestamp,
  }
}

///|
pub fn AgentMessage::is_broadcast(self : AgentMessage) -> Bool {
  self.to_agent is None
}

///|
pub fn AgentMessage::is_directed(
  self : AgentMessage,
  agent_id : String,
) -> Bool {
  match self.to_agent {
    Some(target) => target == agent_id
    None => true
  }
}

///|
pub struct AgentMailboxConfig {
  max_size : Int
  timeout_ms : Int
} derive(ToJson, FromJson, Show)

///|
pub fn agent_mailbox_config(
  max_size? : Int = 1000,
  timeout_ms? : Int = 30000,
) -> AgentMailboxConfig {
  AgentMailboxConfig::{ max_size, timeout_ms }
}
