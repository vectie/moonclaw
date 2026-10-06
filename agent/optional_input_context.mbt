///|
/// A host-supplied optional context block. Only the complete exact block in its
/// originating user message may be omitted. Task instructions, other messages
/// and the durable input remain unchanged. This is not a generic pruner rule.
pub struct OptionalInputContext {
  block : String
  omission : String
  digest : String
  integrity_digest : String
} derive(ToJson, @json.FromJson)

///|
pub fn OptionalInputContext::new(
  block~ : String,
  omission~ : String,
  digest~ : String,
) -> OptionalInputContext {
  {
    block,
    omission,
    digest,
    integrity_digest: optional_input_integrity(block, omission, digest),
  }
}

///|
fn optional_input_integrity(
  block : String,
  omission : String,
  digest : String,
) -> String {
  let canonical : Json = [
    "moonclaw.optional-input-context.v1", block, omission, digest,
  ]
  "sha256:" +
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(canonical.stringify())),
  )
}

///|
pub fn OptionalInputContext::valid_for_message(
  self : OptionalInputContext,
  message : @ai.Message,
) -> Bool {
  guard message is User(content) else { return false }
  !self.block.is_empty() &&
  !self.omission.is_empty() &&
  !self.digest.is_empty() &&
  self.integrity_digest ==
  optional_input_integrity(self.block, self.omission, self.digest) &&
  content.split(self.block).count() == 2
}

///|
priv struct OptionalContextProjection {
  message_id : @uuid.Uuid
  original : String
  fallback : String
  context : OptionalInputContext
  mut status : String
}

///|
pub struct OptionalInputContextStatus {
  message_id : @uuid.Uuid
  digest : String
  status : String
} derive(ToJson)

///|
pub fn Agent::optional_context_statuses(
  self : Agent,
) -> Array[OptionalInputContextStatus] {
  self.optional_contexts.map(context => {
    message_id: context.message_id,
    digest: context.context.digest,
    status: context.status,
  })
}

///|
fn Agent::register_optional_context(
  self : Agent,
  message_id : @uuid.Uuid,
  message : @ai.Message,
  context : OptionalInputContext,
) -> Unit raise {
  guard context.valid_for_message(message) else {
    fail(
      "Optional input context must identify one complete block in its user message",
    )
  }
  let original = message.content()
  self.history.capture_optional_input_context(message_id, context.to_json())
  self.optional_contexts.push({
    message_id,
    original,
    fallback: original.replace_all(old=context.block, new=context.omission),
    context,
    status: "pending",
  })
}

///|
fn Agent::restore_optional_contexts(self : Agent) -> Unit raise {
  for key, value in self.history.optional_input_contexts() {
    let message_id = @uuid.parse(key)
    guard value is { "descriptor": descriptor, "status": String(status), .. } else {
      fail("Invalid stored optional input context entry")
    }
    guard ["pending", "ready", "over_budget", "not_in_projection"].contains(
      status,
    ) else {
      fail("Invalid stored optional input context status")
    }
    let context : OptionalInputContext = @json.from_json(descriptor)
    let events = self.history.events().filter(event => event.id == message_id)
    guard events is [{ desc: UserMessage(original), .. }] else {
      fail("Stored optional input context does not bind one user message")
    }
    guard context.valid_for_message(@ai.user_message(content=original)) else {
      fail(
        "Stored optional input context block does not match its user message",
      )
    }
    self.optional_contexts.push({
      message_id,
      original,
      fallback: original.replace_all(old=context.block, new=context.omission),
      context,
      status,
    })
  }
}

///|
fn optional_context_message_present(
  messages : Array[@openai.ChatCompletionMessageParam],
  original : String,
) -> Bool {
  messages.any(message => {
    match message {
      User({ content: [Text({ text, .. })], .. }) => text == original
      _ => false
    }
  })
}

///|
async fn Agent::compile_optional_contexts(
  self : Agent,
  messages : Array[@openai.ChatCompletionMessageParam],
  tools~ : Array[@openai.ChatCompletionToolParam],
) -> @context_pruner.CompileResult {
  // Ordinary conversations take exactly the original compiler path.
  if self.optional_contexts.is_empty() {
    return self.context_pruner.compile_messages(messages, tools~)
  }
  let active = self.optional_contexts.filter(context => {
    self.history.user_message_is_visible(context.message_id)
  })
  for context in self.optional_contexts {
    if !self.history.user_message_is_visible(context.message_id) {
      context.status = "not_in_projection"
      self.history.set_optional_input_context_status(
        context.message_id,
        context.status,
      )
    }
  }
  // A persisted omission belongs to that exact input event. A model-window
  // change or restart must not silently reintroduce its learned context. A new
  // explicitly queued input may independently include the same saved snapshot.
  let previous_omissions = active.filter(context => {
    context.status == "over_budget"
  })
  let still_optional = active.filter(context => context.status != "over_budget")
  let initial = if previous_omissions.is_empty() {
    messages
  } else {
    self.messages_omitting_optional_contexts(previous_omissions)
  }
  let compiled = self.context_pruner.compile_messages(initial, tools~)
  let omit = !compiled.within_budget ||
    still_optional.any(context => {
      !optional_context_message_present(compiled.messages, context.original)
    })
  let projected = if omit && !still_optional.is_empty() {
    // Recompile from the full original projection, never from a checkpoint
    // that might contain a partial learned procedure or a truncated tail.
    let fallback = self.messages_omitting_optional_contexts(active)
    self.context_pruner.compile_messages(fallback, tools~)
  } else {
    compiled
  }
  for context in active {
    context.status = if omit || context.status == "over_budget" {
      "over_budget"
    } else {
      "ready"
    }
    self.history.set_optional_input_context_status(
      context.message_id,
      context.status,
    )
    self.logger.info("OptionalInputContextProjected", data={
      "message_id": context.message_id.to_string(),
      "digest": context.context.digest,
      "status": context.status,
      "original_token_count": compiled.origin_token_count,
      "final_token_count": projected.final_token_count,
      "within_budget": projected.within_budget,
    })
  }
  // Retain capture and projection evidence even if transport fails or is
  // cancelled after dispatch. Ordinary conversations keep their original path.
  self.session_manager.save(self.history)
  projected
}

///|
async fn Agent::messages_omitting_optional_contexts(
  self : Agent,
  contexts : Array[OptionalContextProjection],
) -> Array[@openai.ChatCompletionMessageParam] {
  let overrides : Map[@uuid.Uuid, String] = Map([])
  for context in contexts {
    overrides[context.message_id] = context.fallback
  }
  let messages = self.history.messages(
    include_system=true,
    user_message_overrides=overrides,
  )
  self.skills.load_and_apply(messages)
  self.rules.apply(messages)
  messages.map(message => message.to_openai())
}
