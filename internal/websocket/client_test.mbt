///|
#cfg(target="native")
async fn websocket_echo_server(addr : @socket.Addr) -> Unit {
  let server = @http.Server::new(addr)
  server.run_forever((request, _, conn) => {
    guard request.path is "/ws" else { conn.send_response(404, "NotFound") }
    let ws = @asyncws.from_http_server(request, conn)
    defer ws.close()
    for ;; {
      let msg = ws.recv()
      ws..start_message(msg.kind)..write_reader(msg).end_message()
    }
  })
}

///|
#cfg(target="native")
async test "internal websocket client sends and receives text messages" {
  @async.with_task_group(group => {
    let addr = @socket.Addr::parse("127.0.0.1:10081")
    group.spawn_bg(() => websocket_echo_server(addr), no_wait=true)
    @async.sleep(50)
    let client = Client::connect(
      ClientConfig::new(url="ws://127.0.0.1:10081/ws"),
    )
    let received : Array[String] = []
    client.set_on_message(fn(msg) {
      received.push(msg.text() catch { _ => "" })
      client.close()
    })
    client.send_text("hello")
    group.spawn_bg(() => client.run(), no_wait=true, allow_failure=true)
    @async.sleep(150)
    json_inspect(received, content=["hello"])
    group.return_immediately(())
  })
}

///|
#cfg(target="native")
async test "internal websocket client close callback fires once" {
  @async.with_task_group(group => {
    let addr = @socket.Addr::parse("127.0.0.1:10082")
    group.spawn_bg(() => websocket_echo_server(addr), no_wait=true)
    @async.sleep(50)
    let client = Client::connect(
      ClientConfig::new(url="ws://127.0.0.1:10082/ws"),
    )
    let close_calls : Array[Int] = []
    client.set_on_close(fn() { close_calls.push(1) })
    group.spawn_bg(() => client.run(), no_wait=true, allow_failure=true)
    @async.sleep(50)
    client.close()
    @async.sleep(100)
    inspect(close_calls.length(), content="1")
    group.return_immediately(())
  })
}
