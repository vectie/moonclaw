///|
async fn Daemon::mooncode_runtime_turn_plan_tool_calls(
  self : Daemon,
  command : Json,
  live_steering? : Array[Json] = [],
  remaining_steps? : Int = -1,
  now~ : @clock.Timestamp,
) -> Json {
  // Treat the provider catalog selector as opaque. Availability is checked
  // against the loader after explicit calls and planner policy are considered.
  let requested_model_name = mooncode_runtime_turn_requested_model(command)
  let requested_model = match
    mooncode_runtime_model_selector(requested_model_name) {
    Some(selector) => selector
    None =>
      return mooncode_runtime_turn_failed_planner_result(
        command,
        requested_model_name,
        "MoonCode requires a model selected from the provider catalog",
        mooncode_event(
          session_id=mooncode_json_string(command, "session_id", default=""),
          command_id=mooncode_command_id(command),
          lane="runtime",
          kind="runtime.planner_started",
          title="MoonCode model planner rejected model",
          status="failed",
          detail="MoonCode requires a model selected from the provider catalog",
          now~,
        ),
        now~,
      )
  }
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
  if !mooncode_runtime_turn_model_planning_allowed(command) {
    return {
      "kind": mooncode_kind_runtime_turn_planner(),
      "protocol": mooncode_protocol_version(),
      "planner_mode": mooncode_planner_mode_deterministic_fallback(),
      "tool_calls": Json::array([]),
      "events": Json::array([]),
    }
  }
  let selected_model = mooncode_runtime_turn_resolve_model(
    self.models,
    self.home,
    command,
    requested_model,
  )
  let model_name = requested_model
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
  match selected_model {
    Some(model) => {
      let messages = if mooncode_runtime_turn_model_is_kimi(model.model_name) {
        mooncode_runtime_turn_kimi_messages(command, live_steering)
      } else {
        let skill_catalog = mooncode_runtime_turn_skill_catalog(
          mooncode_book_root(command),
        )
        mooncode_runtime_turn_model_messages(
          command,
          live_steering,
          remaining_steps,
          skill_catalog~,
        )
      }
      let request = mooncode_runtime_turn_model_plan_request_from_messages(
        model.model_name,
        messages,
        tools=mooncode_runtime_turn_model_tools_for_command(command),
        reasoning_effort=mooncode_runtime_turn_model_reasoning_effort(command),
      )
      let (completion, effective_messages, model_transport) = mooncode_runtime_turn_model_chat(
        model,
        request,
        command,
        source_messages=messages,
      ) catch {
        error =>
          return mooncode_runtime_turn_planner_error_result(
            command,
            model_name,
            "model planner failed",
            error,
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
        "model_transport": model_transport,
        "model_response_id": mooncode_json_string(
          completion.to_json(),
          "id",
          default="",
        ),
        "tool_call_count": tool_calls.length(),
        "tool_calls": Json::array(tool_calls),
        "events": Json::array([started, selected]),
        "planner_metrics": mooncode_runtime_turn_planner_metrics(
          request.to_json(),
          completion.to_json(),
          effective_messages,
          tool_calls,
          model_transport~,
        ),
        "model_messages": Json::array(
          mooncode_runtime_turn_durable_model_messages(effective_messages),
        ),
        "model_response_message": mooncode_runtime_turn_model_response_message(
          completion.to_json(),
          normalized_tool_calls=tool_calls,
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
  mooncode_runtime_turn_model_planning_allowed(command)
}

///|
fn mooncode_runtime_turn_requested_model_label(command : Json) -> String {
  let requested = mooncode_runtime_turn_requested_model(command)
  if requested == "" {
    "default model"
  } else {
    requested
  }
}

///|
/// Resolve against the daemon cache first, then rehydrate from the command's
/// persisted MoonBook root. A daemon may serve its own package directory while
/// resumed MoonCode commands depend on the workspace-local MoonGate catalog.
async fn mooncode_runtime_turn_resolve_model(
  models : @model.Loader,
  home : StringView,
  command : Json,
  selector : String,
) -> @model.Model? {
  match models.get_model(name=selector) {
    Some(model) => Some(model)
    None => {
      let book_root = mooncode_book_root(command)
      if book_root == "" {
        return None
      }
      let book_models = @model.Loader::new(home~, cwd=book_root)
      book_models.get_model(name=selector)
    }
  }
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
  // Direct reasoning models can legitimately need more than 30 seconds once a
  // coding turn reaches edit/verification. Keep the timeout bounded, but do
  // not turn normal reasoning latency into a false runtime failure.
  let timeout = mooncode_json_int(payload, "planner_timeout_ms", default=60000)
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
    _ =>
      // Models routed through MoonGate can legitimately perform a long
      // uninterrupted reasoning pass before their next tool call. A local
      // wall-clock deadline converts healthy provider work into a false
      // transport failure, so these routes run until completion or explicit
      // cancellation by the MoonCode/MoonDesk control plane.
      if mooncode_runtime_turn_model_uses_patient_transport(model) {
        None
      } else {
        Some(mooncode_runtime_turn_model_timeout_ms(command))
      }
  }
}

///|
/// Keep the provider cache identity stable for every planner round in one
/// MoonCode session. Only MoonGate's OpenAI-compatible route receives the
/// additive field; direct providers keep their existing request shape.
fn mooncode_runtime_turn_model_extra_body(
  model : @model.Model,
  command : Json,
) -> Map[String, Json] {
  if !model.base_url.contains("/openclaw/v1") {
    return Map([])
  }
  let session_id = mooncode_json_string(command, "session_id", default="")
    .trim()
    .to_owned()
  if session_id == "" {
    Map([])
  } else {
    { "prompt_cache_key": Json::string("moonclaw-session:\{session_id}") }
  }
}

///|
async fn mooncode_runtime_turn_model_chat(
  model : @model.Model,
  request : @openai.Request,
  command : Json,
  source_messages? : Array[Json] = [],
) -> (@openai.ChatCompletion, Array[Json], String) {
  let mut retry_count = 0
  let mut active_request = request
  while true {
    let completion = Some(
      mooncode_runtime_dispatch_model_request(
        model,
        active_request,
        command,
        timeout_ms=mooncode_runtime_turn_model_timeout_for_provider(
          model, command,
        ),
      ),
    ) catch {
      error => {
        let summary = @openai.error_summary(error)
        let provider_error_class = @openai.error_class(error)
        let retry_after_ms = @openai.error_retry_after_ms(error)
        if !mooncode_runtime_turn_model_retries_until_cancelled(model, error) ||
          @async.is_being_cancelled() {
          raise error
        }
        let delay_ms = mooncode_runtime_turn_model_retry_delay_ms(
          retry_count,
          summary~,
          retry_after_ms~,
          entropy=mooncode_json_string(command, "session_id", default="") +
            ":" +
            mooncode_command_id(command) +
            ":" +
            model.model_name,
        )
        let overload_compaction_tier = if provider_error_class ==
          "server_overloaded" {
          // Begin at tier 2 because the unshaped request has already failed,
          // then reach the emergency tier within one monitoring interval.
          (retry_count + 2).min(7)
        } else {
          0
        }
        active_request = request.compact_for_overload(overload_compaction_tier)
        let retry_request_chars = active_request.to_json().stringify().length()
        mooncode_runtime_turn_record_model_retry(
          command,
          model.model_name,
          retry_count + 1,
          summary,
          delay_ms,
          provider_error_class~,
          retry_after_ms~,
          overload_compaction_tier~,
          retry_request_chars~,
        )
        @async.sleep(delay_ms)
        retry_count += 1
        None
      }
    }
    match completion {
      Some((value, transport)) => {
        if retry_count > 0 {
          mooncode_runtime_turn_record_model_retry_recovered(
            command,
            model.model_name,
            retry_count,
          )
        }
        let provider_messages = mooncode_json_array_items(
          active_request.to_json(),
          "messages",
        )
        return (
          value,
          mooncode_runtime_context_merge_messages(
            provider_messages, source_messages,
          ),
          transport,
        )
      }
      None => continue
    }
  }
  abort("unreachable model retry loop")
}

///|
fn mooncode_runtime_turn_model_retries_until_cancelled(
  model : @model.Model,
  error : Error,
) -> Bool {
  mooncode_runtime_turn_model_uses_patient_transport(model) &&
  (error is @tls.ConnectionClosed || @openai.error_is_transient(error))
}

///|
fn mooncode_runtime_turn_model_retries_transient_summary(
  model_name : String,
  summary : String,
) -> Bool {
  mooncode_runtime_turn_model_name_uses_patient_transport(model_name) &&
  mooncode_runtime_turn_planner_error_summary_is_transient(summary)
}

///|
fn mooncode_runtime_turn_model_retry_delay_ms(
  retry_count : Int,
  summary? : String = "",
  retry_after_ms? : Int? = None,
  entropy? : String = "",
) -> Int {
  let rate_limited = summary.contains("HTTP 429")
  let mut delay = if rate_limited { 30000 } else { 1000 }
  let exponent_cap = if rate_limited { 4 } else { 5 }
  for _ in 0..<retry_count.min(exponent_cap) {
    delay *= 2
  }
  let cap = if rate_limited { 300000 } else { 30000 }
  let capped = delay.min(cap)
  let jitter_percent = mooncode_runtime_turn_model_retry_jitter_percent(
    "\{entropy}:\{summary}:\{retry_count}",
  )
  let jittered = capped * (100 + jitter_percent) / 100
  match retry_after_ms {
    Some(provider_delay) => jittered.max(provider_delay).min(cap)
    None => jittered.min(cap)
  }
}

///|
/// Stable ±15% jitter prevents synchronized MoonCode workers from retrying an
/// overloaded provider together while keeping replay tests deterministic.
fn mooncode_runtime_turn_model_retry_jitter_percent(seed : String) -> Int {
  let mut hash = 5381
  for ch in seed {
    hash = (hash * 33 + ch.to_int()) % 1000003
  }
  if hash < 0 {
    hash = -hash
  }
  hash % 31 - 15
}

///|
fn mooncode_runtime_turn_model_max_steps(command : Json) -> Int {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  // Planner work is milestone-driven by default. Zero means there is no
  // command-wide planner-step ceiling; each model request remains bounded by
  // its own token and timeout controls. A caller may still request a positive
  // resumable scheduling quantum explicitly.
  let requested = mooncode_json_int(payload, "planner_max_steps", default=0)
  if requested < 0 {
    1
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
    reasoning_effort=mooncode_runtime_turn_model_reasoning_effort(command),
  )
}

///|
fn mooncode_runtime_turn_model_reasoning_effort(
  command : Json,
) -> @openai.ChatCompletionReasoningEffort {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  match
    mooncode_json_string(payload, "planner_reasoning_effort", default="none") {
    "minimal" => Minimal
    "low" => Low
    "medium" => Medium
    "high" => High
    "xhigh" => Xhigh
    _ => None_
  }
}

///|
fn mooncode_runtime_turn_model_plan_request_from_messages(
  model_name : String,
  message_jsons : Array[Json],
  tools? : Array[@openai.ChatCompletionToolParam] = mooncode_runtime_turn_model_tools(),
  reasoning_effort? : @openai.ChatCompletionReasoningEffort = None_,
) -> @openai.Request raise {
  let messages : Array[@openai.ChatCompletionMessageParam] = @json.from_json(
    Json::array(message_jsons),
  )
  @openai.chat_completion(
    model=model_name,
    messages~,
    tools~,
    max_tokens=mooncode_runtime_turn_model_max_tokens(model_name),
    reasoning_effort~,
    stream=true,
    temperature=0.0,
    tool_choice=Required,
    parallel_tool_calls=true,
  )
}

///|
fn mooncode_runtime_turn_model_max_tokens(model_name : String) -> Int {
  if mooncode_runtime_turn_model_name_uses_patient_transport(model_name) {
    2000
  } else {
    1200
  }
}

///|
fn mooncode_runtime_turn_model_tools_for_command(
  command : Json,
) -> Array[@openai.ChatCompletionToolParam] {
  let goal_runtime = mooncode_json_object_field_or_empty(
    command, "goal_runtime",
  )
  let tools = mooncode_runtime_turn_model_tools(
    active_goal_runtime=mooncode_json_string(
        goal_runtime,
        "goal_id",
        default="",
      ) !=
      "",
  )
  let allowed_tool_names = mooncode_runtime_turn_explicit_allowed_tool_names(
    command,
  )
  if allowed_tool_names.length() > 0 {
    return tools.filter(tool => {
      let function = mooncode_json_object_field_or_empty(
        tool.to_json(),
        "function",
      )
      allowed_tool_names.contains(
        mooncode_json_string(function, "name", default=""),
      )
    })
  }
  let request = mooncode_runtime_turn_prompt_text(command)
    .to_lower()
    .to_string()
  let path = mooncode_runtime_turn_prompt_path(
    mooncode_runtime_turn_prompt_text(command),
  )
  // Implementation intent takes precedence over incidental analysis words.
  // Prompts such as "implement ...; do not merely explain" must retain the
  // complete coding toolset even when they also name a source path.
  if mooncode_runtime_turn_model_needs_coding_tools(command, request) {
    if mooncode_runtime_turn_dynamic_tool_bundles_enabled(command) {
      let selected = mooncode_runtime_turn_select_model_tools(
        tools,
        mooncode_runtime_turn_dynamic_coding_tool_names(request),
      )
      selected.push(mooncode_runtime_turn_deferred_tool_search_spec())
      return selected
    }
    return tools
  }
  if path != "" && mooncode_runtime_turn_read_needs_model(request) {
    return mooncode_runtime_turn_select_model_tools(tools, [
      "read", "finish", "read_skill",
    ])
  }
  mooncode_runtime_turn_select_model_tools(tools, ["finish", "read_skill"])
}

///|
fn mooncode_runtime_turn_select_model_tools(
  tools : Array[@openai.ChatCompletionToolParam],
  names : ArrayView[String],
) -> Array[@openai.ChatCompletionToolParam] {
  tools.filter(tool => {
    let function = mooncode_json_object_field_or_empty(
      tool.to_json(),
      "function",
    )
    names.contains(mooncode_json_string(function, "name", default=""))
  })
}

///|
fn mooncode_runtime_turn_task_intent(command : Json) -> String? {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  match mooncode_json_string(payload, "task_intent", default="") {
    "workspace_change" => Some("workspace_change")
    "read_only" => Some("read_only")
    _ => None
  }
}

///|
fn mooncode_runtime_turn_model_needs_coding_tools(
  command : Json,
  request : String,
) -> Bool {
  match mooncode_runtime_turn_task_intent(command) {
    Some("workspace_change") => return true
    Some("read_only") => return false
    _ => ()
  }
  let action = mooncode_json_string(command, "command", default="prompt")
  if mooncode_runtime_turn_model_has_mutation_intent(action, request) {
    return true
  }
  if mooncode_runtime_turn_model_is_read_only_request(request) {
    return false
  }
  mooncode_runtime_turn_request_has_word(request, "code") ||
  mooncode_runtime_turn_request_has_word(request, "script") ||
  mooncode_runtime_turn_request_has_word(request, "tool") ||
  mooncode_runtime_turn_request_has_word(request, "app") ||
  mooncode_runtime_turn_request_has_word(request, "miniapp") ||
  mooncode_runtime_turn_request_has_word(request, "site")
}

///|
fn mooncode_runtime_turn_model_has_mutation_intent(
  action : String,
  request : String,
) -> Bool {
  action == "package" ||
  request.contains("implement") ||
  request.contains("fix ") ||
  request.contains("debug") ||
  request.contains("refactor") ||
  request.contains("edit ") ||
  request.contains("write ") ||
  request.contains("create ") ||
  request.contains("build ") ||
  mooncode_runtime_turn_requests_tests(request)
}

///|
fn mooncode_runtime_turn_model_is_read_only_request(request : String) -> Bool {
  request.contains("explain") ||
  request.contains("summarize") ||
  request.contains("summarise") ||
  request.contains("describe") ||
  request.contains("analyze") ||
  request.contains("analyse") ||
  request.contains("review") ||
  request.contains("compare") ||
  request.contains("evaluate") ||
  request.has_prefix("read ") ||
  request.has_prefix("open ") ||
  request.has_prefix("inspect ") ||
  request.has_prefix("what ") ||
  request.has_prefix("tell ")
}

///|
fn mooncode_runtime_turn_requests_tests(request : String) -> Bool {
  let mentions_test = mooncode_runtime_turn_request_has_word(request, "test") ||
    mooncode_runtime_turn_request_has_word(request, "tests") ||
    mooncode_runtime_turn_request_has_word(request, "testing")
  request.has_prefix("test ") ||
  request.has_prefix("please test ") ||
  request.contains(" run test") ||
  request.contains(" run the test") ||
  request.contains(" write test") ||
  request.contains(" add test") ||
  request.contains(" update test") ||
  request.contains(" fix test") ||
  request.contains(" test the ") ||
  request.contains(" test this ") ||
  request.contains("tests pass") ||
  (
    mentions_test &&
    (
      request.contains("run ") ||
      request.contains("add ") ||
      request.contains("write ") ||
      request.contains("update ") ||
      request.contains("fix ") ||
      request.contains("execute ") ||
      request.contains("verify ")
    )
  )
}

///|
fn mooncode_runtime_turn_request_has_word(
  request : String,
  word : String,
) -> Bool {
  for raw in request.split(" ") {
    let token = raw.trim(chars="`'\".,:;!?()[]{}<>").to_owned()
    if token == word {
      return true
    }
  }
  false
}

///|
priv struct MoonCodeCompletionVerdict {
  accepted : Bool
  reason : String
}

///|
fn mooncode_runtime_turn_requires_verification(command : Json) -> Bool {
  match mooncode_runtime_turn_task_intent(command) {
    Some("workspace_change") => return true
    Some("read_only") => return false
    _ => ()
  }
  let action = mooncode_json_string(command, "command", default="prompt")
  if action == "package" || action == "apply_patch" || action == "revert_patch" {
    return true
  }
  if action != "prompt" && action != "steer" {
    return false
  }
  let request = mooncode_runtime_turn_prompt_text(command)
    .to_lower()
    .to_string()
  let source_change = request.contains(".mbt") ||
    request.contains(".js") ||
    request.contains(".ts") ||
    request.contains(".sh") ||
    mooncode_runtime_turn_request_has_word(request, "code") ||
    mooncode_runtime_turn_request_has_word(request, "script") ||
    mooncode_runtime_turn_request_has_word(request, "app") ||
    mooncode_runtime_turn_request_has_word(request, "site")
  request.contains("implement") ||
  request.contains("fix ") ||
  request.contains("debug") ||
  request.contains("refactor") ||
  request.contains("build ") ||
  mooncode_runtime_turn_requests_tests(request) ||
  (
    source_change &&
    (
      request.contains("edit ") ||
      request.contains("write ") ||
      request.contains("create ")
    )
  )
}

///|
fn mooncode_runtime_turn_completion_gate_applies(
  command : Json,
  used_model_planner : Bool,
) -> Bool {
  used_model_planner || mooncode_runtime_turn_requires_verification(command)
}

///|
fn mooncode_runtime_turn_result_payload(result : Json) -> Json {
  let direct = mooncode_json_object_field_or_empty(result, "result")
  match direct {
    Object(fields) if !fields.is_empty() => direct
    _ => mooncode_json_object_field_or_empty(result, "tool_result")
  }
}

///|
fn mooncode_runtime_turn_result_is_mutation(result : Json) -> Bool {
  let payload = mooncode_runtime_turn_result_payload(result)
  let tool = mooncode_json_string(result, "tool", default="")
  let accepted = mooncode_json_bool(
    result,
    "accepted",
    default=tool == "shell" &&
      mooncode_json_string(result, "kind", default="") == "tool_result" &&
      mooncode_json_string(result, "status", default="") == "done" &&
      mooncode_json_bool(payload, "ok", default=false),
  )
  if !accepted {
    return false
  }
  let metadata = mooncode_json_object_field_or_empty(payload, "metadata")
  tool == "write" ||
  tool == "edit" ||
  tool == "apply_patch" ||
  tool == "revert_patch" ||
  (
    tool == "commit" &&
    mooncode_json_string(
      mooncode_json_object_field_or_empty(
        mooncode_json_object_field_or_empty(result, "result"),
        "metadata",
      ),
      "evidence_kind",
      default="",
    ) ==
    "runtime.commit_created"
  ) ||
  (
    tool == "shell" &&
    mooncode_json_bool(metadata, "post_commit_boundary", default=false) &&
    mooncode_json_bool(metadata, "post_commit_capture_valid", default=false) &&
    mooncode_json_string(metadata, "commit_sha", default="") != "" &&
    !mooncode_json_array_string_items(metadata, "changed_paths").is_empty()
  )
}

///|
fn mooncode_runtime_turn_result_is_commit_boundary(result : Json) -> Bool {
  let payload = mooncode_runtime_turn_result_payload(result)
  let metadata = mooncode_json_object_field_or_empty(payload, "metadata")
  let tool = mooncode_json_string(result, "tool", default="")
  (
    tool == "commit" &&
    mooncode_json_string(metadata, "evidence_kind", default="") ==
    "runtime.commit_created"
  ) ||
  (
    tool == "shell" &&
    mooncode_json_bool(metadata, "post_commit_boundary", default=false) &&
    mooncode_json_bool(metadata, "post_commit_capture_valid", default=false) &&
    mooncode_json_string(metadata, "commit_sha", default="") != ""
  )
}

///|
fn mooncode_runtime_turn_result_mutation_states(result : Json) -> Array[Json] {
  if !mooncode_runtime_turn_result_is_mutation(result) {
    return []
  }
  let metadata = mooncode_json_object_field_or_empty(
    mooncode_runtime_turn_result_payload(result),
    "metadata",
  )
  let tool = mooncode_json_string(result, "tool", default="")
  if tool == "commit" ||
    (
      tool == "shell" &&
      mooncode_json_bool(metadata, "post_commit_boundary", default=false)
    ) {
    let commit_sha = mooncode_json_string(metadata, "commit_sha", default="")
      .trim()
      .to_owned()
    if commit_sha == "" {
      return []
    }
    return mooncode_json_array_string_items(metadata, "changed_paths")
      .filter(path => path != "")
      .map(path => {
        "path": path,
        "before": "uncommitted",
        "after": "commit:\{commit_sha}",
      })
  }
  let files = mooncode_json_array_items(metadata, "files")
  let candidates = if files.is_empty() { [metadata] } else { files }
  let states : Array[Json] = []
  for candidate in candidates {
    if !mooncode_json_bool(candidate, "changed", default=false) {
      continue
    }
    let path = mooncode_json_string(
      candidate,
      "file_path",
      default=mooncode_json_string(candidate, "path", default=""),
    )
    let before = mooncode_json_string(
      candidate,
      "before_fingerprint",
      default="",
    )
    let after = mooncode_json_string(candidate, "after_fingerprint", default="")
    if path != "" && before != "" && after != "" {
      states.push({ "path": path, "before": before, "after": after })
    }
  }
  states
}

///|
fn mooncode_runtime_turn_has_net_mutation(results : Array[Json]) -> Bool {
  let paths : Array[Json] = []
  let mut untracked_mutation = false
  for result in results {
    if !mooncode_runtime_turn_result_is_mutation(result) {
      continue
    }
    let metadata = mooncode_json_object_field_or_empty(
      mooncode_json_object_field_or_empty(result, "result"),
      "metadata",
    )
    if !mooncode_json_bool(metadata, "changed", default=true) {
      continue
    }
    let states = mooncode_runtime_turn_result_mutation_states(result)
    if states.is_empty() {
      // Older continuations and explicit test fixtures predate fingerprints.
      // Keep them compatible, while all newly executed native mutations carry
      // enough evidence to compare the first and final content state.
      untracked_mutation = true
      continue
    }
    for state in states {
      let path = mooncode_json_string(state, "path", default="")
      let mut found = false
      for index, existing in paths {
        if mooncode_json_string(existing, "path", default="") == path {
          paths[index] = {
            "path": path,
            "before": mooncode_json_string(existing, "before", default=""),
            "after": mooncode_json_string(state, "after", default=""),
          }
          found = true
          break
        }
      }
      if !found {
        paths.push(state)
      }
    }
  }
  for state in paths {
    if mooncode_json_string(state, "before", default="") !=
      mooncode_json_string(state, "after", default="") {
      return true
    }
  }
  untracked_mutation
}

///|
fn mooncode_runtime_turn_result_verification_kind(result : Json) -> String {
  if !mooncode_json_bool(result, "accepted", default=false) {
    return ""
  }
  let tool = mooncode_json_string(result, "tool", default="")
  if tool == "moon_check" {
    return "check"
  }
  if tool == "moon_cmd" {
    let command = mooncode_json_string(
      mooncode_json_object_field_or_empty(result, "arguments"),
      "command",
      default="",
    )
    if command == "check" || command == "test" || command == "build" {
      return command
    }
    return ""
  }
  if tool == "shell" {
    let arguments = mooncode_json_object_field_or_empty(result, "arguments")
    let claimed = mooncode_json_string(
      arguments,
      "verification_kind",
      default="",
    )
    if mooncode_shell_verifies_kind(
        mooncode_json_string(arguments, "cmd", default=""),
        claimed,
      ) {
      return claimed
    }
    return ""
  }
  if tool == "apply_patch" || tool == "revert_patch" {
    let tool_result = mooncode_json_object_field_or_empty(result, "result")
    let metadata = mooncode_json_object_field_or_empty(tool_result, "metadata")
    let verification = mooncode_json_object_field_or_empty(
      metadata, "verification",
    )
    if mooncode_json_bool(verification, "ok", default=false) {
      return "patch-verification"
    }
  }
  ""
}

///|
fn mooncode_runtime_turn_completion_verdict_json(
  verdict : MoonCodeCompletionVerdict,
) -> Json {
  {
    "kind": "mooncode-coding-completion-verdict",
    "accepted": verdict.accepted,
    "reason": verdict.reason,
  }
}

///|
/// Coding completion requires an accepted net mutation followed by successful
/// verification. If tests were requested, a successful typed test command is
/// required. A verified patch may prove its own mutation at the same index.
fn mooncode_runtime_turn_completion_verdict(
  command : Json,
  results : Array[Json],
  require_horizon? : Bool = false,
) -> MoonCodeCompletionVerdict {
  if results.is_empty() {
    return { accepted: false, reason: "no MoonCode tool result was recorded" }
  }
  let final_result = results[results.length() - 1]
  if mooncode_json_string(final_result, "tool", default="") != "finish" ||
    !mooncode_json_bool(final_result, "accepted", default=false) {
    return {
      accepted: false,
      reason: "the final MoonCode tool result is not an accepted finish",
    }
  }
  if require_horizon &&
    !mooncode_runtime_horizon_completion_ready(command, results) {
    return {
      accepted: false,
      reason: "long-horizon completion requires a final all-done checkpoint after the latest mutation and verification",
    }
  }
  let request = mooncode_runtime_turn_prompt_text(command)
    .to_lower()
    .to_string()
  let requires_verification = mooncode_runtime_turn_requires_verification(
    command,
  )
  let requires_tests = mooncode_runtime_turn_requests_tests(request)
  let mut last_mutation = -1
  let mut last_verification = -1
  let mut last_test = -1
  let mut last_failure = -1
  let mut accepted_mutation = false
  let mut coding_evidence = false
  let mut operator_rejected = false
  for index, result in results {
    let tool = mooncode_json_string(result, "tool", default="")
    let accepted = mooncode_json_bool(result, "accepted", default=false)
    if mooncode_json_string(result, "approval_state", default="") == "rejected" {
      operator_rejected = true
      last_failure = index
    } else if !accepted {
      last_failure = index
    } else if tool != "finish" {
      coding_evidence = coding_evidence ||
        tool == "write" ||
        tool == "edit" ||
        tool == "apply_patch" ||
        tool == "revert_patch" ||
        tool == "shell" ||
        tool == "moon_cmd" ||
        tool == "moon_check"
    }
    if mooncode_runtime_turn_result_is_mutation(result) {
      accepted_mutation = true
      // Creating an exact commit seal does not change the source tree that
      // earlier checks exercised. It remains mutation evidence, but it must
      // not invalidate successful verification of that same tree.
      if !mooncode_runtime_turn_result_is_commit_boundary(result) {
        last_mutation = index
      }
    }
    let verification = mooncode_runtime_turn_result_verification_kind(result)
    if verification != "" {
      last_verification = index
      if verification == "test" {
        last_test = index
      }
    }
  }
  if requires_verification {
    if !accepted_mutation {
      return {
        accepted: false,
        reason: "coding completion has no accepted mutation evidence",
      }
    }
    if !mooncode_runtime_turn_has_net_mutation(results) {
      return {
        accepted: false,
        reason: "coding completion has no net mutation; all accepted file changes were reverted before finish",
      }
    }
    let required_verification = if requires_tests {
      last_test
    } else {
      last_verification
    }
    if required_verification < 0 || required_verification < last_mutation {
      return {
        accepted: false,
        reason: if requires_tests {
          "coding completion has no successful typed test after the final mutation"
        } else {
          "coding completion has no successful verification after the final mutation"
        },
      }
    }
    if required_verification < last_failure {
      return {
        accepted: false,
        reason: if requires_tests {
          "coding completion has no successful typed test after the last failed tool"
        } else {
          "coding completion has no successful verification after the last failed tool"
        },
      }
    }
    return {
      accepted: true,
      reason: if requires_tests {
        "coding completion has accepted mutation and subsequent successful typed test evidence"
      } else {
        "coding completion has accepted mutation and subsequent successful verification"
      },
    }
  }
  if mooncode_runtime_turn_model_needs_coding_tools(command, request) &&
    !coding_evidence &&
    !operator_rejected {
    return {
      accepted: false,
      reason: "the coding request has no accepted coding-tool evidence",
    }
  }
  if last_failure >= 0 {
    let recovered = results[last_failure + 1:].any(result => {
      mooncode_json_bool(result, "accepted", default=false) &&
      mooncode_json_string(result, "tool", default="") != "finish"
    })
    if !recovered {
      return {
        accepted: false,
        reason: "the last failed tool has no successful recovery evidence",
      }
    }
  }
  {
    accepted: true,
    reason: "the final finish follows accepted non-verification work",
  }
}

///|
fn mooncode_runtime_turn_model_execution_accepted(
  command : Json,
  results : Array[Json],
  require_horizon? : Bool = false,
) -> Bool {
  mooncode_runtime_turn_completion_verdict(command, results, require_horizon~).accepted
}

///|
fn mooncode_runtime_turn_recoverable_horizon_finish(
  command : Json,
  plan : Json,
  tool_calls : Array[Json],
  tool_results : Array[Json],
) -> Bool {
  if !mooncode_runtime_turn_requires_verification(command) ||
    mooncode_json_string(plan, "planner_mode", default="") !=
    mooncode_planner_mode_model_tool_calls() ||
    !mooncode_runtime_turn_tool_calls_include_finish(tool_calls) {
    return false
  }
  !mooncode_runtime_turn_completion_verdict(
    command,
    tool_results,
    require_horizon=true,
  ).accepted
}

///|
fn mooncode_runtime_turn_horizon_finish_rejection_message(
  command : Json,
  tool_calls : Array[Json],
  tool_results : Array[Json],
) -> String {
  if !mooncode_runtime_turn_requires_verification(command) ||
    !mooncode_runtime_turn_tool_calls_include_finish(tool_calls) {
    return ""
  }
  let verdict = mooncode_runtime_turn_completion_verdict(
    command,
    tool_results,
    require_horizon=true,
  )
  if verdict.accepted {
    ""
  } else {
    "Completion was rejected by the durable task contract: \{verdict.reason}. Continue the same task from the retained evidence. Do not summarize or call finish again until the rejected condition is resolved and the final all-done checkpoint is accepted."
  }
}

///|
fn mooncode_runtime_turn_language_grounding(command : Json) -> String {
  let request = mooncode_runtime_turn_prompt_text(command)
    .to_lower()
    .to_string()
  if !request.contains("moonbit") &&
    !request.contains("moon check") &&
    !request.contains("moon test") &&
    !request.contains(".mbt") {
    return ""
  }
  "\nMoonBit baseline: `moon.mod` uses current assignments such as `name = \"org/module\"`; module dependencies use an exact block such as `import { \"moonbitlang/x@0.4.46\", }`. Package imports and `supported_targets = \"native\"` belong in `moon.pkg`, not `moon.mod`. `Json` is a built-in type (do not alias `@json.Json`), while parsing is `@json.parse(text)` in a raising/try context without legacy bang syntax. Current entry-point syntax is `fn main { ... }`. A simple native sync CLI can import `moonbitlang/core/env`, `moonbitlang/x/fs` as `@fsx` (for `read_file_to_string`), and `moonbitlang/x/sys` (for `exit`) in `moon.pkg`, then use `@env.args()`. Use compiler diagnostics and MoonCode's moon tools; do not inspect SDK files outside the MoonBook."
}

///|
fn mooncode_runtime_turn_model_is_kimi(model_name : String) -> Bool {
  model_name.to_lower().contains("kimi")
}

///|
fn mooncode_runtime_turn_model_name_uses_patient_transport(
  model_name : String,
) -> Bool {
  let normalized = model_name.to_lower()
  normalized.has_prefix("moongate/") ||
  mooncode_runtime_turn_model_is_kimi(normalized)
}

///|
fn mooncode_runtime_turn_model_uses_patient_transport(
  model : @model.Model,
) -> Bool {
  mooncode_runtime_turn_model_name_uses_patient_transport(model.name) ||
  mooncode_runtime_turn_model_name_uses_patient_transport(model.model_name)
}

///|
fn mooncode_runtime_turn_dynamic_skill_gate_message() -> String {
  "Dynamic skill gate: the user's wording may omit the implementation language. As soon as repository evidence shows .mbt files or a MoonBit command is needed, call read_skill for moonbit-agent-guide when available, read it completely, and follow it before the next MoonBit mutation or command. If accepted read_skill evidence or a loaded-skill receipt for that guide already exists in this preserved command, the gate is already satisfied: continue following it and do not reload it or search filesystem paths. A missing or empty filesystem result cannot invalidate the receipt. Installed skill resources are accessible only through read_skill, never through read, shell, glob, grep, find, ls, or web tools. For MoonTown, treat the application as MoonBit plus Rabbita once those artifacts are discovered."
}

///|
fn mooncode_runtime_turn_kimi_messages(
  command : Json,
  live_steering : Array[Json],
) -> Array[Json] {
  let messages : Array[Json] = [
    mooncode_runtime_context_message(
      {
        "role": "system",
        "content": "You are Kimi K3 operating as MoonCode's autonomous design and implementation agent. Treat the user's complete request as the task contract; do not ask for micro-instructions or wait for another agent to design the solution. Work only inside the selected workspace root. Use your judgment: when the target and intended change are already clear from the task and current context, edit directly; inspect only what is needed to resolve real uncertainty. Form your own coherent plan, implement substantive changes, inspect rendered results when requested, verify important behavior, and continue until the whole request is complete. There is no implicit step, turn, time, or effort budget. Preserve unrelated work and user data. Use read with start_line/end_line for native range reads, and use glob, grep, web_fetch, or web_search for other evidence; use edit, write, or apply_patch for authored file changes rather than shell redirection; use shell and project tools for bounded inspection and verification. Batch independent inspections in one response; start another inference round only when a later action depends on an earlier result. Call finish only after implementation and verification are complete, or after a genuine external blocker prevents further progress.",
      },
      SystemContext,
      "planner.kimi.system",
    ),
    mooncode_runtime_context_message(
      {
        "role": "system",
        "content": mooncode_runtime_turn_dynamic_skill_gate_message(),
      },
      SkillContext,
      "skill.dynamic_gate",
    ),
    mooncode_runtime_context_text_message(
      "user",
      mooncode_runtime_turn_model_prompt(command),
      UserContext,
      "user.task_contract",
    ),
  ]
  for steering in live_steering {
    messages.push(mooncode_runtime_turn_model_live_steering_message(steering))
  }
  messages
}

///|
fn mooncode_runtime_turn_model_initial_messages(
  command : Json,
  skill_catalog? : String = "",
) -> Array[Json] {
  [
    mooncode_runtime_context_message(
      {
        "role": "system",
        "content": "You are MoonClaw's MoonCode planner. Choose bounded MoonCode tool batches to satisfy the user's request inside the selected MoonBook only. A bounded tool batch is not a task budget. Unless the caller explicitly supplies a budget, the task has no implicit token, turn, time, step, context-size, or effort ceiling. Difficulty, elapsed work, a large context, or needing more tool batches are not blockers; continue useful work. Honor real caller-supplied budgets exactly. Never invent a token-budget-exhausted, turn-budget-exhausted, time-budget-exhausted, or step-budget-exhausted blocker unless that exact caller-supplied budget exists and is actually exhausted. Only a genuine external dependency or missing user input or authority that prevents meaningful progress can block a task. Use checkpoint/read_skill/write/edit/apply_patch/read/view_image/browser/shell/moon_ide/moon_cmd/moon_check/spawn_workers/wait_workers/finish. Use view_image to inspect screenshot pixels; use browser for first-class UI navigation, semantic snapshots, interaction, screenshots, console, and errors instead of installing a project-local browser harness. Use spawn_workers only for caller-supplied isolated MoonBook roots; children are ordinary prompt sessions with no special authority, and use wait_workers to project any/all child state. When a selected skill directs MoonBit work, prefer semantic discovery with moon_ide before broad source reads and prefer moon_cmd/moon_check over raw shell for validation. For moon_cmd, select the MoonBit module root with cwd and express package or file selectors with path/paths relative to that module; when cwd is omitted, a path inside a nested module lets the runtime infer its nearest module root. Backend target belongs only to commands that support it. `moon fmt` accepts path/paths but never target or package selectors. Canonical local check, test, info, build, and format calls do not require planner-supplied approval. Never use paths outside the MoonBook root. Never use shell, an interpreter, or an inline script to author workspace files; all authored mutations must use edit, write, or apply_patch. For an implementation request, include a checkpoint in the first batch and update the checkpoint whenever a milestone changes. Batch independent inspections in one response; start another inference round only when a later action depends on an earlier result. Resolve material uncertainty early, but do not treat inspection as a prerequisite to mutation. Implementation discovery is finite: the runtime permits at most six broad and twelve total source-discovery observations without an authored mutation. If a discovery-saturated result appears, the next tool batch must contain edit, write, or apply_patch and no source-discovery call; use retained evidence and let focused validation expose any remaining mistake. Do not vary read ranges, find, ls, status, outline, or search commands to evade the boundary. Before writing contract literals, protocol payloads, schemas, or fixtures, read their authoritative local implementation or specification and derive the current shape from that source; never invent fields or call a synthetic subset a captured runtime payload. Avoid repeating equivalent inspections of the same evidence; every additional diagnostic should distinguish competing causes or expose missing causal evidence. Treat successful repository status, diff, and hosted-result reads as retained until repository or hosted state changes. Prefer narrow, reviewable edits. Before any replace-all or repeated replacement, inspect every match and verify that the same semantic change applies to each one; then rerun the nearest affected tests so adjacent cases are not silently damaged. Prefer one cohesive multi-file patch when the evidence supports it, and do not initialize a nested repository or generic project scaffold unless explicitly requested. A comment-only or documentation-only mutation does not satisfy an implementation or defect-repair request; repair behavior, configuration, tests, or another substantive contract instead. Never create marker files, no-op edits, comments, or other artifacts merely to manufacture checkpoint or completion evidence; evidence must come from requested outputs and real validation. Treat validation failures as new evidence: inspect the exact failure before changing the implementation or environment. Once a repair passes the exact gate it targeted, retain that result as established evidence; a later failure at a different gate is a new problem, and does not justify reverting the earlier repair unless new evidence directly falsifies it. Do not infer environment-specific causality from a local pass: reproduce in the failing environment or expose the exact underlying error before claiming a fix. A shell pipeline used as verification evidence must enable pipefail; a successful inspection pipeline without pipefail is usable observation but not proof of a check, test, or build gate. If a required validator enforces a clean version-control state, do not repeat it against the same intended dirty state; use an authorized reversible checkpoint, validate that clean state, and publish only after validation succeeds. Interpret `no cleanup` and similar scope constraints as forbidding unrelated refactors, not as permission to skip the repository's canonical formatter after semantic work; run required formatting and review its diff for unintended churn. If a necessary tool call requires operator approval, select the exact tool call; the runtime will pause before execution. Never ask for tool approval in assistant prose or use finish to request it. Do not set `requires_approval` or `approval=operator` for read, view_image, local browser observation, moon_ide, moon_check, local check/test/format commands, repository status/diff reads, or hosted-result reads unless the user explicitly required approval or the runtime identifies an operator-controlled boundary. If the operator rejects a tool call, obey its rationale and do not retry the same action by rewriting or splitting the command. Never guess a toolchain or dependency-management command; inspect its local help or the repository's existing version mechanism before changing versions. Respect explicit user constraints as hard boundaries. When an active capability resolution is supplied, use only selected_capability as the active version; shadow_capability is observation-only, and an unavailable assignment must never be invented or treated as active. Before finish, record a checkpoint with every required milestone done. Call `finish` only when the task is complete; otherwise use tools and wait for tool results before deciding the next batch." +
        " Autonomy clarification: inspection is proportional to uncertainty, not a prerequisite to every mutation. When the requested target and current context already establish a safe change, edit directly; otherwise inspect only enough to resolve the missing fact. Prefer native read start_line/end_line ranges over shell-based sed slices. Treat exact paths named by the user and task-contract `context_paths` as authoritative starting evidence: use them before broader repository discovery and never substitute guessed paths. If a supplied path fails, consume its exact error and use narrow repository discovery to resolve it; that failed lookup is not a blocker while a causally different next action remains. If any required milestone is pending or active, choose the next useful tool batch instead of calling finish or returning partial-status prose as terminal work." +
        " Never include finish.goal_runtime unless active goal_runtime context is explicitly present in the current request. When it is present, ordinary finish is only a progress turn: use finish.goal_runtime with an exact achieved or blocked decision only when the whole goal reaches a terminal outcome. Blocked still requires a genuine external or user-authority blocker; task difficulty, elapsed work, context size, and implicit limits do not qualify. Achieved evidence must cover every listed criterion id exactly once." +
        mooncode_runtime_turn_active_tool_bundle_message(command) +
        skill_catalog,
      },
      SystemContext,
      "planner.system",
    ),
    mooncode_runtime_context_message(
      {
        "role": "system",
        "content": mooncode_runtime_turn_dynamic_skill_gate_message(),
      },
      SkillContext,
      "skill.dynamic_gate",
    ),
    mooncode_runtime_context_text_message(
      "user",
      mooncode_runtime_turn_model_prompt(command),
      UserContext,
      "user.task_contract",
    ),
  ]
}

///|
fn mooncode_runtime_turn_model_followup_base_messages(
  command : Json,
  previous_plan : Json,
  tool_results : Array[Json],
  all_tool_results? : Array[Json] = [],
  skill_catalog? : String = "",
) -> Array[Json] {
  ignore(tool_results)
  let previous = mooncode_json_array_items(previous_plan, "model_messages")
  if previous.length() >= 2 {
    // A milestone checkpoint records durable task progress; it is not evidence
    // that the planner can forget the source, diagnostics, and ownership
    // inventory used to reach that milestone. Keep the actual transcript so a
    // long-horizon task continues from retained reasoning instead of repeating
    // discovery after every checkpoint.
    // Build the follow-up transcript without mutating the durable prior plan.
    // A resumed patient-replan checkpoint stores `plan` and `planner_steps`
    // separately after journal decoding; mutating only `plan.model_messages`
    // would make the next continuation fail its integrity check.
    let task_contract = mooncode_runtime_turn_model_prompt(command)
    let compacted = if mooncode_runtime_turn_active_semantic_compaction_enabled(
        command,
      ) {
      mooncode_runtime_turn_active_semantic_compaction_previous_messages(
        previous, task_contract,
      )
    } else {
      mooncode_runtime_turn_compact_followup_transcript(
        previous,
        task_contract~,
      )
    }
    let messages : Array[Json] = []
    // Replace any prior receipt with the current durable receipts so they do
    // not accumulate across long runs and survive transcript compaction.
    for message in compacted {
      let content = mooncode_json_string(message, "content", default="")
      if content.has_prefix("Dynamic skill gate:") {
        messages.push(
          mooncode_json_object_with_field(
            message,
            "content",
            Json::string(mooncode_runtime_turn_dynamic_skill_gate_message()),
          ),
        )
      } else if !content.has_prefix("Loaded-skill receipt:") {
        messages.push(message)
      }
    }
    for
      receipt in mooncode_runtime_turn_loaded_skill_receipt_messages(
        all_tool_results,
      ) {
      messages.push(
        mooncode_runtime_context_normalize_message(
          receipt,
          fallback_kind=SkillContext,
          fallback_source="skill.loaded_receipt",
        ),
      )
    }
    messages
  } else {
    let messages = mooncode_runtime_turn_model_initial_messages(
      command,
      skill_catalog~,
    )
    for
      retained in mooncode_runtime_turn_loaded_skill_messages(all_tool_results) {
      messages.push(
        mooncode_runtime_context_normalize_message(
          retained,
          fallback_kind=SkillContext,
          fallback_source="skill.loaded_resource",
        ),
      )
    }
    messages
  }
}

///|
/// Keep the task contract plus a valid recent assistant/tool suffix. Durable
/// evidence remains in the journal, while the provider request and the next
/// restart checkpoint stay bounded during long autonomous runs.
fn mooncode_runtime_turn_compact_followup_transcript(
  previous : Array[Json],
  task_contract? : String = "",
) -> Array[Json] {
  let previous = mooncode_runtime_turn_compact_provider_tool_evidence(previous)
  // Keep enough raw evidence for roughly eight recent tool quanta. Older raw
  // source and DOM payloads make capable providers time out long before they
  // can act, so retain a small set of the model's own reasoning anchors from
  // the preceding window instead of retaining every byte of those tool calls.
  let compact_after = 32
  let retained_suffix_count = 24
  if previous.length() <= compact_after {
    let retained : Array[Json] = []
    for message in previous {
      retained.push(message)
    }
    return retained
  }
  // Retain every leading system contract plus the first user message. Kimi
  // sessions deliberately start with two system messages (planner contract
  // and dynamic skill gate), so assuming `previous[1]` is the user task drops
  // the actual mission after the first long-run compaction.
  let messages : Array[Json] = []
  let mut task_end = 0
  let mut leading_end = 0
  for index in 0..<previous.length() {
    let role = mooncode_json_string(previous[index], "role", default="")
    if role == "system" {
      messages.push(previous[index])
      leading_end = index + 1
    } else if role == "user" {
      messages.push(
        if task_contract != "" {
          mooncode_runtime_context_text_message(
            "user",
            task_contract,
            UserContext,
            "user.task_contract",
          )
        } else {
          previous[index]
        },
      )
      task_end = index + 1
      break
    } else {
      break
    }
  }
  if task_end == 0 {
    if task_contract != "" {
      messages.push(
        mooncode_runtime_context_text_message(
          "user",
          task_contract,
          UserContext,
          "user.task_contract",
        ),
      )
      task_end = leading_end
    }
  }
  if task_end == 0 {
    // Defensive fallback for malformed legacy transcripts: retain the first
    // two messages rather than compacting away their only available context.
    let prefix_count = previous.length().min(2)
    for index in 0..<prefix_count {
      messages.push(previous[index])
    }
    task_end = prefix_count
  }
  let mut suffix_start = previous.length() - retained_suffix_count
  suffix_start = suffix_start.max(task_end)
  while suffix_start < previous.length() {
    let candidate = previous[suffix_start]
    if mooncode_json_string(candidate, "role", default="") == "assistant" &&
      mooncode_json_array_items(candidate, "tool_calls").length() > 0 {
      break
    }
    suffix_start += 1
  }
  let compacted_count = suffix_start - task_end
  messages.push(
    mooncode_runtime_context_text_message(
      "user",
      "MoonCode compacted \{compacted_count} older provider messages from this request. The complete task contract is retained above and all tool evidence remains durable in the session journal. Continue from the recent valid suffix; do not repeat discovery solely because older transport messages were compacted.",
      EnvironmentContext,
      "environment.transcript_compaction",
    ),
  )
  let older_reasoning : Array[String] = []
  for index in task_end..<suffix_start {
    let candidate = previous[index]
    if mooncode_json_string(candidate, "role", default="") == "assistant" {
      let content = mooncode_json_string(candidate, "content", default="")
      if content != "" {
        older_reasoning.push(
          if content.length() > 1200 {
            content[:1200].to_owned() + "…"
          } else {
            content
          },
        )
      }
    }
  }
  if older_reasoning.length() > 0 {
    let anchor_start = if older_reasoning.length() > 6 {
      older_reasoning.length() - 6
    } else {
      0
    }
    let anchors : Array[String] = []
    for index in anchor_start..<older_reasoning.length() {
      anchors.push(older_reasoning[index])
    }
    messages.push(
      mooncode_runtime_context_text_message(
        "user",
        "Earlier model-authored reasoning anchors retained across transport compaction:\n- " +
        anchors.join("\n- "),
        EnvironmentContext,
        "environment.reasoning_anchors",
      ),
    )
  }
  for index in suffix_start..<previous.length() {
    messages.push(previous[index])
  }
  messages
}

///|
/// A skill or source is delivered in full on the turn that reads it. Later
/// provider calls retain a bounded head/tail receipt while the complete bytes
/// remain in the journal. This prevents one 40–70KB read from dominating every
/// subsequent Ark request after the model has already consumed it.
fn mooncode_runtime_turn_compact_provider_tool_evidence(
  previous : Array[Json],
) -> Array[Json] {
  let tool_names : Map[String, String] = {}
  for message in previous {
    if mooncode_json_string(message, "role", default="") != "assistant" {
      continue
    }
    for tool_call in mooncode_json_array_items(message, "tool_calls") {
      let tool_call_id = mooncode_json_string(tool_call, "id", default="")
      let function = mooncode_json_object_field_or_empty(tool_call, "function")
      let tool_name = mooncode_json_string(function, "name", default="")
      if tool_call_id != "" && tool_name != "" {
        tool_names[tool_call_id] = tool_name
      }
    }
  }
  let compacted : Array[Json] = []
  for message in previous {
    let durable = mooncode_runtime_turn_durable_model_message(message)
    if mooncode_json_string(durable, "role", default="") != "tool" {
      compacted.push(durable)
      continue
    }
    let tool_call_id = mooncode_json_string(durable, "tool_call_id", default="")
    let tool_name = tool_names.get(tool_call_id).unwrap_or("tool")
    let content = mooncode_json_string(durable, "content", default="")
    let limit = if tool_name == "read_skill" {
      MOONCODE_DEFAULT_TOOL_OUTPUT_CHARS
    } else if tool_name == "read" {
      10000
    } else {
      6000
    }
    if content.length() <= limit {
      compacted.push(durable)
      continue
    }
    let head_size = limit * 2 / 3
    let tail_size = limit - head_size
    let head = mooncode_utf8_prefix_within(content, head_size)
    let tail = mooncode_utf8_suffix_within(content, tail_size)
    let omitted = content.length() - head.length() - tail.length()
    let compact_content = head +
      "\n...[MoonCode compacted \{omitted} chars of previously consumed `\{tool_name}` evidence; complete bytes remain in the durable journal]...\n" +
      tail
    compacted.push(
      mooncode_json_object_with_field(
        durable,
        "content",
        Json::string(compact_content),
      ),
    )
  }
  compacted
}

///|
/// Image bytes are transport evidence for one provider call, not durable
/// conversation state. Keep the adjacent path-bearing text and replace each
/// data URL with a stable textual receipt after the model has inspected it.
/// This prevents screenshots from being copied into every later checkpoint.
fn mooncode_runtime_turn_durable_model_message(message : Json) -> Json {
  let content = match message {
    Object(fields) => fields.get("content")
    _ => None
  }
  guard content is Some(Array(parts)) else {
    return mooncode_runtime_context_normalize_message(message)
  }
  let durable_parts : Array[Json] = []
  let mut removed_image_count = 0
  for part in parts {
    let image_url = mooncode_json_object_field_or_empty(part, "image_url")
    let url = mooncode_json_string(image_url, "url", default="")
    if mooncode_json_string(part, "type", default="") == "image_url" &&
      url.has_prefix("data:image/") {
      removed_image_count += 1
    } else {
      durable_parts.push(part)
    }
  }
  if removed_image_count == 0 {
    return mooncode_runtime_context_normalize_message(message)
  }
  durable_parts.push({
    "type": "text",
    "text": "MoonCode delivered \{removed_image_count} image evidence item(s) to the model for pixel inspection. Binary data URLs are intentionally omitted from durable checkpoints; the adjacent text and tool-result metadata retain their MoonBook paths.",
  })
  mooncode_runtime_context_normalize_message(
    mooncode_json_object_with_field(
      message,
      "content",
      Json::array(durable_parts),
    ),
  )
}

///|
fn mooncode_runtime_turn_durable_model_messages(
  messages : Array[Json],
) -> Array[Json] {
  let durable : Array[Json] = []
  for message in messages {
    durable.push(mooncode_runtime_turn_durable_model_message(message))
  }
  durable
}

///|
fn mooncode_runtime_turn_model_messages(
  command : Json,
  live_steering : Array[Json],
  remaining_steps : Int,
  skill_catalog? : String = "",
) -> Array[Json] {
  let messages = mooncode_runtime_turn_model_initial_messages(
    command,
    skill_catalog~,
  )
  for steering in live_steering {
    messages.push(mooncode_runtime_turn_model_live_steering_message(steering))
  }
  ignore(remaining_steps)
  messages
}

///|
fn mooncode_runtime_turn_model_prompt(command : Json) -> String {
  let action = mooncode_json_string(command, "command", default="prompt")
  let request = mooncode_runtime_horizon_compact_request(command)
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
  let active_capability = mooncode_json_object_field_or_empty(
    command, "active_capability",
  )
  let capability_context = if mooncode_json_string(
      active_capability,
      "scope_id",
      default="",
    ) ==
    "" {
    ""
  } else {
    "\nGoverned active capability resolution: " + active_capability.stringify()
  }
  let goal_runtime = mooncode_json_object_field_or_empty(
    command, "goal_runtime",
  )
  let goal_context = if mooncode_json_string(
      goal_runtime,
      "goal_id",
      default="",
    ) ==
    "" {
    ""
  } else {
    "\nActive long-running goal (criteria ids are settlement keys): " +
    goal_runtime.stringify() +
    "\nDo not infer completion or blockage from difficulty, elapsed work, context size, a turn limit, timeout, or generic finish. There is no implicit task budget. Set finish.goal_runtime only for an explicit achieved terminal decision or a genuine external or user-authority blocker."
  }
  "Action: \{action}\n" +
  "User request: \{request}\n" +
  mooncode_runtime_horizon_contract_prompt(command) +
  context +
  "\nWeb search allowed: \{mooncode_command_web_search(command)}." +
  steering +
  capability_context +
  goal_context +
  mooncode_runtime_turn_language_grounding(command) +
  "\n\nChoose one dependency-aware bounded tool batch. Batch every independent inspection or mutation that can run from current evidence; do not spend a new inference round on a trivial action unless its result is required first. Use finish immediately when no code or tool work is needed. Keep all paths relative to the selected MoonBook."
}

///|
fn mooncode_runtime_turn_model_finish_parameters(
  active_goal_runtime : Bool,
) -> Json {
  if !active_goal_runtime {
    return {
      "type": "object",
      "properties": { "answer": { "type": "string" } },
      "required": ["answer"],
      "additionalProperties": false,
    }
  }
  {
    "type": "object",
    "properties": {
      "answer": { "type": "string" },
      "goal_runtime": {
        "description": "Exact terminal decision for the explicitly active goal only. Blocked requires a genuine external dependency or missing user input or authority; difficulty, elapsed work, context size, and implicit token, turn, time, step, or effort limits are not blockers.",
        "anyOf": [
          {
            "type": "object",
            "properties": {
              "type": { "type": "string", "enum": ["achieved"] },
              "summary": { "type": "string" },
              "evidence": {
                "type": "array",
                "items": {
                  "type": "object",
                  "properties": {
                    "criterion": { "type": "string" },
                    "evidence_refs": {
                      "type": "array",
                      "items": { "type": "string" },
                    },
                  },
                  "required": ["criterion", "evidence_refs"],
                  "additionalProperties": false,
                },
              },
            },
            "required": ["type", "summary", "evidence"],
            "additionalProperties": false,
          },
          {
            "type": "object",
            "properties": {
              "type": { "type": "string", "enum": ["blocked"] },
              "reason": {
                "type": "object",
                "properties": {
                  "code": { "type": "string" },
                  "detail": { "type": "string" },
                },
                "required": ["code", "detail"],
                "additionalProperties": false,
              },
              "attempted_alternatives": {
                "type": "array",
                "items": { "type": "string" },
              },
              "required_event": {
                "anyOf": [{ "type": "string" }, { "type": "null" }],
              },
            },
            "required": [
              "type", "reason", "attempted_alternatives", "required_event",
            ],
            "additionalProperties": false,
          },
        ],
      },
    },
    "required": ["answer"],
    "additionalProperties": false,
  }
}

///|
fn mooncode_runtime_turn_model_tools(
  active_goal_runtime? : Bool = false,
) -> Array[@openai.ChatCompletionToolParam] {
  let finish_description = if active_goal_runtime {
    "Finish only completed work with a concise operator-facing summary. Never use finish to request approval; select the exact gated tool call and let the runtime pause. The active long-running goal may be settled only when all criteria are achieved or a genuine external blocker prevents progress."
  } else {
    "Finish only completed work with a concise operator-facing summary. Never use finish to request approval; select the exact gated tool call and let the runtime pause."
  }
  [
    mooncode_runtime_turn_model_tool(
      "read",
      "Read a whole file or an inclusive line range inside the selected MoonBook. Prefer start_line/end_line over shell-based sed slices.",
      {
        "type": "object",
        "properties": {
          "path": { "type": "string" },
          "start_line": { "type": "integer", "minimum": 1 },
          "end_line": { "type": "integer", "minimum": 1 },
          "max_output_chars": { "type": "integer" },
        },
        "required": ["path"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "view_image",
      "Inspect PNG, JPEG, WebP, or GIF pixels from a file inside the selected MoonBook. The image is attached to the next model turn without embedding its bytes in the durable journal.",
      {
        "type": "object",
        "properties": { "path": { "type": "string" } },
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
      "Atomically replace text in an existing MoonBook file. Use old_string/new_string for one edit, or edits for an ordered multi-edit; the file is written only after every edit validates.",
      {
        "type": "object",
        "properties": {
          "path": { "type": "string" },
          "old_string": { "type": "string" },
          "new_string": { "type": "string" },
          "replace_all": { "type": "boolean" },
          "edits": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "old_string": { "type": "string" },
                "new_string": { "type": "string" },
                "replace_all": { "type": "boolean" },
              },
              "required": ["old_string", "new_string"],
              "additionalProperties": false,
            },
          },
        },
        "required": ["path"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "shell",
      "Run a bounded shell command inside the selected MoonBook. Use the typed cwd field instead of an inline cd; parent-relative paths are permitted only when they resolve inside the MoonBook from that cwd. For a long-lived local preview server, set background=true and submit only the foreground server command without `&`; the native daemon owns its lifetime. Set verification_kind only when this command's zero exit status directly proves that exact check, test, or build gate; ordinary inspection commands must omit it.",
      {
        "type": "object",
        "properties": {
          "cmd": { "type": "string" },
          "cwd": { "type": "string" },
          "timeout_ms": { "type": "integer" },
          "max_output_chars": { "type": "integer" },
          "background": { "type": "boolean" },
          "verification_kind": {
            "type": "string",
            "enum": ["check", "test", "build"],
          },
        },
        "required": ["cmd"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "browser",
      "Operate an isolated native browser session for UI-to-UI work. Prefer snapshot for semantic state, screenshot plus view_image for visual judgment, and console/errors for diagnosis. Snapshot returns element refs such as e21; pass them to click/fill/wait as selectors with the required @ prefix (for example @e21). Visible labels such as button text are not selectors. Take a fresh snapshot after navigation or a DOM-changing action before reusing refs.",
      {
        "type": "object",
        "properties": {
          "action": {
            "type": "string",
            "enum": [
              "open", "snapshot", "screenshot", "set_viewport", "click", "fill",
              "press", "wait", "get", "eval", "console", "errors", "reload", "close",
            ],
          },
          "url": { "type": "string" },
          "selector": {
            "type": "string",
            "description": "CSS, XPath, or a snapshot element reference with @ prefix such as @e21; never pass visible label text as the selector.",
          },
          "text": { "type": "string" },
          "key": { "type": "string" },
          "path": { "type": "string" },
          "full_page": { "type": "boolean" },
          "interactive": { "type": "boolean" },
          "compact": { "type": "boolean" },
          "depth": { "type": "integer" },
          "width": { "type": "integer" },
          "height": { "type": "integer" },
          "what": { "type": "string" },
          "attribute": { "type": "string" },
          "script": { "type": "string" },
          "wait_ms": { "type": "integer" },
          "timeout_ms": { "type": "integer" },
          "max_output_chars": { "type": "integer" },
        },
        "required": ["action"],
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
      "Run a structured MoonBit command at a MoonBit module root. Use cwd for a known nested module, or path/paths so the runtime can infer the nearest module. `fmt` accepts paths and formatter options but no target or package selector; check/test/info/build preserve valid target and package/file selectors.",
      {
        "type": "object",
        "properties": {
          "command": {
            "type": "string",
            "enum": ["check", "test", "run", "info", "fmt", "build"],
          },
          "cwd": { "type": "string" },
          "target": {
            "type": "string",
            "description": "Backend for check, test, info, build, or run. Omit for fmt.",
            "enum": ["wasm", "wasm-gc", "js", "native", "llvm", "all"],
          },
          "arg": {
            "type": "string",
            "description": "One command-specific option. Do not put target or package selectors here for fmt.",
          },
          "args": {
            "type": "array",
            "description": "Command-specific options. Do not put target or package selectors here for fmt.",
            "items": { "type": "string" },
          },
          "path": {
            "type": "string",
            "description": "One package directory or file selector; may identify a nested module when cwd is omitted.",
          },
          "paths": {
            "type": "array",
            "description": "Package directory or file selectors within one MoonBit module.",
            "items": { "type": "string" },
          },
          "program_args": { "type": "array", "items": { "type": "string" } },
          "expected_exit_code": {
            "type": "integer",
            "description": "Expected process exit code; use 1 for intentional negative-path CLI validation.",
          },
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
          "cwd": {
            "type": "string",
            "description": "MoonBook-relative directory containing moon.mod; use this for nested modules.",
          },
          "target": {
            "type": "string",
            "enum": ["wasm", "wasm-gc", "js", "native", "llvm", "all"],
          },
          "timeout_ms": { "type": "integer" },
          "max_output_chars": { "type": "integer" },
        },
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "finish",
      finish_description,
      mooncode_runtime_turn_model_finish_parameters(active_goal_runtime),
    ),
    mooncode_runtime_turn_model_tool(
      "apply_patch",
      "Apply one unified diff, including a multi-file diff, inside the selected MoonBook. The diff must use standard `--- a/path`, `+++ b/path`, and `@@` syntax; do not wrap it in `*** Begin Patch` / `*** Update File` markers. For a diff, omit path because targets come from its file headers.",
      {
        "type": "object",
        "properties": {
          "path": { "type": "string" },
          "before": { "type": "string" },
          "after": { "type": "string" },
          "diff": { "type": "string" },
        },
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "checkpoint",
      "Record durable milestone state. A done milestone is accepted only when matching runtime evidence already exists.",
      {
        "type": "object",
        "properties": {
          "horizon_id": { "type": "string" },
          "milestones": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "id": { "type": "string" },
                "title": { "type": "string" },
                "status": {
                  "type": "string",
                  "enum": ["pending", "active", "done"],
                },
                "evidence_kind": {
                  "type": "string",
                  "enum": [
                    "scope", "mutation", "path_changed", "check", "test", "build",
                  ],
                },
                "path": { "type": "string" },
                "context_paths": {
                  "type": "array",
                  "items": { "type": "string" },
                },
              },
              "required": [
                "id", "title", "status", "evidence_kind", "path", "context_paths",
              ],
              "additionalProperties": false,
            },
          },
          "next_action": { "type": "string" },
        },
        "required": ["horizon_id", "milestones", "next_action"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "read_skill",
      "Load the complete installed SKILL.md, or a referenced file inside that selected skill. Use path only after SKILL.md identifies the resource as relevant.",
      {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "path": { "type": "string" },
        },
        "required": ["name"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "spawn_workers",
      "Spawn ordinary MoonCode prompt sessions in caller-supplied isolated MoonBook roots. The parent session remains the controller.",
      {
        "type": "object",
        "properties": {
          "workers": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "id": { "type": "string" },
                "book_root": { "type": "string" },
                "prompt": { "type": "string" },
                "model": { "type": "string" },
                "task_intent": {
                  "type": "string",
                  "enum": ["workspace_change", "read_only"],
                },
              },
              "required": ["id", "book_root", "prompt"],
              "additionalProperties": false,
            },
          },
        },
        "required": ["workers"],
        "additionalProperties": false,
      },
    ),
    mooncode_runtime_turn_model_tool(
      "wait_workers",
      "Project durable child-session state for any or all selected workers.",
      {
        "type": "object",
        "properties": {
          "mode": { "type": "string", "enum": ["any", "all"] },
          "worker_ids": { "type": "array", "items": { "type": "string" } },
        },
        "required": ["mode"],
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
    let arguments = mooncode_runtime_turn_model_argument_values(arguments_text)
    let source_call_id = mooncode_json_string(call, "id", default="")
    for index, argument in arguments {
      let normalized_tool = mooncode_runtime_turn_infer_tool_name(
        tool, argument,
      )
      if mooncode_tool_supported(normalized_tool) ||
        normalized_tool == "tool_search" ||
        normalized_tool == "checkpoint" {
        let tool_call_id = if arguments.length() == 1 {
          source_call_id
        } else {
          "\{source_call_id}-\{index + 1}"
        }
        calls.push({
          "tool": normalized_tool,
          "arguments": argument,
          "tool_call_id": tool_call_id,
          "planner": "model-tool-call",
        })
      }
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
/// Recover provider batches that contain adjacent heterogeneous argument
/// objects under one function name. Strong argument shapes take precedence;
/// ambiguous shapes retain the provider's original function name.
fn mooncode_runtime_turn_infer_tool_name(
  original : String,
  arguments : Json,
) -> String {
  guard arguments is Object(fields) else { return original }
  if fields.contains("cmd") {
    return "shell"
  }
  if fields.contains("diff") {
    return "apply_patch"
  }
  if fields.contains("old_string") && fields.contains("new_string") {
    return "edit"
  }
  if fields.contains("path") && fields.contains("content") {
    return "write"
  }
  if fields.contains("milestones") || fields.contains("horizon_id") {
    return "checkpoint"
  }
  if fields.contains("command") {
    return "moon_cmd"
  }
  if fields.contains("action") {
    let action = mooncode_json_string(arguments, "action", default="")
    if mooncode_browser_action_supported(action) {
      return "browser"
    }
    if action == "doc" ||
      action == "outline" ||
      action == "peek_def" ||
      action == "hover" ||
      action == "find_references" {
      return "moon_ide"
    }
  }
  if fields.contains("workers") {
    return "spawn_workers"
  }
  if fields.contains("worker_ids") && fields.contains("mode") {
    return "wait_workers"
  }
  if fields.length() == 1 && fields.contains("name") {
    // `read_skill` is the only native MoonCode tool with a name-only argument.
    // Recover it when a provider serializes an adjacent read + read_skill batch
    // under the first function name.
    return "read_skill"
  }
  if fields.contains("path") {
    // A bare path is the strong shape of a read call. Preserve tools for which
    // path is already a valid native argument, but recover adjacent path-only
    // objects that an OpenAI-compatible provider serialized under the
    // preceding heterogeneous function name (for example checkpoint + read).
    return match original {
      "read"
      | "view_image"
      | "write"
      | "edit"
      | "apply_patch"
      | "revert_patch"
      | "read_skill" => original
      _ => "read"
    }
  }
  original
}

///|
fn mooncode_runtime_turn_parse_model_argument(text : String) -> Json? {
  let parsed = @json.parse(text) catch { _ => return None }
  Some(parsed)
}

///|
/// Some OpenAI-compatible providers occasionally serialize multiple requested
/// calls as adjacent JSON objects inside one `function.arguments` string. Keep
/// the task model-owned by recovering those objects as separate calls instead
/// of silently replacing the arguments with `{}`.
fn mooncode_runtime_turn_model_argument_values(text : String) -> Array[Json] {
  if mooncode_runtime_turn_parse_model_argument(text) is Some(parsed) {
    return [parsed]
  }
  let values : Array[Json] = []
  let current = StringBuilder()
  let mut depth = 0
  let mut in_string = false
  let mut escaped = false
  let mut started = false
  for ch in text {
    if !started {
      if ch is (' ' | '\t' | '\r' | '\n') {
        continue
      }
      if ch != '{' && ch != '[' {
        return []
      }
      started = true
    }
    current.write_char(ch)
    if in_string {
      if escaped {
        escaped = false
      } else if ch == '\\' {
        escaped = true
      } else if ch == '"' {
        in_string = false
      }
      continue
    }
    if ch == '"' {
      in_string = true
      continue
    }
    if ch == '{' || ch == '[' {
      depth += 1
    } else if ch == '}' || ch == ']' {
      depth -= 1
      if depth < 0 {
        return []
      }
      if depth == 0 {
        guard mooncode_runtime_turn_parse_model_argument(current.to_string())
          is Some(parsed) else {
          return []
        }
        values.push(parsed)
        current.reset()
        started = false
      }
    }
  }
  if depth != 0 || in_string || escaped || started {
    return []
  }
  values
}

///|
fn mooncode_runtime_turn_model_evidence_ledger_message(
  tool_results : Array[Json],
) -> Json {
  let read_paths : Array[String] = []
  let complete_read_paths : Array[String] = []
  let successful_inspections : Array[Json] = []
  let failed_calls : Array[Json] = []
  for execution in tool_results {
    let tool = mooncode_json_string(execution, "tool", default="")
    let arguments = mooncode_json_object_field_or_empty(execution, "arguments")
    let path = mooncode_json_string(arguments, "path", default="")
    let accepted = mooncode_json_bool(execution, "accepted", default=false)
    let result = mooncode_json_object_field_or_empty(execution, "result")
    let ok = mooncode_json_bool(result, "ok", default=accepted)
    if accepted && ok {
      if tool == "shell" {
        let output = mooncode_json_string(result, "output", default="")
        let cmd = mooncode_json_string(arguments, "cmd", default="")
        successful_inspections.push({
          "tool": tool,
          "command": cmd,
          "output_chars": output.length(),
          "output_sha256_base64": mooncode_runtime_turn_sha256_base64(output),
          "output_excerpt": mooncode_runtime_turn_inspection_excerpt(output),
        })
      }
      let normalized_execution : Json = {
        "accepted": accepted,
        "tool": tool,
        "arguments": arguments,
        "result": result,
      }
      let observation = mooncode_runtime_turn_result_file_observation(
        normalized_execution,
      )
      let observed_path = mooncode_json_string(observation, "path", default="")
      let scope = mooncode_json_string(observation, "scope", default="partial")
      if observed_path != "" {
        if !read_paths.contains(observed_path) {
          read_paths.push(observed_path)
        }
        if scope == "complete" &&
          !mooncode_runtime_turn_model_tool_result_content(execution).contains(
            "...[truncated for planner context]",
          ) &&
          !complete_read_paths.contains(observed_path) {
          complete_read_paths.push(observed_path)
        }
      }
    } else if !accepted || !ok {
      failed_calls.push({
        "tool": tool,
        "path": path,
        "message": mooncode_json_string(result, "message", default=""),
      })
    }
  }
  if read_paths.length() == 0 &&
    successful_inspections.length() == 0 &&
    failed_calls.length() == 0 {
    return {}
  }
  let retained_reads : Array[Json] = read_paths.map(path => Json::string(path))
  let retained_complete_reads : Array[Json] = complete_read_paths.map(path => {
    Json::string(path)
  })
  mooncode_runtime_context_message(
    {
      "role": "user",
      "content": "Retained evidence for the next planner opportunity:\n" +
      Json::object({
        "successful_read_paths": Json::array(retained_reads),
        "complete_read_paths": Json::array(retained_complete_reads),
        "successful_inspections": Json::array(successful_inspections),
        "failed_tool_calls": Json::array(failed_calls),
      }).stringify(indent=2) +
      "\n`successful_read_paths` includes complete and partial observations; `complete_read_paths` identifies paths whose full bytes remain in the transcript. `successful_inspections` is a compact durable receipt for successful shell observations whose raw output may be reduced by provider-overload transport shaping. Treat its command, output digest, and excerpt as retained evidence: do not repeat the same or an equivalent directory, status, or inventory inspection merely because older raw output was compacted. Use a causally targeted read of an exact relevant file only when a specific fact is still missing. Do not completely reread a retained complete path merely to recover context. A causally targeted narrow reread remains appropriate after a compiler or patch error, as does a fresh read after mutation or truncation. Consume each exact tool error before acting: while relevant repository and environment state is unchanged, do not repeat an identical failed call, guess an alternative path, or patch against pre-error assumptions. After a relevant repair or transient cause is resolved, rerun the exact focused verification that previously failed. Use repository discovery or an explicit steering path to choose a causally different next action.",
    },
    EnvironmentContext,
    "environment.evidence_ledger",
  )
}

///|
fn mooncode_runtime_turn_inspection_excerpt(output : String) -> String {
  let limit = 1200
  if output.length() <= limit {
    return output
  }
  let head_size = limit * 2 / 3
  let tail_size = limit - head_size
  let head = mooncode_utf8_prefix_within(output, head_size)
  let tail = mooncode_utf8_suffix_within(output, tail_size)
  let omitted = output.length() - head.length() - tail.length()
  head +
  "\n...[MoonCode retained inspection receipt omits \{omitted} chars]...\n" +
  tail
}

///|
async fn mooncode_runtime_turn_model_followup_messages(
  command : Json,
  previous_plan : Json,
  tool_calls : Array[Json],
  tool_results : Array[Json],
  all_tool_results : Array[Json],
  live_steering : Array[Json],
  remaining_steps : Int,
  patient_replan_guidance? : String = "",
  skill_catalog? : String = "",
) -> Array[Json] {
  let messages = mooncode_runtime_turn_model_followup_base_messages(
    command,
    previous_plan,
    tool_results,
    all_tool_results~,
    skill_catalog~,
  )
  messages.push(
    mooncode_json_object_field_or_empty(previous_plan, "model_response_message"),
  )
  for
    message in mooncode_runtime_turn_model_tool_result_messages(
      tool_calls, tool_results,
    ) {
    messages.push(message)
  }
  for
    message in mooncode_runtime_turn_model_image_evidence_messages(
      command, tool_results,
    ) {
    messages.push(message)
  }
  let pipeline_warning = mooncode_runtime_turn_pipeline_evidence_warning(
    tool_results,
  )
  if pipeline_warning != "" {
    messages.push(
      mooncode_runtime_context_text_message(
        "user",
        pipeline_warning,
        WarningContext,
        "warning.pipeline_evidence",
      ),
    )
  }
  let finish_rejection = mooncode_runtime_turn_horizon_finish_rejection_message(
    command, tool_calls, all_tool_results,
  )
  if finish_rejection != "" {
    messages.push(
      mooncode_runtime_context_text_message(
        "user",
        finish_rejection,
        WarningContext,
        "warning.finish_rejection",
      ),
    )
  }
  // Rebuild one cumulative receipt from every durable execution. The recent
  // provider suffix is deliberately compacted during long autonomous runs;
  // a per-batch receipt lets older observations disappear with that suffix
  // and encourages the model to start discovery again. Keeping the compact
  // path/digest ledger cumulative preserves evidence without copying source
  // bytes back into every request.
  let evidence_ledger = mooncode_runtime_turn_model_evidence_ledger_message(
    all_tool_results,
  )
  if mooncode_runtime_turn_model_message_present(evidence_ledger) {
    messages.push(evidence_ledger)
  }
  if patient_replan_guidance != "" {
    messages.push(
      mooncode_runtime_context_text_message(
        "user",
        patient_replan_guidance,
        WarningContext,
        "warning.patient_replan",
      ),
    )
  }
  let skill_receipts = mooncode_runtime_turn_loaded_skill_receipt_messages(
    all_tool_results,
  )
  if mooncode_runtime_turn_requires_verification(command) {
    // Keep the immutable contract after the assistant/tool suffix. Long-lived
    // provider context is weighted toward recent messages; placing recovery
    // guidance before a stale failed checkpoint allowed the stale explanation
    // to override the authoritative contract after compaction.
    let progress = mooncode_runtime_context_normalize_message(
      mooncode_runtime_horizon_progress_message(
        command, all_tool_results, remaining_steps,
      ),
      fallback_kind=EnvironmentContext,
      fallback_source="environment.horizon_progress",
    )
    if skill_receipts.length() == 0 {
      messages.push(
        mooncode_runtime_context_normalize_message(
          progress,
          fallback_kind=EnvironmentContext,
          fallback_source="environment.horizon_progress",
        ),
      )
    } else {
      let content = StringBuilder()
      content.write_string(
        mooncode_json_string(progress, "content", default=""),
      )
      for receipt in skill_receipts {
        content.write_string("\n\n")
        content.write_string(
          mooncode_json_string(receipt, "content", default=""),
        )
      }
      messages.push(
        mooncode_json_object_with_field(
          progress,
          "content",
          Json::string(content.to_string()),
        ),
      )
    }
  } else {
    for receipt in skill_receipts {
      messages.push(
        mooncode_runtime_context_normalize_message(
          receipt,
          fallback_kind=SkillContext,
          fallback_source="skill.loaded_receipt",
        ),
      )
    }
  }
  if mooncode_runtime_turn_discovery_saturation_active(all_tool_results) {
    messages.push(
      mooncode_runtime_context_text_message(
        "user",
        "Implementation lock is active because source discovery saturated without an authored mutation. Your next tool batch MUST contain a substantive edit, write, or apply_patch and MUST NOT contain read, moon_ide, or source-discovery shell calls. Use the retained source snippets and rendered evidence already present. Make the smallest coherent implementation step now; then use focused format/check/build results to discover any correction needed. Repeating or rephrasing an inspection will remain rejected and cannot add evidence.",
        WarningContext,
        "warning.discovery_saturation",
      ),
    )
  }
  for steering in live_steering {
    messages.push(mooncode_runtime_turn_model_live_steering_message(steering))
  }
  messages
}

///|
fn mooncode_runtime_turn_discovery_saturation_active(
  results : Array[Json],
) -> Bool {
  let mut active = false
  for execution in results {
    if mooncode_runtime_turn_result_is_mutation(execution) {
      active = false
    } else {
      let result = mooncode_runtime_turn_result_payload(execution)
      let metadata = mooncode_json_object_field_or_empty(result, "metadata")
      if mooncode_json_bool(metadata, "discovery_saturated", default=false) {
        active = true
      }
    }
  }
  active
}

///|
async fn mooncode_runtime_turn_model_image_evidence_messages(
  command : Json,
  tool_results : Array[Json],
) -> Array[Json] {
  let messages : Array[Json] = []
  let book_root = mooncode_book_root(command)
  if book_root == "" {
    return messages
  }
  for execution in tool_results {
    let result = mooncode_json_object_field_or_empty(execution, "result")
    let metadata = mooncode_json_object_field_or_empty(result, "metadata")
    if !mooncode_json_bool(result, "ok", default=false) ||
      !mooncode_json_bool(metadata, "model_image_evidence", default=false) {
      continue
    }
    let relative = mooncode_json_string(metadata, "path", default="")
    let mime_type = mooncode_json_string(
      metadata,
      "mime_type",
      default="image/png",
    )
    let resolved = mooncode_resolve_book_path(book_root, relative)
    if relative == "" || !mooncode_json_bool(resolved, "ok", default=false) {
      continue
    }
    let absolute = mooncode_json_string(resolved, "absolute_path", default="")
    let bytes = @fs.read_file(absolute).binary() catch { _ => continue }
    if bytes.length() == 0 || bytes.length() > 8 * 1024 * 1024 {
      continue
    }
    let data_url = "data:\{mime_type};base64," + @base64.encode(bytes)
    messages.push(
      mooncode_runtime_context_message(
        {
          "role": "user",
          "content": [
            {
              "type": "text",
              "text": "Visual evidence from MoonBook path `\{relative}`. Inspect the pixels directly and use them with the tool result evidence.",
            },
            {
              "type": "image_url",
              "image_url": { "url": data_url, "detail": "high" },
            },
          ],
        },
        ToolResultContext,
        "tool_result.image_evidence",
      ),
    )
  }
  messages
}

///|
async fn Daemon::mooncode_runtime_turn_model_followup_plan(
  self : Daemon,
  command : Json,
  previous_plan : Json,
  tool_calls : Array[Json],
  tool_results : Array[Json],
  all_tool_results : Array[Json],
  live_steering? : Array[Json] = [],
  remaining_steps? : Int = -1,
  patient_replan_guidance? : String = "",
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
  let response_message = mooncode_json_object_field_or_empty(
    previous_plan, "model_response_message",
  )
  if model_name == "" ||
    !mooncode_runtime_turn_model_message_present(response_message) {
    return mooncode_runtime_turn_failed_planner_result(
      command,
      model_name,
      "model planner cannot continue: missing prior model response",
      started,
      now~,
    )
  }
  let skill_catalog = mooncode_runtime_turn_skill_catalog(
    mooncode_book_root(command),
  )
  let messages = mooncode_runtime_turn_model_followup_messages(
    command,
    previous_plan,
    tool_calls,
    tool_results,
    all_tool_results,
    live_steering,
    remaining_steps,
    patient_replan_guidance~,
    skill_catalog~,
  )
  ignore(remaining_steps)
  match
    mooncode_runtime_turn_resolve_model(
      self.models,
      self.home,
      command,
      model_name,
    ) {
    Some(model) => {
      let followup_tools = mooncode_runtime_turn_model_tools_for_followup(
        command, all_tool_results,
      )
      let semantic_compaction = mooncode_runtime_turn_active_semantic_compaction(
        command,
        previous_plan,
        messages,
        followup_tools,
        model.safe_zone_tokens,
      )
      let request_messages = semantic_compaction.messages
      let request = mooncode_runtime_turn_model_plan_request_from_messages(
        model.model_name,
        request_messages,
        tools=followup_tools,
      )
      let (completion, effective_messages, model_transport) = mooncode_runtime_turn_model_chat(
        model,
        request,
        command,
        source_messages=request_messages,
      ) catch {
        error => {
          let failed = mooncode_runtime_turn_planner_error_result(
            command,
            model_name,
            "model planner follow-up failed",
            error,
            started,
            now~,
          )
          return mooncode_json_object_with_field(
            failed,
            "semantic_compaction_lifecycle",
            semantic_compaction.metrics,
          )
        }
      }
      let response_json = completion.to_json()
      let next_tool_calls = mooncode_runtime_turn_tool_calls_from_model_response(
        response_json,
      )
      if next_tool_calls.length() == 0 {
        if mooncode_runtime_horizon_checkpoint_has_unfinished_milestones(
            command, all_tool_results,
          ) {
          let guidance = "The previous follow-up produced no usable MoonCode tool call while the retained checkpoint still has active or pending milestones. Continue the same claimed task from retained evidence now: choose one causally relevant supported tool call. Do not summarize, abandon, or call finish until the active milestone is repaired or completed and an all-done checkpoint is accepted."
          let replanning = mooncode_event(
            session_id~,
            command_id~,
            lane="runtime",
            kind="runtime.planner_replan_requested",
            title="MoonCode model planner retained unfinished work",
            status="paused",
            detail="MoonClaw retained the claimed command and will ask the model to replan because its accepted checkpoint is unfinished.",
            now~,
          )
          return {
            "kind": mooncode_kind_runtime_turn_planner(),
            "protocol": mooncode_protocol_version(),
            "planner_mode": mooncode_planner_mode_model_tool_calls(),
            "patient_replan": true,
            "model": model_name,
            "tool_calls": Json::array([]),
            "events": Json::array([started, replanning]),
            "message": "model planner follow-up returned no usable MoonCode tool calls while retained milestones remain unfinished",
            "patient_replan_guidance": guidance,
            "semantic_compaction_lifecycle": semantic_compaction.metrics,
          }
        }
        return mooncode_json_object_with_field(
          mooncode_runtime_turn_failed_planner_result(
            command,
            model_name,
            "model planner follow-up returned no usable MoonCode tool calls",
            started,
            now~,
          ),
          "semantic_compaction_lifecycle",
          semantic_compaction.metrics,
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
        "model_transport": model_transport,
        "model_response_id": mooncode_json_string(
          response_json,
          "id",
          default="",
        ),
        "tool_call_count": next_tool_calls.length(),
        "tool_calls": Json::array(next_tool_calls),
        "events": Json::array([started, selected]),
        "planner_metrics": mooncode_runtime_turn_planner_metrics(
          request.to_json(),
          response_json,
          effective_messages,
          next_tool_calls,
          model_transport~,
        ),
        "semantic_compaction_trial": mooncode_runtime_turn_semantic_compaction_trial(
          command, previous_plan, effective_messages,
        ),
        "semantic_compaction_lifecycle": semantic_compaction.metrics,
        "model_messages": Json::array(
          mooncode_runtime_turn_durable_model_messages(effective_messages),
        ),
        "model_response_message": mooncode_runtime_turn_model_response_message(
          response_json,
          normalized_tool_calls=next_tool_calls,
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
fn mooncode_runtime_turn_pipeline_evidence_warning(
  tool_results : Array[Json],
) -> String {
  for result in tool_results {
    if mooncode_json_string(result, "tool", default="") != "shell" {
      continue
    }
    let metadata = mooncode_json_object_field_or_empty(
      mooncode_json_object_field_or_empty(result, "result"),
      "metadata",
    )
    if mooncode_json_bool(metadata, "pipeline_exit_ambiguous", default=false) {
      return "Evidence boundary: this inspection pipeline did not enable pipefail. Its output is usable observation, but its exit status cannot prove that an upstream command succeeded and cannot advance a check, test, or build checkpoint. Rerun only if verification evidence is required, using a direct command or pipefail."
    }
  }
  ""
}

///|
fn mooncode_runtime_turn_model_live_steering_message(steering : Json) -> Json {
  let command_id = mooncode_json_string(steering, "command_id", default="")
  let text = mooncode_json_string(steering, "steering_text", default="")
  mooncode_runtime_context_text_message(
    "user",
    "Live steering for this active turn from command `\{command_id}`:\n\{text}\nApply this instruction before choosing the next MoonCode tool batch. Treat exact file and directory paths in this steering as authoritative; do not substitute guessed paths.",
    UserContext,
    "user.live_steering",
  )
}

///|
fn mooncode_runtime_turn_failed_mutation_path(results : Array[Json]) -> String {
  if results.length() == 0 {
    return ""
  }
  let result = results[results.length() - 1]
  if mooncode_json_bool(result, "accepted", default=false) {
    return ""
  }
  let tool = mooncode_json_string(result, "tool", default="")
  if tool != "edit" &&
    tool != "apply_patch" &&
    tool != "write" &&
    tool != "revert_patch" {
    return ""
  }
  let arguments = mooncode_json_object_field_or_empty(result, "arguments")
  let direct = mooncode_json_string(arguments, "path", default="")
  if mooncode_runtime_turn_mutation_file_path(direct) {
    return direct
  }
  if tool == "apply_patch" || tool == "revert_patch" {
    let diff_path = mooncode_tool_patch_path_from_diff(
      mooncode_json_string(arguments, "diff", default=""),
    )
    if mooncode_runtime_turn_mutation_file_path(diff_path) {
      return diff_path
    }
  }
  let metadata_path = mooncode_json_string(
    mooncode_json_object_field_or_empty(
      mooncode_json_object_field_or_empty(result, "result"),
      "metadata",
    ),
    "path",
    default="",
  )
  if mooncode_runtime_turn_mutation_file_path(metadata_path) {
    metadata_path
  } else {
    ""
  }
}

///|
fn mooncode_runtime_turn_mutation_file_path(path : String) -> Bool {
  path != "" && path != "." && !path.has_suffix("/")
}

///|
fn mooncode_runtime_turn_plan_reads_path(plan : Json, path : String) -> Bool {
  mooncode_json_array_items(plan, "tool_calls").any(call => {
    mooncode_json_string(call, "tool", default="") == "read" &&
    mooncode_json_string(
      mooncode_json_object_field_or_empty(call, "arguments"),
      "path",
      default="",
    ) ==
    path
  })
}

///|
fn mooncode_runtime_turn_recovery_plan(
  plan : Json,
  results : Array[Json],
) -> Json {
  let path = mooncode_runtime_turn_failed_mutation_path(results)
  if path == "" || mooncode_runtime_turn_plan_reads_path(plan, path) {
    return plan
  }
  // Content-based mutation tools fail closed when their assumed source text is
  // stale. Force one exact read before allowing the model to plan another
  // mutation so milestone-driven execution cannot spin on guessed hunks.
  let original_calls = mooncode_json_array_items(plan, "tool_calls")
  let original_id = if original_calls.length() == 0 {
    ""
  } else {
    mooncode_json_string(original_calls[0], "tool_call_id", default="")
  }
  let tool_call_id = if original_id == "" {
    "mooncode-recovery-read-\{results.length()}"
  } else {
    original_id
  }
  let arguments : Json = {
    "path": path,
    "max_output_chars": MOONCODE_MUTATION_RECOVERY_READ_CHARS,
    "mooncode_large_output_enabled": true,
  }
  let calls : Array[Json] = [
    {
      "tool": "read",
      "arguments": arguments,
      "tool_call_id": tool_call_id,
      "planner": "runtime-mutation-recovery",
    },
  ]
  let response_calls : Array[Json] = [
    {
      "id": tool_call_id,
      "type": "function",
      "function": { "name": "read", "arguments": arguments.stringify() },
    },
  ]
  let recovered = mooncode_json_object_with_field(
    plan,
    "tool_calls",
    Json::array(calls),
  )
  mooncode_json_object_with_field(
    recovered,
    "model_response_message",
    mooncode_runtime_context_message(
      {
        "role": "assistant",
        "content": "",
        "tool_calls": Json::array(response_calls),
      },
      AssistantContext,
      "assistant.runtime_recovery",
    ),
  )
}

///|
fn mooncode_runtime_turn_model_response_message(
  response : Json,
  normalized_tool_calls? : Array[Json] = [],
) -> Json {
  let choices = match response {
    { "choices": Array(items), .. } => items
    _ => []
  }
  if choices.length() == 0 {
    return {}
  }
  let message = mooncode_json_object_field_or_empty(choices[0], "message")
  let response_tool_calls = if normalized_tool_calls.length() == 0 {
    mooncode_json_array_items(message, "tool_calls")
  } else {
    normalized_tool_calls.map(call => {
      "id": mooncode_json_string(call, "tool_call_id", default=""),
      "type": "function",
      "function": {
        "name": mooncode_json_string(call, "tool", default=""),
        "arguments": mooncode_json_object_field_or_empty(call, "arguments").stringify(),
      },
    })
  }
  mooncode_runtime_context_message(
    {
      "role": "assistant",
      "content": mooncode_json_string(message, "content", default=""),
      "tool_calls": Json::array(response_tool_calls),
    },
    AssistantContext,
    "assistant.model_response",
  )
}

///|
fn mooncode_runtime_turn_model_message_present(message : Json) -> Bool {
  mooncode_json_array_items(message, "tool_calls").length() > 0 ||
  mooncode_json_string(message, "content", default="") != ""
}

///|
fn mooncode_runtime_turn_model_tool_call_accepts_result(
  tool_call : Json,
) -> Bool {
  mooncode_json_string(tool_call, "planner", default="") !=
  "model-assistant-content" &&
  mooncode_json_string(tool_call, "tool_call_id", default="") != ""
}

///|
fn mooncode_runtime_turn_model_tool_result_message(
  tool_call : Json,
  execution : Json,
) -> Json {
  mooncode_runtime_context_message(
    {
      "role": "tool",
      "tool_call_id": mooncode_json_string(
        tool_call,
        "tool_call_id",
        default="",
      ),
      "content": mooncode_runtime_turn_model_tool_result_content(execution),
    },
    ToolResultContext,
    "tool_result.execution",
  )
}

///|
fn mooncode_runtime_turn_model_tool_result_messages(
  tool_calls : Array[Json],
  tool_results : Array[Json],
) -> Array[Json] {
  let messages : Array[Json] = []
  for index in 0..<tool_calls.length() {
    let tool_call = tool_calls[index]
    if mooncode_runtime_turn_model_tool_call_accepts_result(tool_call) {
      let execution = if index < tool_results.length() {
        tool_results[index]
      } else {
        {
          "tool": mooncode_json_string(tool_call, "tool", default=""),
          "accepted": false,
          "result": {
            "ok": false,
            "message": "tool call was not executed because an earlier call ended the batch; select it again only if it is still needed",
            "metadata": { "skipped": true },
          },
        }
      }
      messages.push(
        mooncode_runtime_turn_model_tool_result_message(tool_call, execution),
      )
    }
  }
  messages
}

///|
fn mooncode_runtime_turn_model_tool_result_content(execution : Json) -> String {
  let result = mooncode_json_object_field_or_empty(execution, "result")
  let event = mooncode_json_object_field_or_empty(execution, "event")
  let event_id = mooncode_json_string(event, "id", default="")
  let payload : Json = {
    "result": result,
    "evidence_ref": if event_id == "" {
      ""
    } else {
      event_id
    },
  }
  let text = payload.stringify(indent=2)
  let tool = mooncode_json_string(execution, "tool", default="")
  let context_limit = if tool == "read" { 40000 } else { 4000 }
  if tool == "read_skill" {
    text
  } else if text.length() > context_limit {
    mooncode_utf8_prefix_within(text, context_limit) +
    "\n...[truncated for planner context]"
  } else {
    text
  }
}

///|
fn mooncode_runtime_turn_model_completed_steps(messages : Array[Json]) -> Int {
  let mut count = 0
  for message in messages {
    if mooncode_json_string(message, "role", default="") == "assistant" &&
      mooncode_json_array_items(message, "tool_calls").length() > 0 {
      count += 1
    }
  }
  count
}

///|
fn mooncode_runtime_turn_model_transcript_has_mutation(
  messages : Array[Json],
) -> Bool {
  for message in messages {
    if mooncode_json_string(message, "role", default="") == "assistant" {
      for tool_call in mooncode_json_array_items(message, "tool_calls") {
        let function = mooncode_json_object_field_or_empty(
          tool_call, "function",
        )
        let name = mooncode_json_string(function, "name", default="")
        if name == "write" || name == "edit" || name == "apply_patch" {
          return true
        }
      }
    }
  }
  false
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
