///|
// ACP calls declared MCP tools; MoonClaw retains execution, Book scope,
// argument validation and approvals. This is not a raw-model sampler API.
fn mooncode_runtime_acp_tool_request(
  model : String,
  messages : Array[Json],
  tools : Array[@openai.ChatCompletionToolParam],
) -> @openai.Request raise {
  @openai.chat_completion(
    model~,
    messages=@json.from_json(Json::array(messages)),
    tools~,
    stream=true,
  )
}
