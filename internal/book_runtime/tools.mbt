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
        "Without server, list enabled MoonBook integrations. Supply one server to retrieve its actual tool schemas; follow nextCursor when supplied."
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
          } else if name == "mcp_list_tools" && text(arguments, "server") == "" {
            {
              "tool": name,
              "ok": true,
              "servers": mcp_servers(book_root)
              .filter(server => flag(server, "enabled", default=true))
              .map(server => {
                "server": text(server, "id"),
                "name": text(server, "name", default=text(server, "id")),
              }),
              "next_step": "Call mcp_list_tools with one server to retrieve the schemas needed for this task. Do not fetch unrelated catalogs.",
            }
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
