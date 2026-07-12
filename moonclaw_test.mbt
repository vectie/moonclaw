///|
async test "moonclaw registers unlimited_ocr as default MoonTool" (
  t : @test.Test,
) {
  let _ = t
  let moonclaw = @moonclaw.Moonclaw::new(
    model=@model.Model::new(
      api_key="",
      base_url="https://example.invalid/v1",
      name="test-model",
      safe_zone_tokens=4096,
    ),
    home="/tmp",
    cwd="/tmp",
  )
  defer moonclaw.close()
  assert_true(moonclaw.agent.tools().contains("unlimited_ocr"))
}

///|
async test "restricted Flow capsule exposes only scoped files and optional public web" (
  t : @test.Test,
) {
  let _ = t
  let moonclaw = @moonclaw.Moonclaw::new(
    model=@model.Model::new(
      api_key="",
      base_url="https://example.invalid/v1",
      name="test-model",
      safe_zone_tokens=4096,
    ),
    home="/tmp",
    cwd="/tmp",
    restricted_workspace=true,
    web_search=true,
  )
  defer moonclaw.close()
  let tools = moonclaw.agent.tools()
  assert_true(tools.contains("read_file"))
  assert_true(tools.contains("write_to_file"))
  assert_true(tools.contains("web_search"))
  assert_true(tools.contains("web_fetch"))
  assert_false(tools.contains("execute_command"))
  assert_false(tools.contains("apply_patch"))
  assert_false(tools.contains("search_files"))
}

///|
#skip
async test "moonclaw/resume" (t : @test.Test) {
  @mock.run(t, mock => {
    let cwd = mock.cwd
    let model = mock.model(name=ClaudeHaiku4_5)
    let id = {
      let moonclaw = @moonclaw.Moonclaw::new(
        model~,
        home=cwd.path(),
        cwd=cwd.path(),
        user_message="Hello, please call me Mr. Rabbit.",
      )
      defer moonclaw.close()
      let id = moonclaw.agent.id()
      moonclaw.start()
      id
    }
    let mut result = None
    let moonclaw = @moonclaw.resume_(
      model~,
      home=cwd.path(),
      id,
      user_message="What is my name? Please use the <submit_user_name/> tool to submit my name.",
    )
    moonclaw.agent.add_tool(
      @tool.new(
        name="submit_user_name",
        description="Submit the user's name.",
        schema=@tool.JsonSchema::from_json({
          "type": "object",
          "properties": { "name": { "type": "string" } },
          "required": ["name"],
        }),
        ToolFn(args => {
          guard args is { "name": String(name), .. } else {
            return @tool.error("Invalid arguments")
          }
          result = Some(name)
          @tool.ok("Name submitted successfully")
        }),
      ),
    )
    moonclaw.start()
    json_inspect(
      result is Some(content) && content.contains("Rabbit"),
      content=true,
    )
  })
}
