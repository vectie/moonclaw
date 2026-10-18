///|
async fn mooncode_tool_mcp(
  book_root : String,
  tool : String,
  arguments : Json,
) -> Json {
  @book_runtime.call_mcp(book_root, tool, arguments)
}

///|
async fn Daemon::mooncode_mcp_inspect(
  self : Daemon,
  config : @moondesk_sandbox_config.Config,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  self.with_mooncode_integration_request(config, r, (payload, book_root) => {
    let result = mooncode_tool_mcp(book_root, "mcp_list_tools", payload) catch {
      _ =>
        raise json_error(403, "Forbidden", {
          "error": { "message": "Book integration resource is unavailable" },
        })
    }
    w.header().set("Content-Type", "application/json")
    w.write_header(200)
    w.write(result.stringify())
  })
}
