///|
test "Responses SSE parser rejects malformed payloads without inventing events" {
  let malformed = [
    "", " ", "{", "[]", "null", "true", "42", "{}", "{\"type\":null}", "{\"type\":42}",
    "{\"type\":\"response.output_text.delta\"}", "{\"type\":\"response.output_text.delta\",\"delta\":null}",
    "{\"type\":\"response.output_text.delta\",\"delta\":{}}", "{\"type\":\"response.content_part.delta\",\"delta\":null}",
    "{\"type\":\"response.content_part.delta\",\"delta\":{\"text\":7}}", "{\"type\":\"response.output_item.done\",\"item\":null}",
    "{\"type\":\"response.output_item.done\",\"item\":{}}", "{\"type\":\"response.unknown\",\"delta\":\"must-not-leak\"}",
  ]
  for payload in malformed {
    assert_true(response_stream_event_from_data(payload) is None)
  }
}

///|
test "Responses SSE parser accepts only typed text deltas" {
  let text = response_stream_event_from_data(
    "{\"type\":\"response.output_text.delta\",\"delta\":\"alpha\\n\\u4e2d\\ud83d\\ude80\"}",
  )
  assert_true(text is Some(TextDelta("alpha\n中🚀")))
  let content = response_stream_event_from_data(
    "{\"type\":\"response.content_part.delta\",\"delta\":{\"text\":\"beta\"}}",
  )
  assert_true(content is Some(TextDelta("beta")))
  assert_true(
    response_stream_event_from_data(
      "{\"type\":\"response.output_text.delta\",\"delta\":false}",
    )
    is None,
  )
}

///|
test "Responses SSE terminal mutations always fail closed" {
  let terminal_types = ["response.failed", "response.incomplete", "error"]
  let nested_errors = [
    "", ",\"error\":null", ",\"error\":{}", ",\"error\":{\"message\":7}", ",\"response\":{\"error\":{\"message\":\"bounded failure\"}}",
  ]
  for terminal in terminal_types {
    for suffix in nested_errors {
      let data = "{\"type\":\"\{terminal}\"\{suffix}}"
      assert_true(response_stream_event_from_data(data) is Some(Failed(_)))
    }
  }
  assert_true(response_stream_event_from_data("[DONE]") is Some(Failed(_)))
}

///|
fn response_qualification_event_key(event : ResponseStreamEvent?) -> String {
  match event {
    None => "none"
    Some(TextDelta(text)) => "text:" + text
    Some(OutputItemDone(_)) => "item"
    Some(Completed(response)) => "completed:" + response.stringify()
    Some(Failed(message)) => "failed:" + message
  }
}

///|
test "Responses SSE parser is deterministic over a mutation corpus" {
  let types = [
    "response.output_text.delta", "response.content_part.delta", "response.output_item.done",
    "response.completed", "response.failed", "response.incomplete", "error", "future.event",
  ]
  let values = ["null", "false", "0", "\"text\"", "{}", "[]"]
  for type_ in types {
    for value in values {
      let data = "{\"type\":\"\{type_}\",\"delta\":\{value},\"item\":\{value},\"response\":\{value}}"
      let first = response_stream_event_from_data(data)
      let second = response_stream_event_from_data(data)
      assert_eq(
        response_qualification_event_key(first),
        response_qualification_event_key(second),
      )
    }
  }
}
