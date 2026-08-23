///|
struct Pruner {
  logger : @pino.Logger
  token_counter : @token_counter.Counter
  safe_zone_tokens : Int
}

///|
/// Result of pruning operation
pub struct PruneResult {
  /// Event IDs that should be pruned
  pruned_ids : Array[@uuid.Uuid]
  /// Original token count before pruning
  origin_token_count : Int
  /// Token count after pruning
  pruned_token_count : Int
}

///|
/// Result of compiling the model-facing context for one request.
///
/// Compilation is deliberately projection-only: the durable conversation is
/// never changed. Normal, in-budget requests are returned unchanged. When a
/// request is over budget, old tool evidence is redacted first and an old
/// history span may be replaced by a deterministic checkpoint while retaining
/// the system/rules/task prefix and the newest complete exchange.
pub struct CompileResult {
  messages : Array[@openai.ChatCompletionMessageParam]
  origin_token_count : Int
  final_token_count : Int
  redacted_tool_results : Int
  compacted_messages : Int
  within_budget : Bool
}

///|
pub fn Pruner::new(
  safe_zone_tokens~ : Int,
  logger~ : @pino.Logger,
) -> Pruner raise {
  {
    logger,
    token_counter: @token_counter.Counter::new(logger~),
    safe_zone_tokens,
  }
}

///|
const ClearedToolOutputPlaceholder : String = "[Cleared: tool output. If you want to see the output, you can use the tool again.]"

///|
const ContextCheckpoint : String = "[Context checkpoint: MoonClaw compacted older model-facing messages to control prompt cost. The original task contract and complete durable journal are unchanged. Continue from the retained recent exchange; re-read exact evidence only when needed.]"

///|
const DefaultRecentContextTokens : Int = 20000

///|
const MaxCheckpointTokens : Int = 768

///|
const MaxCheckpointObservations : Int = 8

///|
fn latest_tool_batch_ids(
  messages : Array[@openai.ChatCompletionMessageParam],
) -> Map[String, Bool] {
  let ids : Map[String, Bool] = Map([])
  let mut latest = -1
  for index in 0..<messages.length() {
    match messages[index] {
      Assistant(param) if !param.tool_calls.is_empty() => latest = index
      _ => ()
    }
  }
  if latest >= 0 {
    guard messages[latest] is Assistant(param) else { return ids }
    for call in param.tool_calls {
      ids[call.id] = true
    }
  }
  ids
}

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
/// Returns the end of the protected task prefix. Rules are injected as user
/// messages before the original task, so retaining everything before the first
/// assistant response protects both without depending on their exact count.
fn protected_prefix_end(
  messages : Array[@openai.ChatCompletionMessageParam],
) -> Int {
  for index in 0..<messages.length() {
    match messages[index] {
      Assistant(_) => return index
      _ => ()
    }
  }
  messages.length()
}

///|
/// Find the newest boundary that still retains a complete final exchange. A
/// suffix must never begin with a tool result because providers require the
/// corresponding assistant tool call to precede it.
fn newest_complete_suffix_start(
  messages : Array[@openai.ChatCompletionMessageParam],
  prefix_end : Int,
) -> Int {
  guard messages.length() > prefix_end else { return -1 }
  let mut latest_assistant = -1
  let mut index = messages.length() - 1
  while index >= prefix_end {
    match messages[index] {
      Tool(_) => index -= 1
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
  start : Int,
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
  let content = StringBuilder::new()
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
      let line = StringBuilder::new()
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
  compacted_start : Int,
  compacted_end : Int,
) -> String {
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
  let checkpoint = StringBuilder::new()
  checkpoint.write_string(ContextCheckpoint)
  checkpoint.write_string(
    " Compacted \{compacted_end - compacted_start} historical messages.",
  )
  if !observations.is_empty() {
    checkpoint.write_string(
      "\nRecent historical observations from the compacted span:",
    )
    for index = observations.length() - 1; index >= 0; index = index - 1 {
      checkpoint.write_string("\n")
      checkpoint.write_string(observations[index])
    }
  }
  checkpoint.write_string(
    "\nExact tool outputs are omitted from this checkpoint; re-read only when exact evidence is needed.",
  )
  let checkpoint_limit = MaxCheckpointTokens.min(
    (pruner.safe_zone_tokens / 4).max(96),
  )
  pruner.token_counter.truncate_string(checkpoint.to_string(), checkpoint_limit)
}

///|
fn Pruner::build_compacted_projection(
  pruner : Pruner,
  messages : Array[@openai.ChatCompletionMessageParam],
  prefix_end : Int,
  suffix_start : Int,
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
  origin_token_count : Int,
  final_token_count : Int,
  redacted_tool_results : Int,
  compacted_messages : Int,
  within_budget : Bool,
) -> Unit {
  pruner.logger.info("ContextCompiled", data={
    "origin_token_count": origin_token_count,
    "final_token_count": final_token_count,
    "redacted_tool_results": redacted_tool_results,
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
/// 1. redacts old tool results, retaining the newest tool batch;
/// 2. retains the complete system/rules/initial-task prefix;
/// 3. retains up to 20k recent message tokens after reserving the measured
///    protected-prefix/tool-schema cost and a bounded checkpoint;
/// 4. falls back once to the newest complete turn if the conservative estimate
///    still misses the budget.
///
/// If the protected prefix plus newest complete exchange cannot fit, the
/// smallest safe projection is returned with `within_budget = false`; required
/// instructions or active tool protocol are never silently removed.
pub async fn Pruner::compile_messages(
  pruner : Pruner,
  messages : Array[@openai.ChatCompletionMessageParam],
  tools? : Array[@openai.ChatCompletionToolParam] = [],
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
      redacted_tool_results: 0,
      compacted_messages: 0,
      within_budget: true,
    }
  }

  // Never transform a malformed overflow transcript. In particular, redacting
  // an orphan or duplicate tool result could hide the protocol defect while
  // still producing an invalid provider request.
  if !tool_transcript_is_valid(projected) {
    pruner.log_compilation(origin_token_count, origin_token_count, 0, 0, false)
    return {
      messages: projected,
      origin_token_count,
      final_token_count: origin_token_count,
      redacted_tool_results: 0,
      compacted_messages: 0,
      within_budget: false,
    }
  }

  // Preserve the newest tool batch as the active working set. Older results
  // are reproducible and usually dominate the prompt.
  let protected_tool_ids = latest_tool_batch_ids(projected)
  let mut current_tokens = origin_token_count
  let mut redacted_tool_results = 0
  for index, message in projected {
    guard current_tokens > pruner.safe_zone_tokens else { break }
    match message {
      Tool(tool) => {
        if protected_tool_ids.contains(tool.tool_call_id) ||
          tool.content is [Text({ text: ClearedToolOutputPlaceholder, .. })] {
          continue
        }
        let replacement = @openai.tool_message(
          content=ClearedToolOutputPlaceholder,
          tool_call_id=tool.tool_call_id,
        )
        let savings = pruner.token_counter.count_message(message) -
          pruner.token_counter.count_message(replacement)
        if savings > 0 {
          projected[index] = replacement
          current_tokens -= savings
          redacted_tool_results += 1
        }
      }
      _ => ()
    }
  }
  if current_tokens <= pruner.safe_zone_tokens {
    pruner.log_compilation(
      origin_token_count, current_tokens, redacted_tool_results, 0, true,
    )
    return {
      messages: projected,
      origin_token_count,
      final_token_count: current_tokens,
      redacted_tool_results,
      compacted_messages: 0,
      within_budget: true,
    }
  }

  let prefix_end = protected_prefix_end(projected)
  let minimum_suffix_start = newest_complete_suffix_start(projected, prefix_end)
  // With no assistant turn there is no safe distinction between injected
  // rules, the initial task, and later user context. Keep it all.
  if prefix_end >= projected.length() || minimum_suffix_start <= prefix_end {
    pruner.log_compilation(
      origin_token_count, current_tokens, redacted_tool_results, 0, false,
    )
    return {
      messages: projected,
      origin_token_count,
      final_token_count: current_tokens,
      redacted_tool_results,
      compacted_messages: 0,
      within_budget: false,
    }
  }
  // System messages are never compacted or reordered. Conversation-generated
  // system messages are expected in the leading prefix; fail safely if a
  // provider-specific adapter inserted one later.
  if contains_system_after(projected, prefix_end) {
    pruner.log_compilation(
      origin_token_count, current_tokens, redacted_tool_results, 0, false,
    )
    return {
      messages: projected,
      origin_token_count,
      final_token_count: current_tokens,
      redacted_tool_results,
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
    origin_token_count, final_token_count, redacted_tool_results, compacted_messages,
    within_budget,
  )
  {
    messages: compiled,
    origin_token_count,
    final_token_count,
    redacted_tool_results,
    compacted_messages,
    within_budget,
  }
}

///|
/// Prunes in-memory chat context until it fits within the configured safe-zone token budget.
///
/// The pruner only redacts tool response messages because they typically contain the
/// largest payloads and can be regenerated on demand. Tool messages are replaced with a
/// short placeholder while preserving the original tool call id so that downstream state
/// remains consistent.
///
/// Parameters:
///
/// * `pruner`: Maintains logging and token counting utilities.
/// * `messages`: Mutable conversation history that will be truncated in place.
/// * `tools`: Tool descriptors needed when estimating token counts.
///
/// The function recalculates the token usage after each redaction, logging the reduction,
/// and stops once the budget is respected or no more tool messages are available.
pub async fn Pruner::prune_messages(
  pruner : Pruner,
  messages : Array[@openai.ChatCompletionMessageParam],
  tools? : Array[@openai.ChatCompletionToolParam] = [],
) -> Unit {
  let tokens = pruner.token_counter.count_param(messages~, tools~)
  if tokens <= pruner.safe_zone_tokens {
    return
  }
  let mut pruned_tokens = tokens // current state
  let pruned_index = []
  let prune_goal_met = for i, message in messages {
    match message {
      Tool(tool) => {
        if tool.content is [Text({ text: ClearedToolOutputPlaceholder, .. })] {
          // Already cleared, skip
          continue
        }
        messages[i] = @openai.tool_message(
          content=ClearedToolOutputPlaceholder,
          tool_call_id=tool.tool_call_id,
        )
        pruned_index.push(i)
        // TODO: this is O(n^2), optimize by tracking deltas
        pruned_tokens = pruner.token_counter.count_param(messages~, tools~)
        if pruned_tokens <= pruner.safe_zone_tokens {
          break true
        }
      }
      _ => ()
    }
  } nobreak {
    false
  }
  pruner.logger.info("ContextPruned", data={
    "origin_token_count": tokens,
    "pruned_token_count": pruned_tokens,
    "pruned_index": pruned_index,
    "pruned_goal_met": prune_goal_met,
  })
}

///|
/// Determines which PostToolCall events should be pruned to fit within budget.
///
/// This method does NOT modify the conversation - it returns the IDs to prune.
/// The caller is responsible for emitting Pruned events.
///
/// Parameters:
///
/// * `conversation` : The conversation to analyze
/// * `tools` : Tool descriptors for token counting
///
/// Returns a PruneResult containing:
///
/// * `pruned_ids`: Array of event IDs to prune (oldest first)
/// * `origin_token_count`: Token count before pruning
/// * `pruned_token_count`: Token count after pruning
pub async fn Pruner::calculate_pruning(
  pruner : Pruner,
  conversation : @conversation.Conversation,
  tools? : Array[@openai.ChatCompletionToolParam] = [],
) -> PruneResult {
  // Build set of already-pruned IDs
  let already_pruned : Set[@uuid.Uuid] = Set([])
  for e in conversation.events() {
    match e.desc {
      Pruned(id~) => already_pruned.add(id)
      _ => ()
    }
  }

  // Count current tokens
  let messages = conversation.messages(include_system=true)
  let openai_messages = messages.map(fn(msg) { msg.to_openai() })
  let origin_token_count = pruner.token_counter.count_param(
    messages=openai_messages,
    tools~,
  )
  if origin_token_count <= pruner.safe_zone_tokens {
    return {
      pruned_ids: [],
      origin_token_count,
      pruned_token_count: origin_token_count,
    }
  }

  // Collect prunable PostToolCall events (oldest first, not already pruned)
  // Each entry: (event_id, tool_call_id, rendered_content)
  let prunables : Array[(@uuid.Uuid, String, String)] = []
  for e in conversation.events() {
    if already_pruned.contains(e.id) {
      continue
    }
    match e.desc {
      PostToolCall(tc, rendered~, ..) => prunables.push((e.id, tc.id, rendered))
      _ => ()
    }
  }

  // Greedily prune oldest until within budget
  // We simulate the effect by building a modified message list
  let pruned_ids : Array[@uuid.Uuid] = []
  let mut current_tokens = origin_token_count
  for entry in prunables {
    let (event_id, tool_call_id, rendered) = entry
    if current_tokens <= pruner.safe_zone_tokens {
      break
    }
    // Estimate token savings from pruning this event
    let original_msg = @ai.tool_message(tool_call_id~, content=rendered)
    let pruned_msg = @ai.tool_message(
      tool_call_id~,
      content=ClearedToolOutputPlaceholder,
    )
    let original_tokens = pruner.token_counter.count_message(
      original_msg.to_openai(),
    )
    let pruned_msg_tokens = pruner.token_counter.count_message(
      pruned_msg.to_openai(),
    )
    let savings = original_tokens - pruned_msg_tokens
    pruned_ids.push(event_id)
    current_tokens -= savings
  }
  { pruned_ids, origin_token_count, pruned_token_count: current_tokens }
}
