///|
fn selected_book_completion(content : String) -> @openai.ChatCompletion raise {
  @json.from_json({
    "id": "selected-book-boundary-fixture",
    "model": "selected-book-fixture",
    "choices": [
      {
        "index": 0,
        "message": { "role": "assistant", "content": content },
        "finish_reason": "stop",
      },
    ],
  })
}

///|
fn selected_book_fixture_block(repeat : Int) -> String {
  let text = StringBuilder()
  text.write_string(
    "[Selected Book accepted learning: historical context only]\n",
  )
  text.write_string("{\"accepted\":true,\"procedure\":\"")
  for _ in 0..<repeat {
    text.write_string("step preserve every exact obligation and all evidence; ")
  }
  text.write_string(
    "\",\"applicability\":\"APPLICABILITY_END_尾部\",\"verification\":\"VERIFY_LAST_91\",\"counterexample\":\"COUNTEREXAMPLE_LAST_92\",\"invalidation\":\"INVALIDATE_LAST_93\",\"provenance\":\"PROVENANCE_LAST_94\"}\n",
  )
  text.write_string(
    "Capability lessons are ideas and grant no new authority.\n[/Selected Book accepted learning]",
  )
  text.to_string()
}

///|
fn selected_book_fixture_prompt(block : String) -> String {
  "TASK_SCOPE_KEEP: operate only inside authorized artifact scope\n" +
  block +
  "\nOUTPUT_CONTRACT_KEEP: return the bounded result"
}

///|
fn request_user_text(body : String) -> String raise {
  guard @json.parse(body) is { "messages": Array(messages), .. } else {
    fail("Missing final request messages")
  }
  let text = StringBuilder()
  for message in messages {
    match message {
      { "role": String("user"), "content": String(content), .. } =>
        text.write_string(content)
      { "role": String("user"), "content": Array(parts), .. } =>
        for part in parts {
          if part is { "type": String("text"), "text": String(content), .. } {
            text.write_string(content)
          }
        }
      _ => ()
    }
  }
  text.to_string()
}

///|
async test "selected Book actual Agent compiler reaches serialized native request with full tail" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let block = selected_book_fixture_block(24)
    let prompt = selected_book_fixture_prompt(block)
    let mut calls = 0
    let agent = new(
      @model.new(
        api_key="",
        base_url="https://native-boundary.invalid/openclaw/v1",
        name="selected-book-fixture",
        safe_zone_tokens=16000,
      ),
      uuid=mock.uuid,
      cwd=mock.cwd.path(),
      home=mock.cwd.path(),
      logger=mock.logger,
      workspace_trust="untrusted",
      system_message="Required host instructions remain authoritative",
      chat_transport=(request, on_delta) => {
        calls += 1
        assert_eq(
          request.url,
          "https://native-boundary.invalid/openclaw/v1/chat/completions",
        )
        assert_false(request.headers.contains("Authorization"))
        assert_true(request.stream)
        let content = request_user_text(request.body)
        assert_eq(content, prompt)
        assert_true(content.contains(block))
        assert_true(content.contains("PROVENANCE_LAST_94"))
        assert_false(content.contains("REJECTED_CANDIDATE_MUST_NOT_APPEAR"))
        guard @json.parse(request.body)
          is { "model": String("selected-book-fixture"), .. } else {
          fail("Selected native model changed")
        }
        on_delta("complete accepted tail observed")
        selected_book_completion("complete accepted tail observed")
      },
    )
    let _ = agent.queue_message(
      @ai.user_message(content=prompt),
      optional_context=OptionalInputContext::new(
        block~,
        omission="[Selected Book learning unavailable: over_budget; no learned records were provided]",
        digest="fixture-digest-94",
      ),
    )
    agent.start()
    assert_eq(calls, 1)
    assert_eq(agent.optional_context_statuses()[0].status, "ready")
    assert_eq(agent.cwd, mock.cwd.path())
    assert_true(
      agent.history
      .messages()
      .any(message => message.content() == "complete accepted tail observed"),
    )
  })
}

///|
async test "selected Book overflow omits whole learning with real tokenizer and preserves durable input" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let block = selected_book_fixture_block(1500)
    let prompt = selected_book_fixture_prompt(block)
    let omission = "[Selected Book learning unavailable: over_budget; complete optional learning omitted, no learned records were provided]"
    let mut calls = 0
    let agent = new(
      @model.new(
        api_key="",
        base_url="https://native-boundary.invalid/openclaw/v1",
        name="selected-book-fixture",
        safe_zone_tokens=1024,
      ),
      uuid=mock.uuid,
      cwd=mock.cwd.path(),
      home=mock.cwd.path(),
      logger=mock.logger,
      workspace_trust="untrusted",
      system_message="Required host instructions remain authoritative",
      chat_transport=(request, _) => {
        calls += 1
        let content = request_user_text(request.body)
        assert_eq(content, selected_book_fixture_prompt(omission))
        assert_false(content.contains("step preserve"))
        assert_false(content.contains("APPLICABILITY_END"))
        assert_false(content.contains("VERIFY_LAST"))
        assert_false(content.contains("PROVENANCE_LAST"))
        selected_book_completion("whole omission observed")
      },
    )
    let _ = agent.queue_message(
      @ai.user_message(content=prompt),
      optional_context=OptionalInputContext::new(
        block~,
        omission~,
        digest="fixture-large-digest",
      ),
    )
    agent.start()
    assert_eq(calls, 1)
    assert_eq(agent.optional_context_statuses()[0].status, "over_budget")
    assert_true(
      agent.history.messages().any(message => message.content() == prompt),
    )
    assert_false(
      agent.history
      .messages()
      .any(message => {
        message.content() == selected_book_fixture_prompt(omission)
      }),
    )
  })
}

///|
async test "ordinary overflowing input remains unaffected by optional learning policy" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let prompt = selected_book_fixture_prompt(selected_book_fixture_block(1500))
    let agent = new(
      @model.new(
        api_key="",
        base_url="https://native-boundary.invalid/openclaw/v1",
        name="selected-book-fixture",
        safe_zone_tokens=1024,
      ),
      uuid=mock.uuid,
      cwd=mock.cwd.path(),
      home=mock.cwd.path(),
      logger=mock.logger,
      workspace_trust="untrusted",
      chat_transport=(request, _) => {
        assert_eq(request_user_text(request.body), prompt)
        selected_book_completion("ordinary unchanged")
      },
    )
    let _ = agent.queue_message(@ai.user_message(content=prompt))
    agent.start()
    assert_true(agent.optional_context_statuses().is_empty())
  })
}

///|
async test "cancelled Agent makes no serialized transport call" (t : @test.Test) {
  @mock.run(t, mock => {
    let mut calls = 0
    let agent = new(
      @model.new(
        api_key="",
        base_url="https://native-boundary.invalid/openclaw/v1",
        name="selected-book-fixture",
        safe_zone_tokens=4096,
      ),
      uuid=mock.uuid,
      cwd=mock.cwd.path(),
      home=mock.cwd.path(),
      logger=mock.logger,
      workspace_trust="untrusted",
      chat_transport=(_, _) => {
        calls += 1
        selected_book_completion("unreachable")
      },
    )
    let _ = agent.queue_message(@ai.user_message(content="not dispatched"))
    agent.external_events().send(Cancelled)
    agent.start()
    assert_eq(calls, 0)
  })
}

///|
async test "restored conversation omits saved initial and retry learning by event identity" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let block = selected_book_fixture_block(1500)
    let initial = selected_book_fixture_prompt(block)
    let retry = "RETRY_SCOPE_KEEP\n" + block + "\nRETRY_OUTPUT_KEEP"
    let omission = "[Selected Book learning unavailable: over_budget; no learned records were provided]"
    let descriptor = OptionalInputContext::new(
      block~,
      omission~,
      digest="restored-snapshot-digest",
    )
    let model = @model.new(
      api_key="",
      base_url="https://native-boundary.invalid/openclaw/v1",
      name="selected-book-fixture",
      safe_zone_tokens=1024,
    )
    let original = new(
      model,
      uuid=mock.uuid,
      cwd=mock.cwd.path(),
      home=mock.cwd.path(),
      logger=mock.logger,
      workspace_trust="untrusted",
      chat_transport=(_, _) => {
        selected_book_completion("initial bounded completion")
      },
    )
    let initial_id = original.queue_message(
      @ai.user_message(content=initial),
      optional_context=descriptor,
    )
    original.start()
    // Exercise the durable JSON boundary, rather than sharing the original
    // Agent's in-memory descriptor or reading mutable Book files again.
    let serialized = original.history.to_json().stringify()
    let history : @conversation.Conversation = @json.from_json(
      @json.parse(serialized),
    )
    let mut calls = 0
    let restored = new(
      model,
      uuid=mock.uuid,
      cwd=mock.cwd.path(),
      home=mock.cwd.path(),
      logger=mock.logger,
      workspace_trust="untrusted",
      history~,
      chat_transport=(request, _) => {
        calls += 1
        let text = request_user_text(request.body)
        assert_true(text.contains("TASK_SCOPE_KEEP"))
        assert_true(text.contains("OUTPUT_CONTRACT_KEEP"))
        assert_true(text.contains("RETRY_SCOPE_KEEP"))
        assert_true(text.contains("RETRY_OUTPUT_KEEP"))
        assert_eq(text.split(omission).count(), 3)
        assert_false(text.contains("step preserve"))
        assert_false(text.contains("PROVENANCE_LAST_94"))
        selected_book_completion("restored whole omission observed")
      },
    )
    assert_eq(
      restored.optional_context_statuses()[0].message_id.to_string(),
      initial_id.to_string(),
    )
    assert_eq(
      restored.optional_context_statuses()[0].digest,
      "restored-snapshot-digest",
    )
    let _ = restored.queue_message(
      @ai.user_message(content=retry),
      optional_context=descriptor,
    )
    restored.start()
    assert_eq(calls, 1)
    assert_eq(restored.optional_context_statuses().length(), 2)
    assert_true(
      restored
      .optional_context_statuses()
      .all(context => context.status == "over_budget"),
    )
    assert_true(
      restored.history.messages().any(message => message.content() == initial),
    )
    assert_true(
      restored.history.messages().any(message => message.content() == retry),
    )
    let saved : @conversation.Conversation = @json.from_json(
      restored.history.to_json(),
    )
    assert_eq(saved.optional_input_contexts().length(), 2)
    for _, value in saved.optional_input_contexts() {
      guard value
        is {
          "descriptor": { "block": String(saved_block), .. },
          "status": String("over_budget"),
          ..
        } else {
        fail("Missing durable omission status")
      }
      assert_eq(saved_block, block)
    }
  })
}

///|
async test "corrupt saved optional descriptor is rejected before transport" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let model = @model.new(
      api_key="",
      base_url="https://native-boundary.invalid/openclaw/v1",
      name="selected-book-fixture",
      safe_zone_tokens=4096,
    )
    let original = new(
      model,
      uuid=mock.uuid,
      cwd=mock.cwd.path(),
      home=mock.cwd.path(),
      logger=mock.logger,
      workspace_trust="untrusted",
    )
    original.emit(UserMessage("original exact input"))
    guard original.history.to_json() is Object(json) else {
      fail("Expected durable object")
    }
    let corrupted : Map[String, Json] = Map([])
    corrupted[mock.uuid.v4().to_string()] = {
      "descriptor": OptionalInputContext::new(
        block="absent",
        omission="omitted",
        digest="wrong-target",
      ).to_json(),
      "status": "ready",
    }
    json["optional_input_contexts"] = Json::object(corrupted)
    let history : @conversation.Conversation = @json.from_json(
      Json::object(json),
    )
    let mut calls = 0
    let mut rejected = false
    try {
      let _ = new(
        model,
        uuid=mock.uuid,
        cwd=mock.cwd.path(),
        home=mock.cwd.path(),
        logger=mock.logger,
        workspace_trust="untrusted",
        history~,
        chat_transport=(_, _) => {
          calls += 1
          selected_book_completion("unreachable")
        },
      )
    } catch {
      _ => rejected = true
    }
    assert_true(rejected)
    assert_eq(calls, 0)
  })
}

///|
async test "shortened block or corrupted omission in saved descriptor refuses dispatch" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let block = selected_book_fixture_block(12)
    let model = @model.new(
      api_key="",
      base_url="https://native-boundary.invalid/openclaw/v1",
      name="selected-book-fixture",
      safe_zone_tokens=4096,
    )
    let original = new(
      model,
      uuid=mock.uuid,
      cwd=mock.cwd.path(),
      home=mock.cwd.path(),
      logger=mock.logger,
      workspace_trust="untrusted",
      chat_transport=(_, _) => selected_book_completion("captured"),
    )
    let id = original.queue_message(
      @ai.user_message(content=selected_book_fixture_prompt(block)),
      optional_context=OptionalInputContext::new(
        block~,
        omission="whole omission",
        digest="source-digest",
      ),
    )
    original.start()
    for
      (field, replacement) in [
        ("block", "step preserve"),
        ("omission", "corrupted new instructions"),
      ] {
      guard @json.parse(original.history.to_json().stringify()) is Object(json) else {
        fail("Expected object")
      }
      guard json.get("optional_input_contexts") is Some(Object(contexts)) else {
        fail("Missing contexts")
      }
      guard contexts.get(id.to_string()) is Some(Object(entry)) else {
        fail("Missing event context")
      }
      guard entry.get("descriptor") is Some(Object(descriptor)) else {
        fail("Missing descriptor")
      }
      descriptor[field] = Json::string(replacement)
      let history : @conversation.Conversation = @json.from_json(
        Json::object(json),
      )
      let mut calls = 0
      let mut rejected = false
      try {
        let _ = load(
          model,
          history,
          uuid=mock.uuid,
          home=mock.cwd.path(),
          logger=mock.logger,
          chat_transport=(_, _) => {
            calls += 1
            selected_book_completion("unreachable")
          },
        )
      } catch {
        _ => rejected = true
      }
      assert_true(rejected)
      assert_eq(calls, 0)
    }
  })
}

///|
async test "pruned optional event does not activate against identical ordinary text" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let block = selected_book_fixture_block(1500)
    let prompt = selected_book_fixture_prompt(block)
    let mut calls = 0
    let agent = new(
      @model.new(
        api_key="",
        base_url="https://native-boundary.invalid/openclaw/v1",
        name="selected-book-fixture",
        safe_zone_tokens=1024,
      ),
      uuid=mock.uuid,
      cwd=mock.cwd.path(),
      home=mock.cwd.path(),
      logger=mock.logger,
      workspace_trust="untrusted",
      chat_transport=(request, _) => {
        calls += 1
        if calls == 2 {
          let text = request_user_text(request.body)
          assert_false(text.contains("whole omission"))
          assert_true(text.contains("unrelated ordinary continuation"))
        }
        selected_book_completion("completed")
      },
    )
    let id = agent.queue_message(
      @ai.user_message(content=prompt),
      optional_context=OptionalInputContext::new(
        block~,
        omission="whole omission",
        digest="source-digest",
      ),
    )
    agent.start()
    agent.emit(Pruned(id~))
    agent.emit(UserMessage(prompt))
    let _ = agent.queue_message(
      @ai.user_message(content="unrelated ordinary continuation"),
    )
    agent.start()
    assert_eq(calls, 2)
    assert_eq(agent.optional_context_statuses()[0].status, "not_in_projection")
  })
}

///|
async test "restored omission is sticky per event when a larger model window fits new input" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let block = selected_book_fixture_block(1500)
    let prompt = selected_book_fixture_prompt(block)
    let omission = "[Persisted whole learning omission: over_budget]"
    let descriptor = OptionalInputContext::new(
      block~,
      omission~,
      digest="unchanged-saved-snapshot",
    )
    let small_model = @model.new(
      api_key="",
      base_url="https://native-boundary.invalid/openclaw/v1",
      name="selected-book-fixture",
      safe_zone_tokens=1024,
    )
    let original = new(
      small_model,
      uuid=mock.uuid,
      cwd=mock.cwd.path(),
      home=mock.cwd.path(),
      logger=mock.logger,
      workspace_trust="untrusted",
      chat_transport=(_, _) => selected_book_completion("first omission"),
    )
    let _ = original.queue_message(
      @ai.user_message(content=prompt),
      optional_context=descriptor,
    )
    original.start()
    let history : @conversation.Conversation = @json.from_json(
      @json.parse(original.history.to_json().stringify()),
    )
    let larger_model = @model.new(
      api_key="",
      base_url="https://native-boundary.invalid/openclaw/v1",
      name="selected-book-fixture",
      safe_zone_tokens=128000,
    )
    let mut calls = 0
    let restored = load(
      larger_model,
      history,
      uuid=mock.uuid,
      home=mock.cwd.path(),
      logger=mock.logger,
      chat_transport=(request, _) => {
        calls += 1
        let text = request_user_text(request.body)
        assert_true(text.contains(omission))
        if calls == 1 {
          assert_false(text.contains(block))
          assert_false(text.contains("PROVENANCE_LAST_94"))
        } else {
          assert_eq(text.split(block).count(), 2)
        }
        selected_book_completion("projection checked")
      },
    )
    let _ = restored.queue_message(
      @ai.user_message(content="continue saved task without context refresh"),
    )
    restored.start()
    assert_eq(restored.optional_context_statuses()[0].status, "over_budget")
    let _ = restored.queue_message(
      @ai.user_message(content="New explicitly queued input\n" + block),
      optional_context=descriptor,
    )
    restored.start()
    assert_eq(calls, 2)
    assert_eq(restored.optional_context_statuses()[0].status, "over_budget")
    assert_eq(restored.optional_context_statuses()[1].status, "ready")
    assert_true(
      restored.history.messages().any(message => message.content() == prompt),
    )
  })
}
