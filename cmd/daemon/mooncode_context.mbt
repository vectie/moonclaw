///|
/// Refresh the canonical task without prematurely discarding transcript evidence.
fn mooncode_runtime_turn_context_previous_messages(
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
priv struct MoonCodeContextProjection {
  messages : Array[Json]
  metrics : Json
}

///|
/// One deterministic projection for initial planning and follow-ups. The compiler
/// owns budget and tool-batch preservation; the journal remains untouched.
async fn mooncode_runtime_turn_compile_context(
  command : Json,
  messages : Array[Json],
  tools : Array[@openai.ChatCompletionToolParam],
  model_window : Int32,
  output_tokens : Int32,
) -> MoonCodeContextProjection {
  // Keep an active working set, rather than waiting for the model's full
  // capacity. The existing payload override can request a larger window.
  let requested_window = mooncode_json_int(
    mooncode_json_object_field_or_empty(command, "payload"),
    "planner_context_window_tokens",
    default=model_window.min(10240),
  )
  let window = if model_window > 0 {
    if requested_window > 0 {
      requested_window.min(model_window)
    } else {
      model_window
    }
  } else {
    requested_window
  }
  if window <= 0 {
    return { messages, metrics: { "reason": "context-window-unknown" }, }
  }
  // Leave a quarter of the window for growth, and always reserve output space.
  let budget = (window - window / 4).min(window - output_tokens.max(0)).max(1)
  let typed : Array[@openai.ChatCompletionMessageParam] = @json.from_json(
    Json::array(mooncode_runtime_context_visible_messages(messages)),
  ) catch {
    _ =>
      return { messages, metrics: { "reason": "unsupported-message-shape" }, }
  }
  let compiled = @context_pruner.Pruner::new(safe_zone_tokens=budget, logger~).compile_messages(
    typed,
    tools~,
  ) catch {
    _ => return { messages, metrics: { "reason": "compiler-failed" }, }
  }
  let changed = compiled.redacted_tool_results > 0 ||
    compiled.compacted_messages > 0
  {
    messages: if changed {
      mooncode_runtime_context_merge_messages(
        compiled.messages.map(message => message.to_json()),
        messages,
      )
    } else {
      messages
    },
    metrics: {
      "applied": changed,
      "input_budget_tokens": budget,
      "before_tokens": compiled.origin_token_count,
      "after_tokens": compiled.final_token_count,
      "redacted_tool_results": compiled.redacted_tool_results,
      "compacted_messages": compiled.compacted_messages,
      "within_budget": compiled.within_budget,
    },
  }
}
