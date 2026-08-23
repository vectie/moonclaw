///|
struct Conversation {
  clock : &@clock.Clock
  name : String
  description : String?
  id : @uuid.Uuid
  events : Array[@event.Event]
  created_at : @clock.Timestamp
  mut updated_at : @clock.Timestamp
  cwd : String
  web_search : Bool
  source_kind : String
  workspace_trust : String
}

///|
/// Returns whether web search functionality is enabled for this conversation.
pub fn Conversation::web_search(self : Conversation) -> Bool {
  self.web_search
}

///|
pub fn Conversation::cwd(self : Conversation) -> String {
  self.cwd
}

///|
pub fn Conversation::events(self : Conversation) -> ArrayView[@event.Event] {
  self.events
}

///|
pub fn Conversation::source_kind(self : Conversation) -> String {
  self.source_kind
}

///|
pub fn source_kind_valid(value : String) -> Bool {
  [
    "user", "moondesk.general", "mooncode", "worker", "validation", "memory_consolidation",
    "safety_review",
  ].contains(value)
}

///|
pub fn Conversation::workspace_trust(self : Conversation) -> String {
  self.workspace_trust
}

///|
pub fn workspace_trust_valid(value : String) -> Bool {
  value == "unknown" || value == "untrusted" || value == "trusted"
}

///|
priv struct Message {
  /// The Unix timestamp (in milliseconds) of when the message was created.
  timestamp : @clock.Timestamp
  /// Usage statistics for the completion request.
  usage : @ai.Usage?
  message : @ai.Message
}
