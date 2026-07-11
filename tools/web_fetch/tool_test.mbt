///|
async test "web_fetch tool fetches and cleans html" (t : @test.Test) {
  @mock.run(t, _ => {
    let router = @httpx.Router::new()
    router.add_handler(Get, "/page", (_, w) => {
      w.header().set("Content-Type", "text/html; charset=utf-8")
      w.write_header(@status.Ok)
      w.write(
        "<html><head><title>Site Page</title></head><body><h1>Hello</h1><p>World &amp; team.</p></body></html>",
      )
    })
    let server = @httpx.Server::new("[::1]", 0)
    @async.with_task_group(group => {
      group.spawn_bg(() => server.serve(router.handler()), no_wait=true)
      let tool = new()
      let result = tool.call({
        "url": "http://localhost:\{server.port()}/page",
        "max_chars": 500,
      })
      guard result is Ok(output) else {
        fail("Expected Ok result but got: \{result}")
      }
      inspect(output.status_code.to_string(), content="200")
      inspect(output.title.unwrap_or(""), content="Site Page")
      inspect(output.text, content="Hello World & team.")
    })
  })
}

///|
async test "web_fetch tool truncates plain text response" (t : @test.Test) {
  @mock.run(t, _ => {
    let router = @httpx.Router::new()
    router.add_handler(Get, "/plain", (_, w) => {
      w.header().set("Content-Type", "text/plain")
      w.write_header(@status.Ok)
      w.write("abcdefghijklmnopqrstuvwxyz")
    })
    let server = @httpx.Server::new("[::1]", 0)
    @async.with_task_group(group => {
      group.spawn_bg(() => server.serve(router.handler()), no_wait=true)
      let tool = new()
      let result = tool.call({
        "url": "http://localhost:\{server.port()}/plain",
        "max_chars": 200,
      })
      guard result is Ok(output) else {
        fail("Expected Ok result but got: \{result}")
      }
      inspect(output.truncated.to_json().stringify(), content="false")
      inspect(output.text, content="abcdefghijklmnopqrstuvwxyz")
    })
  })
}

///|
async test "web_fetch live PDF uses bounded extraction when configured" {
  guard @os.getenv("MOONCLAW_LIVE_PDF_URL") is Some(url) else { return }
  let result = new().call({ "url": url, "max_chars": 2000 })
  guard result is Ok(output) else {
    fail("Expected live PDF fetch to succeed but got: \{result}")
  }
  inspect(output.source, content="http-fetch-pdf")
  assert_true(output.metadata.stringify().contains("Extracted text with pypdf"))
  assert_true(output.text.contains("Lunar Mobility"))
}
