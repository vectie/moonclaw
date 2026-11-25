///|
test "ChatCompletionChunk decodes in-band SSE error frames without id" {
  let raw : Json = {
    "error": {
      "code": "RuntimeUnavailable",
      "message": "the selected runtime could not complete the stream",
      "retryable": false,
    },
  }
  let chunk : ChatCompletionChunk = @json.from_json(raw)
  assert_eq(chunk.id, "")
  assert_eq(chunk.choices.length(), 0)
  match chunk.error {
    Some(err) => {
      assert_eq(err.code, 502)
      assert_eq(
        err.message,
        "RuntimeUnavailable: the selected runtime could not complete the stream",
      )
    }
    None => fail("expected decoded error")
  }
}

///|
test "ChatCompletionChunk decodes reasoning_content and reasoning deltas" {
  let raw1 : Json = {
    "id": "chatcmpl-r1",
    "created": 1700000000,
    "model": "glm-5.3.flash",
    "choices": [
      {
        "index": 0,
        "delta": {
          "role": "assistant",
          "reasoning_content": "Step 1: inspect.",
        },
      },
    ],
  }
  let raw2 : Json = {
    "id": "chatcmpl-r2",
    "created": 1700000000,
    "model": "glm-5.3.flash",
    "choices": [{ "index": 0, "delta": { "reasoning": " Step 2: answer." } }],
  }
  let chunk1 : ChatCompletionChunk = @json.from_json(raw1)
  let chunk2 : ChatCompletionChunk = @json.from_json(raw2)
  let collected : Array[String] = []
  emit_reasoning_deltas_from_chunk(chunk1, delta => collected.push(delta))
  emit_reasoning_deltas_from_chunk(chunk2, delta => collected.push(delta))
  assert_eq(collected, ["Step 1: inspect.", " Step 2: answer."])
}
