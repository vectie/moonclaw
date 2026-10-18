///|
// Shared by the ordinary Agent and MoonCode. This is the existing MoonCode
// Book-local MCP transport, moved to its runtime owner without changing shape.
pub fn mcp_servers(book_root : String) -> Array[Json] raise {
  let book_local_path = @pathx.join(
    book_root, ".moonsuite/products/moonclaw/mcp-servers.json",
  )
  let content = match read_resource(book_local_path) {
    Some(content) => content
    None =>
      read_resource(
        @moonsuite.product_artifact_for_workspace_root(
          book_root, "moonclaw", "mcp-servers.json",
        ),
      ).unwrap_or("")
  }
  let json = @json.parse(content) catch { _ => return [] }
  array(json, "servers")
}

///|
pub fn response_json(content : String, id : Int32) -> Result[Json, String] {
  let candidates = [content]
  let mut data : Array[String] = []
  for line in content.split("\n") {
    let line = line.trim_end().to_owned()
    if line == "" {
      if !data.is_empty() {
        candidates.push(data.join("\n"))
        data = []
      }
    } else if line.has_prefix("data:") {
      data.push(line[5:].trim_start().to_owned())
    }
  }
  if !data.is_empty() {
    candidates.push(data.join("\n"))
  }
  for candidate in candidates {
    let json = @json.parse(candidate) catch { _ => continue }
    if field(json, "id") != Some(Json(id)) {
      continue
    }
    if field(json, "error") is Some(value) {
      return Err(
        text(value, "message", default="The MCP server rejected this request"),
      )
    }
    if field(json, "result") is Some(value) {
      return Ok(value)
    }
  }
  Err("The MCP server did not return a matching JSON-RPC response")
}

///|
async fn mcp_request(
  server : Json,
  method_ : String,
  params : Json,
) -> Result[Json, String] {
  let headers : Map[String, String] = {
    "content-type": "application/json",
    "accept": "application/json, text/event-stream",
  }
  let token = text(server, "token")
  if token != "" {
    headers["authorization"] = "Bearer " + token
  }
  let init : Json = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-11-25",
      "capabilities": {},
      "clientInfo": { "name": "MoonClaw", "version": "0.1" },
    },
  }
  let (response, body) = @http.post(
    text(server, "url"),
    init.stringify(),
    headers~,
  )
  if response.code != 200 {
    return Err("MCP initialization returned HTTP \{response.code}")
  }
  let initialized = match response_json(body.text(), 1) {
    Ok(value) => value
    Err(message) => return Err(redact_token(message, token))
  }
  if response.headers.get("mcp-session-id") is Some(id) {
    headers["mcp-session-id"] = id
  }
  headers["mcp-protocol-version"] = text(
    initialized,
    "protocolVersion",
    default="2025-11-25",
  )
  let notification : Json = {
    "jsonrpc": "2.0",
    "method": "notifications/initialized",
  }
  let (notified, _) = @http.post(
    text(server, "url"),
    notification.stringify(),
    headers~,
  )
  if notified.code < 200 || notified.code >= 300 {
    return Err("MCP initialization notification returned HTTP \{notified.code}")
  }
  let request : Json = {
    "jsonrpc": "2.0",
    "id": 2,
    "method": method_,
    "params": params,
  }
  let (response, body) = @http.post(
    text(server, "url"),
    request.stringify(),
    headers~,
  )
  if response.code != 200 {
    return Err("MCP request returned HTTP \{response.code}")
  }
  match response_json(body.text(), 2) {
    Ok(result) => Ok(redact_response(result, token))
    Err(message) => Err(redact_token(message, token))
  }
}

///|
pub async fn call_mcp(
  book_root : String,
  tool : String,
  arguments : Json,
) -> Json {
  let selected = text(arguments, "server")
  let servers = mcp_servers(book_root).filter(server => {
    flag(server, "enabled", default=true) &&
    (selected == "" || text(server, "id") == selected)
  })
  if selected != "" && servers.is_empty() {
    return error(tool, "The selected integration is unavailable or paused")
  }
  if tool == "mcp_call_tool" && (selected == "" || servers.length() != 1) {
    return error(tool, "Choose an enabled MCP server from mcp_list_tools")
  }
  let results : Array[Json] = []
  for server in servers {
    let method_ = if tool == "mcp_call_tool" {
      "tools/call"
    } else {
      "tools/list"
    }
    let params : Json = if tool == "mcp_call_tool" {
      {
        "name": text(arguments, "name"),
        "arguments": match field(arguments, "arguments") {
          Some(Object(value)) => Json(value)
          _ => {}
        },
      }
    } else {
      match field(arguments, "cursor") {
        Some(cursor) => { "cursor": cursor }
        None => {}
      }
    }
    let result = mcp_request(server, method_, params) catch {
      _ => Err("Could not connect to the MCP server")
    }
    match result {
      Ok(result) =>
        results.push({
          "server": text(server, "id"),
          "ok": !flag(result, "isError"),
          "result": result,
        })
      Err(message) =>
        results.push({
          "server": text(server, "id"),
          "ok": false,
          "message": message,
        })
    }
  }
  let failed = results.any(result => !flag(result, "ok"))
  {
    "tool": tool,
    "ok": !failed,
    "is_error": failed,
    "servers": Json::array(results),
    "output": Json::array(results).stringify(),
  }
}
