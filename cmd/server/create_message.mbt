///|
/// Request body accepted by `POST /v1/message`. Holds the OpenAI-style message
/// plus an optional one-off web search toggle.
struct CreateMessageRequest {
  message : @ai.Message
  web_search : Bool?
  optional_context : @agent.OptionalInputContext?
}

///|
pub fn CreateMessageRequest::new(
  message~ : @ai.Message,
  web_search? : Bool,
  optional_context? : @agent.OptionalInputContext,
) -> CreateMessageRequest {
  { message, web_search, optional_context, }
}

///|
pub impl ToJson for CreateMessageRequest with fn to_json(
  self : CreateMessageRequest,
) -> Json {
  let object : Map[String, Json] = {
    "message": self.message.to_openai().to_json(),
  }
  if self.web_search is Some(ws) {
    object["web_search"] = ws.to_json()
  }
  if self.optional_context is Some(context) {
    object["optional_context"] = context.to_json()
  }
  Json::object(object)
}

///|
pub impl @json.FromJson for CreateMessageRequest with fn from_json(
  json : Json,
  json_path : @json.JsonPath,
) -> CreateMessageRequest raise @json.JsonDecodeError {
  guard json is { "message": message, .. } else {
    raise JsonDecodeError(
      (json_path.add_key("message"), "Missing 'message' field in request body"),
    )
  }
  let message : @openai.ChatCompletionMessageParam = @json.from_json(message)
  let web_search : Bool? = match json {
    { "web_search": ws, .. } => Some(@json.from_json(ws))
    _ => None
  }
  let message = @ai.Message::from_openai(message)
  let optional_context : @agent.OptionalInputContext? = match json {
    { "optional_context": Null, .. } => None
    { "optional_context": context, .. } => Some(@json.from_json(context))
    _ => None
  }
  if optional_context is Some(context) && !context.valid_for_message(message) {
    raise JsonDecodeError(
      (
        json_path.add_key("optional_context"),
        "Optional context must identify one complete block in this user message",
      ),
    )
  }
  { message, web_search, optional_context, }
}

///|
/// The single message-ingress handoff used by both idle and busy server paths.
/// Keeping it explicit permits hermetic native proof of the serialized request
/// path without substituting a second message/config decoder.
pub fn CreateMessageRequest::queue_on(
  self : CreateMessageRequest,
  agent : @agent.Agent,
) -> @uuid.Uuid {
  agent.queue_message(
    self.message,
    web_search?=self.web_search,
    optional_context?=self.optional_context,
  )
}

///|
test "CreateMessageRequest::from_json" {
  let json : Json = {
    "message": { "role": "user", "content": "Hello, world!" },
    "web_search": true,
  }
  let req : CreateMessageRequest = @json.from_json(json)
  json_inspect(req.message, content=["User", "Hello, world!"])
  json_inspect(req.web_search, content=[true])
}

///|
test "CreateMessageRequest optional context remains absent or null for ordinary input" {
  let inputs : Array[Json] = [
    { "message": { "role": "user", "content": "ordinary" } },
    {
      "message": { "role": "user", "content": "ordinary" },
      "optional_context": null,
    },
  ]
  for json in inputs {
    let request : CreateMessageRequest = @json.from_json(json)
    assert_true(request.optional_context is None)
    guard request.to_json() is Object(object) else { fail("Expected object") }
    assert_false(object.contains("optional_context"))
  }
}

///|
test "CreateMessageRequest preserves and binds exact optional context descriptor" {
  let context = @agent.OptionalInputContext::new(
    block="[accepted complete tail]",
    omission="[over_budget]",
    digest="digest-1",
  )
  let request = CreateMessageRequest::new(
    message=@ai.user_message(content="task [accepted complete tail] output"),
    optional_context=context,
  )
  let restored : CreateMessageRequest = @json.from_json(request.to_json())
  guard restored.optional_context is Some(restored) else {
    fail("Missing optional context")
  }
  assert_eq(restored.block, context.block)
  assert_eq(restored.omission, context.omission)
  assert_eq(restored.digest, context.digest)
  for
    content in [
      "unrelated message", "[accepted complete tail] repeated [accepted complete tail]",
    ] {
    let mut rejected = false
    try {
      let _ : CreateMessageRequest = @json.from_json(
        CreateMessageRequest::new(
          message=@ai.user_message(content~),
          optional_context=context,
        ).to_json(),
      )
    } catch {
      @json.JsonDecodeError(_) => rejected = true
    }
    assert_true(rejected)
  }
}

///|
struct CreateMessageResponse {
  id : @uuid.Uuid
  queued : Bool
}

///|
pub fn CreateMessageResponse::new(
  id~ : @uuid.Uuid,
  queued~ : Bool,
) -> CreateMessageResponse {
  { id, queued, }
}

///|
pub impl ToJson for CreateMessageResponse with fn to_json(
  self : CreateMessageResponse,
) -> Json {
  { "id": self.id, "queued": self.queued }
}

///|
pub impl @json.FromJson for CreateMessageResponse with fn from_json(
  json : Json,
  json_path : @json.JsonPath,
) -> CreateMessageResponse raise @json.JsonDecodeError {
  guard json is { "id": id, "queued": queued, .. } else {
    raise JsonDecodeError(
      (json_path, "Expected JSON object for CreateMessageResponse"),
    )
  }
  let id : @uuid.Uuid = @json.from_json(id)
  let queued : Bool = @json.from_json(queued)
  { id, queued, }
}

///|
/// Queues a user message for processing and reports whether it started
/// immediately. The first message in an empty queue begins execution right
/// away; subsequent ones are enqueued until the agent becomes idle again.
async fn Server::create_message(
  self : Server,
  body_json : Json,
  w : @httpx.ResponseWriter,
) -> Unit {
  let request : CreateMessageRequest = @json.from_json(body_json) catch {
    JsonDecodeError(_) as error =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": -1,
          "message": "Invalid 'message' field: \{error}",
          "data": { "error": error, "body": body_json },
        },
      })
  }
  let (id, queued) = {
    let idq = @aqueue.Queue(kind=Unbounded)
    self.message_queue.put((request, idq))
    idq.get()
  }
  let response : CreateMessageResponse = { id, queued, }
  w.send_json(code=200, response.to_json())
}
