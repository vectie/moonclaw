///|
fn json_string_map(value : Json) -> Map[String, String] {
  @json.from_json(value) catch {
    _ => {}
  }
}

///|
fn websocket_request_url(request : @channel.WebSocketDialRequest) -> String? {
  match request.metadata() {
    { "url": String(url), .. } => Some(url)
    _ => None
  }
}

///|
fn websocket_request_headers(
  request : @channel.WebSocketDialRequest,
) -> Map[String, String] {
  match request.metadata() {
    { "headers": headers, .. } => json_string_map(headers)
    _ => {}
  }
}

///|
fn gateway_websocket_connector() -> @channel.WebSocketClientConnector {
  @channel.WebSocketClientConnector::new(connect=async fn(request) {
    let url = match websocket_request_url(request) {
      Some(url) => url
      None =>
        return Err(
          "WebSocket dial request \{request.client_id()} is missing metadata.url",
        )
    }
    let client = @internal/websocket.Client::connect(
      @internal/websocket.ClientConfig::new(
        url~,
        headers=websocket_request_headers(request),
      ),
    ) catch {
      error => return Err(error.to_string())
    }
    let mut message_handler : (async (Bytes) -> Unit)? = None
    let mut close_handler : (() -> Unit)? = None
    client.set_on_message(async fn(message) {
      match message_handler {
        Some(handler) => handler(message.data())
        None => ()
      }
    })
    client.set_on_close(fn() {
      match close_handler {
        Some(handler) => handler()
        None => ()
      }
    })
    Ok(
      @channel.WebSocketManagedConnection::new(
        connection=@channel.WebSocketConnection::new(
          id=request.client_id(),
          send=fn(data) {
            let text : Result[String, Error] = try? @encoding/utf8.decode(data)
            match text {
              Ok(text) => client.send_text(text)
              Err(_) => client.send_binary(data)
            }
          },
          close=fn() { client.close() },
          on_message=fn(handler) { message_handler = Some(handler) },
          on_close=fn(handler) { close_handler = Some(handler) },
        ),
        wait_until_closed=() => client.run(),
      ),
    )
  })
}
