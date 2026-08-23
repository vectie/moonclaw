///|
/// Parameters accepted by the chat completion endpoint.
/// This is the request type
/// ```mbt no check
/// let uri = Uri::parse(url)
/// let client = @http.Client::connect(uri.host, protocol=uri.protocol, headers={
///   "Authorization": "Bearer \{model.api_key}",
///   "Content-Type": "application/json",
///   "Connection": "close",
/// })
/// defer client.close()
/// let response = client.post(uri.path, (request : ChatCompletionParam).to_json())
/// ```
pub struct Request {
  model : String
  messages : Array[ChatCompletionMessageParam]
  tools : Array[ChatCompletionToolParam]
  usage : CompletionUsageParam?
  user : String?
  max_tokens : Int?
  temperature : Double?
  reasoning_effort : ChatCompletionReasoningEffort?
  response_format : ResponseFormat?
  stream : Bool?
  stream_options : ChatCompletionStreamOptionsParam?
  tool_choice : ChatCompletionToolChoice?
  parallel_tool_calls : Bool?
}

///|
/// Produce a progressively smaller retry payload after a provider reports
/// overload. The original request remains intact, so each tier is deterministic
/// and a recovered provider still receives the complete task contract plus a
/// valid assistant/tool transcript. Only previously consumed tool evidence and
/// redundant tool schemas are reduced.
pub fn Request::compact_for_overload(self : Request, tier : Int) -> Request {
  if tier <= 0 {
    return self
  }
  let bounded_tier = tier.min(7)
  let tool_names : Map[String, String] = Map([])
  for message in self.messages {
    match message {
      Assistant(param) =>
        for call in param.tool_calls {
          tool_names[call.id] = call.function.name
        }
      _ => ()
    }
  }
  let recent_read_tool_ids = overload_recent_read_tool_ids(self.messages, 1)
  let compacted_messages : Array[ChatCompletionMessageParam] = []
  for message in self.messages {
    match message {
      Tool(param) => {
        let tool_name = tool_names.get(param.tool_call_id).unwrap_or("tool")
        let limit = if tool_name == "read" &&
          recent_read_tool_ids.contains(param.tool_call_id) {
          overload_recent_read_evidence_limit(bounded_tier)
        } else {
          overload_tool_evidence_limit(tool_name, bounded_tier)
        }
        let content : Array[ChatCompletionContentPartParam] = []
        for part in param.content {
          match part {
            Text(text) =>
              content.push(
                Text({
                  text: overload_compact_text(text.text, limit, tool_name),
                  cache_control: text.cache_control,
                }),
              )
            ImageUrl(image) =>
              if bounded_tier >= 3 && image.url.has_prefix("data:image/") {
                content.push(
                  Text({
                    text: "[MoonCode omitted previously delivered image bytes from overload retry tier 3; the image path and durable receipt remain in the session journal]",
                    cache_control: None,
                  }),
                )
              } else {
                content.push(ImageUrl(image))
              }
          }
        }
        compacted_messages.push(
          Tool({ content, tool_call_id: param.tool_call_id }),
        )
      }
      _ => compacted_messages.push(message)
    }
  }
  let messages = overload_compact_transcript(compacted_messages, bounded_tier)
  let tools = if bounded_tier >= 7 {
    self.tools.filter(tool => overload_retry_tool_is_emergency(tool))
  } else if bounded_tier >= 6 {
    self.tools.filter(tool => overload_retry_tool_is_continuation(tool))
  } else if bounded_tier >= 4 {
    self.tools.filter(tool => overload_retry_tool_is_minimal(tool))
  } else if bounded_tier >= 2 {
    self.tools.filter(tool => overload_retry_tool_is_essential(tool))
  } else {
    self.tools
  }
  {
    model: self.model,
    messages,
    tools,
    usage: self.usage,
    user: self.user,
    max_tokens: self.max_tokens,
    temperature: self.temperature,
    reasoning_effort: self.reasoning_effort,
    response_format: self.response_format,
    stream: self.stream,
    stream_options: self.stream_options,
    tool_choice: self.tool_choice,
    parallel_tool_calls: self.parallel_tool_calls,
  }
}

///|
/// Keep the source bodies from the most recent model tool batch usable during
/// overload retries. Truncating the active working set makes the model re-read
/// the same files after every recovered request, while retaining multiple full
/// batches can make stronger retry tiers larger than weaker ones.
fn overload_recent_read_tool_ids(
  messages : Array[ChatCompletionMessageParam],
  batch_count : Int,
) -> Map[String, Bool] {
  let batches : Array[Array[String]] = []
  for message in messages {
    match message {
      Assistant(param) if !param.tool_calls.is_empty() => {
        let ids : Array[String] = []
        for call in param.tool_calls {
          if call.function.name == "read" {
            ids.push(call.id)
          }
        }
        batches.push(ids)
      }
      _ => ()
    }
  }
  let retained : Map[String, Bool] = Map([])
  let start = (batches.length() - batch_count).max(0)
  for index in start..<batches.length() {
    for id in batches[index] {
      retained[id] = true
    }
  }
  retained
}

///|
/// Prefer the active source batch over older evidence without letting it defeat
/// stronger overload tiers. Even the emergency tier retains enough head/tail
/// context to identify the file and current edit site.
const OVERLOAD_TIER_ONE_RECENT_READ_CHARS : Int = 12000

///|
fn overload_recent_read_evidence_limit(tier : Int) -> Int {
  match tier {
    1 => OVERLOAD_TIER_ONE_RECENT_READ_CHARS
    2 => 8000
    3 => 6000
    4 => 4000
    5 => 3000
    6 => 2000
    _ => 1200
  }
}

///|
fn overload_tool_evidence_limit(tool_name : String, tier : Int) -> Int {
  match tier {
    1 =>
      if tool_name == "read_skill" {
        6000
      } else if tool_name == "read" {
        6000
      } else {
        4000
      }
    2 =>
      if tool_name == "read_skill" || tool_name == "read" {
        3000
      } else {
        2000
      }
    3 =>
      if tool_name == "read_skill" || tool_name == "read" {
        1200
      } else {
        800
      }
    4 =>
      if tool_name == "read_skill" || tool_name == "read" {
        600
      } else {
        400
      }
    5 =>
      if tool_name == "read_skill" || tool_name == "read" {
        300
      } else {
        200
      }
    6 =>
      if tool_name == "read_skill" || tool_name == "read" {
        160
      } else {
        100
      }
    _ => if tool_name == "read_skill" || tool_name == "read" { 80 } else { 60 }
  }
}

///|
/// At the strongest overload tiers, retain the complete system/task contract
/// and a recent valid assistant/tool suffix. The full omitted transcript stays
/// in the durable journal and is restored automatically on the next planner
/// turn; this is transport shaping, not task-state mutation.
fn overload_compact_transcript(
  messages : Array[ChatCompletionMessageParam],
  tier : Int,
) -> Array[ChatCompletionMessageParam] {
  if tier < 4 {
    return messages
  }
  let suffix_count = if tier >= 6 { 4 } else if tier >= 5 { 6 } else { 12 }
  if messages.length() <= suffix_count + 4 {
    return messages
  }
  let mut suffix_start = messages.length() - suffix_count
  if tier >= 6 {
    // Emergency retries need the latest complete assistant/tool exchange,
    // not an arbitrary suffix which may begin in the middle of tool results.
    // The latest read batch remains intact through
    // `overload_recent_read_tool_ids`; retaining an additional full exchange
    // can make a stronger compaction tier larger than the preceding tier.
    let mut latest_tool_batch = -1
    for index in 0..<messages.length() {
      match messages[index] {
        Assistant(param) if !param.tool_calls.is_empty() =>
          latest_tool_batch = index
        _ => ()
      }
    }
    if latest_tool_batch >= 0 {
      suffix_start = latest_tool_batch
    }
  } else {
    while suffix_start < messages.length() {
      match messages[suffix_start] {
        Assistant(param) if !param.tool_calls.is_empty() => break
        _ => suffix_start += 1
      }
    }
  }
  if suffix_start >= messages.length() {
    return messages
  }
  let retained : Array[ChatCompletionMessageParam] = []
  let mut retained_task = false
  for index in 0..<suffix_start {
    match messages[index] {
      System(_) => retained.push(messages[index])
      User(_) if !retained_task => {
        retained.push(messages[index])
        retained_task = true
      }
      _ => ()
    }
  }
  retained.push(
    user_message(
      content="MoonCode compacted \{suffix_start - retained.length()} older transport messages after repeated provider overload. The complete evidence and checkpoint remain in the durable journal. Continue the retained mission from the recent valid suffix without repeating discovery.",
    ),
  )
  for index in suffix_start..<messages.length() {
    retained.push(messages[index])
  }
  retained
}

///|
fn overload_compact_text(
  text : String,
  limit : Int,
  tool_name : String,
) -> String {
  if text.length() <= limit {
    return text
  }
  let head_size = limit * 2 / 3
  let tail_size = limit - head_size
  let head = openai_utf8_prefix_within(text, head_size)
  let tail = openai_utf8_suffix_within(text, tail_size)
  let omitted = text.length() - head.length() - tail.length()
  head +
  "\n...[MoonCode compacted \{omitted} chars of previously consumed `\{tool_name}` evidence for an overloaded-provider retry; complete bytes remain in the durable journal]...\n" +
  tail
}

///|
fn openai_utf8_prefix_within(text : String, limit : Int) -> String {
  if limit <= 0 {
    return ""
  }
  let bytes = @encoding/utf8.encode(text)
  if bytes.length() <= limit {
    return text
  }
  let mut end = limit.min(bytes.length())
  while end > 0 {
    let decoded = Some(@encoding/utf8.decode(bytes[:end])) catch { _ => None }
    match decoded {
      Some(value) => return value
      None => end -= 1
    }
  }
  ""
}

///|
fn openai_utf8_suffix_within(text : String, limit : Int) -> String {
  if limit <= 0 {
    return ""
  }
  let bytes = @encoding/utf8.encode(text)
  if bytes.length() <= limit {
    return text
  }
  let mut start = (bytes.length() - limit).max(0)
  while start < bytes.length() {
    let decoded = Some(@encoding/utf8.decode(bytes[start:])) catch { _ => None }
    match decoded {
      Some(value) => return value
      None => start += 1
    }
  }
  ""
}

///|
fn overload_retry_tool_is_essential(tool : ChatCompletionToolParam) -> Bool {
  match tool {
    Function(definition) =>
      definition.name != "moon_check" &&
      definition.name != "spawn_workers" &&
      definition.name != "wait_workers"
  }
}

///|
fn overload_retry_tool_is_minimal(tool : ChatCompletionToolParam) -> Bool {
  match tool {
    Function(definition) =>
      definition.name == "read" ||
      definition.name == "edit" ||
      definition.name == "shell" ||
      definition.name == "browser" ||
      definition.name == "moon_cmd" ||
      definition.name == "finish" ||
      definition.name == "apply_patch" ||
      definition.name == "checkpoint"
  }
}

///|
fn overload_retry_tool_is_continuation(tool : ChatCompletionToolParam) -> Bool {
  match tool {
    Function(definition) =>
      definition.name == "read" ||
      definition.name == "edit" ||
      definition.name == "write" ||
      definition.name == "shell" ||
      definition.name == "finish" ||
      definition.name == "apply_patch" ||
      definition.name == "checkpoint"
  }
}

///|
fn overload_retry_tool_is_emergency(tool : ChatCompletionToolParam) -> Bool {
  match tool {
    Function(definition) =>
      definition.name == "read" ||
      definition.name == "edit" ||
      definition.name == "shell" ||
      definition.name == "finish" ||
      definition.name == "apply_patch"
  }
}

///|
pub impl ToJson for Request with fn to_json(self : Request) -> Json {
  let json : Map[String, Json] = {
    "model": Json::string(self.model),
    "messages": self.messages,
  }
  if !self.tools.is_empty() {
    json["tools"] = self.tools.to_json()
  }
  if self.usage is Some(usage) {
    json["usage"] = ToJson::to_json(usage)
  }
  if self.user is Some(user) {
    json["user"] = Json::string(user)
  }
  if self.max_tokens is Some(max_tokens) {
    json["max_tokens"] = max_tokens.to_json()
  }
  if self.temperature is Some(temperature) {
    json["temperature"] = temperature.to_json()
  }
  if self.reasoning_effort is Some(reasoning_effort) {
    json["reasoning_effort"] = ToJson::to_json(reasoning_effort)
  }
  if self.response_format is Some(response_format) {
    json["response_format"] = response_format.to_json()
  }
  if self.stream is Some(stream) {
    json["stream"] = stream.to_json()
  }
  if self.stream_options is Some(stream_options) {
    json["stream_options"] = stream_options.to_json()
  }
  if self.parallel_tool_calls is Some(parallel_tool_calls) {
    json["parallel_tool_calls"] = parallel_tool_calls.to_json()
  }
  Json::object(json)
}
