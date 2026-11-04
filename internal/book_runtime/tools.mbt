///|
pub fn tools(book_root : String) -> Array[@tool.AgentTool] {
  let result : Array[@tool.AgentTool] = []
  for name in ["read_skill", "mcp_list_tools", "mcp_call_tool"] {
    let schema : Json = match name {
      "read_skill" =>
        {
          "type": "object",
          "properties": {
            "name": { "type": "string" },
            "path": {
              "type": "string",
              "description": "Optional relative resource path inside the selected Skill; omit to read complete SKILL.md.",
            },
          },
          "required": ["name"],
        }
      "mcp_list_tools" =>
        {
          "type": "object",
          "properties": {
            "server": { "type": "string" },
            "cursor": { "type": "string" },
          },
        }
      _ =>
        {
          "type": "object",
          "properties": {
            "server": { "type": "string" },
            "name": { "type": "string" },
            "arguments": { "type": "object" },
          },
          "required": ["server", "name", "arguments"],
        }
    }
    let description = match name {
      "read_skill" =>
        "Load complete installed Skill instructions or one referenced resource through the MoonBook's existing Skill loader."
      "mcp_list_tools" =>
        "Discover actual tool schemas from enabled MCP integrations configured in the selected MoonBook; follow nextCursor when supplied."
      _ =>
        "Execute one discovered MCP tool on a selected enabled MoonBook integration. Preserve the returned source/result metadata."
    }
    let tool : @tool.Tool[Json] = @tool.Tool::new(
      description~,
      name~,
      schema=@tool.JsonSchema::from_json(schema),
      ToolFn(arguments => {
        let value = try {
          if name == "read_skill" {
            read_skill(book_root, arguments)
          } else {
            call_mcp(book_root, name, arguments)
          }
        } catch {
          e => return @tool.ToolResult::error("MoonBook tool failed: \{e}")
        }
        @tool.ToolResult::ok(value)
      }),
    )
    result.push(tool.to_agent_tool())
  }
  result
}
