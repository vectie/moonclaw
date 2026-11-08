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
    "CONTEXT_BENCH case=\{label} before=\{result.origin_token_count} after=\{result.final_token_count} compacted=\{result.compacted_messages} within_budget=\{result.within_budget}",
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
async test "compile_messages/tool_heavy_compacts_complete_old_exchange" (
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
    assert_true(result.compacted_messages > 0)
    assert_false(transcript.contains("OLD-EVIDENCE"))
    assert_true(transcript.contains("Context checkpoint"))
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
