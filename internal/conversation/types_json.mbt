///|
test "Message to_json" {
  let messages : Array[Message] = [
    {
      timestamp: @clock.Timestamp::from_ms(1625079600),
      usage: None,
      message: @ai.user_message(content="Hello, world!"),
    },
    {
      timestamp: @clock.Timestamp::from_ms(1625079600),
      usage: Some(@ai.usage(input_tokens=10, total_tokens=20, output_tokens=10)),
      message: @ai.user_message(content="Hello, world!"),
    },
  ]
  json_inspect(messages, content=[
    {
      "timestamp": 1625079600,
      "message": { "role": "user", "content": "Hello, world!" },
    },
    {
      "timestamp": 1625079600,
      "usage": {
        "completion_tokens": 10,
        "prompt_tokens": 10,
        "total_tokens": 20,
      },
      "message": { "role": "user", "content": "Hello, world!" },
    },
  ])
}

///|
impl ToJson for Message with fn to_json(self : Message) -> Json {
  let object : Map[String, Json] = Map([])
  object["timestamp"] = self.timestamp.to_json()
  if self.usage is Some(usage) {
    object["usage"] = usage.to_openai().to_json()
  }
  object["message"] = self.message.to_openai().to_json()
  Json::object(object)
}
