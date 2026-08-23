///|
fn adversarial_transcript_json(
  messages : Array[@openai.ChatCompletionMessageParam],
) -> String {
  Json::array(messages.map(message => message.to_json())).stringify()
}

///|
/// Stricter than the regression helper: calls must be unique, tool results
/// must be adjacent to their assistant batch, and every call must be answered
/// exactly once before another role begins.
fn adversarial_tool_protocol_is_valid(
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
async fn assert_malformed_overflow_rejected(
  mock : @mock.Context,
  label : String,
  messages : Array[@openai.ChatCompletionMessageParam],
) -> Unit {
  let before = adversarial_transcript_json(messages)
  let pruner = @context_pruner.Pruner::new(
    safe_zone_tokens=100,
    logger=mock.logger,
  )
  let result = pruner.compile_messages(messages)
  guard !result.within_budget else {
    fail("malformed case unexpectedly fit: " + label)
  }
  guard result.redacted_tool_results == 0 else {
    fail("malformed case was redacted: " + label)
  }
  guard result.compacted_messages == 0 else {
    fail("malformed case was compacted: " + label)
  }
  guard result.origin_token_count == result.final_token_count else {
    fail("malformed case count changed: " + label)
  }
  guard adversarial_transcript_json(result.messages) == before else {
    fail("malformed case projection changed: " + label)
  }
  guard adversarial_transcript_json(messages) == before else {
    fail("malformed case mutated its input: " + label)
  }
}

///|
async test "compile_messages/empty_zero_negative_and_exact_budget_boundaries" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let empty : Array[@openai.ChatCompletionMessageParam] = []
    for budget in [0, -1] {
      let pruner = @context_pruner.Pruner::new(
        safe_zone_tokens=budget,
        logger=mock.logger,
      )
      let result = pruner.compile_messages(empty)
      assert_false(result.within_budget)
      assert_eq(result.origin_token_count, 7)
      assert_eq(result.final_token_count, 7)
      assert_eq(result.messages.length(), 0)
    }

    let messages = [
      @openai.system_message(content="SYSTEM-BOUNDARY"),
      @openai.user_message(content="TASK-BOUNDARY"),
      @openai.assistant_message(content="ANSWER-BOUNDARY"),
    ]
    let before = adversarial_transcript_json(messages)
    let counter = @token_counter.Counter::new(logger=mock.logger)
    let exact_tokens = counter.count_param(messages~)
    let exact = @context_pruner.Pruner::new(
      safe_zone_tokens=exact_tokens,
      logger=mock.logger,
    ).compile_messages(messages)
    assert_true(exact.within_budget)
    assert_eq(exact.final_token_count, exact_tokens)
    assert_eq(adversarial_transcript_json(exact.messages), before)

    let one_short = @context_pruner.Pruner::new(
      safe_zone_tokens=exact_tokens - 1,
      logger=mock.logger,
    ).compile_messages(messages)
    assert_false(one_short.within_budget)
    assert_eq(one_short.final_token_count, exact_tokens)
    assert_eq(adversarial_transcript_json(one_short.messages), before)
  })
}

///|
async test "compile_messages/overflow_does_not_mutate_caller_array" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let messages = [
      @openai.system_message(content="system"),
      @openai.user_message(content="IMMUTABLE-TASK"),
      @openai.assistant_message(content="old analysis"),
      @openai.user_message(content="old context ".repeat(3000)),
      @openai.assistant_message(content="old answer"),
      @openai.user_message(content="IMMUTABLE-LATEST"),
      @openai.assistant_message(content="IMMUTABLE-ANSWER"),
    ]
    let before = adversarial_transcript_json(messages)
    let result = @context_pruner.Pruner::new(
      safe_zone_tokens=350,
      logger=mock.logger,
    ).compile_messages(messages)
    assert_true(result.within_budget)
    assert_true(result.compacted_messages > 0)
    assert_eq(adversarial_transcript_json(messages), before)
    assert_true(
      adversarial_transcript_json(result.messages).contains(
        "Context checkpoint",
      ),
    )
  })
}

///|
async test "compile_messages/preserves_complete_parallel_active_tool_batch" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let messages = [
      @openai.system_message(content="system"),
      @openai.user_message(content="PARALLEL-TOOL-TASK"),
      @openai.assistant_message(content="", tool_calls=[
        @openai.tool_call(id="old-call", name="read", arguments="{}"),
      ]),
      @openai.tool_message(
        tool_call_id="old-call",
        content="OLD-RESULT " + "old ".repeat(3000),
      ),
      @openai.user_message(content="inspect three current files"),
      @openai.assistant_message(content="", tool_calls=[
        @openai.tool_call(
          id="active-a",
          name="read",
          arguments="{\"path\":\"a.mbt\"}",
        ),
        @openai.tool_call(
          id="active-b",
          name="read",
          arguments="{\"path\":\"b.mbt\"}",
        ),
        @openai.tool_call(
          id="active-c",
          name="read",
          arguments="{\"path\":\"c.mbt\"}",
        ),
      ]),
      @openai.tool_message(tool_call_id="active-a", content="ACTIVE-A result"),
      @openai.tool_message(tool_call_id="active-b", content="ACTIVE-B result"),
      @openai.tool_message(tool_call_id="active-c", content="ACTIVE-C result"),
    ]
    let result = @context_pruner.Pruner::new(
      safe_zone_tokens=650,
      logger=mock.logger,
    ).compile_messages(messages)
    let transcript = adversarial_transcript_json(result.messages)
    assert_true(result.within_budget)
    assert_eq(result.redacted_tool_results, 1)
    assert_true(transcript.contains("Cleared: tool output"))
    for
      marker in [
        "active-a", "active-b", "active-c", "ACTIVE-A", "ACTIVE-B", "ACTIVE-C",
      ] {
      guard transcript.contains(marker) else {
        fail("parallel tool batch lost marker: " + marker)
      }
    }
    assert_true(adversarial_tool_protocol_is_valid(result.messages))
  })
}

///|
async test "compile_messages/malformed_tool_protocol_fails_unchanged" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    assert_malformed_overflow_rejected(mock, "orphan result", [
      @openai.system_message(content="system"),
      @openai.user_message(content="task"),
      @openai.tool_message(
        tool_call_id="missing-call",
        content="orphan ".repeat(1000),
      ),
    ])
    assert_malformed_overflow_rejected(mock, "interrupted batch", [
      @openai.system_message(content="system"),
      @openai.user_message(content="task"),
      @openai.assistant_message(content="", tool_calls=[
        @openai.tool_call(id="pending", name="read", arguments="{}"),
      ]),
      @openai.user_message(content="interrupt ".repeat(1000)),
    ])
    assert_malformed_overflow_rejected(mock, "duplicate call id", [
      @openai.system_message(content="system"),
      @openai.user_message(content="task"),
      @openai.assistant_message(content="", tool_calls=[
        @openai.tool_call(id="duplicate", name="read", arguments="{}"),
      ]),
      @openai.tool_message(tool_call_id="duplicate", content="first"),
      @openai.assistant_message(content="", tool_calls=[
        @openai.tool_call(id="duplicate", name="read", arguments="{}"),
      ]),
      @openai.tool_message(
        tool_call_id="duplicate",
        content="second ".repeat(1000),
      ),
    ])
    assert_malformed_overflow_rejected(mock, "duplicate result", [
      @openai.system_message(content="system"),
      @openai.user_message(content="task"),
      @openai.assistant_message(content="", tool_calls=[
        @openai.tool_call(id="once", name="read", arguments="{}"),
      ]),
      @openai.tool_message(tool_call_id="once", content="first"),
      @openai.tool_message(
        tool_call_id="once",
        content="duplicate ".repeat(1000),
      ),
    ])
  })
}

///|
async test "compile_messages/ambiguous_user_only_and_late_system_fail_unchanged" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let user_only = [
      @openai.system_message(content="USER-ONLY-SYSTEM"),
      @openai.user_message(content="USER-ONLY-TASK"),
      @openai.user_message(content="ambiguous context ".repeat(2000)),
    ]
    let user_only_before = adversarial_transcript_json(user_only)
    let user_only_result = @context_pruner.Pruner::new(
      safe_zone_tokens=100,
      logger=mock.logger,
    ).compile_messages(user_only)
    assert_false(user_only_result.within_budget)
    assert_eq(
      adversarial_transcript_json(user_only_result.messages),
      user_only_before,
    )

    let late_system = [
      @openai.system_message(content="LEADING-SYSTEM"),
      @openai.user_message(content="LATE-SYSTEM-TASK"),
      @openai.assistant_message(content="old ".repeat(2000)),
      @openai.system_message(content="LATE-SYSTEM-MUST-STAY"),
      @openai.user_message(content="latest request"),
      @openai.assistant_message(content="latest answer"),
    ]
    let late_system_before = adversarial_transcript_json(late_system)
    let late_system_result = @context_pruner.Pruner::new(
      safe_zone_tokens=100,
      logger=mock.logger,
    ).compile_messages(late_system)
    assert_false(late_system_result.within_budget)
    assert_eq(
      adversarial_transcript_json(late_system_result.messages),
      late_system_before,
    )
  })
}

///|
async test "compile_messages/images_are_described_not_leaked_from_checkpoint" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let messages = [
      @openai.system_message(content="system"),
      @openai.user_message(content="IMAGE-TASK"),
      @openai.assistant_message(content=[
        @openai.image_url_content_part(
          "data:image/png;base64,SECRET_OLD_IMAGE_PAYLOAD",
        ),
        @openai.text_content_part(
          "old visual finding " + "detail ".repeat(1800),
        ),
      ]),
      @openai.user_message(content="old follow-up"),
      @openai.user_message(content=[
        @openai.text_content_part("LATEST-IMAGE-REQUEST"),
        @openai.image_url_content_part(
          "https://example.invalid/LATEST_IMAGE.png",
        ),
      ]),
      @openai.assistant_message(content="LATEST-IMAGE-ANSWER"),
    ]
    let result = @context_pruner.Pruner::new(
      safe_zone_tokens=450,
      logger=mock.logger,
    ).compile_messages(messages)
    let transcript = adversarial_transcript_json(result.messages)
    assert_true(result.within_budget)
    assert_true(result.compacted_messages > 0)
    assert_true(transcript.contains("[image evidence]"))
    assert_false(transcript.contains("SECRET_OLD_IMAGE_PAYLOAD"))
    assert_true(transcript.contains("LATEST_IMAGE.png"))
    assert_true(transcript.contains("LATEST-IMAGE-ANSWER"))
  })
}

///|
async test "compile_messages/already_cleared_outputs_are_idempotent" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let cleared = "[Cleared: tool output. If you want to see the output, you can use the tool again.]"
    let messages = [
      @openai.system_message(content="system"),
      @openai.user_message(content="IDEMPOTENT-TASK"),
      @openai.assistant_message(content="", tool_calls=[
        @openai.tool_call(id="cleared-call", name="read", arguments="{}"),
      ]),
      @openai.tool_message(tool_call_id="cleared-call", content=cleared),
      @openai.assistant_message(content="old context ".repeat(1800)),
      @openai.user_message(content="latest request"),
      @openai.assistant_message(content="", tool_calls=[
        @openai.tool_call(id="latest-call", name="read", arguments="{}"),
      ]),
      @openai.tool_message(tool_call_id="latest-call", content="latest result"),
    ]
    let input_before = adversarial_transcript_json(messages)
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=400,
      logger=mock.logger,
    )
    let first = pruner.compile_messages(messages)
    let second = pruner.compile_messages(first.messages)
    assert_true(first.within_budget)
    assert_eq(first.redacted_tool_results, 0)
    assert_eq(adversarial_transcript_json(messages), input_before)
    assert_eq(
      adversarial_transcript_json(first.messages),
      adversarial_transcript_json(second.messages),
    )
    assert_true(adversarial_tool_protocol_is_valid(first.messages))
  })
}

///|
fn generated_adversarial_history(
  case_index : Int,
) -> Array[@openai.ChatCompletionMessageParam] {
  let messages : Array[@openai.ChatCompletionMessageParam] = [
    @openai.system_message(content="GENERATED-SYSTEM-\{case_index}"),
    @openai.user_message(content="GENERATED-TASK-\{case_index}"),
  ]
  let turns = 4 + case_index % 5
  for turn in 0..<turns {
    if (case_index + turn) % 3 == 0 {
      let call_id = "generated-\{case_index}-\{turn}"
      messages.push(
        @openai.assistant_message(content="", tool_calls=[
          @openai.tool_call(
            id=call_id,
            name="read",
            arguments="{\"path\":\"case-\{case_index}-\{turn}.mbt\"}",
          ),
        ]),
      )
      messages.push(
        @openai.tool_message(
          tool_call_id=call_id,
          content="GENERATED-EVIDENCE-\{case_index}-\{turn} " +
            "evidence🙂 ".repeat(100 + (case_index + turn) % 40),
        ),
      )
    } else {
      messages.push(
        @openai.assistant_message(
          content="GENERATED-ANSWER-\{case_index}-\{turn} " +
            "analysis🌙 ".repeat(100 + (case_index * 7 + turn) % 40),
        ),
      )
    }
    if turn < turns - 1 {
      messages.push(
        @openai.user_message(
          content="GENERATED-FOLLOWUP-\{case_index}-\{turn} validate carefully",
        ),
      )
    }
  }
  messages.push(
    @openai.user_message(content="GENERATED-LATEST-REQUEST-\{case_index}"),
  )
  messages.push(
    @openai.assistant_message(content="GENERATED-LATEST-ANSWER-\{case_index}"),
  )
  messages
}

///|
async test "compile_messages/deterministic_generated_property_matrix" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let pruner = @context_pruner.Pruner::new(
      safe_zone_tokens=720,
      logger=mock.logger,
    )
    let counter = @token_counter.Counter::new(logger=mock.logger)
    let mut total_before = 0
    let mut total_after = 0
    let mut total_compacted = 0
    let mut total_redacted = 0
    for case_index in 0..<24 {
      let messages = generated_adversarial_history(case_index)
      let input_before = adversarial_transcript_json(messages)
      let first = pruner.compile_messages(messages)
      let second = pruner.compile_messages(messages)
      let transcript = adversarial_transcript_json(first.messages)
      guard first.within_budget else {
        fail("generated case exceeded budget: \{case_index}")
      }
      guard first.final_token_count <= 720 else {
        fail("generated case reported oversized result: \{case_index}")
      }
      guard first.final_token_count ==
        counter.count_param(messages=first.messages) else {
        fail("generated case count mismatch: \{case_index}")
      }
      guard adversarial_tool_protocol_is_valid(first.messages) else {
        fail("generated case broke tool protocol: \{case_index}")
      }
      guard transcript.contains("GENERATED-TASK-\{case_index}") else {
        fail("generated case lost task: \{case_index}")
      }
      guard transcript.contains("GENERATED-LATEST-REQUEST-\{case_index}") &&
        transcript.contains("GENERATED-LATEST-ANSWER-\{case_index}") else {
        fail("generated case lost latest exchange: \{case_index}")
      }
      guard transcript == adversarial_transcript_json(second.messages) else {
        fail("generated case was nondeterministic: \{case_index}")
      }
      guard adversarial_transcript_json(messages) == input_before else {
        fail("generated case mutated input: \{case_index}")
      }
      guard first.compacted_messages > 0 || first.redacted_tool_results > 0 else {
        fail("generated overflow case did no work: \{case_index}")
      }
      total_before += first.origin_token_count
      total_after += first.final_token_count
      total_compacted += first.compacted_messages
      total_redacted += first.redacted_tool_results
    }
    println(
      "CONTEXT_BENCH case=generated_24 before=\{total_before} after=\{total_after} redacted=\{total_redacted} compacted=\{total_compacted} within_budget=true",
    )
  })
}

///|
async test "compile_messages/five_thousand_message_scaling_case" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let messages : Array[@openai.ChatCompletionMessageParam] = [
      @openai.system_message(content="production contract"),
      @openai.user_message(content="FIVE-THOUSAND-TASK"),
    ]
    for index in 0..<2500 {
      messages.push(
        @openai.assistant_message(content="SCALE-ANSWER-\{index} stable"),
      )
      messages.push(
        @openai.user_message(content="SCALE-FOLLOWUP-\{index} continue"),
      )
    }
    messages.push(@openai.user_message(content="FIVE-THOUSAND-LATEST"))
    messages.push(@openai.assistant_message(content="FIVE-THOUSAND-DONE"))
    let result = @context_pruner.Pruner::new(
      safe_zone_tokens=900,
      logger=mock.logger,
    ).compile_messages(messages)
    let transcript = adversarial_transcript_json(result.messages)
    println(
      "CONTEXT_BENCH case=five_thousand_messages before=\{result.origin_token_count} after=\{result.final_token_count} redacted=\{result.redacted_tool_results} compacted=\{result.compacted_messages} within_budget=\{result.within_budget}",
    )
    assert_true(result.within_budget)
    assert_true(result.compacted_messages > 4800)
    assert_true(result.final_token_count <= 900)
    assert_true(transcript.contains("FIVE-THOUSAND-TASK"))
    assert_true(transcript.contains("FIVE-THOUSAND-LATEST"))
    assert_true(transcript.contains("FIVE-THOUSAND-DONE"))
  })
}
