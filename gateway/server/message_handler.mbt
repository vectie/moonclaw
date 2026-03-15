///|
pub struct SendMessageParams {
  from_agent : String
  to_agent : String?
  topic : String
  payload : Json
} derive(FromJson, ToJson)

///|
pub struct CreateMailboxParams {
  agent_id : String
} derive(FromJson, ToJson)

///|
async fn Gateway::handle_agent_message(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let body = r.body.read_all().binary()
  let text : String = @encoding/utf8.decode(body) catch {
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_utf8",
          "message": "Invalid UTF-8 in request body",
        },
      })
  }
  let json = @json.parse(text) catch {
    e =>
      raise json_error(400, "BadRequest", {
        "error": { "code": "parse_error", "message": "Invalid JSON: \{e}" },
      })
  }
  let params : SendMessageParams = @json.from_json(json) catch {
    e =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_params",
          "message": "Invalid message params: \{e}",
        },
      })
  }
  let message = match params.to_agent {
    Some(target) =>
      agent_message(
        uuid=self.uuid,
        from_agent=params.from_agent,
        to_agent=target,
        topic=params.topic,
        payload=params.payload,
        timestamp=current_time_ms(),
      )
    None =>
      agent_message(
        uuid=self.uuid,
        from_agent=params.from_agent,
        topic=params.topic,
        payload=params.payload,
        timestamp=current_time_ms(),
      )
  }
  let delivered = self.mailbox_manager.deliver_sync(message)
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  let result : Json = {
    "message_id": message.message_id.to_json(),
    "delivered": delivered.to_json(),
  }
  w.write(result.stringify())
}

///|
async fn Gateway::handle_get_messages(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  agent_id : StringView,
) -> Unit {
  let mailbox = match self.mailbox_manager.get(agent_id.to_string()) {
    Some(m) => m
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "mailbox_not_found",
          "message": "Mailbox not found for agent: \{agent_id}",
        },
      })
  }
  let messages = mailbox.try_get()
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  let result : Json = {
    "agent_id": agent_id.to_string().to_json(),
    "messages": match messages {
      Some(msg) => [msg.to_json()].to_json()
      None => ([] : Array[Json]).to_json()
    },
  }
  w.write(result.stringify())
}

///|
async fn Gateway::handle_create_mailbox(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let body = r.body.read_all().binary()
  let text : String = @encoding/utf8.decode(body) catch {
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_utf8",
          "message": "Invalid UTF-8 in request body",
        },
      })
  }
  let json = @json.parse(text) catch {
    e =>
      raise json_error(400, "BadRequest", {
        "error": { "code": "parse_error", "message": "Invalid JSON: \{e}" },
      })
  }
  let params : CreateMailboxParams = @json.from_json(json) catch {
    e =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_params",
          "message": "Invalid mailbox params: \{e}",
        },
      })
  }
  if self.mailbox_manager.has(params.agent_id) {
    raise json_error(409, "Conflict", {
      "error": {
        "code": "mailbox_exists",
        "message": "Mailbox already exists for agent: \{params.agent_id}",
      },
    })
  }
  let mailbox = self.mailbox_manager.create(
    params.agent_id,
    timestamp=current_time_ms(),
  )
  w.header().set("Content-Type", "application/json")
  w.write_header(201)
  w.write(mailbox.to_json().stringify())
}

///|
async fn Gateway::handle_delete_mailbox(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  mailbox_id : StringView,
) -> Unit {
  match self.mailbox_manager.remove(mailbox_id.to_string()) {
    Some(_) => {
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      let result : Json = {
        "deleted": true.to_json(),
        "agent_id": mailbox_id.to_string().to_json(),
      }
      w.write(result.stringify())
    }
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "mailbox_not_found",
          "message": "Mailbox not found: \{mailbox_id}",
        },
      })
  }
}

///|
async fn Gateway::handle_list_mailboxes(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let agents = self.mailbox_manager.list()
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  let result : Json = {
    "mailbox_count": agents.length().to_json(),
    "agents": agents.to_json(),
  }
  w.write(result.stringify())
}
