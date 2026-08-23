///|
/// Helper to create a conversation with events for testing
async fn create_test_conversation(
  mock : @mock.Context,
  events : Array[@event.EventDesc],
) -> @conversation.Conversation {
  let manager = @conversation.Manager::new(
    uuid=mock.uuid,
    clock=mock.clock,
    home=mock.cwd.path(),
  )
  let conversation = manager.new_conversation(
    name="Test Conversation",
    cwd=mock.cwd.path(),
  )
  let event_target = @event.EventTarget::new(uuid=mock.uuid)
  event_target.add_listener(event => conversation.add_event(event))
  for desc in events {
    event_target.emit(desc)
  }
  event_target.flush()
  conversation
}

///|
async test "calculate_pruning/no_pruning_needed" (t : @test.Test) {
  @mock.run(t, mock => {
    let conversation = create_test_conversation(mock, [
      UserMessage("Hello"),
      AssistantMessage(usage=None, "Hi there!", tool_calls=[]),
    ])
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=10000,
      logger=mock.logger,
    )
    let result = pruner.calculate_pruning(conversation)
    // Should not prune anything since we're well within budget
    json_inspect(result.pruned_ids.length(), content=0)
    json_inspect(
      result.origin_token_count == result.pruned_token_count,
      content=true,
    )
  })
}

///|
async test "calculate_pruning/prunes_tool_output" (t : @test.Test) {
  @mock.run(t, mock => {
    let large_output = "x".repeat(10000)
    let conversation = create_test_conversation(mock, [
      UserMessage("Run command"),
      AssistantMessage(usage=None, "Running", tool_calls=[
        @ai.tool_call(id="call_1", name="execute", arguments="{}"),
      ]),
      PostToolCall(
        @ai.tool_call(id="call_1", name="execute", arguments="{}"),
        result=Ok(Json::string(large_output)),
        rendered=large_output,
      ),
    ])
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=100,
      logger=mock.logger,
    )
    let result = pruner.calculate_pruning(conversation)
    // Should mark the PostToolCall event for pruning
    json_inspect(result.pruned_ids.length(), content=1)
    json_inspect(
      result.pruned_token_count < result.origin_token_count,
      content=true,
    )
  })
}

///|
async test "calculate_pruning/multiple_tools_oldest_first" (t : @test.Test) {
  @mock.run(t, mock => {
    let output1 = "output1".repeat(500)
    let output2 = "output2".repeat(500)
    let output3 = "output3".repeat(500)
    let conversation = create_test_conversation(mock, [
      UserMessage("Test"),
      AssistantMessage(usage=None, "Calling tool 1", tool_calls=[
        @ai.tool_call(id="call_1", name="tool", arguments="{}"),
      ]),
      PostToolCall(
        @ai.tool_call(id="call_1", name="tool", arguments="{}"),
        result=Ok(Json::string(output1)),
        rendered=output1,
      ),
      AssistantMessage(usage=None, "Calling tool 2", tool_calls=[
        @ai.tool_call(id="call_2", name="tool", arguments="{}"),
      ]),
      PostToolCall(
        @ai.tool_call(id="call_2", name="tool", arguments="{}"),
        result=Ok(Json::string(output2)),
        rendered=output2,
      ),
      AssistantMessage(usage=None, "Calling tool 3", tool_calls=[
        @ai.tool_call(id="call_3", name="tool", arguments="{}"),
      ]),
      PostToolCall(
        @ai.tool_call(id="call_3", name="tool", arguments="{}"),
        result=Ok(Json::string(output3)),
        rendered=output3,
      ),
    ])
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=200,
      logger=mock.logger,
    )
    let result = pruner.calculate_pruning(conversation)
    // Should prune multiple tool outputs, oldest first
    json_inspect(result.pruned_ids.length() > 0, content=true)
    json_inspect(
      result.pruned_token_count < result.origin_token_count,
      content=true,
    )
    json_inspect(result.pruned_token_count <= 200, content=true)
  })
}

///|
async test "calculate_pruning/respects_already_pruned" (t : @test.Test) {
  @mock.run(t, mock => {
    let output = "x".repeat(5000)
    // First, create conversation with a PostToolCall
    let manager = @conversation.Manager::new(
      uuid=mock.uuid,
      clock=mock.clock,
      home=mock.cwd.path(),
    )
    let conversation = manager.new_conversation(
      name="Test",
      cwd=mock.cwd.path(),
    )
    let event_target = @event.EventTarget::new(uuid=mock.uuid)
    event_target.add_listener(event => conversation.add_event(event))
    event_target.emit(UserMessage("Test"))
    event_target.emit(
      AssistantMessage(usage=None, "Running", tool_calls=[
        @ai.tool_call(id="call_1", name="tool", arguments="{}"),
      ]),
    )
    event_target.emit(
      PostToolCall(
        @ai.tool_call(id="call_1", name="tool", arguments="{}"),
        result=Ok(Json::string(output)),
        rendered=output,
      ),
    )
    event_target.flush()

    // Get the PostToolCall event ID
    let post_tool_call_id = conversation.events()[2].id

    // Now add a Pruned event for that PostToolCall
    event_target.emit(Pruned(id=post_tool_call_id))
    event_target.flush()
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=100,
      logger=mock.logger,
    )
    let result = pruner.calculate_pruning(conversation)

    // Should not re-prune already pruned events
    json_inspect(result.pruned_ids.length(), content=0)
  })
}

///|
async test "calculate_pruning/no_tool_messages" (t : @test.Test) {
  @mock.run(t, mock => {
    let conversation = create_test_conversation(mock, [
      UserMessage("Hello"),
      AssistantMessage(usage=None, "Hi there!", tool_calls=[]),
      UserMessage("How are you?"),
      AssistantMessage(usage=None, "I'm fine, thanks!", tool_calls=[]),
    ])
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=10, // Very low budget
      logger=mock.logger,
    )
    let result = pruner.calculate_pruning(conversation)
    // Should not prune anything since there are no PostToolCall events
    json_inspect(result.pruned_ids.length(), content=0)
  })
}

///|
async test "calculate_pruning/empty_conversation" (t : @test.Test) {
  @mock.run(t, mock => {
    let conversation = create_test_conversation(mock, [])
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=100,
      logger=mock.logger,
    )
    let result = pruner.calculate_pruning(conversation)
    // Should handle empty conversation gracefully
    json_inspect(result.pruned_ids.length(), content=0)
    json_inspect(result.origin_token_count, content=7) // Just system overhead
  })
}

///|
async test "calculate_pruning/stops_at_budget" (t : @test.Test) {
  @mock.run(t, mock => {
    let small_output = "x".repeat(100)
    let conversation = create_test_conversation(mock, [
      UserMessage("Test"),
      AssistantMessage(usage=None, "Tool 1", tool_calls=[
        @ai.tool_call(id="call_1", name="tool", arguments="{}"),
      ]),
      PostToolCall(
        @ai.tool_call(id="call_1", name="tool", arguments="{}"),
        result=Ok(Json::string(small_output)),
        rendered=small_output,
      ),
      AssistantMessage(usage=None, "Tool 2", tool_calls=[
        @ai.tool_call(id="call_2", name="tool", arguments="{}"),
      ]),
      PostToolCall(
        @ai.tool_call(id="call_2", name="tool", arguments="{}"),
        result=Ok(Json::string(small_output)),
        rendered=small_output,
      ),
    ])
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=100,
      logger=mock.logger,
    )
    let result = pruner.calculate_pruning(conversation)
    // Should stop pruning once budget is met
    json_inspect(result.pruned_token_count <= 100, content=true)
  })
}

///|
async test "calculate_pruning/with_tools_parameter" (t : @test.Test) {
  @mock.run(t, mock => {
    let output = "x".repeat(5000)
    let conversation = create_test_conversation(mock, [
      UserMessage("Test"),
      AssistantMessage(usage=None, "Running", tool_calls=[
        @ai.tool_call(id="call_1", name="tool", arguments="{}"),
      ]),
      PostToolCall(
        @ai.tool_call(id="call_1", name="tool", arguments="{}"),
        result=Ok(Json::string(output)),
        rendered=output,
      ),
    ])
    let tools = [
      @openai.tool(name="test_tool", description="A test tool", parameters={
        "type": "object",
        "properties": {},
      }),
    ]
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=100,
      logger=mock.logger,
    )
    let result = pruner.calculate_pruning(conversation, tools~)
    // Should count tool overhead in token calculation
    json_inspect(result.pruned_ids.length() > 0, content=true)
  })
}

// ============================================================================
// Existing message-pruning behavior
// ============================================================================

///|
async test "prune_messages/basic" (t : @test.Test) {
  let messages = [
    @openai.user_message(content="Hello"),
    @openai.assistant_message(content="Hi!"),
    @openai.user_message(content="What's the weather?"),
  ]
  @mock.run(t, mock => {
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=100,
      logger=mock.logger,
    )
    pruner.prune_messages(messages)
    // Should not modify anything since there are no tool messages
    json_inspect(messages.length(), content=3)
  })
}

///|
async test "prune_messages/large_tool_output" (t : @test.Test) {
  let messages = [
    @openai.user_message(content="Run command"),
    @openai.assistant_message(content="Running", tool_calls=[
      @openai.tool_call(id="call_1", name="execute", arguments="{}"),
    ]),
    @openai.tool_message(tool_call_id="call_1", content="x".repeat(10000)),
  ]
  @mock.run(t, mock => {
    let counter = @token_counter.Counter::new(logger=mock.logger)
    let tokens_before = counter.count_param(messages~)
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=100,
      logger=mock.logger,
    )
    pruner.prune_messages(messages)
    let tokens_after = counter.count_param(messages~)
    // Tool output should be replaced with placeholder
    json_inspect(tokens_after < tokens_before, content=true)
  })
}

///|
async test "prune_messages/empty" (t : @test.Test) {
  let messages : Array[@openai.ChatCompletionMessageParam] = []
  @mock.run(t, mock => {
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=100,
      logger=mock.logger,
    )
    pruner.prune_messages(messages)
    // Should handle empty array gracefully
    json_inspect(messages.length(), content=0)
  })
}

// ============================================================================
// Model-facing context compiler regression and benchmark matrix
// ============================================================================

///|
fn compile_transcript_json(
  messages : Array[@openai.ChatCompletionMessageParam],
) -> String {
  Json::array(messages.map(message => message.to_json())).stringify()
}

///|
fn tool_protocol_is_valid(
  messages : Array[@openai.ChatCompletionMessageParam],
) -> Bool {
  let calls : Map[String, Bool] = Map([])
  for message in messages {
    match message {
      Assistant(assistant) =>
        for call in assistant.tool_calls {
          calls[call.id] = true
        }
      Tool(tool) => if !calls.contains(tool.tool_call_id) { return false }
      _ => ()
    }
  }
  true
}

///|
fn print_compile_metrics(
  label : String,
  result : @context_pruner.CompileResult,
) -> Unit {
  println(
    "CONTEXT_BENCH case=\{label} before=\{result.origin_token_count} after=\{result.final_token_count} redacted=\{result.redacted_tool_results} compacted=\{result.compacted_messages} within_budget=\{result.within_budget}",
  )
}

///|
async test "compile_messages/in_budget_identity" (t : @test.Test) {
  @mock.run(t, mock => {
    let messages = [
      @openai.system_message(content="production system contract"),
      @openai.user_message(content="make the focused change"),
      @openai.assistant_message(content="done"),
    ]
    let before = compile_transcript_json(messages)
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=10000,
      logger=mock.logger,
    )
    let result = pruner.compile_messages(messages)
    print_compile_metrics("in_budget", result)
    assert_eq(compile_transcript_json(result.messages), before)
    assert_eq(result.origin_token_count, result.final_token_count)
    assert_eq(result.redacted_tool_results, 0)
    assert_eq(result.compacted_messages, 0)
    assert_true(result.within_budget)
  })
}

///|
async test "compile_messages/long_chat_is_deterministic_and_bounded" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let messages : Array[@openai.ChatCompletionMessageParam] = [
      @openai.system_message(content="production system contract"),
      @openai.user_message(content="INITIAL-TASK: preserve service behavior"),
    ]
    for index = 0; index < 12; index = index + 1 {
      messages.push(
        @openai.assistant_message(
          content="OLD-ASSISTANT-\{index} " + "analysis detail ".repeat(350),
        ),
      )
      messages.push(
        @openai.user_message(
          content="OLD-USER-\{index} " + "followup detail ".repeat(350),
        ),
      )
    }
    messages.push(@openai.user_message(content="LATEST-REQUEST: finish safely"))
    messages.push(@openai.assistant_message(content="LATEST-ANSWER: verified"))
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=800,
      logger=mock.logger,
    )
    let first = pruner.compile_messages(messages)
    let second = pruner.compile_messages(messages)
    let transcript = compile_transcript_json(first.messages)
    print_compile_metrics("long_chat", first)
    assert_true(first.within_budget)
    assert_true(first.final_token_count <= 800)
    assert_true(first.compacted_messages > 0)
    assert_true(transcript.contains("INITIAL-TASK"))
    assert_true(transcript.contains("LATEST-ANSWER"))
    assert_true(transcript.contains("Context checkpoint"))
    assert_false(transcript.contains("OLD-ASSISTANT-0"))
    assert_eq(transcript, compile_transcript_json(second.messages))
  })
}

///|
async test "compile_messages/tool_heavy_redacts_old_evidence_first" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let messages = [
      @openai.system_message(content="system"),
      @openai.user_message(content="inspect and repair"),
      @openai.assistant_message(content="", tool_calls=[
        @openai.tool_call(
          id="old-read",
          name="read",
          arguments="{\"path\":\"old.mbt\"}",
        ),
      ]),
      @openai.tool_message(
        content="OLD-EVIDENCE " + "old evidence ".repeat(2500),
        tool_call_id="old-read",
      ),
      @openai.assistant_message(content="", tool_calls=[
        @openai.tool_call(
          id="latest-read",
          name="read",
          arguments="{\"path\":\"active.mbt\"}",
        ),
      ]),
      @openai.tool_message(
        content="LATEST-EVIDENCE " + "active evidence ".repeat(40),
        tool_call_id="latest-read",
      ),
    ]
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=500,
      logger=mock.logger,
    )
    let result = pruner.compile_messages(messages)
    let transcript = compile_transcript_json(result.messages)
    print_compile_metrics("tool_heavy", result)
    assert_true(result.within_budget)
    assert_eq(result.redacted_tool_results, 1)
    assert_eq(result.compacted_messages, 0)
    assert_false(transcript.contains("OLD-EVIDENCE"))
    assert_true(transcript.contains("Cleared: tool output"))
    assert_true(transcript.contains("LATEST-EVIDENCE"))
    assert_true(tool_protocol_is_valid(result.messages))
  })
}

///|
async test "compile_messages/mixed_history_keeps_latest_complete_tool_turn" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let messages : Array[@openai.ChatCompletionMessageParam] = [
      @openai.system_message(content="system"),
      @openai.user_message(content="INITIAL-TASK"),
    ]
    for index = 0; index < 8; index = index + 1 {
      messages.push(
        @openai.assistant_message(
          content="prior analysis " + "reasoning ".repeat(180),
        ),
      )
      messages.push(
        @openai.user_message(
          content="FOLLOWUP-\{index} " + "request ".repeat(180),
        ),
      )
      let call_id = "read-\{index}"
      messages.push(
        @openai.assistant_message(content="", tool_calls=[
          @openai.tool_call(
            id=call_id,
            name="read",
            arguments="{\"path\":\"file-\{index}.mbt\"}",
          ),
        ]),
      )
      messages.push(
        @openai.tool_message(
          content="RESULT-\{index} " + "source ".repeat(180),
          tool_call_id=call_id,
        ),
      )
    }
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=700,
      logger=mock.logger,
    )
    let result = pruner.compile_messages(messages)
    let transcript = compile_transcript_json(result.messages)
    print_compile_metrics("mixed_history", result)
    assert_true(result.within_budget)
    assert_true(result.compacted_messages > 0)
    assert_true(transcript.contains("INITIAL-TASK"))
    assert_true(transcript.contains("FOLLOWUP-7"))
    assert_true(transcript.contains("read-7"))
    assert_true(transcript.contains("RESULT-7"))
    assert_false(transcript.contains("FOLLOWUP-0"))
    assert_true(tool_protocol_is_valid(result.messages))
  })
}

///|
async test "compile_messages/oversized_protected_prompt_fails_without_data_loss" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let messages = [
      @openai.system_message(
        content="PROTECTED-SYSTEM " + "instruction ".repeat(1000),
      ),
      @openai.user_message(
        content="PROTECTED-TASK " + "requirement ".repeat(1000),
      ),
      @openai.assistant_message(content="LATEST-ANSWER"),
    ]
    let before = compile_transcript_json(messages)
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=100,
      logger=mock.logger,
    )
    let result = pruner.compile_messages(messages)
    print_compile_metrics("oversized_protected", result)
    assert_false(result.within_budget)
    assert_eq(result.compacted_messages, 0)
    assert_eq(result.final_token_count, result.origin_token_count)
    assert_eq(compile_transcript_json(result.messages), before)
  })
}

///|
async test "compile_messages/tool_schema_pressure_does_not_drop_task" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let messages = [
      @openai.system_message(content="system"),
      @openai.user_message(content="SCHEMA-PRESSURE-TASK"),
    ]
    let tools = [
      @openai.tool(
        name="large_tool",
        description="schema description ".repeat(2000),
        parameters={ "type": "object", "properties": {} },
      ),
    ]
    let before = compile_transcript_json(messages)
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=300,
      logger=mock.logger,
    )
    let result = pruner.compile_messages(messages, tools~)
    print_compile_metrics("schema_pressure", result)
    assert_false(result.within_budget)
    assert_eq(result.compacted_messages, 0)
    assert_eq(compile_transcript_json(result.messages), before)
  })
}

///|
async test "compile_messages/unicode_checkpoint_uses_valid_token_boundaries" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let messages = [
      @openai.system_message(content="系统契约 🌙"),
      @openai.user_message(content="初始任务：保持多语言内容完整"),
      @openai.assistant_message(
        content="旧观察：修复路径 /工作区/模块.mbt 🚀 " +
          "上下文证据🙂 ".repeat(800),
      ),
      @openai.user_message(content="旧跟进：继续验证边界 🧪"),
      @openai.assistant_message(content="旧答复：已验证"),
      @openai.user_message(content="最新请求：安全完成"),
      @openai.assistant_message(content="最新答复：完成 ✅"),
    ]
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=350,
      logger=mock.logger,
    )
    let result = pruner.compile_messages(messages)
    let transcript = compile_transcript_json(result.messages)
    print_compile_metrics("unicode", result)
    assert_true(result.within_budget)
    assert_true(result.compacted_messages > 0)
    assert_true(transcript.contains("初始任务"))
    assert_true(transcript.contains("最新请求"))
    assert_true(transcript.contains("Context checkpoint"))
    assert_false(transcript.contains("�"))
  })
}

///|
async test "compile_messages/thousand_message_history_stays_bounded" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let messages : Array[@openai.ChatCompletionMessageParam] = [
      @openai.system_message(content="production contract"),
      @openai.user_message(content="INITIAL-LARGE-HISTORY-TASK"),
    ]
    for index = 0; index < 500; index = index + 1 {
      messages.push(
        @openai.assistant_message(
          content="OBSERVATION-\{index}: stable implementation decision",
        ),
      )
      messages.push(
        @openai.user_message(content="FOLLOWUP-\{index}: continue validation"),
      )
    }
    messages.push(@openai.user_message(content="LATEST-LARGE-HISTORY-REQUEST"))
    messages.push(
      @openai.assistant_message(content="LATEST-LARGE-HISTORY-ANSWER"),
    )
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=800,
      logger=mock.logger,
    )
    let result = pruner.compile_messages(messages)
    let transcript = compile_transcript_json(result.messages)
    print_compile_metrics("thousand_messages", result)
    assert_true(result.within_budget)
    assert_true(result.compacted_messages > 900)
    assert_true(transcript.contains("INITIAL-LARGE-HISTORY-TASK"))
    assert_true(transcript.contains("LATEST-LARGE-HISTORY-REQUEST"))
    assert_true(transcript.contains("LATEST-LARGE-HISTORY-ANSWER"))
    assert_false(transcript.contains("FOLLOWUP-0"))
  })
}
