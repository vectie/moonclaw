///|
pub struct ClientConfig {
  url : String
  headers : Map[String, String]
} derive(Show, Eq)

///|
pub fn ClientConfig::new(
  url~ : String,
  headers? : Map[String, String] = {},
) -> ClientConfig {
  ClientConfig::{ url, headers }
}

///|
pub(all) enum MessageKind {
  Text
  Binary
} derive(Show, Eq)

///|
pub struct Message {
  kind : MessageKind
  data : Bytes
} derive(Show, Eq)

///|
pub fn Message::new(kind~ : MessageKind, data~ : Bytes) -> Message {
  Message::{ kind, data }
}

///|
pub fn Message::kind(self : Message) -> MessageKind {
  self.kind
}

///|
pub fn Message::data(self : Message) -> Bytes {
  self.data
}

///|
pub fn Message::text(self : Message) -> String raise {
  @encoding/utf8.decode(self.data)
}

///|
pub suberror WebSocketClientError {
  ConnectFailed(String)
  SendFailed(String)
  ReceiveFailed(String)
} derive(Show)

///|
enum ClientCommand {
  Send(Message)
  SendJson(Json)
  Close
}

///|
pub struct Client {
  conn : @asyncws.Conn
  outbox : @aqueue.Queue[ClientCommand]
  mut on_message : (async (Message) -> Unit)?
  mut on_close : (() -> Unit)?
  closed : Ref[Bool]
}

///|
pub async fn Client::connect(config : ClientConfig) -> Client {
  try {
    let conn = @asyncws.connect(config.url, headers=config.headers)
    Client::{
      conn,
      outbox: @aqueue.Queue::new(kind=Unbounded),
      on_message: None,
      on_close: None,
      closed: Ref::new(false),
    }
  } catch {
    error => raise ConnectFailed(error.to_string())
  }
}

///|
pub fn Client::set_on_message(
  self : Client,
  handler : async (Message) -> Unit,
) -> Unit {
  self.on_message = Some(handler)
}

///|
pub fn Client::set_on_close(self : Client, handler : () -> Unit) -> Unit {
  self.on_close = Some(handler)
}

///|
pub fn Client::is_closed(self : Client) -> Bool {
  self.closed.val
}

///|
fn Client::notify_closed(self : Client) -> Unit {
  if !self.closed.val {
    self.closed.val = true
    match self.on_close {
      Some(handler) => handler()
      None => ()
    }
  }
}

///|
pub fn Client::send_text(self : Client, text : String) -> Unit {
  ignore(
    self.outbox.try_put(
      Send(Message::new(kind=Text, data=@encoding/utf8.encode(text))),
    ),
  ) catch {
    _ => ()
  }
}

///|
pub fn Client::send_binary(self : Client, data : Bytes) -> Unit {
  ignore(self.outbox.try_put(Send(Message::new(kind=Binary, data~)))) catch {
    _ => ()
  }
}

///|
pub fn Client::send_json(self : Client, data : Json) -> Unit {
  ignore(self.outbox.try_put(SendJson(data))) catch {
    _ => ()
  }
}

///|
pub fn Client::close(self : Client) -> Unit {
  ignore(self.outbox.try_put(Close)) catch {
    _ => ()
  }
}

///|
async fn Client::writer_loop(self : Client) -> Unit {
  while !self.closed.val {
    match self.outbox.get() {
      Send(message) =>
        try {
          match message.kind() {
            Text => self.conn.send_text(message.text() catch { _ => "" })
            Binary => self.conn.send_binary(message.data())
          }
        } catch {
          error => raise SendFailed(error.to_string())
        }
      SendJson(data) =>
        self.conn.send_text(data.stringify()) catch {
          error => raise SendFailed(error.to_string())
        }
      Close => {
        self.conn.send_close() catch {
          _ => ()
        }
        self.conn.close()
        self.notify_closed()
        return
      }
    }
  }
}

///|
async fn recv_message(conn : @asyncws.Conn) -> Message {
  let message = conn.recv() catch {
    error => raise ReceiveFailed(error.to_string())
  }
  let data = message.read_all().binary() catch {
      error => raise ReceiveFailed(error.to_string())
    }
  let kind = match message.kind {
    @asyncws.Text => Text
    @asyncws.Binary => Binary
  }
  Message::{ kind, data }
}

///|
pub async fn Client::run(self : Client) -> Unit {
  defer {
    self.conn.close()
    self.notify_closed()
  }
  @async.with_task_group(group => {
    group.spawn_bg(() => self.writer_loop(), no_wait=true, allow_failure=true)
    while !self.closed.val {
      let message = recv_message(self.conn)
      match self.on_message {
        Some(handler) => handler(message)
        None => ()
      }
    }
  }) catch {
    _ => ()
  }
}
