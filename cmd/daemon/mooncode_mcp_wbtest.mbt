///|
fn mooncode_mcp_response(text : String, id : Int32) -> Result[Json, String] {
  @book_runtime.response_json(text, id)
}

///|
test "MCP accepts JSON and SSE responses matching the requested id" {
  assert_true(
    mooncode_mcp_response(
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[]}}", 2,
    )
    is Ok(_),
  )
  assert_true(
    mooncode_mcp_response(
      "event: message\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\"}\n\nevent: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[]}}\n\n",
      2,
    )
    is Ok(_),
  )
  assert_true(mooncode_mcp_response("{\"id\":3,\"result\":{}}", 2) is Err(_))
  assert_true(
    mooncode_mcp_response(
      "{\"id\":2,\"error\":{\"message\":\"Unavailable\"}}", 2,
    )
    is Err("Unavailable"),
  )
}

///|
async test "MCP discovers and invokes a real HTTP tool after initialization" {
  let server = @httpx.Server::new("[::1]", 0)
  defer server.close()
  let router = @httpx.Router::new()
  let methods : Array[String] = []
  router.add_handler(Post, "/mcp", (r, w) => {
    let body : Json = @httpx.JsonRequestReader::new(r).read()
    let method_ = mooncode_json_string(body, "method", default="")
    methods.push(method_)
    assert_eq(r.headers.get("authorization"), Some("Bearer fixture-token"))
    if method_ == "initialize" {
      w.header().set("mcp-session-id", "fixture-session")
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      w.write(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"tools\":{}}}}",
      )
    } else {
      assert_eq(r.headers.get("mcp-session-id"), Some("fixture-session"))
      assert_eq(r.headers.get("mcp-protocol-version"), Some("2025-11-25"))
      if method_ == "notifications/initialized" {
        w.write_header(202)
      } else if method_ == "tools/list" {
        w.header().set("Content-Type", "text/event-stream")
        w.write_header(200)
        w.write(
          "data: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[{\"name\":\"echo\",\"inputSchema\":{\"type\":\"object\"}}]}}\n\n",
        )
      } else {
        assert_eq(method_, "tools/call")
        let params = mooncode_json_object_field_or_empty(body, "params")
        assert_eq(mooncode_json_string(params, "name", default=""), "echo")
        assert_eq(
          mooncode_json_string(
            mooncode_json_object_field_or_empty(params, "arguments"),
            "text",
            default="",
          ),
          "hello",
        )
        w.header().set("Content-Type", "application/json")
        w.write_header(200)
        w.write(
          "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"hello\"}]}}",
        )
      }
    }
  })
  @fsx.with_temporary_directory("mooncode-mcp-XXXXXX", root => {
    let root = @fs.realpath(root)
    let path = @moonsuite.product_artifact_for_workspace_root(
      root, "moonclaw", "mcp-servers.json",
    )
    @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
    let config : Json = {
      "servers": [
        {
          "id": "fixture",
          "url": "http://localhost:\{server.port()}/mcp",
          "token": "fixture-token",
          "enabled": true,
        },
      ],
    }
    @fsx.write_to_file(path, config.stringify())
    @async.with_task_group(group => {
      group.spawn_bg(() => server.serve(router.handler()), no_wait=true)
      let listed = mooncode_tool_mcp(root, "mcp_list_tools", {})
      assert_true(mooncode_json_bool(listed, "ok", default=false))
      assert_true(listed.stringify().contains("echo"))
      assert_false(listed.stringify().contains("fixture-token"))
      let called = mooncode_tool_mcp(root, "mcp_call_tool", {
        "server": "fixture",
        "name": "echo",
        "arguments": { "text": "hello" },
      })
      assert_true(mooncode_json_bool(called, "ok", default=false))
      assert_true(called.stringify().contains("hello"))
      assert_eq(methods.length(), 6)
    })
  })
}

///|
async test "MCP removes configured token echoed in results keys and provider errors" {
  let server = @httpx.Server::new("[::1]", 0)
  defer server.close()
  let router = @httpx.Router::new()
  let token = "fixture-mcp-echo-secret"
  let mode = ["success"]
  router.add_handler(Post, "/mcp", (r, w) => {
    let body : Json = @httpx.JsonRequestReader::new(r).read()
    let method_ = mooncode_json_string(body, "method", default="")
    if method_ == "notifications/initialized" {
      w.write_header(202)
      return
    }
    let response : Json = if method_ == "initialize" {
      { "id": 1, "result": { "protocolVersion": "2025-11-25" } }
    } else if mode[0] == "error" {
      { "id": 2, "error": { "message": "Rejected " + token + " and " + token } }
    } else {
      let fields : Map[String, Json] = {
        "nested": [token, { "text": "Echo " + token }],
      }
      fields[token] = Json(token)
      { "id": 2, "result": Json(fields) }
    }
    w.header().set("Content-Type", "application/json")
    w.write_header(200)
    w.write(response.stringify())
  })
  @fsx.with_temporary_directory("mooncode-mcp-echo-XXXXXX", root => {
    let root = @fs.realpath(root)
    let path = @moonsuite.product_artifact_for_workspace_root(
      root, "moonclaw", "mcp-servers.json",
    )
    @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
    let config : Json = {
      "servers": [
        {
          "id": "fixture",
          "url": "http://localhost:\{server.port()}/mcp",
          "token": token,
        },
      ],
    }
    @fsx.write_to_file(path, config.stringify())
    @async.with_task_group(group => {
      group.spawn_bg(() => server.serve(router.handler()), no_wait=true)
      for outcome in ["success", "error"] {
        mode[0] = outcome
        let result = mooncode_tool_mcp(root, "mcp_list_tools", {})
        assert_false(result.stringify().contains(token))
        assert_true(result.stringify().contains("[redacted]"))
        assert_eq(
          mooncode_json_bool(result, "ok", default=false),
          outcome == "success",
        )
      }
    })
  })
}
