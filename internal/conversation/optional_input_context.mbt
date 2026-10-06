///|
/// Immutable optional input descriptors are persisted once, keyed by the exact
/// originating UserMessage event. Projection status is kept separately inside
/// the entry; neither field changes durable user-message bytes.
pub fn Conversation::capture_optional_input_context(
  self : Conversation,
  message_id : @uuid.Uuid,
  descriptor : Json,
) -> Unit raise {
  let key = message_id.to_string()
  match self.optional_input_contexts.get(key) {
    Some({ "descriptor": existing, .. }) => {
      guard existing == descriptor else {
        fail("Optional input context descriptor is immutable")
      }
    }
    Some(_) => fail("Invalid stored optional input context")
    None =>
      self.optional_input_contexts[key] = {
        "descriptor": descriptor,
        "status": "pending",
      }
  }
}

///|
pub fn Conversation::set_optional_input_context_status(
  self : Conversation,
  message_id : @uuid.Uuid,
  status : String,
) -> Unit raise {
  let key = message_id.to_string()
  guard self.optional_input_contexts.get(key)
    is Some({ "descriptor": descriptor, .. }) else {
    fail("Missing stored optional input context")
  }
  self.optional_input_contexts[key] = {
    "descriptor": descriptor,
    "status": status,
  }
}

///|
pub fn Conversation::optional_input_contexts(
  self : Conversation,
) -> Map[String, Json] {
  let copy : Map[String, Json] = {}
  for key, value in self.optional_input_contexts {
    copy[key] = value
  }
  copy
}

///|
/// Check the same event identity/pruning boundary used by `messages`. Equal
/// user text in an unrelated event cannot activate an optional descriptor.
pub fn Conversation::user_message_is_visible(
  self : Conversation,
  message_id : @uuid.Uuid,
) -> Bool {
  let mut found = false
  for event in self.events {
    match event.desc {
      Pruned(id~) if id == message_id => return false
      UserMessage(_) if event.id == message_id => found = true
      _ => ()
    }
  }
  found
}
