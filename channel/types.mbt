///|
pub type ChannelId = String

///|
pub(all) enum ChatType {
  Direct
  Group
  Channel
  Thread
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ChannelCapabilities {
  chat_types : Array[ChatType]
  polls : Bool
  reactions : Bool
  edit : Bool
  unsend : Bool
  reply : Bool
  effects : Bool
  group_management : Bool
  threads : Bool
  media : Bool
  native_commands : Bool
  block_streaming : Bool
} derive(ToJson, FromJson, Show)

///|
pub fn default_capabilities() -> ChannelCapabilities {
  ChannelCapabilities::{
    chat_types: [ChatType::Direct],
    polls: false,
    reactions: false,
    edit: false,
    unsend: false,
    reply: false,
    effects: false,
    group_management: false,
    threads: false,
    media: false,
    native_commands: false,
    block_streaming: false,
  }
}

///|
pub(all) struct ChannelMeta {
  id : ChannelId
  label : String
  selection_label : String
  docs_path : String
  docs_label : String?
  blurb : String
  order : Int?
  aliases : Array[String]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct Attachment {
  id : String
  mime_type : String
  url : String
  filename : String?
  size : Int?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct Message {
  id : String
  channel : ChannelId
  from : String
  to : String
  content : String
  content_type : String
  timestamp : Int
  thread_id : String?
  reply_to : String?
  attachments : Array[Attachment]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct SendResult {
  channel : ChannelId
  message_id : String
  timestamp : Int
  status : String
} derive(ToJson, FromJson, Show)

///|
pub(all) enum ChannelError {
  NotConfigured(message~ : String)
  ConnectionFailed(message~ : String)
  SendMessageFailed(message~ : String)
  InvalidRecipient(message~ : String)
  RateLimited(message~ : String, retry_after_ms~ : Int?)
  Unknown(message~ : String)
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ChannelConfig {
  enabled : Bool
  accounts : Map[String, Json]
  global_settings : Json
} derive(ToJson, FromJson, Show)

///|
pub fn default_config() -> ChannelConfig {
  ChannelConfig::{ enabled: false, accounts: {}, global_settings: {} }
}

///|
pub(all) struct ChannelEvent {
  channel : ChannelId
  account_id : String
  event_type : String
  payload : Json
  timestamp : Int
} derive(ToJson, FromJson, Show)

///|
pub(all) enum ChannelEventType {
  MessageReceived
  MessageSent
  MessageUpdated
  MessageDeleted
  ReactionAdded
  ReactionRemoved
  UserJoined
  UserLeft
  TypingStarted
  TypingStopped
  Custom(String)
}

///|
pub(open) trait Channel {
  id(Self) -> ChannelId
  meta(Self) -> ChannelMeta
  capabilities(Self) -> ChannelCapabilities
  configure(Self, ChannelConfig) -> Unit
  async start(Self, account_id : String, config : Json) -> Result[
    Unit,
    ChannelError,
  ]
  async stop(Self, account_id : String) -> Result[Unit, ChannelError]
  async send(Self, to : String, message : Message, account_id : String?) -> Result[
    SendResult,
    ChannelError,
  ]
  handle_event(Self, event : ChannelEvent) -> Unit
  is_running(Self, account_id : String) -> Bool
}

///|
pub(all) struct ChannelDock {
  id : ChannelId
  meta : ChannelMeta
  capabilities : ChannelCapabilities
  is_configured : Bool
  is_running : Bool
  account_ids : Array[String]
  outbound : OutboundConfig?
  streaming : StreamingConfig?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct OutboundConfig {
  delivery_mode : String
  chunker_mode : String
  text_chunk_limit : Int
} derive(ToJson, FromJson, Show)

///|
pub(all) struct StreamingConfig {
  enabled : Bool
  chunk_size : Int
  chunk_delay_ms : Int
} derive(ToJson, FromJson, Show)
