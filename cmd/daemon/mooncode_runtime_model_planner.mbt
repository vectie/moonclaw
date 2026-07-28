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
  let selected_model = self.models.get_model(name=requested_model)
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
      let skill_catalog = mooncode_runtime_turn_skill_catalog(
        mooncode_book_root(command),
      )
      let messages = mooncode_runtime_turn_model_messages(
        command,
        live_steering,
        remaining_steps,
        skill_catalog~,
      )
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
        "model_messages": Json::array(messages),
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
    stream=true,
    temperature=0.0,
  )
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
    return tools
  }
  if path != "" && mooncode_runtime_turn_read_needs_model(request) {
    return [tools[0], tools[7], tools[10]]
  }
  [tools[7], tools[10]]
}

///|
fn mooncode_runtime_turn_model_needs_coding_tools(
  command : Json,
  request : String,
) -> Bool {
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
fn mooncode_runtime_turn_result_is_mutation(result : Json) -> Bool {
  if !mooncode_json_bool(result, "accepted", default=false) {
    return false
  }
  let tool = mooncode_json_string(result, "tool", default="")
  tool == "write" ||
  tool == "edit" ||
  tool == "apply_patch" ||
  tool == "revert_patch"
}

///|
fn mooncode_runtime_turn_result_mutation_states(result : Json) -> Array[Json] {
  if !mooncode_runtime_turn_result_is_mutation(result) {
    return []
  }
  let metadata = mooncode_json_object_field_or_empty(
    mooncode_json_object_field_or_empty(result, "result"),
    "metadata",
  )
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
    let verification_kind = mooncode_json_string(
      mooncode_json_object_field_or_empty(result, "arguments"),
      "verification_kind",
      default="",
    )
    if verification_kind == "check" ||
      verification_kind == "test" ||
      verification_kind == "build" {
      return verification_kind
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
      last_mutation = index
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
    if last_mutation < 0 {
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
    if required_verification < last_mutation {
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
  if mooncode_runtime_horizon_explicit_id(command) == "" ||
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
  if mooncode_runtime_horizon_explicit_id(command) == "" ||
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
fn mooncode_runtime_turn_model_initial_messages(
  command : Json,
  skill_catalog? : String = "",
) -> Array[Json] {
  [
    {
      "role": "system",
      "content": "You are MoonClaw's MoonCode planner. Choose bounded MoonCode tool batches to satisfy the user's request inside the selected MoonBook only. A bounded tool batch is not a task budget. Unless the caller explicitly supplies a budget, the task has no implicit token, turn, time, step, context-size, or effort ceiling. Difficulty, elapsed work, a large context, or needing more tool batches are not blockers; continue useful work. Honor real caller-supplied budgets exactly. Never invent a token-budget-exhausted, turn-budget-exhausted, time-budget-exhausted, or step-budget-exhausted blocker unless that exact caller-supplied budget exists and is actually exhausted. Only a genuine external dependency or missing user input or authority that prevents meaningful progress can block a task. Use checkpoint/read_skill/write/edit/apply_patch/read/shell/moon_ide/moon_cmd/moon_check/finish. When a selected skill directs MoonBit work, prefer semantic discovery with moon_ide before broad source reads and prefer moon_cmd/moon_check over raw shell for validation. Never use paths outside the MoonBook root. Never use shell, an interpreter, or an inline script to author workspace files; all authored mutations must use edit, write, or apply_patch. For an implementation request, include a checkpoint in the first batch and update the checkpoint whenever a milestone changes. Gather enough evidence to distinguish plausible causes before mutating. Avoid repeating equivalent inspections of the same evidence; every additional diagnostic should distinguish competing causes or expose missing causal evidence. Treat successful repository status, diff, and hosted-result reads as retained until repository or hosted state changes. Prefer one cohesive multi-file patch when the evidence supports it, and do not initialize a nested repository or generic project scaffold unless explicitly requested. A comment-only or documentation-only mutation does not satisfy an implementation or defect-repair request; repair behavior, configuration, tests, or another substantive contract instead. Treat validation failures as new evidence: inspect the exact failure before changing the implementation or environment. Once a repair passes the exact gate it targeted, retain that result as established evidence; a later failure at a different gate is a new problem, and does not justify reverting the earlier repair unless new evidence directly falsifies it. Do not infer environment-specific causality from a local pass: reproduce in the failing environment or expose the exact underlying error before claiming a fix. A shell pipeline used as evidence must enable pipefail, because its ordinary exit status reflects only the final stage. If a required validator enforces a clean version-control state, do not repeat it against the same intended dirty state; use an authorized reversible checkpoint, validate that clean state, and publish only after validation succeeds. If a necessary tool call requires operator approval, select the exact tool call; the runtime will pause before execution. Never ask for tool approval in assistant prose or use finish to request it. If the operator rejects a tool call, obey its rationale and do not retry the same action by rewriting or splitting the command. Never guess a toolchain or dependency-management command; inspect its local help or the repository's existing version mechanism before changing versions. Respect explicit user constraints as hard boundaries. When an active capability resolution is supplied, use only selected_capability as the active version; shadow_capability is observation-only, and an unavailable assignment must never be invented or treated as active. Before finish, record a checkpoint with every required milestone done. Call `finish` only when the task is complete; otherwise use tools and wait for tool results before deciding the next batch." +
      " Never include finish.goal_runtime unless active goal_runtime context is explicitly present in the current request. When it is present, ordinary finish is only a progress turn: use finish.goal_runtime with an exact achieved or blocked decision only when the whole goal reaches a terminal outcome. Blocked still requires a genuine external or user-authority blocker; task difficulty, elapsed work, context size, and implicit limits do not qualify. Achieved evidence must cover every listed criterion id exactly once." +
      skill_catalog,
    },
    { "role": "user", "content": mooncode_runtime_turn_model_prompt(command) },
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
    previous
  } else {
    let messages = mooncode_runtime_turn_model_initial_messages(
      command,
      skill_catalog~,
    )
    for
      retained in mooncode_runtime_turn_loaded_skill_messages(all_tool_results) {
      messages.push(retained)
    }
    messages
  }
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
  "\n\nChoose the smallest useful tool batch. Use finish immediately when no code or tool work is needed. Keep all paths relative to the selected MoonBook."
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
      "Run a bounded shell command inside the selected MoonBook. Set verification_kind only when this command's zero exit status directly proves that exact check, test, or build gate; ordinary inspection commands must omit it.",
      {
        "type": "object",
        "properties": {
          "cmd": { "type": "string" },
          "cwd": { "type": "string" },
          "timeout_ms": { "type": "integer" },
          "max_output_chars": { "type": "integer" },
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
      "Finish only completed work with a concise operator-facing summary. Never use finish to request approval; select the exact gated tool call and let the runtime pause. goal_runtime is available only when the current request explicitly includes an active long-running goal.",
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
    if mooncode_tool_supported(tool) || tool == "checkpoint" {
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
  all_tool_results : Array[Json],
  live_steering? : Array[Json] = [],
  remaining_steps? : Int = -1,
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
  let messages = mooncode_runtime_turn_model_followup_base_messages(
    command,
    previous_plan,
    tool_results,
    all_tool_results~,
    skill_catalog~,
  )
  let prior_results : Array[Json] = []
  let prior_count = if all_tool_results.length() > tool_results.length() {
    all_tool_results.length() - tool_results.length()
  } else {
    0
  }
  for index in 0..<prior_count {
    prior_results.push(all_tool_results[index])
  }
  if mooncode_runtime_turn_requires_verification(command) {
    messages.push(
      mooncode_runtime_horizon_progress_message(
        command, prior_results, remaining_steps,
      ),
    )
  }
  messages.push(response_message)
  for
    message in mooncode_runtime_turn_model_tool_result_messages(
      tool_calls, tool_results,
    ) {
    messages.push(message)
  }
  let pipeline_warning = mooncode_runtime_turn_pipeline_evidence_warning(
    tool_results,
  )
  if pipeline_warning != "" {
    messages.push({ "role": "user", "content": pipeline_warning })
  }
  let finish_rejection = mooncode_runtime_turn_horizon_finish_rejection_message(
    command, tool_calls, all_tool_results,
  )
  if finish_rejection != "" {
    messages.push({ "role": "user", "content": finish_rejection })
  }
  for steering in live_steering {
    messages.push(mooncode_runtime_turn_model_live_steering_message(steering))
  }
  ignore(remaining_steps)
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
      return "Evidence boundary: this shell pipeline did not enable pipefail, so its exit status reflects only the final pipeline stage and cannot prove that an upstream command succeeded. Do not rely on it, commit from it, or advance a checkpoint from it. Rerun the evidence command directly or with pipefail enabled."
    }
  }
  ""
}

///|
fn mooncode_runtime_turn_model_live_steering_message(steering : Json) -> Json {
  let command_id = mooncode_json_string(steering, "command_id", default="")
  let text = mooncode_json_string(steering, "steering_text", default="")
  {
    "role": "user",
    "content": "Live steering for this active turn from command `\{command_id}`:\n\{text}\nApply this instruction before choosing the next MoonCode tool batch.",
  }
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
  let arguments : Json = { "path": path, "max_output_chars": 120000 }
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
  mooncode_json_object_with_field(recovered, "model_response_message", {
    "role": "assistant",
    "content": "",
    "tool_calls": Json::array(response_calls),
  })
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
  {
    "role": "tool",
    "tool_call_id": mooncode_json_string(tool_call, "tool_call_id", default=""),
    "content": mooncode_runtime_turn_model_tool_result_content(execution),
  }
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
  if mooncode_json_string(execution, "tool", default="") == "read_skill" {
    text
  } else if text.length() > 4000 {
    text[:4000].to_owned() + "\n...[truncated for planner context]"
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
