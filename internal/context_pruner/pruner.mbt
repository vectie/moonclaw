///|
struct Pruner {
  logger : @pino.Logger
  token_counter : @token_counter.Counter
  safe_zone_tokens : Int32
}

///|
/// Result of compiling the model-facing context for one request.
///
/// Compilation is deliberately projection-only: the durable conversation is
/// never changed. Normal, in-budget requests are returned unchanged. When a
/// request is over budget, an old history span is replaced by the existing
/// deterministic checkpoint while retaining
/// the system/rules/task prefix and the newest complete exchange.
pub struct CompileResult {
  messages : Array[@openai.ChatCompletionMessageParam]
  origin_token_count : Int32
  final_token_count : Int32
  compacted_messages : Int32
  within_budget : Bool
}

///|
pub fn Pruner::new(
  safe_zone_tokens~ : Int32,
  logger~ : @pino.Logger,
) -> Pruner raise {
  {
    logger,
    token_counter: @token_counter.Counter::new(logger~),
    safe_zone_tokens,
  }
}

///|
fn context_result_reference(
  message : @openai.ChatCompletionMessageParam,
) -> String? {
  guard message is Tool(tool) else { return None }
  let value = @json.parse(
    checkpoint_content_text(tool.content).split("\n").head().unwrap_or(""),
  ) catch {
    _ => return None
  }
  match value {
    { "evidence_ref": String(reference), .. } if reference != "" &&
      reference.length() <= 1024 => Some(reference)
    _ => None
  }
}

///|
const ContextResultRangePrefix : String = "Retained result range: "

///|
fn context_result_span(
  message : @openai.ChatCompletionMessageParam,
) -> (String, String)? {
  if context_result_reference(message) is Some(reference) {
    return Some((reference, reference))
  }
  guard message is User(user) else { return None }
  for line in checkpoint_content_text(user.content).split("\n") {
    if line.has_prefix(ContextResultRangePrefix) {
      let value = @json.parse(line[ContextResultRangePrefix.length():]) catch {
        _ => return None
      }
      match value {
        { "evidence_ref": String(first), "end_ref": String(last), .. } =>
          return Some((first, last))
        _ => return None
      }
    }
  }
  None
}

///|
const ContextCheckpoint : String = "[Context checkpoint: retained observations, not exact evidence]"

///|
const DefaultRecentContextTokens : Int32 = 20000

///|
const MaxCheckpointTokens : Int32 = 768

///|
const MaxCheckpointObservations : Int32 = 8

///|
/// Check the provider ordering contract before transforming an overflowing
/// transcript. Every tool result must answer one unique call from the
/// immediately preceding assistant tool batch, and every call must have one
/// result before another non-tool message begins.
///
/// The normal in-budget path deliberately skips this pass. The compiler is a
/// context projection layer, not a general request validator; validation here
/// only prevents pruning from concealing or worsening malformed overflow input.
fn tool_transcript_is_valid(
  messages : Array[@openai.ChatCompletionMessageParam],
) -> Bool {
  let pending : Map[String, Bool] = Map([])
  let seen : Map[String, Bool] = Map([])
  for message in messages {
    match message {
      Tool(tool) => {
        if !pending.contains(tool.tool_call_id) {
          return false
        }
        pending.remove(tool.tool_call_id)
      }
      Assistant(assistant) => {
        if !pending.is_empty() {
          return false
        }
        for call in assistant.tool_calls {
          if seen.contains(call.id) {
            return false
          }
          seen[call.id] = true
          pending[call.id] = true
        }
      }
      User(_) | System(_) => if !pending.is_empty() { return false }
    }
  }
  pending.is_empty()
}

///|
fn is_context_checkpoint(message : @openai.ChatCompletionMessageParam) -> Bool {
  message is User(user) &&
  checkpoint_content_text(user.content).has_prefix("[Context checkpoint:")
}

///|
/// Returns the end of the protected task prefix. Rules are injected as user
/// messages before the original task. Generated checkpoints are derived
/// history, not another protected instruction prefix.
fn protected_prefix_end(
  messages : Array[@openai.ChatCompletionMessageParam],
) -> Int32 {
  for index in 0..<messages.length() {
    match messages[index] {
      Assistant(_) => return index
      User(_) if is_context_checkpoint(messages[index]) => return index
      _ => ()
    }
  }
  messages.length()
}

///|
/// Find the newest boundary that still retains a complete final exchange. A
/// suffix must never begin with a tool result because providers require the
/// corresponding assistant tool call to precede it. A generated checkpoint
/// does not start a new user turn.
fn newest_complete_suffix_start(
  messages : Array[@openai.ChatCompletionMessageParam],
  prefix_end : Int32,
) -> Int32 {
  guard messages.length() > prefix_end else { return -1 }
  let mut latest_assistant = -1
  let mut index = messages.length() - 1
  while index >= prefix_end {
    match messages[index] {
      Tool(_) => index -= 1
      User(_) if is_context_checkpoint(messages[index]) => index -= 1
      User(_) => return index
      Assistant(_) => {
        if latest_assistant < 0 {
          latest_assistant = index
        }
        index -= 1
      }
      System(_) => return -1
    }
  }
  latest_assistant
}

///|
fn contains_system_after(
  messages : Array[@openai.ChatCompletionMessageParam],
  start : Int32,
) -> Bool {
  for index in start..<messages.length() {
    match messages[index] {
      System(_) => return true
      _ => ()
    }
  }
  false
}

///|
fn checkpoint_content_text(
  parts : Array[@openai.ChatCompletionContentPartParam],
) -> String {
  let content = StringBuilder()
  let mut has_content = false
  for part in parts {
    match part {
      Text(text) => {
        if has_content {
          content.write_string(" ")
        }
        content.write_string(text.text)
        has_content = true
      }
      ImageUrl(_) => {
        content.write_string(" [image evidence]")
        has_content = true
      }
    }
  }
  content.to_string()
}

///|
fn Pruner::checkpoint_observation(
  pruner : Pruner,
  message : @openai.ChatCompletionMessageParam,
) -> String? {
  match message {
    User(user) => {
      let text = checkpoint_content_text(user.content).trim().to_owned()
      if text == "" {
        None
      } else {
        Some("- User: " + pruner.token_counter.truncate_string(text, 96))
      }
    }
    Assistant(assistant) => {
      let text = checkpoint_content_text(assistant.content).trim().to_owned()
      let line = StringBuilder()
      let mut has_content = false
      if text != "" {
        line.write_string(
          "- Assistant: " + pruner.token_counter.truncate_string(text, 96),
        )
        has_content = true
      }
      for call in assistant.tool_calls {
        if has_content {
          line.write_string("; ")
        } else {
          line.write_string("- Assistant: ")
          has_content = true
        }
        line.write_string("tool `\{call.function.name}`")
        match call.function.arguments {
          Some(arguments) if arguments != "" =>
            line.write_string(
              " args=" + pruner.token_counter.truncate_string(arguments, 64),
            )
          _ => ()
        }
      }
      if has_content {
        Some(line.to_string())
      } else {
        None
      }
    }
    Tool(_) | System(_) => None
  }
}

///|
fn Pruner::context_checkpoint(
  pruner : Pruner,
  messages : Array[@openai.ChatCompletionMessageParam],
  compacted_start : Int32,
  compacted_end : Int32,
) -> String {
  let mut first_ref = ""
  let mut last_ref = ""
  for index in compacted_start..<compacted_end {
    if context_result_span(messages[index]) is Some((first, last)) {
      if first_ref == "" {
        first_ref = first
      }
      last_ref = last
    }
  }
  let recall = if first_ref == "" {
    ContextCheckpoint + "\n"
  } else {
    ContextCheckpoint +
    "\n" +
    ContextResultRangePrefix +
    Json::object({ "evidence_ref": Json(first_ref), "end_ref": Json(last_ref) }).stringify() +
    "\n"
  }
  let observations : Array[String] = []
  let mut index = compacted_end - 1
  while index >= compacted_start &&
        observations.length() < MaxCheckpointObservations {
    match pruner.checkpoint_observation(messages[index]) {
      Some(observation) => observations.push(observation)
      None => ()
    }
    index -= 1
  }
  let checkpoint = StringBuilder()
  if !observations.is_empty() {
    checkpoint.write_string("\nObservations:")
    for index = observations.length() - 1; index >= 0; index = index - 1 {
      checkpoint.write_string("\n")
      checkpoint.write_string(observations[index])
    }
  }
  let checkpoint_limit = MaxCheckpointTokens.min(
    (pruner.safe_zone_tokens / 4).max(96),
  )
  // Keep opaque handles intact; only the descriptive checkpoint is lossy.
  recall +
  pruner.token_counter.truncate_string(
    checkpoint.to_string(),
    (checkpoint_limit - pruner.token_counter.count_string(recall)).max(0),
  )
}

///|
fn Pruner::build_compacted_projection(
  pruner : Pruner,
  messages : Array[@openai.ChatCompletionMessageParam],
  prefix_end : Int32,
  suffix_start : Int32,
) -> Array[@openai.ChatCompletionMessageParam] {
  let compiled : Array[@openai.ChatCompletionMessageParam] = []
  for index in 0..<prefix_end {
    compiled.push(messages[index])
  }
  compiled.push(
    @openai.user_message(
      content=pruner.context_checkpoint(messages, prefix_end, suffix_start),
    ),
  )
  for index in suffix_start..<messages.length() {
    compiled.push(messages[index])
  }
  compiled
}

///|
async fn Pruner::log_compilation(
  pruner : Pruner,
  origin_token_count : Int32,
  final_token_count : Int32,
  compacted_messages : Int32,
  within_budget : Bool,
) -> Unit {
  pruner.logger.info("ContextCompiled", data={
    "origin_token_count": origin_token_count,
    "final_token_count": final_token_count,
    "compacted_messages": compacted_messages,
    "within_budget": within_budget,
  })
}

///|
/// Compile a bounded, model-facing projection without mutating durable state.
///
/// The fast path performs one token count and returns the input values in the
/// same order. The overflow path:
///
/// 1. retains the complete system/rules/initial-task prefix;
/// 2. retains up to 20k recent message tokens after reserving the measured
///    protected-prefix/tool-schema cost and a bounded checkpoint;
/// 3. falls back once to the newest complete turn if the conservative estimate
///    still misses the budget.
///
/// If the protected prefix plus newest complete exchange cannot fit, the
/// smallest safe projection is returned with `within_budget = false`; required
/// instructions or active tool protocol are never silently removed.
pub async fn Pruner::compile_messages(
  pruner : Pruner,
  messages : Array[@openai.ChatCompletionMessageParam],
  tools~ : Array[@openai.ChatCompletionToolParam] = [],
) -> CompileResult {
  let projected = messages.map(fn(message) { message })
  let origin_token_count = pruner.token_counter.count_param(
    messages=projected,
    tools~,
  )
  if origin_token_count <= pruner.safe_zone_tokens {
    return {
      messages: projected,
      origin_token_count,
      final_token_count: origin_token_count,
      compacted_messages: 0,
      within_budget: true,
    }
  }

  // Never transform a malformed overflow transcript. Compacting an orphan
  // or duplicate tool result could hide the protocol defect while
  // still producing an invalid provider request.
  if !tool_transcript_is_valid(projected) {
    pruner.log_compilation(origin_token_count, origin_token_count, 0, false)
    return {
      messages: projected,
      origin_token_count,
      final_token_count: origin_token_count,
      compacted_messages: 0,
      within_budget: false,
    }
  }

  let prefix_end = protected_prefix_end(projected)
  let minimum_suffix_start = newest_complete_suffix_start(projected, prefix_end)
  // With no assistant turn there is no safe distinction between injected
  // rules, the initial task, and later user context. Keep it all.
  if prefix_end >= projected.length() || minimum_suffix_start <= prefix_end {
    pruner.log_compilation(origin_token_count, origin_token_count, 0, false)
    return {
      messages: projected,
      origin_token_count,
      final_token_count: origin_token_count,
      compacted_messages: 0,
      within_budget: false,
    }
  }
  // System messages are never compacted or reordered. Conversation-generated
  // system messages are expected in the leading prefix; fail safely if a
  // provider-specific adapter inserted one later.
  if contains_system_after(projected, prefix_end) {
    pruner.log_compilation(origin_token_count, origin_token_count, 0, false)
    return {
      messages: projected,
      origin_token_count,
      final_token_count: origin_token_count,
      compacted_messages: 0,
      within_budget: false,
    }
  }

  let protected_messages : Array[@openai.ChatCompletionMessageParam] = []
  for index in 0..<prefix_end {
    protected_messages.push(projected[index])
  }
  let protected_tokens = pruner.token_counter.count_param(
    messages=protected_messages,
    tools~,
  )
  let checkpoint_reserve = MaxCheckpointTokens.min(
    (pruner.safe_zone_tokens / 4).max(96),
  )
  let recent_token_target = DefaultRecentContextTokens.min(
    (pruner.safe_zone_tokens - protected_tokens - checkpoint_reserve).max(0),
  )
  let mut recent_tokens = 0
  let mut suffix_start = projected.length()
  for index = projected.length() - 1; index >= prefix_end; index = index - 1 {
    let message_tokens = pruner.token_counter.count_message(projected[index])
    if suffix_start < projected.length() &&
      recent_tokens + message_tokens > recent_token_target {
      break
    }
    suffix_start = index
    recent_tokens += message_tokens
  }
  // Extend backwards to a coherent user-turn boundary when available. If this
  // is one long initial tool turn, retaining its assistant call is the next
  // safest boundary.
  while suffix_start > prefix_end {
    match projected[suffix_start] {
      User(_) => break
      _ => suffix_start -= 1
    }
  }
  if suffix_start <= prefix_end {
    suffix_start = minimum_suffix_start
  }

  let mut compiled = pruner.build_compacted_projection(
    projected, prefix_end, suffix_start,
  )
  let mut final_token_count = pruner.token_counter.count_param(
    messages=compiled,
    tools~,
  )
  // A single conservative fallback bounds overflow compilation to two full
  // counts. This avoids quadratic behavior on long transcripts while retaining
  // the newest complete turn and active tool protocol.
  if final_token_count > pruner.safe_zone_tokens &&
    suffix_start < minimum_suffix_start {
    suffix_start = minimum_suffix_start
    compiled = pruner.build_compacted_projection(
      projected, prefix_end, suffix_start,
    )
    final_token_count = pruner.token_counter.count_param(
      messages=compiled,
      tools~,
    )
  }
  let compacted_messages = suffix_start - prefix_end
  let within_budget = final_token_count <= pruner.safe_zone_tokens
  pruner.log_compilation(
    origin_token_count, final_token_count, compacted_messages, within_budget,
  )
  {
    messages: compiled,
    origin_token_count,
    final_token_count,
    compacted_messages,
    within_budget,
  }
}
