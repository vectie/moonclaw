///|
test "chat completion serializes required tool choice" {
  let request = chat_completion(
    model="fixture",
    messages=[],
    tool_choice=Required,
  )
  assert_eq(
    ToJson::to_json(request)
    .stringify()
    .contains("\"tool_choice\":\"required\""),
    true,
  )
}

///|
test "chat completion serializes a named function tool choice" {
  let request = chat_completion(
    model="fixture",
    messages=[],
    tool_choice=Function({ name: "finish", }),
  )
  let json = ToJson::to_json(request)
  guard json
    is {
      "tool_choice": {
        "type": "function",
        "function": { "name": "finish", .. },
        ..
      },
      ..
    } else {
    fail("named function choice was not serialized")
  }
}
