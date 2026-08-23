///|
const MOONCODE_SEMANTIC_COMPACTION_TRIAL_DEFAULT_MESSAGES = 96

///|
const MOONCODE_SEMANTIC_COMPACTION_PRESSURE_THRESHOLD_PPM = 750000

///|
const MOONCODE_SEMANTIC_COMPACTION_DEFAULT_CONTEXT_WINDOW_TOKENS = 0

///|
const MOONCODE_SEMANTIC_COMPACTION_TARGET_PRESSURE_PPM = 500000

///|
priv struct MoonCodeSemanticCompactionLifecycle {
  messages : Array[Json]
  metrics : Json
}

///|
fn mooncode_runtime_turn_active_semantic_compaction_enabled(
  command : Json,
) -> Bool {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  mooncode_json_bool(
    payload,
    "planner_hybrid_semantic_compaction_active",
    default=false,
  )
}

///|
fn mooncode_runtime_turn_semantic_compaction_target_pressure(
  command : Json,
) -> Int {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let trigger = mooncode_json_int(
      payload,
      "planner_semantic_compaction_pressure_threshold_ppm",
      default=MOONCODE_SEMANTIC_COMPACTION_PRESSURE_THRESHOLD_PPM,
    )
    .max(600000)
    .min(900000)
  mooncode_json_int(
    payload,
    "planner_semantic_compaction_target_pressure_ppm",
    default=MOONCODE_SEMANTIC_COMPACTION_TARGET_PRESSURE_PPM,
  )
  .max(300000)
  .min(700000)
  .min(trigger - 100000)
}

///|
/// Active mode defers the legacy 32-message suffix projection until measured
/// pressure is eligible. It still refreshes the canonical task contract and
/// removes non-durable image bytes before the lifecycle compiler runs.
fn mooncode_runtime_turn_active_semantic_compaction_previous_messages(
  previous : Array[Json],
  task_contract : String,
) -> Array[Json] {
  let retained : Array[Json] = []
  let mut saw_assistant = false
  let mut replaced_task = false
  for message in previous {
    let durable = mooncode_runtime_turn_durable_model_message(message)
    let role = mooncode_json_string(durable, "role", default="")
    if role == "assistant" {
      saw_assistant = true
    }
    if !saw_assistant && !replaced_task && role == "user" && task_contract != "" {
      retained.push(
        mooncode_runtime_context_text_message(
          "user",
          task_contract,
          UserContext,
          "user.task_contract",
        ),
      )
      replaced_task = true
    } else {
      retained.push(durable)
    }
  }
  retained
}

///|
fn mooncode_runtime_turn_semantic_compaction_instructions(
  messages : Array[Json],
) -> Array[Json] {
  let instructions : Array[Json] = []
  for message in messages {
    let role = mooncode_json_string(message, "role", default="")
    if role == "system" || role == "developer" {
      instructions.push(mooncode_runtime_context_visible_message(message))
    }
  }
  instructions
}

///|
fn mooncode_runtime_turn_semantic_compaction_provenance_valid(
  messages : Array[Json],
) -> Bool {
  for message in messages {
    if !mooncode_runtime_context_provenance_valid(
        mooncode_runtime_context_provenance(message),
      ) {
      return false
    }
  }
  true
}

///|
fn mooncode_runtime_turn_semantic_compaction_instruction_positions_safe(
  messages : Array[Json],
) -> Bool {
  let mut saw_assistant = false
  for message in messages {
    let role = mooncode_json_string(message, "role", default="")
    if role == "assistant" {
      saw_assistant = true
    } else if saw_assistant && (role == "system" || role == "developer") {
      return false
    }
  }
  true
}

///|
fn mooncode_runtime_turn_semantic_compaction_tool_protocol_valid(
  messages : Array[Json],
) -> Bool {
  let pending : Map[String, Bool] = Map([])
  let seen : Map[String, Bool] = Map([])
  for message in messages {
    let role = mooncode_json_string(message, "role", default="")
    if role == "assistant" {
      if !pending.is_empty() {
        return false
      }
      for call in mooncode_json_array_items(message, "tool_calls") {
        let id = mooncode_json_string(call, "id", default="")
        if id == "" || seen.contains(id) {
          return false
        }
        seen[id] = true
        pending[id] = true
      }
    } else if role == "tool" {
      let id = mooncode_json_string(message, "tool_call_id", default="")
      if id == "" || !pending.contains(id) {
        return false
      }
      pending.remove(id)
    } else if !pending.is_empty() {
      return false
    }
  }
  pending.is_empty()
}

///|
fn mooncode_runtime_turn_semantic_compaction_lifecycle_metrics(
  enabled : Bool,
  eligible : Bool,
  applied : Bool,
  reason : String,
  threshold : Int,
  before_message_count : Int,
  after_message_count : Int,
  before_chars : Int,
  after_chars : Int,
  context_window_tokens : Int,
  estimated_context_tokens : Int,
  observed_context_tokens : Int,
  context_usage_source : String,
  context_pressure_ppm : Int,
  pressure_threshold_ppm : Int,
  target_pressure_ppm : Int,
  target_tokens : Int,
  before_tokens : Int,
  after_tokens : Int,
  redacted_tool_results : Int,
  compacted_messages : Int,
  within_budget : Bool,
  invariants_preserved : Bool,
) -> Json {
  {
    "contract": "moonclaw.semantic-compaction-lifecycle.v1",
    "mode": if enabled {
      "active"
    } else {
      "disabled"
    },
    "enabled": enabled,
    "eligible": eligible,
    "applied": applied,
    "reason": reason,
    "message_threshold": threshold,
    "before_message_count": before_message_count,
    "after_message_count": after_message_count,
    "before_message_chars": before_chars,
    "after_message_chars": after_chars,
    "deterministic_reduction_chars": (before_chars - after_chars).max(0),
    "context_window_tokens": context_window_tokens,
    "estimated_context_tokens": estimated_context_tokens,
    "observed_context_tokens": observed_context_tokens,
    "context_usage_source": context_usage_source,
    "context_pressure_ppm": context_pressure_ppm,
    "pressure_threshold_ppm": pressure_threshold_ppm,
    "target_pressure_ppm": target_pressure_ppm,
    "target_tokens": target_tokens,
    "before_tokens": before_tokens,
    "after_tokens": after_tokens,
    "redacted_tool_results": redacted_tool_results,
    "compacted_messages": compacted_messages,
    "within_budget": within_budget,
    "invariants_preserved": invariants_preserved,
  }
}

///|
fn mooncode_runtime_turn_semantic_compaction_trial_enabled(
  command : Json,
) -> Bool {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  mooncode_json_bool(
    payload,
    "planner_hybrid_semantic_compaction_trial",
    default=false,
  )
}

///|
fn mooncode_runtime_turn_semantic_compaction_trial_threshold(
  command : Json,
) -> Int {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  mooncode_json_int(
    payload,
    "planner_semantic_compaction_message_threshold",
    default=MOONCODE_SEMANTIC_COMPACTION_TRIAL_DEFAULT_MESSAGES,
  )
  .max(64)
  .min(512)
}

///|
/// The semantic trial is eligible only when the caller supplies a model
/// context window and the measured serialized conversation reaches the
/// pressure threshold. The message count remains a cheap lower bound so a
/// short burst of oversized messages cannot accidentally opt in too early.
fn mooncode_runtime_turn_semantic_compaction_pressure(
  command : Json,
  previous_chars : Int,
  previous_message_count : Int,
  threshold : Int,
  observed_context_tokens? : Int = 0,
) -> (Int, Int, Int, Bool, String, String) {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let context_window_tokens = mooncode_json_int(
    payload,
    "planner_context_window_tokens",
    default=MOONCODE_SEMANTIC_COMPACTION_DEFAULT_CONTEXT_WINDOW_TOKENS,
  ).max(0)
  let pressure_threshold_ppm = mooncode_json_int(
      payload,
      "planner_semantic_compaction_pressure_threshold_ppm",
      default=MOONCODE_SEMANTIC_COMPACTION_PRESSURE_THRESHOLD_PPM,
    )
    .max(600000)
    .min(900000)
  // Prefer the provider-observed prompt usage from the preceding round. The
  // four-characters-per-token estimate remains a conservative fallback for
  // providers that do not return usage in streamed responses.
  let estimated_context_tokens = if observed_context_tokens > 0 {
    observed_context_tokens
  } else {
    (previous_chars + 3) / 4
  }
  let context_usage_source = if observed_context_tokens > 0 {
    "provider-prompt-tokens"
  } else {
    "serialized-char-estimate"
  }
  let context_pressure_ppm = if context_window_tokens <= 0 {
    0
  } else {
    (estimated_context_tokens.to_int64() *
    1000000L /
    context_window_tokens.to_int64())
    .min(2000000L)
    .to_int()
  }
  let has_pressure = context_window_tokens > 0 &&
    estimated_context_tokens.to_int64() * 1000000L >=
    context_window_tokens.to_int64() * pressure_threshold_ppm.to_int64()
  let eligible = previous_message_count >= threshold && has_pressure
  let reason = if context_window_tokens <= 0 {
    "context-window-unknown"
  } else if previous_message_count < threshold {
    "below-very-long-task-threshold"
  } else if !has_pressure {
    "below-context-pressure-threshold"
  } else {
    "eligible-for-offline-semantic-summary-evaluation"
  }
  (
    context_window_tokens, estimated_context_tokens, context_pressure_ppm, eligible,
    reason, context_usage_source,
  )
}

///|
/// Compile only the current provider-facing projection. The durable command,
/// execution journal, and tool results are never changed. Any parse,
/// provenance, instruction, or tool-protocol uncertainty returns the exact
/// input messages with a closed refusal reason.
async fn mooncode_runtime_turn_active_semantic_compaction(
  command : Json,
  previous_plan : Json,
  messages : Array[Json],
  tools : Array[@openai.ChatCompletionToolParam],
  model_safe_zone_tokens : Int,
) -> MoonCodeSemanticCompactionLifecycle {
  let enabled = mooncode_runtime_turn_active_semantic_compaction_enabled(
    command,
  )
  let threshold = mooncode_runtime_turn_semantic_compaction_trial_threshold(
    command,
  )
  let provider_messages = mooncode_runtime_context_visible_messages(messages)
  let before_message_count = provider_messages.length()
  let before_chars = Json::array(provider_messages).stringify().length()
  let previous_metrics = mooncode_json_object_field_or_empty(
    previous_plan, "planner_metrics",
  )
  let observed_context_tokens = mooncode_json_int(
    previous_metrics,
    "prompt_tokens",
    default=0,
  ).max(0)
  let (
    context_window_tokens,
    estimated_context_tokens,
    context_pressure_ppm,
    pressure_eligible,
    pressure_reason,
    context_usage_source,
  ) = mooncode_runtime_turn_semantic_compaction_pressure(
    command,
    before_chars,
    before_message_count,
    threshold,
    observed_context_tokens~,
  )
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let pressure_threshold_ppm = mooncode_json_int(
      payload,
      "planner_semantic_compaction_pressure_threshold_ppm",
      default=MOONCODE_SEMANTIC_COMPACTION_PRESSURE_THRESHOLD_PPM,
    )
    .max(600000)
    .min(900000)
  let target_pressure_ppm = mooncode_runtime_turn_semantic_compaction_target_pressure(
    command,
  )
  let policy_target_tokens = if context_window_tokens <= 0 {
    0
  } else {
    (context_window_tokens.to_int64() *
    target_pressure_ppm.to_int64() /
    1000000L)
    .max(1L)
    .to_int()
  }
  let target_tokens = if model_safe_zone_tokens > 0 && policy_target_tokens > 0 {
    model_safe_zone_tokens.min(policy_target_tokens)
  } else if policy_target_tokens > 0 {
    policy_target_tokens
  } else {
    model_safe_zone_tokens.max(0)
  }
  let eligible = enabled && pressure_eligible
  if !eligible {
    let reason = if !enabled { "flag-disabled" } else { pressure_reason }
    return {
      messages,
      metrics: mooncode_runtime_turn_semantic_compaction_lifecycle_metrics(
        enabled, false, false, reason, threshold, before_message_count, before_message_count,
        before_chars, before_chars, context_window_tokens, estimated_context_tokens,
        observed_context_tokens, context_usage_source, context_pressure_ppm, pressure_threshold_ppm,
        target_pressure_ppm, target_tokens, estimated_context_tokens, estimated_context_tokens,
        0, 0, true, true,
      ),
    }
  }
  let source_instructions = mooncode_runtime_turn_semantic_compaction_instructions(
    messages,
  )
  if !mooncode_runtime_turn_semantic_compaction_provenance_valid(messages) ||
    !mooncode_runtime_turn_semantic_compaction_instruction_positions_safe(
      messages,
    ) ||
    !mooncode_runtime_turn_semantic_compaction_tool_protocol_valid(messages) {
    return {
      messages,
      metrics: mooncode_runtime_turn_semantic_compaction_lifecycle_metrics(
        true, true, false, "source-invariant-invalid", threshold, before_message_count,
        before_message_count, before_chars, before_chars, context_window_tokens,
        estimated_context_tokens, observed_context_tokens, context_usage_source,
        context_pressure_ppm, pressure_threshold_ppm, target_pressure_ppm, target_tokens,
        estimated_context_tokens, estimated_context_tokens, 0, 0, false, false,
      ),
    }
  }
  let typed_messages : Array[@openai.ChatCompletionMessageParam] = @json.from_json(
    Json::array(provider_messages),
  ) catch {
    _ =>
      return {
        messages,
        metrics: mooncode_runtime_turn_semantic_compaction_lifecycle_metrics(
          true, true, false, "unsupported-message-shape", threshold, before_message_count,
          before_message_count, before_chars, before_chars, context_window_tokens,
          estimated_context_tokens, observed_context_tokens, context_usage_source,
          context_pressure_ppm, pressure_threshold_ppm, target_pressure_ppm, target_tokens,
          estimated_context_tokens, estimated_context_tokens, 0, 0, false, true,
        ),
      }
  }
  let compiled = Some(
    @context_pruner.Pruner::new(safe_zone_tokens=target_tokens, logger~).compile_messages(
      typed_messages,
      tools~,
    ),
  ) catch {
    _ => None
  }
  guard compiled is Some(compiled) else {
    return {
      messages,
      metrics: mooncode_runtime_turn_semantic_compaction_lifecycle_metrics(
        true, true, false, "compiler-failed", threshold, before_message_count, before_message_count,
        before_chars, before_chars, context_window_tokens, estimated_context_tokens,
        observed_context_tokens, context_usage_source, context_pressure_ppm, pressure_threshold_ppm,
        target_pressure_ppm, target_tokens, estimated_context_tokens, estimated_context_tokens,
        0, 0, false, true,
      ),
    }
  }
  let compiled_provider_messages = compiled.messages.map(message => {
    message.to_json()
  })
  let projected = mooncode_runtime_context_merge_messages(
    compiled_provider_messages, messages,
  )
  let after_provider_messages = mooncode_runtime_context_visible_messages(
    projected,
  )
  let after_chars = Json::array(after_provider_messages).stringify().length()
  let invariants_preserved = source_instructions ==
    mooncode_runtime_turn_semantic_compaction_instructions(projected) &&
    mooncode_runtime_turn_semantic_compaction_provenance_valid(projected) &&
    mooncode_runtime_turn_semantic_compaction_tool_protocol_valid(projected)
  let reduced = after_chars < before_chars &&
    (compiled.redacted_tool_results > 0 || compiled.compacted_messages > 0)
  let applied = invariants_preserved && reduced
  if !applied {
    let reason = if !invariants_preserved {
      "compiled-invariant-invalid"
    } else {
      "no-safe-reduction"
    }
    return {
      messages,
      metrics: mooncode_runtime_turn_semantic_compaction_lifecycle_metrics(
        true,
        true,
        false,
        reason,
        threshold,
        before_message_count,
        before_message_count,
        before_chars,
        before_chars,
        context_window_tokens,
        estimated_context_tokens,
        observed_context_tokens,
        context_usage_source,
        context_pressure_ppm,
        pressure_threshold_ppm,
        target_pressure_ppm,
        target_tokens,
        compiled.origin_token_count,
        compiled.origin_token_count,
        0,
        0,
        compiled.within_budget,
        invariants_preserved,
      ),
    }
  }
  {
    messages: projected,
    metrics: mooncode_runtime_turn_semantic_compaction_lifecycle_metrics(
      true,
      true,
      true,
      if compiled.within_budget {
        "applied-within-target"
      } else {
        "applied-minimum-safe-projection"
      },
      threshold,
      before_message_count,
      projected.length(),
      before_chars,
      after_chars,
      context_window_tokens,
      estimated_context_tokens,
      observed_context_tokens,
      context_usage_source,
      context_pressure_ppm,
      pressure_threshold_ppm,
      target_pressure_ppm,
      target_tokens,
      compiled.origin_token_count,
      compiled.final_token_count,
      compiled.redacted_tool_results,
      compiled.compacted_messages,
      compiled.within_budget,
      true,
    ),
  }
}

///|
fn mooncode_runtime_turn_semantic_compaction_trial(
  command : Json,
  previous_plan : Json,
  effective_messages : Array[Json],
) -> Json {
  let enabled = mooncode_runtime_turn_semantic_compaction_trial_enabled(command)
  let threshold = mooncode_runtime_turn_semantic_compaction_trial_threshold(
    command,
  )
  let previous_messages = mooncode_json_array_items(
    previous_plan, "model_messages",
  )
  let previous_provider_messages = mooncode_runtime_context_visible_messages(
    previous_messages,
  )
  let effective_provider_messages = mooncode_runtime_context_visible_messages(
    effective_messages,
  )
  let previous_chars = Json::array(previous_provider_messages)
    .stringify()
    .length()
  let effective_chars = Json::array(effective_provider_messages)
    .stringify()
    .length()
  let previous_metrics = mooncode_json_object_field_or_empty(
    previous_plan, "planner_metrics",
  )
  let observed_context_tokens = mooncode_json_int(
    previous_metrics,
    "prompt_tokens",
    default=0,
  ).max(0)
  let (
    context_window_tokens,
    estimated_context_tokens,
    context_pressure_ppm,
    pressure_eligible,
    pressure_reason,
    context_usage_source,
  ) = mooncode_runtime_turn_semantic_compaction_pressure(
    command,
    previous_chars,
    previous_messages.length(),
    threshold,
    observed_context_tokens~,
  )
  let eligible = enabled && pressure_eligible
  {
    "contract": "moonclaw.semantic-compaction-trial.v1",
    "mode": "shadow",
    "enabled": enabled,
    "eligible": eligible,
    "message_threshold": threshold,
    "previous_message_count": previous_messages.length(),
    "effective_message_count": effective_messages.length(),
    "previous_message_chars": previous_chars,
    "effective_message_chars": effective_chars,
    "context_window_tokens": context_window_tokens,
    "estimated_context_tokens": estimated_context_tokens,
    "observed_context_tokens": observed_context_tokens,
    "context_usage_source": context_usage_source,
    "context_pressure_ppm": context_pressure_ppm,
    "pressure_threshold_ppm": mooncode_json_int(
      mooncode_json_object_field_or_empty(command, "payload"),
      "planner_semantic_compaction_pressure_threshold_ppm",
      default=MOONCODE_SEMANTIC_COMPACTION_PRESSURE_THRESHOLD_PPM,
    )
    .max(600000)
    .min(900000),
    "deterministic_reduction_chars": (previous_chars - effective_chars).max(0),
    "reason": if !enabled {
      "flag-disabled"
    } else {
      pressure_reason
    },
  }
}
