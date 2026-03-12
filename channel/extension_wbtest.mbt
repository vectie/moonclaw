///|
async test "WebSocketClientRuntimeManager reconnects closed clients and stops removed clients" {
  let manager = WebSocketClientRuntimeManager::new()
  let runtime = manager.controller()
  let mut connect_calls = 0
  let connected_ids : Array[String] = []
  let closed_ids : Array[String] = []
  let close_hooks : Array[() -> Unit] = []

  @async.with_task_group(group => {
    group.spawn_bg(() => manager.start(), no_wait=true, allow_failure=true)
    runtime.upsert(
      WebSocketClientRegistration::new(
        spec=WebSocketClientSpec::new(
          client_id="feishu:runtime-test",
          label="runtime-test",
          reconnect_delay_ms=10,
        ),
        connect=fn() {
          connect_calls = connect_calls + 1
          let connection_id = "conn-\{connect_calls}"
          let mut on_close : (() -> Unit)? = None
          let closed = Ref::new(false)
          close_hooks.push(fn() {
            closed.val = true
            match on_close {
              Some(handler) => handler()
              None => ()
            }
          })
          Ok(
            WebSocketManagedConnection::new(
              connection=WebSocketConnection::new(
                id=connection_id,
                send=fn(_) {  },
                close=fn() { closed_ids.push(connection_id) },
                on_close=fn(handler) { on_close = Some(handler) },
              ),
              wait_until_closed=async fn() {
                for ;; {
                  if closed.val {
                    return
                  }
                  @async.sleep(10)
                }
              },
            ),
          )
        },
        on_connect=fn(connection) { connected_ids.push(connection.id()) },
      ),
    )
    @async.sleep(50)
    inspect(connect_calls, content="1")
    json_inspect(connected_ids, content=["conn-1"])

    close_hooks[0]()
    @async.sleep(150)
    inspect(connect_calls, content="2")
    json_inspect(connected_ids, content=["conn-1", "conn-2"])

    runtime.remove("feishu:runtime-test")
    @async.sleep(50)
    inspect(closed_ids.contains("conn-2"), content="true")
    runtime.stop_all()
    group.return_immediately(())
  })
}
