///|
async test "result handles survive repeated context compaction" (t : @test.Test) {
  @mock.run(t, mock => {
    let messages : Array[@openai.ChatCompletionMessageParam] = [
      @openai.system_message(content="system"),
      @openai.user_message(content="Implement the requested change"),
    ]
    for index in 0..<12 {
      messages.push(
        @openai.assistant_message(content="", tool_calls=[
          @openai.tool_call(id="call-\{index}", name="read", arguments="{}"),
        ]),
      )
      messages.push(
        @openai.tool_message(
          tool_call_id="call-\{index}",
          content=({ "evidence_ref": "result-\{index}" } : Json).stringify() +
            "\n" +
            "source \"quoted\"\n".repeat(500),
        ),
      )
      messages.push(
        @openai.user_message(
          content="Continue \{index} " + "context ".repeat(100),
        ),
      )
    }
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=1200,
      logger=mock.logger,
    )
    let first = pruner.compile_messages(messages)
    assert_true(first.within_budget)
    assert_true(first.compacted_messages > 0)
    let text = compile_transcript_json(first.messages)
    assert_true(text.contains("result-0"))
    assert_true(text.contains("Retained result range:"))
    let extended = first.messages.copy()
    for index in 12..<24 {
      extended.push(
        @openai.assistant_message(content="", tool_calls=[
          @openai.tool_call(id="call-\{index}", name="read", arguments="{}"),
        ]),
      )
      extended.push(
        @openai.tool_message(
          tool_call_id="call-\{index}",
          content=({ "evidence_ref": "result-\{index}" } : Json).stringify() +
            "\n" +
            "later \"quoted\"\n".repeat(300),
        ),
      )
      extended.push(
        @openai.user_message(
          content="Continue \{index} " + "context ".repeat(100),
        ),
      )
    }
    let second = pruner.compile_messages(extended)
    assert_true(second.within_budget)
    assert_true(second.compacted_messages > 0)
    let text = compile_transcript_json(second.messages)
    assert_true(text.contains("result-0"))
    assert_true(text.contains("result-23"))
    assert_true(text.contains("Implement the requested change"))
    assert_eq(
      second.messages
      .filter(message => {
        compile_transcript_json([message]).contains("Retained result range:")
      })
      .length(),
      1,
    )
  })
}
