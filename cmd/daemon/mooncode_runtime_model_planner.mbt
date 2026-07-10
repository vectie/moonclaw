///|
async fn Daemon::mooncode_runtime_turn_plan_tool_calls(
  self : Daemon,
  command : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let explicit = mooncode_runtime_turn_explicit_tool_calls(command)
  if explicit.length() > 0 {
    return {
      "kind": mooncode_kind_runtime_turn_planner(),
      "protocol": mooncode_protocol_version(),
      "planner_mode": "explicit-tool-calls",
      "tool_calls": Json::array(explicit),
      "events": Json::array([]),
    }
  }
  let deterministic = mooncode_runtime_turn_deterministic_preplan(command)
  if deterministic.length() > 0 {
    return {
      "kind": mooncode_kind_runtime_turn_planner(),
      "protocol": mooncode_protocol_version(),
      "planner_mode": mooncode_planner_mode_deterministic_fallback(),
      "tool_calls": Json::array(deterministic),
      "events": Json::array([]),
    }
  }
  let model_name = mooncode_runtime_turn_requested_model(command)
  if model_name == "" || !mooncode_runtime_turn_model_planning_allowed(command) {
    return {
      "kind": mooncode_kind_runtime_turn_planner(),
      "protocol": mooncode_protocol_version(),
      "planner_mode": mooncode_planner_mode_deterministic_fallback(),
      "tool_calls": Json::array([]),
      "events": Json::array([]),
    }
  }
  let session_id = mooncode_json_string(command, "session_id", default="")
  let command_id = mooncode_command_id(command)
  let started = mooncode_event(
    session_id~,
    command_id~,
    lane="runtime",
    kind="runtime.planner_started",
    title="MoonCode model planner started",
    status="running",
    detail="MoonClaw is asking model `\{model_name}` to choose one bounded MoonCode tool batch.",
    now~,
  )
  let requested_model : String? = Some(model_name)
  match self.models.get_model(name?=requested_model) {
    Some(model) => {
      let request = mooncode_runtime_turn_model_plan_request(
        model.model_name,
        command,
      )
      let completion = mooncode_runtime_turn_model_chat(model, request, command) catch {
        error =>
          return mooncode_runtime_turn_failed_planner_result(
            command,
            model_name,
            "model planner failed: \{@openai.error_summary(error)}",
            started,
            now~,
          )
      }
      let tool_calls = mooncode_runtime_turn_tool_calls_from_model_response(
        completion.to_json(),
      )
      if tool_calls.length() == 0 {
        return mooncode_runtime_turn_failed_planner_result(
          command,
          model_name,
          "model planner returned no usable MoonCode tool calls",
          started,
          now~,
        )
      }
      let selected = mooncode_event(
        session_id~,
        command_id~,
        lane="runtime",
        kind="runtime.planner_selected",
        title="MoonCode model planner selected tools",
        status="done",
        detail="Model `\{model_name}` selected \{tool_calls.length()} MoonCode tool call(s).",
        now~,
      )
      {
        "kind": mooncode_kind_runtime_turn_planner(),
        "protocol": mooncode_protocol_version(),
        "planner_mode": mooncode_planner_mode_model_tool_calls(),
        "model": model_name,
        "tool_call_count": tool_calls.length(),
        "tool_calls": Json::array(tool_calls),
        "events": Json::array([started, selected]),
        "model_messages": Json::array(
          mooncode_runtime_turn_model_initial_messages(command),
        ),
        "model_response_message": mooncode_runtime_turn_model_response_message(
          completion.to_json(),
        ),
      }
    }
    None =>
      mooncode_runtime_turn_failed_planner_result(
        command,
        model_name,
        "model planner unavailable: model not found",
        started,
        now~,
      )
  }
}

///|
fn mooncode_runtime_turn_explicit_tool_calls(command : Json) -> Array[Json] {
  let explicit = mooncode_json_array_items(command, "runtime_tool_calls")
  if explicit.length() > 0 {
    return explicit
  }
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  mooncode_json_array_items(packet, "runtime_tool_calls")
}

///|
fn mooncode_runtime_turn_model_planning_allowed(command : Json) -> Bool {
  let action = mooncode_json_string(command, "command", default="prompt")
  action == "prompt" || action == "steer" || action == "package"
}

///|
fn mooncode_runtime_turn_requires_model_planning(command : Json) -> Bool {
  mooncode_runtime_turn_explicit_tool_calls(command).length() == 0 &&
  mooncode_runtime_turn_deterministic_preplan(command).length() == 0 &&
  mooncode_runtime_turn_requested_model(command) != "" &&
  mooncode_runtime_turn_model_planning_allowed(command)
}

///|
fn mooncode_runtime_turn_requested_model(command : Json) -> String {
  let model = mooncode_json_string(command, "model", default="")
  if model != "" {
    return model
  }
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let model = mooncode_json_string(payload, "model", default="")
  if model != "" {
    return model
  }
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let model = mooncode_json_string(packet, "model", default="")
  if model != "" {
    return model
  }
  let packet_payload = mooncode_json_object_field_or_empty(packet, "payload")
  mooncode_json_string(packet_payload, "model", default="")
}

///|
fn mooncode_runtime_turn_model_timeout_ms(command : Json) -> Int {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let timeout = mooncode_json_int(payload, "planner_timeout_ms", default=30000)
  if timeout < 1000 {
    1000
  } else if timeout > 120000 {
    120000
  } else {
    timeout
  }
}

///|
fn mooncode_runtime_turn_model_timeout_for_provider(
  model : @model.Model,
  command : Json,
) -> Int? {
  match model.model_type {
    SaaS(CodexOAuth) => None
    _ => Some(mooncode_runtime_turn_model_timeout_ms(command))
  }
}

///|
async fn mooncode_runtime_turn_model_chat(
  model : @model.Model,
  request : @openai.Request,
  command : Json,
) -> @openai.ChatCompletion {
  match mooncode_runtime_turn_model_timeout_for_provider(model, command) {
    Some(timeout_ms) =>
      @openai.chat(model~, request, timeout_ms=Some(timeout_ms))
    None => @openai.chat(model~, request)
  }
}

///|
fn mooncode_runtime_turn_model_max_steps(command : Json) -> Int {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let requested = mooncode_json_int(payload, "planner_max_steps", default=3)
  if requested < 1 {
    1
  } else if requested > 8 {
    8
  } else {
    requested
  }
}

///|
fn mooncode_runtime_turn_model_plan_request(
  model_name : String,
  command : Json,
) -> @openai.Request raise {
  mooncode_runtime_turn_model_plan_request_from_messages(
    model_name,
    mooncode_runtime_turn_model_initial_messages(command),
    tools=mooncode_runtime_turn_model_tools_for_command(command),
  )
}

///|
fn mooncode_runtime_turn_model_plan_request_from_messages(
  model_name : String,
  message_jsons : Array[Json],
  tools? : Array[@openai.ChatCompletionToolParam] = mooncode_runtime_turn_model_tools(),
) -> @openai.Request raise {
  let messages : Array[@openai.ChatCompletionMessageParam] = @json.from_json(
    Json::array(message_jsons),
  )
  @openai.chat_completion(
    model=model_name,
    messages~,
    tools~,
    max_tokens=1200,
    reasoning_effort=None_,
    temperature=0.0,
  )
}

///|
fn mooncode_runtime_turn_model_tools_for_command(
  command : Json,
) -> Array[@openai.ChatCompletionToolParam] {
  let tools = mooncode_runtime_turn_model_tools()
  let request = mooncode_runtime_turn_prompt_text(command)
    .to_lower()
    .to_string()
  let path = mooncode_runtime_turn_prompt_path(
    mooncode_runtime_turn_prompt_text(command),
  )
  if path != "" && mooncode_runtime_turn_read_needs_model(request) {
    return [tools[0], tools[7]]
  }
  if mooncode_runtime_turn_model_needs_coding_tools(command, request) {
    return tools
  }
  [tools[7]]
}

///|
fn mooncode_runtime_turn_model_needs_coding_tools(
  command : Json,
  request : String,
) -> Bool {
  let action = mooncode_json_string(command, "command", default="prompt")
  action == "package" ||
  request.contains("implement") ||
  request.contains("fix ") ||
  request.contains("debug") ||
  request.contains("refactor") ||
  request.contains("edit ") ||
  request.contains("write ") ||
  request.contains("create ") ||
  request.contains("build ") ||
  request.contains("test ") ||
  request.contains("code") ||
  request.contains("script") ||
  request.contains("tool") ||
  request.contains("app") ||
  request.contains("site")
}

///|
fn mooncode_runtime_turn_model_initial_messages(command : Json) -> Array[Json] {
  [
    {
      "role": "system",
      "content": "You are MoonClaw's MoonCode planner. Choose bounded MoonCode tool batches to satisfy the user's request inside the selected MoonBook only. Prefer semantic MoonBit discovery with moon_ide before broad source reads, and prefer moon_cmd/moon_check over raw shell for MoonBit validation. Use write/edit/read/shell/moon_ide/moon_cmd/moon_check/finish. Never use paths outside the MoonBook root. Call `finish` only when the task is complete; otherwise use tools and wait for tool results before deciding the next batch.",
    },
    { "role": "user", "content": mooncode_runtime_turn_model_prompt(command) },
  ]
}

///|
fn mooncode_runtime_turn_model_prompt(command : Json) -> String {
  let action = mooncode_json_string(command, "command", default="prompt")
  let request = mooncode_runtime_turn_prompt_text(command).trim().to_owned()
  let context_path = mooncode_json_string(command, "context_path", default="")
  let deferred = mooncode_json_array_items(command, "deferred_steering")
  let context = if context_path == "" {
    "No file is preselected."
  } else {
    "Selected context: `\{context_path}`."
  }
  let steering = if deferred.length() == 0 {
    ""
  } else {
    "\nDeferred steering: " + Json::array(deferred).stringify()
  }
  "Action: \{action}\n" +
  "User request: \{request}\n" +
  context +
  "\nWeb search allowed: \{mooncode_command_web_search(command)}." +
  steering +
  "\n\nChoose the smallest useful tool batch. Use finish immediately when no code or tool work is needed. Keep all paths relative to the selected MoonBook."
}

///|
fn mooncode_runtime_turn_model_tools() -> Array[@openai.ChatCompletionToolParam] {
  [
    mooncode_runtime_turn_model_tool(
      "read",
      "Read a file inside the selected MoonBook.",
      {
        "type": "object",
        "properties": {
          "path": { "type": "string" },
          "max_output_chars": { "type": "integer" },
        },
        "required": ["path"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "write",
      "Write a complete file inside the selected MoonBook.",
      {
        "type": "object",
        "properties": {
          "path": { "type": "string" },
          "content": { "type": "string" },
        },
        "required": ["path", "content"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "edit",
      "Replace text in an existing MoonBook file.",
      {
        "type": "object",
        "properties": {
          "path": { "type": "string" },
          "old_string": { "type": "string" },
          "new_string": { "type": "string" },
          "replace_all": { "type": "boolean" },
        },
        "required": ["path", "old_string", "new_string"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "shell",
      "Run a bounded shell command inside the selected MoonBook.",
      {
        "type": "object",
        "properties": {
          "cmd": { "type": "string" },
          "cwd": { "type": "string" },
          "timeout_ms": { "type": "integer" },
          "max_output_chars": { "type": "integer" },
        },
        "required": ["cmd"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "moon_ide",
      "Run read-only MoonBit semantic navigation inside the selected MoonBook.",
      {
        "type": "object",
        "properties": {
          "action": {
            "type": "string",
            "enum": ["doc", "outline", "peek_def", "hover", "find_references"],
          },
          "query": { "type": "string" },
          "path": { "type": "string" },
          "loc": { "type": "string" },
          "target": { "type": "string" },
          "no_check": { "type": "boolean" },
          "max_output_chars": { "type": "integer" },
        },
        "required": ["action"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "moon_cmd",
      "Run a structured MoonBit command inside the selected MoonBook.",
      {
        "type": "object",
        "properties": {
          "command": {
            "type": "string",
            "enum": ["check", "test", "run", "info", "fmt", "build"],
          },
          "cwd": { "type": "string" },
          "target": { "type": "string" },
          "arg": { "type": "string" },
          "args": { "type": "array", "items": { "type": "string" } },
          "path": { "type": "string" },
          "paths": { "type": "array", "items": { "type": "string" } },
          "program_args": { "type": "array", "items": { "type": "string" } },
          "test_update_kind": { "type": "string" },
          "test_update_reason": { "type": "string" },
          "timeout_ms": { "type": "integer" },
          "max_output_chars": { "type": "integer" },
        },
        "required": ["command"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "moon_check",
      "Run moon check inside the selected MoonBook.",
      {
        "type": "object",
        "properties": {
          "target": { "type": "string" },
          "timeout_ms": { "type": "integer" },
          "max_output_chars": { "type": "integer" },
        },
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "finish",
      "Finish the turn with a concise operator-facing summary.",
      {
        "type": "object",
        "properties": { "answer": { "type": "string" } },
        "required": ["answer"],
        "additionalProperties": false,
      },
    ),
  ]
}

///|
fn mooncode_runtime_turn_model_tool(
  name : String,
  description : String,
  parameters : Json,
) -> @openai.ChatCompletionToolParam {
  @openai.tool(name~, description~, parameters~, strict=true)
}

///|
fn mooncode_runtime_turn_tool_calls_from_model_response(
  response : Json,
) -> Array[Json] {
  let calls : Array[Json] = []
  let choices = match response {
    { "choices": Array(items), .. } => items
    _ => []
  }
  if choices.length() == 0 {
    return calls
  }
  let message = mooncode_json_object_field_or_empty(choices[0], "message")
  for call in mooncode_json_array_items(message, "tool_calls") {
    let function = mooncode_json_object_field_or_empty(call, "function")
    let tool = mooncode_json_string(function, "name", default="")
    let arguments_text = mooncode_json_string(function, "arguments", default="")
    let arguments = @json.parse(arguments_text) catch { _ => Json::object({}) }
    if mooncode_tool_supported(tool) {
      calls.push({
        "tool": tool,
        "arguments": arguments,
        "tool_call_id": mooncode_json_string(call, "id", default=""),
        "planner": "model-tool-call",
      })
    }
  }
  if calls.length() == 0 {
    let content = mooncode_json_string(message, "content", default="")
      .trim()
      .to_owned()
    if content != "" {
      calls.push({
        "tool": "finish",
        "arguments": { "answer": content },
        "tool_call_id": "model-assistant-content-finish",
        "planner": "model-assistant-content",
      })
    }
  }
  calls
}

///|
async fn Daemon::mooncode_runtime_turn_model_followup_plan(
  self : Daemon,
  command : Json,
  previous_plan : Json,
  tool_calls : Array[Json],
  tool_results : Array[Json],
  now~ : @clock.Timestamp,
) -> Json {
  let model_name = mooncode_json_string(previous_plan, "model", default="")
  let session_id = mooncode_json_string(command, "session_id", default="")
  let command_id = mooncode_command_id(command)
  let started = mooncode_event(
    session_id~,
    command_id~,
    lane="runtime",
    kind="runtime.planner_started",
    title="MoonCode model planner continued",
    status="running",
    detail="MoonClaw is feeding tool results back to model `\{model_name}` for another bounded MoonCode tool batch.",
    now~,
  )
  let previous_messages = mooncode_json_array_items(
    previous_plan, "model_messages",
  )
  let response_message = mooncode_json_object_field_or_empty(
    previous_plan, "model_response_message",
  )
  if model_name == "" ||
    previous_messages.length() == 0 ||
    !mooncode_runtime_turn_model_message_present(response_message) {
    return mooncode_runtime_turn_failed_planner_result(
      command,
      model_name,
      "model planner cannot continue: missing prior model transcript",
      started,
      now~,
    )
  }
  let messages = previous_messages
  messages.push(response_message)
  for index in 0..<tool_calls.length() {
    if index < tool_results.length() {
      messages.push(
        mooncode_runtime_turn_model_tool_result_message(
          tool_calls[index],
          tool_results[index],
        ),
      )
    }
  }
  let requested_model : String? = Some(model_name)
  match self.models.get_model(name?=requested_model) {
    Some(model) => {
      let request = mooncode_runtime_turn_model_plan_request_from_messages(
        model.model_name,
        messages,
        tools=mooncode_runtime_turn_model_tools_for_command(command),
      )
      let completion = mooncode_runtime_turn_model_chat(model, request, command) catch {
        error =>
          return mooncode_runtime_turn_failed_planner_result(
            command,
            model_name,
            "model planner follow-up failed: \{@openai.error_summary(error)}",
            started,
            now~,
          )
      }
      let response_json = completion.to_json()
      let next_tool_calls = mooncode_runtime_turn_tool_calls_from_model_response(
        response_json,
      )
      if next_tool_calls.length() == 0 {
        return mooncode_runtime_turn_failed_planner_result(
          command,
          model_name,
          "model planner follow-up returned no usable MoonCode tool calls",
          started,
          now~,
        )
      }
      let selected = mooncode_event(
        session_id~,
        command_id~,
        lane="runtime",
        kind="runtime.planner_selected",
        title="MoonCode model planner continued with tools",
        status="done",
        detail="Model `\{model_name}` selected \{next_tool_calls.length()} follow-up MoonCode tool call(s).",
        now~,
      )
      {
        "kind": mooncode_kind_runtime_turn_planner(),
        "protocol": mooncode_protocol_version(),
        "planner_mode": mooncode_planner_mode_model_tool_calls(),
        "model": model_name,
        "tool_call_count": next_tool_calls.length(),
        "tool_calls": Json::array(next_tool_calls),
        "events": Json::array([started, selected]),
        "model_messages": Json::array(messages),
        "model_response_message": mooncode_runtime_turn_model_response_message(
          response_json,
        ),
      }
    }
    None =>
      mooncode_runtime_turn_failed_planner_result(
        command,
        model_name,
        "model planner follow-up unavailable: model not found",
        started,
        now~,
      )
  }
}

///|
fn mooncode_runtime_turn_model_response_message(response : Json) -> Json {
  let choices = match response {
    { "choices": Array(items), .. } => items
    _ => []
  }
  if choices.length() == 0 {
    return {}
  }
  let message = mooncode_json_object_field_or_empty(choices[0], "message")
  {
    "role": "assistant",
    "content": mooncode_json_string(message, "content", default=""),
    "tool_calls": Json::array(mooncode_json_array_items(message, "tool_calls")),
  }
}

///|
fn mooncode_runtime_turn_model_message_present(message : Json) -> Bool {
  mooncode_json_array_items(message, "tool_calls").length() > 0 ||
  mooncode_json_string(message, "content", default="") != ""
}

///|
fn mooncode_runtime_turn_model_tool_result_message(
  tool_call : Json,
  execution : Json,
) -> Json {
  {
    "role": "tool",
    "tool_call_id": mooncode_json_string(tool_call, "tool_call_id", default=""),
    "content": mooncode_runtime_turn_model_tool_result_content(execution),
  }
}

///|
fn mooncode_runtime_turn_model_tool_result_content(execution : Json) -> String {
  let result = mooncode_json_object_field_or_empty(execution, "result")
  let text = result.stringify(indent=2)
  if text.length() > 12000 {
    text[:12000].to_owned() + "\n...[truncated]"
  } else {
    text
  }
}

///|
fn mooncode_runtime_turn_tool_calls_include_finish(
  tool_calls : Array[Json],
) -> Bool {
  for tool_call in tool_calls {
    if mooncode_json_string(tool_call, "tool", default="") == "finish" {
      return true
    }
  }
  false
}
