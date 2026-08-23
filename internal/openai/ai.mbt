///|
priv suberror HttpError {
  HttpError(code~ : Int, body~ : String)
} derive(Debug, ToJson)

///|
/// HTTP failure that retains the provider's explicit retry window. MoonGate
/// forwards only safe retry/rate-limit headers, so callers can pace a durable
/// retry loop without guessing or immediately bursting again.
priv suberror HttpRetryError {
  HttpRetryError(code~ : Int, body~ : String, retry_after_ms~ : Int?)
} derive(Debug, ToJson)

///|
pub fn error_summary(error : Error) -> String {
  match error {
    HttpError(code~, body~) => http_error_summary(code, body)
    HttpRetryError(code~, body~, ..) => http_error_summary(code, body)
    _ => error.to_string()
  }
}

///|
fn http_error_summary(code : Int, body : String) -> String {
  let body = body.trim().to_owned()
  if body == "" {
    "HTTP \{code}"
  } else if body.length() > 500 {
    "HTTP \{code}: \{body[:500]}..."
  } else {
    "HTTP \{code}: \{body}"
  }
}

///|
/// Stable provider failure classes used by MoonCode's durable retry owner.
/// These names are intentionally transport-neutral and safe for journals.
pub fn error_class(error : Error) -> String {
  match error {
    HttpError(code~, body~) | HttpRetryError(code~, body~, ..) =>
      http_error_class(code, body)
    _ => "transport"
  }
}

///|
pub fn error_retry_after_ms(error : Error) -> Int? {
  match error {
    HttpRetryError(retry_after_ms~, ..) => retry_after_ms
    _ => None
  }
}

///|
pub fn error_is_transient(error : Error) -> Bool {
  match error {
    HttpError(code~, body~) | HttpRetryError(code~, body~, ..) => {
      let class = http_error_class(code, body)
      class == "server_overloaded" ||
      class == "request_burst" ||
      class == "rate_limited" ||
      class == "transient_http"
    }
    _ => false
  }
}

///|
fn http_error_class(code : Int, body : String) -> String {
  let normalized = body.to_lower()
  if normalized.contains("serveroverloaded") ||
    normalized.contains("server overloaded") {
    return "server_overloaded"
  }
  if normalized.contains("requestbursttoofast") ||
    normalized.contains("request burst too fast") {
    return "request_burst"
  }
  if normalized.contains("quotaexceeded") ||
    normalized.contains("quota exhausted") ||
    normalized.contains("insufficient_quota") ||
    normalized.contains("accountoverdue") ||
    normalized.contains("account overdue") {
    return "quota_exhausted"
  }
  if code == 429 {
    return "rate_limited"
  }
  if code == 408 || code == 500 || code == 502 || code == 503 || code == 504 {
    return "transient_http"
  }
  "permanent_http"
}

///|
fn response_retry_after_ms(headers : Map[String, String]) -> Int? {
  let mut raw : String? = None
  for key, value in headers {
    if key.to_lower() == "retry-after" {
      raw = Some(value.trim().to_owned())
      break
    }
  }
  guard raw is Some(value) else { return None }
  let seconds = @string.parse_int(value, base=10) catch { _ => return None }
  if seconds < 0 {
    None
  } else {
    Some((seconds * 1000).min(300000))
  }
}

///|
/// Execute a chat completion request with the OpenAI API.
///
/// Sends a chat completion request to the model's endpoint and returns the parsed response.
/// Includes automatic retry logic with exponential backoff for transient failures.
///
/// Parameters:
/// - model: The model configuration containing API credentials and endpoint
/// - request: The chat completion parameters including messages, tools, and settings
///
/// Returns a ChatCompletion object containing the model's response, including generated
/// messages, token usage, and metadata.
///
/// Raises HttpError if the API returns a non-2xx status code.
pub async fn chat(
  model~ : @model.Model,
  request : Request,
  logger? : @pino.Logger = @pino.logger("openai", @pino.Transport::sink()),
  extra_body? : Map[String, Json] = {},
  timeout_ms? : Int? = None,
) -> ChatCompletion {
  chat_with_text_deltas(model~, request, logger~, extra_body~, timeout_ms~)
}

///|
pub async fn chat_with_text_deltas(
  model~ : @model.Model,
  request : Request,
  logger? : @pino.Logger = @pino.logger("openai", @pino.Transport::sink()),
  extra_body? : Map[String, Json] = {},
  on_text_delta? : (String) -> Unit = _ => (),
  timeout_ms? : Int? = None,
) -> ChatCompletion {
  let run = async fn() {
    match model.model_type {
      SaaS(CodexOAuth) => chat_codex(model~, request, logger~, on_text_delta~)
      SaaS(Copilot) => chat_copilot(model~, request, logger~, on_text_delta~)
      SaaS(Anthropic) =>
        chat_anthropic(model~, request, logger~, on_text_delta~)
      _ => chat_openai(model~, request, logger~, extra_body~, on_text_delta~)
    }
  }
  match timeout_ms {
    Some(timeout_ms) if timeout_ms > 0 =>
      @async.with_timeout(timeout_ms, run) catch {
        @async.TimeoutError =>
          raise HttpError(
            code=408,
            body="Model request timed out after \{timeout_ms}ms",
          )
        error => raise error
      }
    _ => run()
  }
}

///|
/// Execute an opt-in Responses API request while preserving the Chat
/// Completions result shape used by existing MoonClaw callers. Provider-side
/// response storage remains off; MoonClaw does not infer upstream retention
/// authority from an agent transport experiment.
pub async fn responses_chat(
  model~ : @model.Model,
  request : Request,
  prompt_cache_key? : String,
  prompt_cache_mode? : String,
  prompt_cache_ttl? : String,
  reasoning_context? : String = "current_turn",
  timeout_ms? : Int? = None,
) -> ChatCompletion {
  responses_chat_with_text_deltas(
    model~,
    request,
    prompt_cache_key?,
    prompt_cache_mode?,
    prompt_cache_ttl?,
    reasoning_context~,
    timeout_ms~,
  )
}

///|
pub async fn responses_chat_with_text_deltas(
  model~ : @model.Model,
  request : Request,
  prompt_cache_key? : String,
  prompt_cache_mode? : String,
  prompt_cache_ttl? : String,
  reasoning_context? : String = "current_turn",
  on_text_delta? : (String) -> Unit = _ => (),
  timeout_ms? : Int? = None,
) -> ChatCompletion {
  let run = async fn() {
    let responses_request = openai_responses_request(
      model,
      request,
      prompt_cache_key?,
      prompt_cache_mode?,
      prompt_cache_ttl?,
      reasoning_context~,
    )
    let result = do_openai_responses_stream_request(
      model,
      responses_request,
      on_text_delta~,
    )
    responses_stream_result_to_chat_completion(model.model_name, result)
  }
  match timeout_ms {
    Some(timeout_ms) if timeout_ms > 0 =>
      @async.with_timeout(timeout_ms, run) catch {
        @async.TimeoutError =>
          raise HttpError(
            code=408,
            body="Responses request timed out after \{timeout_ms}ms",
          )
        error => raise error
      }
    _ => run()
  }
}

///|
fn openai_responses_request(
  model : @model.Model,
  request : Request,
  prompt_cache_key? : String,
  prompt_cache_mode? : String,
  prompt_cache_ttl? : String,
  reasoning_context? : String = "current_turn",
) -> @responses.ResponsesRequest {
  @responses.ResponsesRequest::new(
    model=model.model_name,
    input=convert_messages_to_input(request.messages),
    instructions=extract_system_instructions(request.messages),
    tools=convert_tools_to_responses_api(request.tools),
    reasoning_effort?=request.reasoning_effort.map(
      chat_completion_reasoning_effort_text,
    ),
    reasoning_context~,
    stream=true,
    store=false,
    prompt_cache_key?,
    prompt_cache_mode?,
    prompt_cache_ttl?,
    max_output_tokens?=request.max_tokens,
    parallel_tool_calls?=request.parallel_tool_calls,
  )
}

///|
/// Execute a chat completion request using the standard OpenAI API.
async fn chat_openai(
  model~ : @model.Model,
  request : Request,
  logger~ : @pino.Logger,
  extra_body~ : Map[String, Json],
  on_text_delta~ : (String) -> Unit,
) -> ChatCompletion {
  let route = openai_chat_route_for_model(model)
  @async.retry(
    ExponentialDelay(initial=1000, factor=2.0, maximum=16000),
    // MoonCode owns durable retries for MoonGate requests. Retrying here as
    // well multiplied one logical attempt into six immediate Ark requests and
    // made overload recovery worse. Direct API users retain the legacy retry.
    max_retry=if route.via_moongate { 0 } else { 5 },
    fatal_error=error => {
      match error {
        HttpError(code~, ..) => codex_http_status_is_fatal(code)
        HttpRetryError(code~, ..) => codex_http_status_is_fatal(code)
        _ => false
      }
    },
    () => {
      logger.debug("RequestSent", data={
        "model": { "name": model.model_name, "base_url": model.base_url },
        "route": { "url": route.url, "via_moongate": route.via_moongate },
        "request": request,
      })
      let uri = Uri::parse(route.url)
      let client = @http.Client(
        "\{uri.schema}://\{uri.host}",
        headers=route.headers,
      )
      defer client.close()
      let body = request.to_json()
      guard body is Object(body) else {
        abort("Request body is not a JSON object")
      }
      if route.via_moongate {
        body["stream"] = Json::boolean(true)
      }
      for k, v in extra_body {
        body[k] = v
      }
      let response = client.post(uri.path, Json::object(body))
      guard response.code is (200..=299) else {
        raise HttpRetryError(
          code=response.code,
          body=client.read_all().text(),
          retry_after_ms=response_retry_after_ms(response.headers),
        )
      }
      if route.via_moongate || request.stream is Some(true) {
        let reader = ChunkReader::new(client)
        let builder = ChatCompletionBuilder::new()
        while reader.read() is Some(chunk) {
          logger.debug("ChunkReceived", data={ "chunk": chunk })
          emit_text_deltas_from_chunk(chunk, on_text_delta)
          builder.add_chunk(chunk)
        }
        let chat_completion = builder.to_chat_completion()
        logger.debug("ResponseReceived", data={
          "model": { "name": model.model_name, "base_url": model.base_url },
          "response_code": response.code,
          "response_body": chat_completion,
        })
        chat_completion
      } else {
        let body = client.read_all().text()
        let json = @json.parse(body)
        let chat_completion : ChatCompletion = @json.from_json(json)
        logger.debug("ResponseReceived", data={
          "model": { "name": model.model_name, "base_url": model.base_url },
          "response_code": response.code,
          "response_body": chat_completion,
        })
        chat_completion
      }
    },
  )
}

///|
priv struct OpenAIChatRoute {
  url : String
  headers : Map[String, String]
  via_moongate : Bool
}

///|
fn openai_chat_route_for_model(model : @model.Model) -> OpenAIChatRoute {
  let via_moongate = model.base_url.contains("/openclaw/v1")
  {
    url: "\{model.base_url}/chat/completions",
    headers: if via_moongate {
      moonclaw_moongate_chat_headers()
    } else {
      openai_direct_chat_headers(model.api_key)
    },
    via_moongate,
  }
}

///|
fn openai_direct_chat_headers(api_key : String) -> Map[String, String] {
  {
    "Authorization": "Bearer \{api_key}",
    "Content-Type": "application/json",
    "Connection": "close",
    "User-Agent": "moonclaw",
  }
}

///|
fn moonclaw_moongate_chat_headers() -> Map[String, String] {
  {
    "Content-Type": "application/json",
    "Connection": "close",
    "User-Agent": "moonclaw",
  }
}

///|
async fn chat_anthropic(
  model~ : @model.Model,
  request : Request,
  logger~ : @pino.Logger,
  on_text_delta~ : (String) -> Unit,
) -> ChatCompletion {
  @async.retry(
    ExponentialDelay(initial=1000, factor=2.0, maximum=16000),
    max_retry=5,
    fatal_error=error => {
      match error {
        HttpError(code=403, ..) => true
        _ => false
      }
    },
    () => {
      logger.debug("AnthropicRequestSent", data={
        "model": { "name": model.model_name, "base_url": model.base_url },
        "request": request,
      })
      let anthropic_request = convert_to_anthropic_request(model~, request~)
      let url = "\{model.base_url}/v1/messages"
      let uri = Uri::parse(url)
      let client = @http.Client("\{uri.schema}://\{uri.host}", headers={
        "x-api-key": model.api_key,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
        "Connection": "close",
      })
      defer client.close()
      let body = anthropic_request.to_json()
      let response = client.post(uri.path, body)
      guard response.code is (200..=299) else {
        raise HttpError(code=response.code, body=client.read_all().text())
      }
      if request.stream is Some(true) {
        let reader = ChunkReader::new(client)
        let builder = ChatCompletionBuilder::new()
        while reader.read() is Some(chunk) {
          logger.debug("AnthropicChunkReceived", data={ "chunk": chunk })
          emit_text_deltas_from_chunk(chunk, on_text_delta)
          builder.add_chunk(chunk)
        }
        let chat_completion = builder.to_chat_completion()
        logger.debug("AnthropicResponseReceived", data={
          "model": { "name": model.model_name, "base_url": model.base_url },
          "response_code": response.code,
          "response_body": chat_completion,
        })
        chat_completion
      } else {
        let body = client.read_all().text()
        let json = @json.parse(body)
        let anthropic_response : AnthropicResponse = @json.from_json(json)
        let chat_completion = anthropic_response_to_chat_completion(
          anthropic_response,
        )
        logger.debug("AnthropicResponseReceived", data={
          "model": { "name": model.model_name, "base_url": model.base_url },
          "response_code": response.code,
          "response_body": chat_completion,
        })
        chat_completion
      }
    },
  )
}

///|
async fn chat_codex(
  model~ : @model.Model,
  request : Request,
  logger~ : @pino.Logger,
  on_text_delta~ : (String) -> Unit,
) -> ChatCompletion {
  let (access_token, account_id) = try {
    let creds = @codex.load_credentials()
    (creds.accessToken, creds.accountId)
  } catch {
    _ =>
      match (model.access_token, model.account_id) {
        (Some(at), Some(aid)) => (at, aid)
        _ =>
          raise HttpError(
            code=401,
            body="Missing access_token/account_id for CodexOAuth model and no saved credentials found",
          )
      }
  }
  let has_refreshed = Ref::Ref(false)
  let current_access_token = Ref::Ref(access_token)
  let current_account_id = Ref::Ref(account_id)
  @async.retry(
    ExponentialDelay(initial=1000, factor=2.0, maximum=16000),
    max_retry=5,
    fatal_error=error => {
      match error {
        HttpError(code~, ..) => codex_http_status_is_fatal(code)
        _ => false
      }
    },
    () => {
      logger.debug("CodexRequestSent", data={
        "model": { "name": model.model_name, "base_url": model.base_url },
        "request": request,
      })
      let codex_request = codex_responses_request(model, request)
      let result = do_codex_stream_request(
        current_access_token.val,
        current_account_id.val,
        codex_request,
        on_text_delta~,
      ) catch {
        HttpError(code=401, ..) as err if !has_refreshed.val => {
          logger.info("Received 401, attempting to refresh token")
          has_refreshed.val = true // Mark as refreshed to prevent infinite loop
          // Try refresh first, then re-login if refresh fails
          let refresh_result : @codex.Credentials? = Some(
            @codex.refresh_and_save_credentials(),
          ) catch {
            _ => None
          }
          match refresh_result {
            Some(refreshed) => {
              current_access_token.val = refreshed.accessToken
              current_account_id.val = refreshed.accountId
              logger.info("Token refreshed successfully, retrying request")
            }
            None => {
              logger.info("Refresh failed, triggering re-login flow")
              let new_creds = @codex.start_oauth_flow() catch {
                login_err => {
                  logger.error("Re-login failed", data={
                    "error": login_err.to_string(),
                  })
                  raise HttpError(
                    code=401,
                    body="Re-login failed: \{login_err}",
                  )
                }
              }
              current_access_token.val = new_creds.accessToken
              current_account_id.val = new_creds.accountId
              logger.info("Re-login successful, retrying request")
            }
          }
          raise err
        }
        err => raise err
      }
      let chat_completion = responses_stream_result_to_chat_completion(
        model.model_name,
        result,
      )
      logger.debug("CodexResponseReceived", data={
        "model": { "name": model.model_name, "base_url": model.base_url },
        "response": chat_completion,
      })
      chat_completion
    },
  )
}

///|
fn codex_responses_request(
  model : @model.Model,
  request : Request,
) -> @responses.ResponsesRequest {
  let input = convert_messages_to_input(request.messages)
  let requested_instructions = extract_system_instructions(request.messages)
  let instructions = if requested_instructions == "" {
    @codex.base_instructions
  } else {
    requested_instructions
  }
  let tools = convert_tools_to_responses_api(request.tools)
  @responses.ResponsesRequest::new(
    model=model.model_name,
    input~,
    instructions~,
    tools~,
    reasoning_effort?=request.reasoning_effort.map(
      chat_completion_reasoning_effort_text,
    ),
    stream=true,
    store=false,
  )
}

///|
/// Execute a chat completion request using GitHub Copilot API.
async fn chat_copilot(
  model~ : @model.Model,
  request : Request,
  logger~ : @pino.Logger,
  on_text_delta~ : (String) -> Unit,
) -> ChatCompletion {
  // Get valid credentials (auto-refresh if needed)
  let credentials = @copilot.get_valid_credentials() catch {
    err =>
      raise HttpError(
        code=401,
        body="Failed to get Copilot credentials: \{err}",
      )
  }
  let has_refreshed = Ref::Ref(false)
  let current_token = Ref::Ref(credentials.copilot_token)
  @async.retry(
    ExponentialDelay(initial=1000, factor=2.0, maximum=16000),
    max_retry=5,
    fatal_error=error => {
      match error {
        HttpError(code=403, ..) => true
        _ => false
      }
    },
    () => {
      logger.debug("CopilotRequestSent", data={
        "model": { "name": model.model_name, "base_url": model.base_url },
        "request": request,
      })
      let url = "\{model.base_url}/chat/completions"
      let uri = Uri::parse(url)
      // Check if this is an agent call (has tool/assistant messages)
      let is_agent_call = request.messages
        .iter()
        .any(fn(msg) {
          match msg {
            Tool(_) | Assistant(_) => true
            _ => false
          }
        })
      let client = @http.Client("\{uri.schema}://\{uri.host}", headers={
        "Authorization": "Bearer \{current_token.val}",
        "Content-Type": "application/json",
        "Connection": "close",
        "User-Agent": "GitHubCopilotChat/0.32.4",
        "Editor-Version": "vscode/1.105.1",
        "Editor-Plugin-Version": "copilot-chat/0.32.4",
        "Copilot-Integration-Id": "vscode-chat",
        "Openai-Intent": "conversation-edits",
        "X-Initiator": if is_agent_call {
          "agent"
        } else {
          "user"
        },
      })
      defer client.close()
      let body = request.to_json()
      let response = client.post(uri.path, body)
      guard response.code is (200..=299) else {
        let error_body = client.read_all().text()
        // Try to refresh token on 401
        if response.code == 401 && !has_refreshed.val {
          has_refreshed.val = true // Mark as refreshed to prevent infinite loop
          logger.info("Received 401, attempting to refresh Copilot token")
          let refresh_result : @copilot.Credentials? = Some(
            @copilot.refresh_and_save_credentials(),
          ) catch {
            _ => None
          }
          match refresh_result {
            Some(refreshed) => {
              current_token.val = refreshed.copilot_token
              logger.info(
                "Copilot token refreshed successfully, retrying request",
              )
            }
            None => {
              logger.info("Copilot refresh failed, triggering re-login flow")
              let new_creds = @copilot.start_oauth_flow() catch {
                login_err => {
                  logger.error("Copilot re-login failed", data={
                    "error": login_err.to_string(),
                  })
                  raise HttpError(
                    code=401,
                    body="Copilot re-login failed: \{login_err}",
                  )
                }
              }
              current_token.val = new_creds.copilot_token
              logger.info("Copilot re-login successful, retrying request")
            }
          }
          raise HttpError(code=response.code, body=error_body)
        }
        raise HttpError(code=response.code, body=error_body)
      }
      if request.stream is Some(true) {
        let reader = ChunkReader::new(client)
        let builder = ChatCompletionBuilder::new()
        while reader.read() is Some(chunk) {
          emit_text_deltas_from_chunk(chunk, on_text_delta)
          builder.add_chunk(chunk)
        }
        builder.to_chat_completion()
      } else {
        let body = client.read_all().text()
        let json = @json.parse(body)
        @json.from_json(json)
      }
    },
  )
}

///|
fn codex_http_status_is_fatal(code : Int) -> Bool {
  code >= 400 && code < 500 && code != 401 && code != 408 && code != 429
}

///|
fn convert_tools_to_responses_api(
  tools : Array[ChatCompletionToolParam],
) -> Array[Json] {
  tools.map(fn(tool) {
    match tool {
      Function(func_def) =>
        {
          "type": "function",
          "name": func_def.name,
          "description": func_def.description,
          "parameters": func_def.parameters,
        }
    }
  })
}

///|
priv struct ResponsesStreamResult {
  response_id : String
  text_chunks : Array[String]
  output_items : Array[@responses.ResponseItem]
  usage : Json?
}

///|
async fn do_codex_stream_request(
  access_token : String,
  _account_id : String,
  request : @responses.ResponsesRequest,
  on_text_delta~ : (String) -> Unit,
) -> ResponsesStreamResult raise Error {
  let client = @http.Client(
    "https://chatgpt.com",
    headers=codex_request_headers(access_token),
  )
  defer client.close()
  let body = request.to_json()
  guard body is Object(body_obj) else {
    raise HttpError(code=500, body="Invalid request body")
  }
  body_obj["stream"] = true
  let response = client.post(
    "/backend-api/codex/responses",
    Json::object(body_obj),
  )
  guard response.code is (200..=299) else {
    let error_text = client.read_all().text()
    raise HttpError(
      code=response.code,
      body="API request failed: \{error_text}",
    )
  }
  let reader = ResponseStreamEventReader::new(client)
  let text_chunks : Array[String] = []
  let output_items : Array[@responses.ResponseItem] = []
  let mut response_id = ""
  let mut usage : Json? = None
  let mut completed = false
  while reader.read() is Some(event) {
    match event {
      TextDelta(delta) => {
        text_chunks.push(delta)
        on_text_delta(delta)
      }
      OutputItemDone(item) => output_items.push(item)
      Completed(response) => {
        response_id = response_json_string(response, "id")
        usage = response_json_field(response, "usage")
        completed = true
        break
      }
      Failed(message) => raise HttpError(code=502, body=message)
    }
  }
  if !completed {
    raise HttpError(
      code=502,
      body="Responses stream ended without a completed response",
    )
  }
  { response_id, text_chunks, output_items, usage }
}

///|
fn codex_request_headers(access_token : String) -> Map[String, String] {
  {
    "Authorization": "Bearer \{access_token}",
    "Content-Type": "application/json",
    "Accept": "text/event-stream",
    "originator": "moonclaw",
    "User-Agent": "moonclaw/0.1.0",
  }
}

///|
priv struct MoonGateResponsesRoute {
  url : String
  headers : Map[String, String]
}

///|
fn moongate_responses_route_for_model(
  model : @model.Model,
) -> MoonGateResponsesRoute? {
  let trimmed = model.base_url.trim().to_owned()
  let base_url = if trimmed.has_suffix("/") {
    trimmed[:trimmed.length() - 1].to_owned()
  } else {
    trimmed
  }
  if !moongate_responses_loopback_base_url(base_url) {
    return None
  }
  Some({
    url: "\{base_url}/responses",
    headers: {
      "Content-Type": "application/json",
      "Accept": "text/event-stream",
      "Connection": "close",
      "User-Agent": "moonclaw",
    },
  })
}

///|
/// Accept the narrow URL grammar emitted by local MoonGate discovery. String
/// prefix checks alone are insufficient because an authority such as
/// `127.0.0.1:123@remote.example` also begins with a loopback-looking prefix.
fn moongate_responses_loopback_base_url(base_url : String) -> Bool {
  let prefixes = ["http://127.0.0.1:", "http://localhost:", "http://[::1]:"]
  let mut remainder = ""
  for prefix in prefixes {
    if base_url.has_prefix(prefix) {
      remainder = base_url[prefix.length():].to_owned()
      break
    }
  }
  if remainder == "" {
    return false
  }
  guard remainder.find("/") is Some(slash) else { return false }
  let port = remainder[:slash].to_owned()
  let path = remainder[slash:].to_owned()
  if port == "" || port.length() > 5 || path != "/openclaw/v1" {
    return false
  }
  port.all(character => character.is_ascii_digit())
}

///|
async fn do_openai_responses_stream_request(
  model : @model.Model,
  request : @responses.ResponsesRequest,
  on_text_delta~ : (String) -> Unit,
) -> ResponsesStreamResult raise Error {
  guard moongate_responses_route_for_model(model) is Some(route) else {
    raise HttpError(
      code=400,
      body="Responses transport requires a loopback MoonGate /openclaw/v1 endpoint",
    )
  }
  let uri = Uri::parse(route.url)
  let client = @http.Client(
    "\{uri.schema}://\{uri.host}",
    headers=route.headers,
  )
  defer client.close()
  let response = client.post(uri.path, request.to_json())
  guard response.code is (200..=299) else {
    raise HttpRetryError(
      code=response.code,
      body=client.read_all().text(),
      retry_after_ms=response_retry_after_ms(response.headers),
    )
  }
  let reader = ResponseStreamEventReader::new(client)
  let text_chunks : Array[String] = []
  let output_items : Array[@responses.ResponseItem] = []
  let mut response_id = ""
  let mut usage : Json? = None
  let mut completed = false
  while reader.read() is Some(event) {
    match event {
      TextDelta(delta) => {
        text_chunks.push(delta)
        on_text_delta(delta)
      }
      OutputItemDone(item) => output_items.push(item)
      Completed(response) => {
        response_id = response_json_string(response, "id")
        usage = response_json_field(response, "usage")
        completed = true
        break
      }
      Failed(message) => raise HttpError(code=502, body=message)
    }
  }
  if !completed {
    raise HttpError(
      code=502,
      body="Responses stream ended without a completed response",
    )
  }
  { response_id, text_chunks, output_items, usage }
}

///|
fn emit_text_deltas_from_chunk(
  chunk : ChatCompletionChunk,
  on_text_delta : (String) -> Unit,
) -> Unit {
  for choice in chunk.choices {
    match choice.delta.content {
      Some(content) if !content.is_blank() => on_text_delta(content)
      _ => ()
    }
  }
}

///|
priv enum ResponseStreamEvent {
  TextDelta(String)
  OutputItemDone(@responses.ResponseItem)
  Completed(Json)
  Failed(String)
}

///|
priv struct ResponseStreamEventReader(&@io.Reader)

///|
fn ResponseStreamEventReader::new(
  reader : &@io.Reader,
) -> ResponseStreamEventReader {
  ResponseStreamEventReader(reader)
}

///|
async fn ResponseStreamEventReader::read(
  self : ResponseStreamEventReader,
) -> ResponseStreamEvent? {
  while true {
    guard self.0.read_until("\n") is Some(line) else { return None }
    guard line is [.. "data: ", .. rest] else { continue }
    let data = rest.trim().to_owned()
    match response_stream_event_from_data(data) {
      Some(event) => return Some(event)
      None => continue
    }
  } nobreak {
    None
  }
}

///|
fn response_stream_event_from_data(data : String) -> ResponseStreamEvent? {
  if data == "[DONE]" {
    return Some(Failed("Responses stream ended without a completed response"))
  }
  let json = @json.parse(data) catch { _ => return None }
  guard json is Object(obj) else { return None }
  guard obj.get("type") is Some(String(event_type)) else { return None }
  match event_type {
    "response.output_text.delta" =>
      match obj.get("delta") {
        Some(String(delta)) => Some(TextDelta(delta))
        _ => None
      }
    "response.content_part.delta" =>
      match obj.get("delta") {
        Some(Object(delta)) =>
          match delta.get("text") {
            Some(String(text)) => Some(TextDelta(text))
            _ => None
          }
        _ => None
      }
    "response.output_item.done" =>
      match obj.get("item") {
        Some(item_json) => {
          let item : @responses.ResponseItem = @json.from_json(item_json) catch {
            _ => return None
          }
          Some(OutputItemDone(item))
        }
        None => None
      }
    "response.completed" => {
      let response = obj.get("response").unwrap_or(Json::object({}))
      if response_json_string(response, "status") == "incomplete" {
        Some(Failed(response_incomplete_message(response)))
      } else {
        Some(Completed(response))
      }
    }
    "response.failed" | "response.incomplete" | "error" =>
      Some(Failed(response_stream_error_message(obj)))
    _ => None
  }
}

///|
fn response_incomplete_message(response : Json) -> String {
  match response_json_field(response, "incomplete_details") {
    Some(Object(details)) =>
      match details.get("reason") {
        Some(String(reason)) if reason != "" =>
          "Responses request incomplete: \{reason}"
        _ => "Responses request ended incomplete"
      }
    _ => "Responses request ended incomplete"
  }
}

///|
fn response_stream_error_message(event : Map[String, Json]) -> String {
  for key in ["error", "response"] {
    if event.get(key) is Some(Object(value)) {
      if value.get("error") is Some(Object(error)) {
        if error.get("message") is Some(String(message)) {
          return message
        }
      }
      if value.get("message") is Some(String(message)) {
        return message
      }
    }
  }
  if event.get("message") is Some(String(message)) {
    message
  } else {
    "Codex response stream ended without a completed response"
  }
}

///|
fn response_json_string(response : Json, key : String) -> String {
  match response {
    Object(fields) =>
      match fields.get(key) {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
fn response_json_field(response : Json, key : String) -> Json? {
  match response {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn responses_usage_to_completion_usage(usage : Json?) -> CompletionUsage? {
  guard usage is Some(Object(fields)) else { return None }
  guard fields.get("input_tokens") is Some(Number(input_tokens, ..)) &&
    fields.get("output_tokens") is Some(Number(output_tokens, ..)) else {
    return None
  }
  let total_tokens = match fields.get("total_tokens") {
    Some(Number(value, ..)) => value.to_int()
    _ => input_tokens.to_int() + output_tokens.to_int()
  }
  let normalized : Map[String, Json] = {
    "prompt_tokens": input_tokens.to_int(),
    "completion_tokens": output_tokens.to_int(),
    "total_tokens": total_tokens,
  }
  if fields.get("input_tokens_details") is Some(details) {
    normalized["prompt_tokens_details"] = details
  }
  if fields.get("output_tokens_details") is Some(details) {
    normalized["completion_tokens_details"] = details
  }
  Some(@json.from_json(Json::object(normalized))) catch {
    _ => None
  }
}

///|
/// Extract text content from content parts array.
fn extract_text_content(
  parts : Array[ChatCompletionContentPartParam],
) -> String {
  let texts : Array[String] = []
  for part in parts {
    match part {
      Text(text_part) => texts.push(text_part.text)
      ImageUrl(_) => ()
    }
  }
  texts
  .iter()
  .fold(init="", fn(acc, t) { if acc.is_empty() { t } else { acc + "\n" + t } })
}

///|
fn convert_messages_to_input(
  messages : Array[ChatCompletionMessageParam],
) -> Array[@responses.ResponseInputItem] {
  let result : Array[@responses.ResponseInputItem] = []
  for msg in messages {
    match msg {
      System(_) => continue
      User(user_msg) => {
        let text = extract_text_content(user_msg.content)
        result.push(@responses.message_input(role="user", content=text))
      }
      Assistant(assistant_msg) => {
        let text = extract_text_content(assistant_msg.content)
        if !text.is_empty() {
          result.push(@responses.message_input(role="assistant", content=text))
        }
        for tc in assistant_msg.tool_calls {
          result.push(
            FunctionCall(
              call_id=tc.id,
              name=tc.function.name,
              arguments=tc.function.arguments.unwrap_or("{}"),
            ),
          )
        }
      }
      Tool(tool_msg) => {
        let text = extract_text_content(tool_msg.content)
        result.push(
          @responses.function_call_output(
            call_id=tool_msg.tool_call_id,
            output=text,
          ),
        )
      }
    }
  }
  result
}

///|
fn extract_system_instructions(
  messages : Array[ChatCompletionMessageParam],
) -> String {
  let instructions : Array[String] = []
  for message in messages {
    match message {
      System(system) => {
        let text = extract_text_content(system.content).trim().to_owned()
        if text != "" {
          instructions.push(text)
        }
      }
      _ => ()
    }
  }
  instructions.join("\n\n")
}

///|
fn chat_completion_reasoning_effort_text(
  effort : ChatCompletionReasoningEffort,
) -> String {
  match effort {
    None_ => "none"
    Minimal => "minimal"
    Low => "low"
    Medium => "medium"
    High => "high"
    Xhigh => "xhigh"
  }
}

///|
fn responses_stream_result_to_chat_completion(
  model_name : String,
  result : ResponsesStreamResult,
) -> ChatCompletion {
  let mut content : String? = None
  let tool_calls : Array[ChatCompletionMessageToolCall] = []
  for item in result.output_items {
    match item {
      Message(content=parts, ..) => {
        let texts = parts.map(fn(part) { part.text })
        let text = texts
          .iter()
          .fold(init="", fn(acc, t) {
            if acc.is_empty() {
              t
            } else {
              "\{acc}\n\{t}"
            }
          })
        content = Some(text)
      }
      FunctionCall(call_id~, name~, arguments~) =>
        tool_calls.push(tool_call(id=call_id, name~, arguments~))
    }
  }
  if content is None && !result.text_chunks.is_empty() {
    content = Some(
      result.text_chunks.iter().fold(init="", fn(acc, c) { acc + c }),
    )
  }
  let finish_reason = if tool_calls.is_empty() { Stop } else { ToolCalls }
  ChatCompletion::new(
    id=if result.response_id == "" {
      "responses-response"
    } else {
      result.response_id
    },
    choices=[
      ChatCompletionChoice::new(
        index=0,
        message=ChatCompletionMessage::new(content?, tool_calls~),
        finish_reason~,
      ),
    ],
    created=0,
    model=model_name,
    usage?=responses_usage_to_completion_usage(result.usage),
  )
}

///|
priv struct ChunkReader(&@io.Reader)

///|
fn ChunkReader::new(reader : &@io.Reader) -> ChunkReader {
  ChunkReader(reader)
}

///|
async fn ChunkReader::read(self : ChunkReader) -> ChatCompletionChunk? {
  while true {
    guard self.0.read_until("\n") is Some(line) else { return None }
    guard line is [.. "data: ", .. rest] else { continue }
    if rest.trim() == "[DONE]" {
      return None
    }
    let json = @json.parse(rest)
    let chunk : ChatCompletionChunk = @json.from_json(json)
    return Some(chunk)
  } nobreak {
    None
  }
}

///|
/// Generate a simple text response from a prompt.
///
/// Convenience function that sends a single user prompt to the model and returns
/// the text content of the response. Automatically handles the system message and
/// extraction of the response content.
///
/// Parameters:
/// - model: The model configuration containing API credentials and endpoint
/// - prompt: The user's prompt text
///
/// Returns the text content of the model's response.
/// Fails if the completion has no content in the message.
pub async fn text(model~ : @model.Model, prompt~ : String) -> String {
  let completion = chat(
    model~,
    chat_completion(
      model=model.model_name,
      messages=[
        system_message(content="You are a helpful assistant."),
        user_message(content=prompt),
      ],
      max_tokens=150,
      temperature=0.7,
    ),
  )
  guard completion.choices[0].message.content is Some(content) else {
    fail("No content in completion message")
  }
  content
}

///|
fn extract_first_json_block(content : String) -> String? {
  content
  .split("```json")
  .drop(1)
  .take(1)
  .next()
  .bind(block => {
    block
    .split("```")
    .take(1)
    .next()
    .map(s => s.trim(char_set=" \r\n\t").to_owned())
  })
}

///|
test "extract_first_json_block" {
  let content =
    #|Here is some text.
    #|```json
    #|{
    #|  "key": "value"
    #|}
    #|```
    #|Some more text.
    #|```json
    #|{
    #|  "another_key": "another_value"
    #|}
    #|```
  json_inspect(extract_first_json_block(content), content=[
    "{\n  \"key\": \"value\"\n}",
  ])
}

///|
/// Generate a JSON response from a prompt.
///
/// Requests the model to return a JSON object in a code block (wrapped in ```json```)
/// and extracts the first JSON block from the response.
///
/// Parameters:
/// - model: The model configuration containing API credentials and endpoint
/// - prompt: The user's prompt text requesting JSON output
///
/// Returns a parsed Json object from the model's response.
///
/// Fails if the completion has no content, no JSON code block is found in the response,
/// or the JSON cannot be parsed.
pub async fn json(model~ : @model.Model, prompt~ : String) -> Json {
  let completion = chat(
    model~,
    chat_completion(
      model=model.model_name,
      messages=[
        system_message(content="You are a helpful assistant."),
        user_message(content=prompt),
      ],
      max_tokens=150,
      temperature=0.7,
    ),
  )
  guard completion.choices[0].message.content is Some(content) else {
    fail("No content in completion message")
  }
  guard extract_first_json_block(content) is Some(content) else {
    fail("No JSON block found in completion message")
  }
  content |> @json.parse()
}

///|
/// Trait for types that can be automatically generated from structured prompts.
///
/// Types implementing this trait can describe themselves with a name, description,
/// and JSON schema, allowing the model to generate responses that conform to
/// the expected structure.
pub(open) trait Structural: @json.FromJson {
  fn name() -> String
  fn description() -> String
  fn schema() -> @schema.Schema
}

///|
/// Generate structured data from a prompt using JSON schema.
///
/// This function uses the model's JSON schema support to ensure the response
/// conforms to a specific structure defined by the type parameter `T`. The
/// response is automatically parsed and validated against the schema.
///
/// # Type Parameters
/// - `T`: A type implementing `Structural` trait that defines the expected schema
///
/// # Parameters
/// - `model`: The model configuration containing API credentials and endpoint
/// - `prompt`: The user's prompt text
///
/// # Returns
/// A value of type `T` parsed from the model's structured response
///
/// Fails if the completion has no content, the JSON cannot be parsed,
/// or the parsed JSON doesn't match the expected schema.
pub async fn[T : Structural] data(model~ : @model.Model, prompt~ : String) -> T {
  let completion = chat(
    model~,
    chat_completion(
      model=model.model_name,
      messages=[
        system_message(content="You are a helpful assistant."),
        user_message(content=prompt),
      ],
      max_tokens=150,
      temperature=0.7,
      response_format=json_schema(
        name=T::name(),
        schema=T::schema().to_json(),
        description=T::description(),
      ),
    ),
  )
  guard completion.choices[0].message.content is Some(content) else {
    fail("No content in completion message")
  }
  content |> @json.parse() |> @json.from_json()
}

///|
fn convert_to_anthropic_request(
  model~ : @model.Model,
  request~ : Request,
) -> AnthropicRequest {
  let mut system : String? = None
  let anthropic_messages : Array[AnthropicMessage] = []
  for msg in request.messages {
    match msg {
      System(sys_msg) => {
        let content = extract_text_content(sys_msg.content)
        system = Some(content)
      }
      User(user_msg) => {
        let content = extract_text_content(user_msg.content)
        anthropic_messages.push({ role: "user", content: Text(content) })
      }
      Assistant(assistant_msg) => {
        let content = extract_text_content(assistant_msg.content)
        anthropic_messages.push({ role: "assistant", content: Text(content) })
      }
      Tool(tool_msg) => {
        let content = extract_text_content(tool_msg.content)
        anthropic_messages.push({
          role: "user",
          content: Blocks([{ type_: "tool_result", text: Some(content) }]),
        })
      }
    }
  }
  let tools : Array[AnthropicTool]? = if request.tools.is_empty() {
    None
  } else {
    Some(
      request.tools.map(fn(tool) {
        match tool {
          Function(func_def) =>
            {
              name: func_def.name,
              description: Some(func_def.description),
              input_schema: func_def.parameters,
            }
        }
      }),
    )
  }
  let max_tokens = match request.max_tokens {
    Some(tokens) => tokens
    None => 4096
  }
  {
    model: model.model_name,
    max_tokens,
    messages: anthropic_messages,
    system,
    tools,
    stream: request.stream,
  }
}

///|
fn anthropic_response_to_chat_completion(
  response : AnthropicResponse,
) -> ChatCompletion {
  let mut content : String? = None
  let tool_calls : Array[ChatCompletionMessageToolCall] = []
  for block in response.content {
    match block.type_ {
      "text" => if block.text is Some(text) { content = Some(text) }
      "tool_use" =>
        if block.id is Some(id) && block.name is Some(name) {
          let args = match block.input {
            Some(input) => input.stringify()
            None => "{}"
          }
          tool_calls.push(tool_call(id~, name~, arguments=args))
        }
      _ => continue
    }
  }
  let finish_reason = if tool_calls.is_empty() { Stop } else { ToolCalls }
  ChatCompletion::new(
    id=response.id,
    choices=[
      ChatCompletionChoice::new(
        index=0,
        message=ChatCompletionMessage::new(content?, tool_calls~),
        finish_reason~,
      ),
    ],
    created=0,
    model=response.model,
  )
}
