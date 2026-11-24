///|
// A deliberately smaller request contract, selected by explicit catalog
// metadata. Do not strip fields from tool-capable API requests on failure.
fn mooncode_runtime_text_chat_request(
  model : String,
  source : Array[Json],
) -> @openai.Request raise {
  let messages : Array[Json] = [
    {
      "role": "system",
      "content": "You are MoonDesk's text-only chat assistant. Answer the user's message directly. This connection cannot call tools, read or modify files, browse, or run commands. Do not claim to have performed those actions. If the task requires them, explain that a tool-capable connection is needed.",
    },
  ]
  for message in source {
    match message {
      { "role": "system" | "developer", .. } => ()
      { "role": String(role), "content": content, .. } if role == "user" ||
        role == "assistant" => {
        if message is { "tool_calls"? : Some(_), .. } {
          fail("A text-only connection cannot resume a tool conversation")
        }
        messages.push({ "role": role, "content": content })
      }
      _ => fail("A text-only connection cannot accept tool results")
    }
  }
  @openai.chat_completion(
    model~,
    messages=@json.from_json(Json::array(messages)),
    stream=true,
  )
}
