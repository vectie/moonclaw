///|
fn assert_cors_headers(headers : Map[String, String]) -> Unit raise {
  assert_eq(headers["access-control-allow-origin"], "*")
  assert_eq(headers["access-control-allow-methods"], "*")
  assert_eq(headers["access-control-allow-headers"], "*")
}

///|
async test "@vectie/moonclaw/internal/httpx.cors" (t : @test.Test) {
  @mock.run(t, _ => {
    let router = @httpx.Router::new()
    router.add_handler(Post, "/task", (_, w) => {
      w.write_header(@status.Ok)
      w.write("Hello, world! from Post Handler\n")
    })
    router.add_handler(Get, "/tasks", (_, w) => {
      w.write_header(@status.Ok)
      w.write("Hello, world! from Tasks Handler\n")
    })
    router.add_handler(Get, "/task/{id}", (r, w) => {
      let id = r.vars["id"]
      w.write_header(@status.Ok)
      w.write("Hello, world! from Task \{id} Handler\n")
    })
    let server = @httpx.Server::new("[::1]", 0)
    @async.with_task_group(group => {
      group.spawn_bg(
        () => server.serve(@httpx.cors(router.handler())),
        no_wait=true,
      )
      let client = @http.Client("http://localhost:\{server.port()}")
      client.request(Options, "*")
      let response = client.end_request()
      json_inspect(response.code, content=204)
      json_inspect(response.reason, content="No Content")
      assert_cors_headers(response.headers)
      let client = @http.Client("http://localhost:\{server.port()}")
      client.request(Options, "/task")
      let response = client.end_request()
      json_inspect(response.code, content=204)
      json_inspect(response.reason, content="No Content")
      assert_cors_headers(response.headers)
      let client = @http.Client("http://localhost:\{server.port()}")
      client.request(Options, "/tasks")
      let response = client.end_request()
      json_inspect(response.code, content=204)
      json_inspect(response.reason, content="No Content")
      assert_cors_headers(response.headers)
      let (response, body) = @http.get(
        "http://localhost:\{server.port()}/task/42",
      )
      json_inspect(response.code, content=200)
      json_inspect(response.reason, content="OK")
      json_inspect(body.text(), content="Hello, world! from Task 42 Handler\n")
      let (response, body) = @http.get(
        "http://localhost:\{server.port()}/task/100",
      )
      json_inspect(response.code, content=200)
      json_inspect(response.reason, content="OK")
      json_inspect(body.text(), content="Hello, world! from Task 100 Handler\n")
    })
  })
}
