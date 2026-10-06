///|
fn gating_stream_fixture() -> Array[ChatCompletionChunk] {
  [
    chunk(id="logging-fixture", created=123, model="synthetic", choices=[
      chunk_choice(
        index=0,
        delta=chunk_choice_delta(role=Assistant, content=""),
      ),
    ]),
    chunk(id="logging-fixture", created=123, model="synthetic", choices=[
      chunk_choice(
        index=0,
        delta=chunk_choice_delta(content="你🌙 \"quoted\""),
      ),
    ]),
    chunk(id="logging-fixture", created=123, model="synthetic", choices=[
      chunk_choice(
        index=0,
        delta=chunk_choice_delta(tool_calls=[
          chunk_choice_delta_tool_call(
            index=1,
            id="second",
            function=chunk_choice_delta_tool_call_function(
              name="tool_b",
              arguments="{",
            ),
          ),
          chunk_choice_delta_tool_call(
            index=0,
            id="first",
            function=chunk_choice_delta_tool_call_function(
              name="tool_a",
              arguments="{\"x\":",
            ),
          ),
        ]),
      ),
    ]),
    chunk(id="logging-fixture", created=123, model="synthetic", choices=[
      chunk_choice(
        index=0,
        delta=chunk_choice_delta(tool_calls=[
          chunk_choice_delta_tool_call(
            index=0,
            function=chunk_choice_delta_tool_call_function(arguments="1}"),
          ),
          chunk_choice_delta_tool_call(
            index=1,
            function=chunk_choice_delta_tool_call_function(arguments="\"y\":2}"),
          ),
        ]),
      ),
    ]),
    chunk(
      id="logging-fixture",
      created=123,
      model="synthetic",
      choices=[
        chunk_choice(
          index=0,
          delta=chunk_choice_delta(),
          finish_reason=ToolCalls,
        ),
      ],
      usage=CompletionUsage::new(
        prompt_tokens=7,
        completion_tokens=9,
        total_tokens=16,
      ),
    ),
  ]
}

///|
fn gating_stable_log(log : Json) -> Json {
  guard log is Object(fields) else { return log }
  let copy = fields.copy()
  copy.remove("time")
  Json::object(copy)
}

///|
async test "gated stream preserves exact output logs callbacks and tool ordering at all thresholds" {
  for threshold in [@pino.Trace, Debug, Info, Warn, Error, Fatal] {
    let old_logs : Array[String] = []
    let new_logs : Array[String] = []
    let old_order : Array[String] = []
    let new_order : Array[String] = []
    let before = @pino.logger(
      "stream",
      level=threshold,
      @pino.Transport::callback(log => {
        old_logs.push(gating_stable_log(log).stringify())
        old_order.push("log")
      }),
    )
    let after = @pino.logger(
      "stream",
      level=threshold,
      @pino.Transport::callback(log => {
        new_logs.push(gating_stable_log(log).stringify())
        new_order.push("log")
      }),
    )
    let old_builder = ChatCompletionBuilder::new()
    let new_builder = ChatCompletionBuilder::new()
    for chunk in gating_stream_fixture() {
      before.debug("ChunkReceived", data={ "chunk": chunk })
      emit_text_deltas_from_chunk(chunk, delta => {
        old_order.push("delta:" + delta)
      })
      old_builder.add_chunk(chunk)
      receive_chat_stream_chunk(
        chunk,
        after,
        delta => new_order.push("delta:" + delta),
        new_builder,
      )
      assert_eq(
        ToJson::to_json(old_builder.to_chat_completion()).stringify(),
        ToJson::to_json(new_builder.to_chat_completion()).stringify(),
      )
    }
    assert_eq(old_logs, new_logs)
    assert_eq(old_order, new_order)
    assert_eq(new_logs.length(), if threshold <= Debug { 5 } else { 0 })
    let output = new_builder.to_chat_completion()
    assert_eq(output.choices[0].message.tool_calls[0].id, "first")
    assert_eq(output.choices[0].message.tool_calls[1].id, "second")
  }
}

///|
async test "enabled diagnostic errors still precede stream callbacks and accumulation" {
  for threshold in [@pino.Trace, Debug, Info] {
    let queue : @aqueue.Queue[Json] = @aqueue.Queue(kind=Unbounded)
    queue.close()
    let logger = @pino.logger(
      "closed",
      level=threshold,
      @pino.Transport::channel(queue),
    )
    let builder = ChatCompletionBuilder::new()
    let deltas : Array[String] = []
    let mut failed = false
    receive_chat_stream_chunk(
      gating_stream_fixture()[1],
      logger,
      delta => deltas.push(delta),
      builder,
    ) catch {
      @aqueue.QueueAlreadyClosed => failed = true
      error => raise error
    }
    assert_eq(failed, threshold <= Debug)
    assert_eq(deltas.length(), if failed { 0 } else { 1 })
  }
}

///|
async test "blocked enabled diagnostics remain cancellable without emitting a delta" {
  let queue : @aqueue.Queue[Json] = @aqueue.Queue(kind=Blocking(0))
  let logger = @pino.logger(
    "blocked",
    level=Debug,
    @pino.Transport::channel(queue),
  )
  let builder = ChatCompletionBuilder::new()
  let deltas : Array[String] = []
  let result = @async.with_timeout_opt(1, () => {
    receive_chat_stream_chunk(
      gating_stream_fixture()[1],
      logger,
      delta => deltas.push(delta),
      builder,
    )
  })
  assert_true(result is None)
  assert_eq(deltas.length(), 0)
  assert_true(queue.try_get() is None)
}

///|
async test "request gating preserves serialized MoonGate body and enabled diagnostics" {
  let model = @model.new(
    api_key="",
    base_url="https://fixture.invalid/openclaw/v1",
    name="synthetic",
    safe_zone_tokens=16000,
  )
  let request = chat_completion(
    model="synthetic",
    messages=[user_message(content="Continuation 你🌙")],
    stream=false,
  )
  let mut expected_body : String? = None
  for threshold in [@pino.Trace, Debug, Info, Warn, Error, Fatal] {
    let logs : Array[Json] = []
    let logger = @pino.logger(
      "request",
      level=threshold,
      @pino.Transport::callback(log => logs.push(log)),
    )
    let _ = chat(model~, request, logger~, transport=(serialized, _) => {
      match expected_body {
        Some(body) => assert_eq(serialized.body, body)
        None => expected_body = Some(serialized.body)
      }
      assert_true(serialized.stream)
      assert_eq(
        serialized.url,
        "https://fixture.invalid/openclaw/v1/chat/completions",
      )
      assert_eq(logs.length(), if threshold <= Debug { 1 } else { 0 })
      if threshold <= Debug {
        guard logs[0] is { "msg": String("RequestSent"), "request": data, .. } else {
          fail("Missing request log")
        }
        assert_eq(data.stringify(), ToJson::to_json(request).stringify())
      }
      @json.from_json({
        "id": "reply",
        "model": "synthetic",
        "choices": [
          {
            "index": 0,
            "message": { "role": "assistant", "content": "ok" },
            "finish_reason": "stop",
          },
        ],
      })
    })
  }
}
