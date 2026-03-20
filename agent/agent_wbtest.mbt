///|
#skip
async test "queue_message" (t : @test.Test) {
  @mock.run(t, mock => {
    let model = mock.model(name=ClaudeHaiku4_5)
    let agent = new(
      model,
      uuid=mock.uuid,
      cwd=mock.cwd.path(),
      logger=mock.logger,
      user_message="Hello.",
    )
    let _ = agent.queue_message(
      @ai.user_message(content="First queued message."),
    )
    json_inspect(
      json_inspect(agent.queued_messages(), content=[
        {
          "id": "42858c8d-3684-43ab-837d-ef6894a9b8dc",
          "message": { "role": "user", "content": "First queued message." },
          "web_search": false,
        },
      ]),
      content=null,
    )
    agent.start()
    json_inspect(agent.pending_queue.length(), content=0)
    json_inspect(agent.input_queue.length(), content=0)
  })
}

///|
async test "execute_tool preserves unknown tool response in history" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let agent = new(
      @model.Model::new(
        api_key="",
        base_url="https://example.invalid/v1",
        name="test-model",
        safe_zone_tokens=4096,
      ),
      uuid=mock.uuid,
      cwd=mock.cwd.path(),
      logger=mock.logger,
    )
    let tool_call = @ai.tool_call(
      id="tc-unknown",
      name="execute_command",
      arguments="{}",
    )
    agent.emit(AssistantMessage(usage=None, tool_calls=[tool_call], ""))
    let _ = agent.execute_tool(tool_call)
    json_inspect(
      agent.history
      .messages(include_system=false)
      .map(fn(message) { message.to_openai() }),
      content=[
        {
          "role": "assistant",
          "content": "",
          "tool_calls": [
            {
              "id": "tc-unknown",
              "function": { "name": "execute_command", "arguments": "{}" },
              "type": "function",
            },
          ],
        },
        {
          "role": "tool",
          "content": [
            { "type": "text", "text": "Unknown tool: execute_command" },
          ],
          "tool_call_id": "tc-unknown",
        },
      ],
    )
  })
}
