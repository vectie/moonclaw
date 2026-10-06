///|
/// Final serialized OpenAI-compatible HTTP request. The ordinary transport posts
/// exactly `body`; explicit transports observe the same endpoint, headers and
/// bytes after routing, stream selection and extra-body merging. Installing a
/// transport is an in-process dependency injection, never a model route change.
pub struct ChatTransportRequest {
  url : String
  headers : Map[String, String]
  body : String
  stream : Bool
}

///|
/// Explicit per-call transport. This seam supports hermetic request-boundary
/// tests without listening sockets, provider credentials or a live provider.
pub type ChatTransport = async (ChatTransportRequest, (String) -> Unit) -> ChatCompletion

///|
async fn send_chat_request(
  request : ChatTransportRequest,
  model~ : @model.Model,
  logger~ : @pino.Logger,
  on_text_delta~ : (String) -> Unit,
) -> ChatCompletion {
  let uri = Uri::parse(request.url)
  let client = @http.Client(
    "\{uri.schema}://\{uri.host}",
    headers=request.headers,
  )
  defer client.close()
  let response = client.post(uri.path, request.body)
  guard response.code is (200..=299) else {
    raise HttpRetryError(
      code=response.code,
      body=client.read_all().text(),
      retry_after_ms=response_retry_after_ms(response.headers),
    )
  }
  let completion = if request.stream {
    let reader = ChunkReader::new(client)
    let builder = ChatCompletionBuilder::new()
    while reader.read() is Some(chunk) {
      receive_chat_stream_chunk(chunk, logger, on_text_delta, builder)
    }
    builder.to_chat_completion()
  } else {
    @json.from_json(@json.parse(client.read_all().text()))
  }
  if logger.is_enabled(Debug) {
    logger.debug("ResponseReceived", data={
      "model": { "name": model.model_name, "base_url": model.base_url },
      "response_code": response.code,
      "response_body": completion,
    })
  }
  completion
}

///|
/// Keep diagnostics, visible deltas, and accumulation in the existing order.
/// Disabled diagnostics must not construct another JSON tree for every chunk.
async fn receive_chat_stream_chunk(
  chunk : ChatCompletionChunk,
  logger : @pino.Logger,
  on_text_delta : (String) -> Unit,
  builder : ChatCompletionBuilder,
) -> Unit {
  if logger.is_enabled(Debug) {
    logger.debug("ChunkReceived", data={ "chunk": chunk })
  }
  emit_text_deltas_from_chunk(chunk, on_text_delta)
  builder.add_chunk(chunk)
}
