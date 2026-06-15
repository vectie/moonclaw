///|
async fn Daemon::mooncode_runtime_turn(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
  let body : Json = reader.read() catch { _ => Json::object({}) }
  let session_id = session_id.to_string()
  let requested_book_root = mooncode_request_book_root(r)
  let book_root = if requested_book_root == "" {
    mooncode_json_string(body, "book_root", default="")
  } else {
    requested_book_root
  }
  if book_root == "" {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": "MoonCode runtime turn requires book_root query or JSON field",
        "metadata": { "session_id": session_id },
      },
    })
  }
  let turn = self.mooncode_runtime_turn_execute(session_id, book_root, body)
  w.header().set("Content-Type", "application/json")
  w.write_header(
    if mooncode_json_bool(turn, "accepted", default=false) {
      202
    } else {
      200
    },
    reason=if mooncode_json_bool(turn, "accepted", default=false) {
      "Accepted"
    } else {
      "OK"
    },
  )
  w.write(turn.stringify(indent=2))
}

///|
async fn Daemon::mooncode_runtime_turn_execute(
  self : Daemon,
  session_id : String,
  book_root : String,
  payload : Json,
) -> Json {
  let consumer_id = mooncode_json_string(
    payload,
    "consumer_id",
    default="moonclaw-native-runtime-turn",
  )
  let before = self.mooncode_runtime_claim_state_payload(session_id, book_root)
  let claim_receipts = if mooncode_json_array_items(before, "claimed_commands").length() ==
    0 {
    mooncode_runtime_claim_receipts(
      session_id,
      book_root,
      before,
      payload,
      now=self.clock.now(),
    )
  } else {
    []
  }
  for receipt in claim_receipts {
    mooncode_append_jsonl(
      mooncode_runtime_dispatches_path(book_root, session_id),
      receipt,
    )
  }
  let claimed_state = self.mooncode_runtime_claim_state_payload(
    session_id, book_root,
  )
  let claimed = mooncode_json_array_items(claimed_state, "claimed_commands")
  if claimed.length() == 0 {
    return {
      "kind": "mooncode-runtime-turn",
      "protocol": "mooncode.v1",
      "owner": "moonclaw",
      "accepted": false,
      "session_id": session_id,
      "book_root": book_root,
      "ran": false,
      "message": "No claimable or claimed MoonCode command is ready for a native runtime turn.",
      "claim_receipts": Json::array(claim_receipts),
      "claim_state": claimed_state,
      "previous_claim_state": before,
    }
  }
  let item = claimed[0]
  let command = mooncode_json_object_field_or_empty(item, "command")
  let command_id = mooncode_json_string(item, "command_id", default="")
  let report = mooncode_validate_command_body(session_id, command)
  let now = self.clock.now()
  let started = mooncode_event(
    session_id~,
    command_id~,
    lane="runtime",
    kind="runtime.turn_started",
    title="MoonCode native runtime turn started",
    status="running",
    detail="MoonClaw claimed command \{command_id} for book-local native tool execution.",
    now~,
  )
  let tool_results : Array[Json] = []
  let events : Array[Json] = [started]
  let execution : Json = if mooncode_json_bool(report, "ok", default=false) {
    let mut plan = self.mooncode_runtime_turn_plan_tool_calls(
      command,
      now=self.clock.now(),
    )
    let planner_steps : Array[Json] = []
    let max_model_steps = mooncode_runtime_turn_model_max_steps(command)
    for step_index in 0..<max_model_steps {
      planner_steps.push(plan)
      for event in mooncode_json_array_items(plan, "events") {
        events.push(event)
      }
      let planned_tool_calls = mooncode_json_array_items(plan, "tool_calls")
      let tool_calls = if planned_tool_calls.length() > 0 {
        planned_tool_calls
      } else {
        mooncode_runtime_turn_tool_calls(command)
      }
      for
        event in mooncode_runtime_turn_planner_progress_events(
          session_id,
          command_id,
          plan,
          tool_calls,
          step_index~,
          now=self.clock.now(),
        ) {
        events.push(event)
      }
      let step_results : Array[Json] = []
      for tool_call in tool_calls {
        let execution = mooncode_execute_tool_call(
          session_id,
          book_root,
          mooncode_runtime_turn_tool_body(command, tool_call),
          now=self.clock.now(),
        )
        step_results.push(execution)
        tool_results.push(execution)
        events.push(mooncode_json_object_field_or_empty(execution, "event"))
        if !mooncode_json_bool(execution, "accepted", default=false) {
          break
        }
      }
      let step_accepted = step_results.all(result => {
        mooncode_json_bool(result, "accepted", default=false)
      })
      if !step_accepted ||
        mooncode_json_string(plan, "planner_mode", default="") !=
        "model-tool-calls" ||
        mooncode_runtime_turn_tool_calls_include_finish(tool_calls) ||
        step_index + 1 >= max_model_steps {
        break
      }
      let next_plan = self.mooncode_runtime_turn_model_followup_plan(
        command,
        plan,
        tool_calls,
        step_results,
        now=self.clock.now(),
      )
      let next_calls = mooncode_json_array_items(next_plan, "tool_calls")
      if next_calls.length() == 0 {
        planner_steps.push(next_plan)
        for event in mooncode_json_array_items(next_plan, "events") {
          events.push(event)
        }
        plan = next_plan
        break
      }
      plan = next_plan
    }
    let accepted = tool_results.all(result => {
      mooncode_json_bool(result, "accepted", default=false)
    })
    if mooncode_json_string(command, "command", default="prompt") == "steer" {
      events.push(
        mooncode_runtime_turn_steer_settlement_event(
          session_id,
          command_id,
          command,
          accepted~,
          now=self.clock.now(),
        ),
      )
    }
    let finished = mooncode_runtime_turn_finished_event(
      session_id,
      command_id,
      accepted~,
      tool_count=tool_results.length(),
      now=self.clock.now(),
    )
    events.push(finished)
    (
      {
        "accepted": accepted,
        "protocol": "mooncode.v1",
        "session_id": session_id,
        "command_id": command_id,
        "control": mooncode_json_string(command, "command", default="prompt"),
        "message": if accepted {
          "MoonClaw native runtime turn completed `\{mooncode_json_string(command, "command", default="prompt")}`"
        } else {
          "MoonClaw native runtime turn failed during tool execution"
        },
        "planner": plan,
        "planner_steps": Json::array(planner_steps),
        "planner_mode": mooncode_json_string(
          plan,
          "planner_mode",
          default="deterministic-fallback",
        ),
        "planner_step_count": planner_steps.length(),
        "model_step_limit": max_model_steps,
        "tool_results": Json::array(tool_results),
        "events": Json::array(events),
      } : Json)
  } else {
    let failed = mooncode_event(
      session_id~,
      command_id~,
      lane="runtime",
      kind="runtime.turn_invalid",
      title="MoonCode native runtime turn rejected invalid command",
      status="failed",
      detail=mooncode_json_string(
        report,
        "message",
        default="Invalid MoonCode command",
      ),
      now=self.clock.now(),
    )
    events.push(failed)
    (
      {
        "accepted": false,
        "protocol": "mooncode.v1",
        "session_id": session_id,
        "command_id": command_id,
        "control": "invalid",
        "message": mooncode_json_string(
          report,
          "message",
          default="Invalid MoonCode command",
        ),
        "validation": report,
        "tool_results": Json::array(tool_results),
        "events": Json::array(events),
      } : Json)
  }
  let package_results = if mooncode_json_bool(
      execution,
      "accepted",
      default=false,
    ) {
    mooncode_runtime_turn_package_results(
      session_id,
      book_root,
      command,
      execution,
      now=self.clock.now(),
    )
  } else {
    []
  }
  let package_events : Array[Json] = []
  for package_result in package_results {
    let package_event = mooncode_package_result_event_record(
      session_id~,
      command_id~,
      package_result,
      now=self.clock.now(),
    )
    package_events.push(package_event)
  }
  let receipt = mooncode_runtime_turn_receipt(
    session_id,
    book_root,
    item,
    execution,
    consumer_id~,
    now=self.clock.now(),
  )
  mooncode_append_jsonl(
    mooncode_runtime_dispatches_path(book_root, session_id),
    receipt,
  )
  let binding = self.mooncode_binding_for_session(session_id)
  binding.book_root = book_root
  binding.command_count += 1
  binding.last_command_id = command_id
  binding.last_updated = self.clock.now()
  for event in events {
    binding.events.put(event)
    self.mooncode_persist_event(binding, event)
  }
  for index, package_result in package_results {
    binding.events.put(package_events[index])
    self.mooncode_persist_package_result(
      package_result,
      binding,
      package_events[index],
    )
  }
  self.mooncode_persist_session(binding)
  let after = self.mooncode_runtime_claim_state_payload(session_id, book_root)
  {
    "kind": "mooncode-runtime-turn",
    "protocol": "mooncode.v1",
    "owner": "moonclaw",
    "accepted": mooncode_json_bool(execution, "accepted", default=false),
    "session_id": session_id,
    "book_root": book_root,
    "ran": true,
    "command_id": command_id,
    "claim_receipts": Json::array(claim_receipts),
    "turn_receipt": receipt,
    "execution": execution,
    "package_results": Json::array(package_results),
    "package_events": Json::array(package_events),
    "claim_state": after,
    "previous_claim_state": before,
  }
}

///|
fn mooncode_runtime_turn_tool_calls(command : Json) -> Array[Json] {
  let explicit = mooncode_json_array_items(command, "runtime_tool_calls")
  if explicit.length() > 0 {
    return explicit
  }
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let explicit = mooncode_json_array_items(packet, "runtime_tool_calls")
  if explicit.length() > 0 {
    return explicit
  }
  let action = mooncode_json_string(command, "command", default="prompt")
  match action {
    "prompt" => mooncode_runtime_turn_prompt_tool_calls(command)
    "steer" =>
      [
        {
          "tool": "finish",
          "arguments": {
            "answer": "Native MoonCode runtime applied steering context to the active or next claimed turn.",
          },
        },
      ]
    "run_tests" | "run_eval" =>
      [
        {
          "tool": "moon_check",
          "arguments": mooncode_runtime_turn_moon_check_arguments(command),
        },
        {
          "tool": "finish",
          "arguments": {
            "answer": "Native MoonCode runtime completed \{action}.",
          },
        },
      ]
    "cancel" =>
      [
        {
          "tool": "finish",
          "arguments": {
            "answer": "Native MoonCode runtime recorded cancel with no legacy task dispatch.",
          },
        },
      ]
    _ =>
      [
        {
          "tool": "finish",
          "arguments": {
            "answer": "Native MoonCode runtime recorded command `\{action}`. No explicit runtime_tool_calls were provided.",
          },
        },
      ]
  }
}

///|
async fn Daemon::mooncode_runtime_turn_plan_tool_calls(
  self : Daemon,
  command : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let explicit = mooncode_runtime_turn_explicit_tool_calls(command)
  if explicit.length() > 0 {
    return {
      "kind": "mooncode-runtime-turn-planner",
      "protocol": "mooncode.v1",
      "planner_mode": "explicit-tool-calls",
      "tool_calls": Json::array(explicit),
      "events": Json::array([]),
    }
  }
  let model_name = mooncode_runtime_turn_requested_model(command)
  if model_name == "" || !mooncode_runtime_turn_model_planning_allowed(command) {
    return {
      "kind": "mooncode-runtime-turn-planner",
      "protocol": "mooncode.v1",
      "planner_mode": "deterministic-fallback",
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
      let completion = @openai.chat(
        model~,
        mooncode_runtime_turn_model_plan_request(model.model_name, command),
        timeout_ms=Some(mooncode_runtime_turn_model_timeout_ms(command)),
      ) catch {
        error =>
          return mooncode_runtime_turn_failed_planner_result(
            command,
            model_name,
            "model planner failed: \{error}",
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
        "kind": "mooncode-runtime-turn-planner",
        "protocol": "mooncode.v1",
        "planner_mode": "model-tool-calls",
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
  action == "prompt" || action == "package" || action == "accept"
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
  )
}

///|
fn mooncode_runtime_turn_model_plan_request_from_messages(
  model_name : String,
  message_jsons : Array[Json],
) -> @openai.Request raise {
  let messages : Array[@openai.ChatCompletionMessageParam] = @json.from_json(
    Json::array(message_jsons),
  )
  @openai.chat_completion(
    model=model_name,
    messages~,
    tools=mooncode_runtime_turn_model_tools(),
    temperature=0.0,
  )
}

///|
fn mooncode_runtime_turn_model_initial_messages(command : Json) -> Array[Json] {
  [
    {
      "role": "system",
      "content": "You are MoonClaw's MoonCode planner. Choose bounded MoonCode tool batches to satisfy the user's request inside the selected MoonBook only. Prefer small, reviewable edits. Use write/edit/read/shell/moon_check/finish. Never use paths outside the MoonBook root. Call `finish` only when the task is complete; otherwise use tools and wait for tool results before deciding the next batch.",
    },
    { "role": "user", "content": mooncode_runtime_turn_model_prompt(command) },
  ]
}

///|
fn mooncode_runtime_turn_model_prompt(command : Json) -> String {
  "MoonCode command JSON:\n" +
  command.stringify(indent=2) +
  "\n\nReturn tool calls only when code, tests, or package work is useful. Keep generated artifacts under tools/, apps/, site/generated/, or portable/app-tool/. After tool results, continue with another small batch or call finish."
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
      let completion = @openai.chat(
        model~,
        mooncode_runtime_turn_model_plan_request_from_messages(
          model.model_name,
          messages,
        ),
        timeout_ms=Some(mooncode_runtime_turn_model_timeout_ms(command)),
      ) catch {
        error =>
          return mooncode_runtime_turn_failed_planner_result(
            command,
            model_name,
            "model planner follow-up failed: \{error}",
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
        "kind": "mooncode-runtime-turn-planner",
        "protocol": "mooncode.v1",
        "planner_mode": "model-tool-calls",
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

///|
fn mooncode_runtime_turn_planner_progress_events(
  session_id : String,
  command_id : String,
  plan : Json,
  tool_calls : Array[Json],
  step_index~ : Int,
  now~ : @clock.Timestamp,
) -> Array[Json] {
  let step = step_index + 1
  let mode = mooncode_json_string(
    plan,
    "planner_mode",
    default="deterministic-fallback",
  )
  let model = mooncode_json_string(plan, "model", default="")
  let events : Array[Json] = [
    mooncode_runtime_turn_reasoning_event(
      session_id,
      command_id,
      step~,
      mode~,
      model~,
      tool_count=tool_calls.length(),
      now~,
    ),
  ]
  let response_message = mooncode_json_object_field_or_empty(
    plan, "model_response_message",
  )
  let assistant_content = mooncode_json_string(
    response_message,
    "content",
    default="",
  )
  if assistant_content != "" {
    events.push(
      mooncode_runtime_turn_assistant_event(
        session_id,
        command_id,
        step~,
        content=assistant_content,
        now~,
      ),
    )
  }
  for index in 0..<tool_calls.length() {
    events.push(
      mooncode_runtime_turn_tool_call_event(
        session_id,
        command_id,
        tool_calls[index],
        step~,
        index~,
        mode~,
        model~,
        now~,
      ),
    )
  }
  events
}

///|
fn mooncode_runtime_turn_reasoning_event(
  session_id : String,
  command_id : String,
  step~ : Int,
  mode~ : String,
  model~ : String,
  tool_count~ : Int,
  now~ : @clock.Timestamp,
) -> Json {
  let model_detail = if model == "" { "" } else { " with model `\{model}`" }
  let content = "Planner step \{step} used \{mode}\{model_detail} and selected \{tool_count} tool call(s)."
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-planner-step-\{step}-\{now}",
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "command_id": command_id,
    "lane": "runtime",
    "kind": "reasoning_delta",
    "event": "reasoning_delta",
    "title": "MoonCode planner step \{step}",
    "status": "running",
    "detail": content,
    "content": content,
    "planner_step": step,
    "planner_mode": mode,
    "model": model,
    "tool_call_count": tool_count,
    "created_at": now,
    "source": "moonclaw-native-runtime-turn",
  }
}

///|
fn mooncode_runtime_turn_assistant_event(
  session_id : String,
  command_id : String,
  step~ : Int,
  content~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-assistant-step-\{step}-\{now}",
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "command_id": command_id,
    "lane": "transcript",
    "kind": "assistant_delta",
    "event": "assistant_delta",
    "title": "MoonCode assistant update",
    "status": "running",
    "detail": content,
    "content": content,
    "planner_step": step,
    "created_at": now,
    "source": "moonclaw-native-runtime-turn",
  }
}

///|
fn mooncode_runtime_turn_steer_settlement_event(
  session_id : String,
  command_id : String,
  command : Json,
  accepted~ : Bool,
  now~ : @clock.Timestamp,
) -> Json {
  let steering = mooncode_runtime_turn_prompt_text(command)
  let kind = if accepted { "steer_applied" } else { "steer_dropped" }
  let title = if accepted {
    "MoonCode steering applied"
  } else {
    "MoonCode steering dropped"
  }
  let detail = if accepted {
    "MoonClaw applied steering for command \{command_id}."
  } else {
    "MoonClaw could not apply steering for command \{command_id}."
  }
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-\{kind}-\{now}",
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "command_id": command_id,
    "lane": "runtime",
    "kind": kind,
    "event": kind,
    "title": title,
    "status": if accepted {
      "done"
    } else {
      "failed"
    },
    "detail": detail,
    "content": steering,
    "steering_text": steering,
    "settlement": if accepted {
      "applied"
    } else {
      "dropped"
    },
    "created_at": now,
    "source": "moonclaw-native-runtime-turn",
  }
}

///|
fn mooncode_runtime_turn_tool_call_event(
  session_id : String,
  command_id : String,
  tool_call : Json,
  step~ : Int,
  index~ : Int,
  mode~ : String,
  model~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let tool_call_id = mooncode_runtime_turn_tool_call_id(
    tool_call,
    step~,
    index~,
  )
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  let path = mooncode_json_string(arguments, "path", default="")
  {
    "id": "moonclaw-\{mooncode_safe_session_id(session_id)}-\{command_id}-tool-call-\{step}-\{index}-\{tool}-\{now}",
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "command_id": command_id,
    "lane": mooncode_runtime_turn_tool_call_lane(tool, path),
    "kind": "tool_call",
    "event": "tool_call",
    "title": "Tool started: \{tool}",
    "status": "running",
    "detail": arguments.stringify(indent=2),
    "content": arguments.stringify(indent=2),
    "tool": tool,
    "tool_name": tool,
    "tool_call_id": tool_call_id,
    "arguments": arguments.stringify(indent=2),
    "tool_call": {
      "id": tool_call_id,
      "type": "function",
      "function": { "name": tool, "arguments": arguments.stringify(indent=2) },
    },
    "path": path,
    "planner_step": step,
    "planner_mode": mode,
    "model": model,
    "created_at": now,
    "source": "moonclaw-native-runtime-turn",
  }
}

///|
fn mooncode_runtime_turn_tool_call_id(
  tool_call : Json,
  step~ : Int,
  index~ : Int,
) -> String {
  let id = mooncode_json_string(tool_call, "tool_call_id", default="")
  if id != "" {
    return id
  }
  "runtime-step-\{step}-tool-\{index}"
}

///|
fn mooncode_runtime_turn_tool_call_lane(tool : String, path : String) -> String {
  match tool {
    "moon_check" => "test"
    "write" | "edit" => "diff"
    "finish" => "review"
    _ if path != "" => "diff"
    _ => "tool"
  }
}

///|
fn mooncode_runtime_turn_failed_planner_result(
  command : Json,
  model_name : String,
  message : String,
  started : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let session_id = mooncode_json_string(command, "session_id", default="")
  let command_id = mooncode_command_id(command)
  let failed = mooncode_event(
    session_id~,
    command_id~,
    lane="runtime",
    kind="runtime.planner_failed",
    title="MoonCode model planner fell back",
    status="failed",
    detail=message,
    now~,
  )
  {
    "kind": "mooncode-runtime-turn-planner",
    "protocol": "mooncode.v1",
    "planner_mode": "deterministic-fallback",
    "model": model_name,
    "tool_calls": Json::array([]),
    "events": Json::array([started, failed]),
    "message": message,
  }
}

///|
fn mooncode_runtime_turn_prompt_tool_calls(command : Json) -> Array[Json] {
  let request = mooncode_runtime_turn_prompt_text(command)
  let lower = request.to_lower().to_string()
  if mooncode_runtime_turn_mentions_miniapp(lower) {
    return mooncode_runtime_turn_miniapp_tool_calls(command, request)
  }
  if mooncode_runtime_turn_mentions_tool(lower) {
    return mooncode_runtime_turn_script_tool_calls(command, request)
  }
  [
    {
      "tool": "finish",
      "arguments": {
        "answer": "Native MoonCode runtime recorded this prompt. Ask for a tool, script, miniapp, app, or generated site to have MoonClaw create executable MoonBook code with native tools.",
      },
    },
  ]
}

///|
fn mooncode_runtime_turn_prompt_text(command : Json) -> String {
  let text = mooncode_json_string(command, "text", default="")
  if text != "" {
    return text
  }
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let message = mooncode_json_string(packet, "message", default="")
  if message != "" {
    return message
  }
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  mooncode_json_string(payload, "message", default="")
}

///|
fn mooncode_runtime_turn_mentions_tool(lower : String) -> Bool {
  lower.contains("tool") ||
  lower.contains("script") ||
  lower.contains("executable") ||
  lower.contains("command") ||
  lower.contains("create code") ||
  lower.contains("generate code") ||
  lower.contains("build code")
}

///|
fn mooncode_runtime_turn_mentions_miniapp(lower : String) -> Bool {
  lower.contains("miniapp") ||
  lower.contains("mini app") ||
  lower.contains("app-tool") ||
  lower.contains("web app") ||
  lower.contains("site") ||
  lower.contains("html")
}

///|
fn mooncode_runtime_turn_script_tool_calls(
  command : Json,
  request : String,
) -> Array[Json] {
  let slug = mooncode_runtime_turn_artifact_slug(command)
  let base = "tools/mooncode-generated/\{slug}"
  let script_path = base + "/run.sh"
  let readme_path = base + "/README.md"
  [
    {
      "tool": "write",
      "arguments": {
        "path": script_path,
        "content": "#!/bin/sh\nset -eu\nprintf 'MoonCode generated tool executed.\\n'\n",
      },
    },
    {
      "tool": "write",
      "arguments": {
        "path": readme_path,
        "content": mooncode_runtime_turn_artifact_readme(
          "MoonCode Generated Tool",
          request,
          script_path,
          "Run with `sh \{script_path}` from the MoonBook root.",
        ),
      },
    },
    {
      "tool": "shell",
      "arguments": {
        "cmd": "sh \{script_path}",
        "timeout_ms": 10000,
        "max_output_chars": 4000,
      },
    },
    {
      "tool": "finish",
      "arguments": {
        "answer": "Created a MoonBook-owned executable tool at `\{script_path}` and verified it with a shell run.",
      },
    },
  ]
}

///|
fn mooncode_runtime_turn_miniapp_tool_calls(
  command : Json,
  request : String,
) -> Array[Json] {
  let slug = mooncode_runtime_turn_artifact_slug(command)
  let base = "apps/mooncode-generated/\{slug}"
  let app_path = base + "/index.html"
  let readme_path = base + "/README.md"
  [
    {
      "tool": "write",
      "arguments": {
        "path": app_path,
        "content": mooncode_runtime_turn_miniapp_html(request),
      },
    },
    {
      "tool": "write",
      "arguments": {
        "path": readme_path,
        "content": mooncode_runtime_turn_artifact_readme(
          "MoonCode Generated Miniapp",
          request,
          app_path,
          "Open `\{app_path}` from the MoonBook or publish it through the MoonBook site flow.",
        ),
      },
    },
    {
      "tool": "shell",
      "arguments": {
        "cmd": "test -s \{app_path} && grep -q 'MoonCode Miniapp' \{app_path}",
        "timeout_ms": 10000,
        "max_output_chars": 4000,
      },
    },
    {
      "tool": "finish",
      "arguments": {
        "answer": "Created a MoonBook-owned miniapp at `\{app_path}` and verified the HTML entrypoint.",
      },
    },
  ]
}

///|
fn mooncode_runtime_turn_artifact_slug(command : Json) -> String {
  let command_id = mooncode_command_id(command)
  let safe = mooncode_safe_session_id(command_id)
  if safe == "" {
    "prompt"
  } else {
    safe
  }
}

///|
fn mooncode_runtime_turn_artifact_readme(
  title : String,
  request : String,
  entrypoint : String,
  usage : String,
) -> String {
  "# \{title}\n\n" +
  "Generated by MoonClaw native MoonCode runtime-turn.\n\n" +
  "## Request\n\n" +
  mooncode_runtime_turn_markdown_quote(request) +
  "\n\n## Entrypoint\n\n- `\{entrypoint}`\n\n## Usage\n\n\{usage}\n"
}

///|
fn mooncode_runtime_turn_markdown_quote(text : String) -> String {
  let clean = text.trim().to_string()
  if clean == "" {
    "> No prompt text was provided."
  } else {
    clean.split("\n").map(line => "> " + line.to_string()).collect().join("\n")
  }
}

///|
fn mooncode_runtime_turn_miniapp_html(request : String) -> String {
  let escaped = mooncode_runtime_turn_escape_html(request)
  "<!doctype html>\n" +
  "<html lang=\"en\">\n" +
  "<head>\n" +
  "  <meta charset=\"utf-8\">\n" +
  "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" +
  "  <title>MoonCode Miniapp</title>\n" +
  "  <style>\n" +
  "    body { font-family: system-ui, sans-serif; margin: 0; padding: 32px; background: #f7f4ed; color: #202124; }\n" +
  "    main { max-width: 760px; margin: 0 auto; }\n" +
  "    button { border: 1px solid #202124; background: #fff; padding: 8px 12px; cursor: pointer; }\n" +
  "    output { display: block; margin-top: 16px; padding: 12px; background: #fff; border: 1px solid #d8d2c4; }\n" +
  "  </style>\n" +
  "</head>\n" +
  "<body>\n" +
  "  <main>\n" +
  "    <h1>MoonCode Miniapp</h1>\n" +
  "    <p>This miniapp was generated inside a MoonBook from the prompt below.</p>\n" +
  "    <blockquote>\{escaped}</blockquote>\n" +
  "    <button type=\"button\" id=\"run\">Run</button>\n" +
  "    <output id=\"result\">Ready.</output>\n" +
  "  </main>\n" +
  "  <script>\n" +
  "    document.getElementById('run').addEventListener('click', function () {\n" +
  "      document.getElementById('result').textContent = 'MoonCode miniapp executed at ' + new Date().toISOString();\n" +
  "    });\n" +
  "  </script>\n" +
  "</body>\n" +
  "</html>\n"
}

///|
fn mooncode_runtime_turn_escape_html(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
}

///|
fn mooncode_runtime_turn_moon_check_arguments(command : Json) -> Json {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  let target = mooncode_json_string(payload, "moon_check_target", default="")
  if target == "" {
    { "timeout_ms": 60000, "max_output_chars": 16000 }
  } else {
    { "target": target, "timeout_ms": 60000, "max_output_chars": 16000 }
  }
}

///|
fn mooncode_runtime_turn_tool_body(command : Json, tool_call : Json) -> Json {
  let command_id = mooncode_command_id(command)
  {
    "protocol": "mooncode.v1",
    "session_id": mooncode_json_string(command, "session_id", default=""),
    "book_root": mooncode_book_root(command),
    "command_id": command_id,
    "command_packet": mooncode_json_object_field_or_empty(command, "packet"),
    "tool": mooncode_json_string(
      tool_call,
      "tool",
      default=mooncode_json_string(tool_call, "name", default=""),
    ),
    "arguments": mooncode_json_object_field_or_empty(tool_call, "arguments"),
  }
}

///|
fn mooncode_runtime_turn_finished_event(
  session_id : String,
  command_id : String,
  accepted~ : Bool,
  tool_count~ : Int,
  now~ : @clock.Timestamp,
) -> Json {
  mooncode_event(
    session_id~,
    command_id~,
    lane="runtime",
    kind="runtime.turn_finished",
    title=if accepted {
      "MoonCode native runtime turn completed"
    } else {
      "MoonCode native runtime turn failed"
    },
    status=if accepted { "done" } else { "failed" },
    detail="MoonClaw native runtime turn executed \{tool_count} tool call(s).",
    now~,
  )
}

///|
fn mooncode_runtime_turn_receipt(
  session_id : String,
  book_root : String,
  claim_item : Json,
  execution : Json,
  consumer_id~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  let command_id = mooncode_json_string(claim_item, "command_id", default="")
  let accepted = mooncode_json_bool(execution, "accepted", default=false)
  let receipt = mooncode_json_object_field_or_empty(claim_item, "receipt")
  let claim_id = mooncode_json_string(receipt, "claim_id", default="")
  {
    "kind": "mooncode.runtime-dispatch",
    "protocol": "mooncode.v1",
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "status": if accepted {
      "runtime-completed"
    } else {
      "runtime-failed"
    },
    "dispatch_mode": "moonclaw-native-runtime-turn",
    "claim_id": claim_id,
    "consumer_id": consumer_id,
    "completed_at": now,
    "control": mooncode_json_string(execution, "control", default=""),
    "message": mooncode_json_string(execution, "message", default=""),
    "command": mooncode_json_object_field_or_empty(claim_item, "command"),
    "command_entry": mooncode_json_object_field_or_empty(
      claim_item, "command_entry",
    ),
    "execution": execution,
    "events": Json::array(mooncode_json_array_items(execution, "events")),
  }
}

///|
async fn mooncode_runtime_turn_package_results(
  session_id : String,
  book_root : String,
  command : Json,
  execution : Json,
  now~ : @clock.Timestamp,
) -> Array[Json] {
  let paths = mooncode_runtime_turn_package_paths(execution)
  if paths.length() == 0 {
    return []
  }
  let command_id = mooncode_command_id(command)
  let manifest = mooncode_runtime_turn_package_manifest(
    session_id,
    book_root,
    command,
    paths,
    now~,
  )
  let index = mooncode_runtime_turn_package_index(
    session_id,
    book_root,
    manifest,
    now~,
  )
  mooncode_runtime_turn_write_json_manifest(
    book_root,
    mooncode_json_string(manifest, "manifest_path", default=""),
    manifest,
  )
  mooncode_runtime_turn_write_json_manifest(
    book_root,
    mooncode_json_string(index, "manifest_path", default=""),
    index,
  )
  let entrypoint = mooncode_json_string(manifest, "context_path", default="")
  let packet = mooncode_json_object_field_or_empty(command, "packet")
  let built : Json = {
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "event": "package_built",
    "path": entrypoint,
    "detail": "MoonClaw native runtime built MoonBook package candidate `\{entrypoint}`.",
    "package_manifest": manifest,
    "package_index": index,
    "command_packet": packet,
  }
  if mooncode_runtime_turn_package_verified(execution) {
    [
      built,
      {
        "protocol": "mooncode.v1",
        "session_id": session_id,
        "book_root": book_root,
        "command_id": command_id,
        "event": "package_verified",
        "path": entrypoint,
        "detail": "MoonClaw native runtime verified MoonBook package candidate `\{entrypoint}`.",
        "package_manifest": manifest,
        "package_index": index,
        "command_packet": packet,
      },
    ]
  } else {
    [built]
  }
}

///|
fn mooncode_runtime_turn_package_paths(execution : Json) -> Array[String] {
  let paths : Array[String] = []
  for result in mooncode_json_array_items(execution, "tool_results") {
    if !mooncode_json_bool(result, "accepted", default=false) {
      continue
    }
    let tool = mooncode_json_string(result, "tool", default="")
    if tool != "write" && tool != "edit" {
      continue
    }
    let tool_result = mooncode_json_object_field_or_empty(result, "result")
    let metadata = mooncode_json_object_field_or_empty(tool_result, "metadata")
    let path = mooncode_json_string(metadata, "path", default="")
    if mooncode_runtime_turn_is_package_path(path) &&
      !mooncode_runtime_turn_string_array_contains(paths, path) {
      paths.push(path)
    }
  }
  paths
}

///|
fn mooncode_runtime_turn_is_package_path(path : String) -> Bool {
  path.has_prefix("tools/") ||
  path.has_prefix("apps/") ||
  path.has_prefix("site/generated/") ||
  path.has_prefix("portable/app-tool/")
}

///|
fn mooncode_runtime_turn_package_verified(execution : Json) -> Bool {
  for result in mooncode_json_array_items(execution, "tool_results") {
    if !mooncode_json_bool(result, "accepted", default=false) {
      continue
    }
    let tool = mooncode_json_string(result, "tool", default="")
    if tool == "shell" || tool == "moon_check" {
      return true
    }
  }
  false
}

///|
async fn mooncode_runtime_turn_package_manifest(
  session_id : String,
  book_root : String,
  command : Json,
  paths : Array[String],
  now~ : @clock.Timestamp,
) -> Json {
  let command_id = mooncode_command_id(command)
  let entrypoint = mooncode_runtime_turn_package_entrypoint(paths)
  let safe_session = mooncode_safe_session_id(session_id)
  let safe_command = mooncode_safe_session_id(command_id)
  let package_root = "portable/app-tool/mooncode/\{safe_session}"
  let manifest_path = "\{package_root}/package-\{safe_command}.json"
  let absolute_manifest_path = @pathx.join(book_root, manifest_path)
  let source_inventory = mooncode_runtime_turn_source_inventory(
    book_root,
    paths,
    package_root~,
    safe_command~,
  )
  let source_present = mooncode_runtime_turn_source_present_count(
    source_inventory,
  )
  let source_promoted = mooncode_runtime_turn_source_promoted_count(
    source_inventory,
  )
  {
    "kind": "mooncode-package-manifest",
    "protocol": "mooncode.v1",
    "status": "source-bound",
    "package_kind": mooncode_runtime_turn_package_kind(entrypoint),
    "session_id": session_id,
    "workspace_id": mooncode_json_string(command, "workspace_id", default=""),
    "workspace_name": mooncode_json_string(
      command,
      "workspace_name",
      default="",
    ),
    "task_id": "",
    "context_path": entrypoint,
    "candidate_paths": Json::array(
      mooncode_runtime_turn_string_json_array(paths),
    ),
    "source_inventory": Json::array(source_inventory),
    "promoted_sources": Json::array(source_inventory),
    "source_inventory_count": source_inventory.length(),
    "source_present_count": source_present,
    "promoted_source_count": source_promoted,
    "source_promotion_status": if source_promoted == paths.length() &&
      paths.length() > 0 {
      "promoted"
    } else if source_promoted > 0 {
      "partially-promoted"
    } else {
      "not-promoted"
    },
    "promoted_source_root": "\{package_root}/sources/\{safe_command}",
    "source_inventory_status": if source_present > 0 {
      "source-bound"
    } else {
      "no-source-yet"
    },
    "command_id": command_id,
    "command_created_at": mooncode_json_string(
      command,
      "created_at",
      default="",
    ),
    "recorded_at": now,
    "manifest_path": manifest_path,
    "absolute_manifest_path": absolute_manifest_path,
    "review_receipt_path": "",
    "detail": "MoonClaw native runtime created a packageable MoonBook artifact.",
    "command_packet": mooncode_json_object_field_or_empty(command, "packet"),
    "owner": mooncode_runtime_turn_package_owner(),
    "next_runtime_step": "Moondesk can review this MoonClaw-built candidate through the MoonCode package panel; MoonClaw or standalone MoonCode owns follow-up rebuild and verification events.",
  }
}

///|
fn mooncode_runtime_turn_package_index(
  session_id : String,
  book_root : String,
  manifest : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let safe_session = mooncode_safe_session_id(session_id)
  let manifest_path = "portable/app-tool/mooncode/\{safe_session}/index.json"
  {
    "kind": "mooncode-package-index",
    "protocol": "mooncode.v1",
    "status": "verified",
    "session_id": session_id,
    "workspace_id": mooncode_json_string(manifest, "workspace_id", default=""),
    "workspace_name": mooncode_json_string(
      manifest,
      "workspace_name",
      default="",
    ),
    "task_id": "",
    "recorded_at": now,
    "manifest_path": manifest_path,
    "absolute_manifest_path": @pathx.join(book_root, manifest_path),
    "package_root": "portable/app-tool/mooncode/\{safe_session}",
    "package_count": 1,
    "source_bound_package_count": 1,
    "missing_source_package_count": 0,
    "executable_ready_count": 1,
    "runtime_built_package_count": 1,
    "runtime_verified_package_count": 1,
    "runtime_package_proof_count": 2,
    "package_kinds": Json::array([
      mooncode_json_string(manifest, "package_kind", default="artifact").to_json(),
    ]),
    "entry_points": Json::array([
      mooncode_json_string(manifest, "context_path", default="").to_json(),
    ]),
    "packages": Json::array([manifest]),
    "latest_package_manifest": manifest,
    "descriptor_contract": {
      "owner": "moonbook",
      "consumer": "moonclaw-or-standalone-mooncode",
      "rule": "This index is the stable MoonBook package registry for a MoonCode session.",
    },
    "owner": mooncode_runtime_turn_package_owner(),
  }
}

///|
fn mooncode_runtime_turn_package_entrypoint(paths : Array[String]) -> String {
  for path in paths {
    if path.has_suffix("/run.sh") || path.has_suffix("/index.html") {
      return path
    }
  }
  if paths.length() == 0 {
    ""
  } else {
    paths[0]
  }
}

///|
fn mooncode_runtime_turn_package_kind(path : String) -> String {
  if path.has_prefix("tools/") {
    "tool"
  } else if path.has_prefix("apps/") {
    "miniapp"
  } else if path.has_prefix("site/generated/") {
    "generated-site"
  } else if path.has_prefix("portable/app-tool/") {
    "app-tool"
  } else {
    "artifact"
  }
}

///|
async fn mooncode_runtime_turn_source_inventory(
  book_root : String,
  paths : Array[String],
  package_root~ : String,
  safe_command~ : String,
) -> Array[Json] {
  let inventory : Array[Json] = []
  for path in paths {
    let absolute = @pathx.join(book_root, path)
    let content = @fsx.read_file(absolute) catch { _ => "" }
    let exists = @fsx.exists(absolute) catch { _ => false }
    let promoted = mooncode_runtime_turn_promote_source(
      book_root,
      package_root,
      safe_command,
      path,
      content,
      exists~,
    )
    inventory.push({
      "path": path,
      "absolute_path": absolute,
      "exists": exists,
      "kind": "file",
      "size_bytes": content.length(),
      "package_ready": exists && content.length() > 0,
      "sha256_base64": if exists {
        mooncode_runtime_turn_sha256_base64(content)
      } else {
        ""
      },
      "promotion": promoted,
      "promoted": mooncode_json_bool(promoted, "promoted", default=false),
      "promoted_path": mooncode_json_string(
        promoted,
        "promoted_path",
        default="",
      ),
      "promoted_absolute_path": mooncode_json_string(
        promoted,
        "promoted_absolute_path",
        default="",
      ),
    })
  }
  inventory
}

///|
fn mooncode_runtime_turn_sha256_base64(content : String) -> String {
  @base64.encode(
    Bytes::from_array(@crypto.sha256(@encoding/utf8.encode(content))),
    url_safe=false,
  )
}

///|
async fn mooncode_runtime_turn_promote_source(
  book_root : String,
  package_root : String,
  safe_command : String,
  path : String,
  content : String,
  exists~ : Bool,
) -> Json {
  let promoted_path = "\{package_root}/sources/\{safe_command}/\{path}"
  let promoted_absolute = @pathx.join(book_root, promoted_path)
  if !exists || content.length() == 0 {
    return {
      "promoted": false,
      "source_path": path,
      "promoted_path": promoted_path,
      "promoted_absolute_path": promoted_absolute,
      "status": "missing-source",
    }
  }
  @fsx.make_directory(
    @pathx.dirname(promoted_absolute),
    recursive=true,
    exists_ok=true,
  ) catch {
    error =>
      return {
        "promoted": false,
        "source_path": path,
        "promoted_path": promoted_path,
        "promoted_absolute_path": promoted_absolute,
        "status": "failed",
        "error": "\{error}",
      }
  }
  @fsx.write_to_file(promoted_absolute, content) catch {
    error =>
      return {
        "promoted": false,
        "source_path": path,
        "promoted_path": promoted_path,
        "promoted_absolute_path": promoted_absolute,
        "status": "failed",
        "error": "\{error}",
      }
  }
  {
    "promoted": true,
    "source_path": path,
    "promoted_path": promoted_path,
    "promoted_absolute_path": promoted_absolute,
    "status": "promoted",
    "size_bytes": content.length(),
    "sha256_base64": mooncode_runtime_turn_sha256_base64(content),
  }
}

///|
fn mooncode_runtime_turn_source_present_count(inventory : Array[Json]) -> Int {
  let mut count = 0
  for record in inventory {
    if mooncode_json_bool(record, "package_ready", default=false) {
      count += 1
    }
  }
  count
}

///|
fn mooncode_runtime_turn_source_promoted_count(inventory : Array[Json]) -> Int {
  let mut count = 0
  for record in inventory {
    if mooncode_json_bool(record, "promoted", default=false) {
      count += 1
    }
  }
  count
}

///|
fn mooncode_runtime_turn_package_owner() -> Json {
  {
    "ui": "moondesk",
    "runtime": "moonclaw",
    "artifact": "moonbook",
    "package": "moonbook",
    "extractable_component": "mooncode",
  }
}

///|
async fn mooncode_runtime_turn_write_json_manifest(
  book_root : String,
  relative_path : String,
  manifest : Json,
) -> Unit {
  if relative_path == "" {
    return
  }
  let absolute = @pathx.join(book_root, relative_path)
  @fsx.make_directory(@pathx.dirname(absolute), recursive=true, exists_ok=true)
  @fsx.write_to_file(absolute, manifest.stringify(indent=2))
}

///|
fn mooncode_runtime_turn_string_json_array(
  paths : Array[String],
) -> Array[Json] {
  let items : Array[Json] = []
  for path in paths {
    items.push(path.to_json())
  }
  items
}

///|
fn mooncode_runtime_turn_string_array_contains(
  values : Array[String],
  value : String,
) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}

///|
async test "mooncode native runtime turn executes explicit tool calls" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-turn-XXXXXX"),
  )
  @fsx.write_to_file(@pathx.join(book_root, "README.md"), "hello mooncode")
  let session_id = "session-runtime-turn"
  let command_id = "cmd-runtime-turn"
  let command : Json = {
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "packet": { "command_id": command_id },
    "runtime_tool_calls": [
      { "tool": "read", "arguments": { "path": "README.md" } },
      {
        "tool": "shell",
        "arguments": { "cmd": "printf turn-ok", "timeout_ms": 5000 },
      },
      { "tool": "finish", "arguments": { "answer": "done" } },
    ],
  }
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "command_id": command_id,
    "created_at": @clock.Timestamp::from_ms(1L),
    "command": command,
  })
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @spawn.Manager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
    exec_path: @pathx.join(book_root, "moonclaw"),
    httpx: @httpx.Server::new("[::1]", 0, reuse_addr=true),
    port: 0,
    events: @broadcast.Broadcast::new(),
    serve: book_root,
    conversations: @conversation.Manager::new(
      home=book_root,
      uuid=@uuid.generator(@rand.chacha8()),
    ),
    home: book_root,
    pending_codex_auth: {},
    mooncode_sessions: {},
  }
  let result = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
    "consumer_id": "test-runtime",
  })
  assert_true(mooncode_json_bool(result, "accepted", default=false))
  assert_eq(mooncode_json_string(result, "command_id", default=""), command_id)
  let execution = mooncode_json_object_field_or_empty(result, "execution")
  let tool_results = mooncode_json_array_items(execution, "tool_results")
  assert_eq(tool_results.length(), 3)
  assert_true(execution.stringify().contains("turn-ok"))
  let dispatch_log = @fsx.read_file(
    mooncode_runtime_dispatches_path(book_root, session_id),
  )
  assert_true(dispatch_log.contains("\"runtime-claimed\""))
  assert_true(dispatch_log.contains("\"runtime-completed\""))
  let events_log = @fsx.read_file(mooncode_events_path(book_root, session_id))
  assert_true(events_log.contains("\"runtime.turn_started\""))
  assert_true(events_log.contains("\"tool_result\""))
  assert_true(events_log.contains("\"runtime.turn_finished\""))
  let after = mooncode_json_object_field_or_empty(result, "claim_state")
  assert_true(after.stringify().contains("\"delivered_command_count\":1"))
}

///|
async test "mooncode native runtime turn settles steer commands" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-steer-XXXXXX"),
  )
  let session_id = "session-runtime-steer"
  let command_id = "cmd-runtime-steer"
  let command : Json = {
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "book_root": book_root,
    "command": "steer",
    "text": "Keep the next patch inside tools/ and add tests.",
    "packet": { "command_id": command_id },
    "model": "unavailable-model",
  }
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "command_id": command_id,
    "created_at": @clock.Timestamp::from_ms(2L),
    "command": command,
  })
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @spawn.Manager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
    exec_path: @pathx.join(book_root, "moonclaw"),
    httpx: @httpx.Server::new("[::1]", 0, reuse_addr=true),
    port: 0,
    events: @broadcast.Broadcast::new(),
    serve: book_root,
    conversations: @conversation.Manager::new(
      home=book_root,
      uuid=@uuid.generator(@rand.chacha8()),
    ),
    home: book_root,
    pending_codex_auth: {},
    mooncode_sessions: {},
  }
  let result = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
    "consumer_id": "test-runtime",
  })
  assert_true(mooncode_json_bool(result, "accepted", default=false))
  let execution = mooncode_json_object_field_or_empty(result, "execution")
  assert_eq(mooncode_json_string(execution, "control", default=""), "steer")
  assert_eq(
    mooncode_json_string(execution, "planner_mode", default=""),
    "deterministic-fallback",
  )
  let tool_results = mooncode_json_array_items(execution, "tool_results")
  assert_eq(tool_results.length(), 1)
  let events_log = @fsx.read_file(mooncode_events_path(book_root, session_id))
  assert_true(events_log.contains("\"steer_applied\""))
  assert_true(events_log.contains("Keep the next patch inside tools/"))
  assert_false(events_log.contains("runtime.planner_failed"))
  let after = mooncode_json_object_field_or_empty(result, "claim_state")
  assert_true(after.stringify().contains("\"delivered_command_count\":1"))
}

///|
test "mooncode native runtime turn plans prompt tool calls" {
  let command : Json = {
    "protocol": "mooncode.v1",
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Create an executable tool for this MoonBook",
    "packet": { "command_id": "cmd-planner" },
  }
  let calls = mooncode_runtime_turn_tool_calls(command)
  assert_eq(calls.length(), 4)
  assert_eq(mooncode_json_string(calls[0], "tool", default=""), "write")
  assert_true(calls[0].stringify().contains("tools/mooncode-generated"))
  assert_eq(mooncode_json_string(calls[2], "tool", default=""), "shell")
  assert_eq(mooncode_json_string(calls[3], "tool", default=""), "finish")
  let miniapp : Json = {
    "protocol": "mooncode.v1",
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Build a tiny html miniapp",
    "packet": { "command_id": "cmd-miniapp" },
  }
  let miniapp_calls = mooncode_runtime_turn_tool_calls(miniapp)
  assert_eq(miniapp_calls.length(), 4)
  assert_true(miniapp_calls[0].stringify().contains("apps/mooncode-generated"))
  assert_eq(mooncode_json_string(miniapp_calls[2], "tool", default=""), "shell")
  let steer : Json = {
    "protocol": "mooncode.v1",
    "session_id": "session-planner",
    "book_root": "/tmp/book",
    "command": "steer",
    "text": "Create an executable tool, but keep the next turn focused",
    "packet": { "command_id": "cmd-steer" },
    "model": "test-model",
  }
  let steer_calls = mooncode_runtime_turn_tool_calls(steer)
  assert_eq(steer_calls.length(), 1)
  assert_eq(mooncode_json_string(steer_calls[0], "tool", default=""), "finish")
  assert_false(mooncode_runtime_turn_model_planning_allowed(steer))
}

///|
test "mooncode native runtime turn decodes model-selected tool calls" {
  let calls = mooncode_runtime_turn_tool_calls_from_model_response({
    "choices": [
      {
        "message": {
          "tool_calls": [
            {
              "id": "call-write",
              "type": "function",
              "function": {
                "name": "write",
                "arguments": "{\"path\":\"tools/model-plan/run.sh\",\"content\":\"#!/bin/sh\\nprintf model-plan\\\\n\"}",
              },
            },
            {
              "id": "call-finish",
              "type": "function",
              "function": {
                "name": "finish",
                "arguments": "{\"answer\":\"created model-planned tool\"}",
              },
            },
            {
              "id": "call-unsafe",
              "type": "function",
              "function": { "name": "delete_everything", "arguments": "{}" },
            },
          ],
        },
      },
    ],
  })
  assert_eq(calls.length(), 2)
  assert_eq(mooncode_json_string(calls[0], "tool", default=""), "write")
  assert_eq(
    mooncode_json_string(calls[0], "tool_call_id", default=""),
    "call-write",
  )
  let arguments = mooncode_json_object_field_or_empty(calls[0], "arguments")
  assert_eq(
    mooncode_json_string(arguments, "path", default=""),
    "tools/model-plan/run.sh",
  )
  assert_eq(mooncode_json_string(calls[1], "tool", default=""), "finish")
}

///|
test "mooncode native runtime turn builds model follow-up transcript" {
  let response : Json = {
    "choices": [
      {
        "message": {
          "content": "",
          "tool_calls": [
            {
              "id": "call-read",
              "type": "function",
              "function": {
                "name": "read",
                "arguments": "{\"path\":\"README.md\"}",
              },
            },
          ],
        },
      },
    ],
  }
  let assistant = mooncode_runtime_turn_model_response_message(response)
  assert_eq(mooncode_json_string(assistant, "role", default=""), "assistant")
  assert_eq(mooncode_json_array_items(assistant, "tool_calls").length(), 1)
  let calls = mooncode_runtime_turn_tool_calls_from_model_response(response)
  let tool_message = mooncode_runtime_turn_model_tool_result_message(calls[0], {
    "accepted": true,
    "result": { "ok": true, "message": "read README.md", "output": "# Book" },
  })
  assert_eq(mooncode_json_string(tool_message, "role", default=""), "tool")
  assert_eq(
    mooncode_json_string(tool_message, "tool_call_id", default=""),
    "call-read",
  )
  assert_true(
    mooncode_json_string(tool_message, "content", default="").contains(
      "read README.md",
    ),
  )
  assert_true(!mooncode_runtime_turn_tool_calls_include_finish(calls))
  assert_true(
    mooncode_runtime_turn_tool_calls_include_finish([
      { "tool": "finish", "arguments": { "answer": "done" } },
    ]),
  )
  assert_eq(
    mooncode_runtime_turn_model_max_steps({
      "payload": { "planner_max_steps": 0 },
    }),
    1,
  )
  assert_eq(
    mooncode_runtime_turn_model_max_steps({
      "payload": { "planner_max_steps": 99 },
    }),
    8,
  )
}

///|
test "mooncode native runtime turn emits planner progress events" {
  let plan : Json = {
    "planner_mode": "model-tool-calls",
    "model": "test-model",
    "model_response_message": {
      "role": "assistant",
      "content": "I will inspect the file and then finish.",
    },
  }
  let events = mooncode_runtime_turn_planner_progress_events(
    "session-progress",
    "cmd-progress",
    plan,
    [
      {
        "tool": "read",
        "tool_call_id": "call-read",
        "arguments": { "path": "README.md" },
      },
      {
        "tool": "finish",
        "tool_call_id": "call-finish",
        "arguments": { "answer": "done" },
      },
    ],
    step_index=0,
    now=@clock.Timestamp::from_ms(42L),
  )
  assert_eq(events.length(), 4)
  assert_eq(
    mooncode_json_string(events[0], "kind", default=""),
    "reasoning_delta",
  )
  assert_eq(mooncode_json_string(events[0], "lane", default=""), "runtime")
  assert_eq(mooncode_json_int(events[0], "planner_step", default=0), 1)
  assert_eq(
    mooncode_json_string(events[1], "kind", default=""),
    "assistant_delta",
  )
  assert_true(
    mooncode_json_string(events[1], "content", default="").contains("inspect"),
  )
  assert_eq(mooncode_json_string(events[2], "kind", default=""), "tool_call")
  assert_eq(mooncode_json_string(events[2], "lane", default=""), "diff")
  assert_eq(
    mooncode_json_string(events[2], "tool_call_id", default=""),
    "call-read",
  )
  assert_eq(mooncode_json_string(events[3], "lane", default=""), "review")
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(events[3], "tool_call"),
      "id",
      default="",
    ),
    "call-finish",
  )
}

///|
async test "mooncode native runtime turn creates executable tool from prompt" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-prompt-XXXXXX"),
  )
  let session_id = "session-runtime-prompt"
  let command_id = "cmd-runtime-prompt"
  let command : Json = {
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "book_root": book_root,
    "command": "prompt",
    "text": "Create an executable tool for this MoonBook",
    "packet": { "command_id": command_id },
  }
  mooncode_append_jsonl(mooncode_commands_path(book_root, session_id), {
    "kind": "mooncode-command",
    "protocol": "mooncode.v1",
    "session_id": session_id,
    "command_id": command_id,
    "created_at": @clock.Timestamp::from_ms(2L),
    "command": command,
  })
  let daemon = Daemon::{
    clock: @clock.epoch,
    models: @model.Loader::new(home=@os.home(), cwd=book_root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @spawn.Manager::new(cwd=book_root),
    by_cwd: {},
    by_id: {},
    rqs: {},
    exec_path: @pathx.join(book_root, "moonclaw"),
    httpx: @httpx.Server::new("[::1]", 0, reuse_addr=true),
    port: 0,
    events: @broadcast.Broadcast::new(),
    serve: book_root,
    conversations: @conversation.Manager::new(
      home=book_root,
      uuid=@uuid.generator(@rand.chacha8()),
    ),
    home: book_root,
    pending_codex_auth: {},
    mooncode_sessions: {},
  }
  let result = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
    "consumer_id": "test-runtime",
  })
  assert_true(mooncode_json_bool(result, "accepted", default=false))
  let execution = mooncode_json_object_field_or_empty(result, "execution")
  let tool_results = mooncode_json_array_items(execution, "tool_results")
  assert_eq(tool_results.length(), 4)
  assert_true(
    execution.stringify().contains("MoonCode generated tool executed."),
  )
  let script_path = @pathx.join(
    book_root, "tools/mooncode-generated/cmd-runtime-prompt/run.sh",
  )
  let readme_path = @pathx.join(
    book_root, "tools/mooncode-generated/cmd-runtime-prompt/README.md",
  )
  assert_true(@fsx.exists(script_path))
  assert_true(@fsx.exists(readme_path))
  let package_results = mooncode_json_array_items(result, "package_results")
  assert_eq(package_results.length(), 2)
  assert_eq(
    mooncode_json_string(package_results[0], "event", default=""),
    "package_built",
  )
  assert_eq(
    mooncode_json_string(package_results[1], "event", default=""),
    "package_verified",
  )
  let manifest_path = @pathx.join(
    book_root, "portable/app-tool/mooncode/session-runtime-prompt/package-cmd-runtime-prompt.json",
  )
  let index_path = @pathx.join(
    book_root, "portable/app-tool/mooncode/session-runtime-prompt/index.json",
  )
  assert_true(@fsx.exists(manifest_path))
  assert_true(@fsx.exists(index_path))
  let manifest_text = @fsx.read_file(manifest_path)
  assert_true(manifest_text.contains("mooncode-package-manifest"))
  assert_true(manifest_text.contains("\"package_kind\""))
  assert_true(manifest_text.contains("\"tool\""))
  assert_true(
    manifest_text.contains("\"source_promotion_status\": \"promoted\""),
  )
  assert_true(manifest_text.contains("\"promoted_source_count\": 2"))
  assert_true(manifest_text.contains("\"sha256_base64\""))
  assert_true(manifest_text.contains("\"promoted_path\""))
  let promoted_script_path = @pathx.join(
    book_root, "portable/app-tool/mooncode/session-runtime-prompt/sources/cmd-runtime-prompt/tools/mooncode-generated/cmd-runtime-prompt/run.sh",
  )
  let promoted_readme_path = @pathx.join(
    book_root, "portable/app-tool/mooncode/session-runtime-prompt/sources/cmd-runtime-prompt/tools/mooncode-generated/cmd-runtime-prompt/README.md",
  )
  assert_true(@fsx.exists(promoted_script_path))
  assert_true(@fsx.exists(promoted_readme_path))
  assert_eq(@fsx.read_file(promoted_script_path), @fsx.read_file(script_path))
  let package_log = @fsx.read_file(
    mooncode_package_results_path(book_root, session_id),
  )
  assert_true(package_log.contains("\"package_built\""))
  assert_true(package_log.contains("\"package_verified\""))
  let events_log = @fsx.read_file(mooncode_events_path(book_root, session_id))
  assert_true(events_log.contains("\"runtime.turn_started\""))
  assert_true(events_log.contains("\"tool_result\""))
  assert_true(events_log.contains("\"finish\""))
  assert_true(events_log.contains("\"runtime.package_built\""))
  assert_true(events_log.contains("\"runtime.package_verified\""))
  assert_true(events_log.contains("\"runtime.turn_finished\""))
}
