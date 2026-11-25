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
