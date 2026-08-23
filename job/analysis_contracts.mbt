///|
pub(all) struct AnalysisToolContract {
  shell : Bool
  list_files : Bool
  glob_files : Bool
  list_resources : Bool
  read_resource : Bool
  runtime_context : Bool
  list_worktrees : Bool
  delegate_run : Bool
  enter_worktree : Bool
  exit_worktree : Bool
  read_files : Bool
  search_files : Bool
  todo : Bool
  file_write : Bool
  patch_edit : Bool
  unlimited_ocr : Bool
  web_fetch : Bool
  web_search : Bool
} derive(ToJson, FromJson, Debug)

///|
pub fn AnalysisToolContract::new(
  shell? : Bool = true,
  list_files? : Bool = true,
  glob_files? : Bool = true,
  list_resources? : Bool = true,
  read_resource? : Bool = true,
  runtime_context? : Bool = false,
  list_worktrees? : Bool = false,
  delegate_run? : Bool = false,
  enter_worktree? : Bool = false,
  exit_worktree? : Bool = false,
  read_files? : Bool = true,
  search_files? : Bool = true,
  todo? : Bool = true,
  file_write? : Bool = true,
  patch_edit? : Bool = true,
  unlimited_ocr? : Bool = true,
  web_fetch? : Bool = false,
  web_search? : Bool = false,
) -> AnalysisToolContract {
  {
    shell,
    list_files,
    glob_files,
    list_resources,
    read_resource,
    runtime_context,
    list_worktrees,
    delegate_run,
    enter_worktree,
    exit_worktree,
    read_files,
    search_files,
    todo,
    file_write,
    patch_edit,
    unlimited_ocr,
    web_fetch,
    web_search,
  }
}

///|
fn default_analysis_tool_contract(enable_tools : Bool) -> AnalysisToolContract {
  if !enable_tools {
    AnalysisToolContract::new(
      shell=false,
      list_files=false,
      glob_files=false,
      list_resources=false,
      read_resource=false,
      runtime_context=false,
      list_worktrees=false,
      delegate_run=false,
      enter_worktree=false,
      exit_worktree=false,
      read_files=false,
      search_files=false,
      todo=false,
      file_write=false,
      patch_edit=false,
      unlimited_ocr=false,
      web_fetch=false,
      web_search=false,
    )
  } else {
    AnalysisToolContract::new(delegate_run=true, patch_edit=true)
  }
}

///|
pub fn analysis_tool_contract(
  config : AnalysisStepConfig,
) -> AnalysisToolContract {
  let fallback = default_analysis_tool_contract(config.enable_tools)
  match metadata_with_step_metadata(config.metadata, "tool_contract") {
    Some(json) => @json.from_json(json) catch { _ => fallback }
    None => fallback
  }
}

///|
pub fn constrain_tool_contract_for_role(
  contract : AnalysisToolContract,
  role_runtime_contract : RoleRuntimeContract?,
) -> AnalysisToolContract {
  match role_runtime_contract {
    None => contract
    Some(role) => {
      let delegate_run = if role.allow_delegate {
        contract.delegate_run
      } else {
        false
      }
      let writable = role.allow_workspace_write
      let execution_tools = role.allow_execution_tools
      match role.tool_access {
        Disabled =>
          AnalysisToolContract::new(
            shell=false,
            list_files=false,
            glob_files=false,
            list_resources=false,
            read_resource=false,
            runtime_context=false,
            list_worktrees=false,
            delegate_run=false,
            enter_worktree=false,
            exit_worktree=false,
            read_files=false,
            search_files=false,
            todo=false,
            file_write=false,
            patch_edit=false,
            unlimited_ocr=false,
            web_fetch=false,
            web_search=false,
          )
        Limited =>
          AnalysisToolContract::new(
            shell=false,
            list_files=contract.list_files,
            glob_files=contract.glob_files,
            list_resources=contract.list_resources,
            read_resource=contract.read_resource,
            runtime_context=contract.runtime_context,
            list_worktrees=false,
            delegate_run~,
            enter_worktree=false,
            exit_worktree=false,
            read_files=contract.read_files,
            search_files=contract.search_files,
            todo=contract.todo,
            file_write=false,
            patch_edit=false,
            unlimited_ocr=false,
            web_fetch=false,
            web_search=false,
          )
        Full =>
          AnalysisToolContract::new(
            shell=contract.shell && execution_tools,
            list_files=contract.list_files,
            glob_files=contract.glob_files,
            list_resources=contract.list_resources,
            read_resource=contract.read_resource,
            runtime_context=contract.runtime_context,
            list_worktrees=contract.list_worktrees && execution_tools,
            delegate_run~,
            enter_worktree=contract.enter_worktree && execution_tools,
            exit_worktree=contract.exit_worktree && execution_tools,
            read_files=contract.read_files,
            search_files=contract.search_files,
            todo=contract.todo,
            file_write=contract.file_write && writable && execution_tools,
            patch_edit=contract.patch_edit && writable && execution_tools,
            unlimited_ocr=contract.unlimited_ocr && execution_tools,
            web_fetch=contract.web_fetch && execution_tools,
            web_search=contract.web_search && execution_tools,
          )
      }
    }
  }
}

///|
fn constrain_tool_contract_for_request(
  request : AnalysisRequest,
) -> AnalysisToolContract {
  let constrained = constrain_tool_contract_for_role(
    request.tool_contract,
    request.role_runtime_contract,
  )
  let provider_derived = metadata_bool_with_step_metadata(
    request.step_metadata,
    "provider_subplan_execution",
    false,
  )
  if provider_execution_requested(request.execution_mode) || provider_derived {
    {
      ..constrained,
      shell: false,
      list_resources: false,
      read_resource: false,
      list_worktrees: false,
      delegate_run: false,
      enter_worktree: false,
      exit_worktree: false,
      todo: false,
      web_fetch: constrained.web_fetch && request.web_search,
      web_search: constrained.web_search && request.web_search,
      unlimited_ocr: constrained.unlimited_ocr,
    }
  } else {
    constrained
  }
}

///|
pub fn analysis_result_content_contract(config : AnalysisStepConfig) -> String? {
  metadata_string(config.metadata, "result_content_json_contract")
}

///|
fn has_text_prefix(text : String, prefix : String) -> Bool {
  text.length() >= prefix.length() && text[:prefix.length()] == prefix
}

///|
fn normalize_blocker_payload(value : String) -> String {
  value.trim().trim(chars=" -[]{}'\"`.,;").to_owned()
}

///|
fn blocker_payload_is_empty(value : String) -> Bool {
  match normalize_blocker_payload(value) {
    "" | "none" | "no" | "n/a" | "na" | "null" | "false" => true
    _ => false
  }
}

///|
fn is_result_marker_line(line : String) -> Bool {
  if has_text_prefix(line, "-") {
    false
  } else {
    has_text_prefix(line, "planbook_decision:") ||
    has_text_prefix(line, "repair_decision:") ||
    has_text_prefix(line, "result_decision:") ||
    has_text_prefix(line, "decision:") ||
    has_text_prefix(line, "plan_path:") ||
    has_text_prefix(line, "acceptance_criteria:") ||
    has_text_prefix(line, "validation:") ||
    has_text_prefix(line, "validation_commands:") ||
    has_text_prefix(line, "changed_artifacts:") ||
    has_text_prefix(line, "follow_up_gaps:") ||
    has_text_prefix(line, "requires_review:") ||
    has_text_prefix(line, "notify_town:")
  }
}

///|
fn remaining_blockers_has_content(lower : String) -> Bool {
  let marker = "remaining_blockers:"
  let mut reading_blockers = false
  for raw in lower.split("\n") {
    let line = raw.trim().to_owned()
    if line.is_blank() {
      continue
    }
    if has_text_prefix(line, marker) {
      let payload = normalize_blocker_payload(line[marker.length():].to_owned())
      if payload.is_blank() {
        reading_blockers = true
        continue
      }
      return !blocker_payload_is_empty(payload)
    }
    if reading_blockers {
      if is_result_marker_line(line) {
        return false
      }
      if !blocker_payload_is_empty(line) {
        return true
      }
    }
  }
  false
}

///|
fn json_remaining_blockers_has_content(lower : String) -> Bool {
  let compact = lower
    .replace(old=" ", new="")
    .replace(old="\n", new="")
    .replace(old="\r", new="")
    .replace(old="\t", new="")
  if !compact.contains("\"remaining_blockers\":") {
    return false
  }
  if compact.contains("\"remaining_blockers\":[]") ||
    compact.contains("\"remaining_blockers\":null") ||
    compact.contains("\"remaining_blockers\":false") ||
    compact.contains("\"remaining_blockers\":\"\"") ||
    compact.contains("\"remaining_blockers\":\"none\"") ||
    compact.contains("\"remaining_blockers\":[\"none\"]") ||
    compact.contains("\"remaining_blockers\":[\"n/a\"]") ||
    compact.contains("\"remaining_blockers\":[\"na\"]") {
    false
  } else {
    compact.contains("\"remaining_blockers\":[") ||
    compact.contains("\"remaining_blockers\":\"")
  }
}

///|
fn analysis_result_decision_from_text(content : String) -> String {
  let lower = content.to_lower()
  if lower.contains("repair_decision: needs_external_owner") ||
    lower.contains("repair_decision: blocked") ||
    remaining_blockers_has_content(lower) ||
    json_remaining_blockers_has_content(lower) ||
    lower.contains("\"result_decision\":\"blocked\"") ||
    lower.contains("\"result_decision\": \"blocked\"") {
    "blocked"
  } else if lower.contains("repair_decision: no_change") ||
    lower.contains("\"result_decision\":\"no_change\"") ||
    lower.contains("\"result_decision\": \"no_change\"") {
    "no_change"
  } else if lower.contains("repair_decision: review") ||
    lower.contains("\"result_decision\":\"review\"") ||
    lower.contains("\"result_decision\": \"review\"") {
    "review"
  } else {
    "accepted"
  }
}

///|
fn normalize_analysis_result_decision(value : String) -> String? {
  match value.trim().to_lower() {
    "accepted" => Some("accepted")
    "no_change" => Some("no_change")
    "review" => Some("review")
    "blocked" => Some("blocked")
    _ => None
  }
}

///|
fn analysis_result_decision(
  config : AnalysisStepConfig,
  execution : AnalysisExecution,
) -> String {
  match metadata_with_step_metadata(execution.metadata, "result_decision") {
    Some(String(value)) =>
      match normalize_analysis_result_decision(value) {
        Some(decision) => return decision
        None => ()
      }
    _ => ()
  }
  match metadata_string(config.metadata, "result_decision") {
    Some(value) =>
      match normalize_analysis_result_decision(value) {
        Some(decision) => decision
        None => analysis_result_decision_from_text(execution.content)
      }
    None => analysis_result_decision_from_text(execution.content)
  }
}

///|
pub fn structured_analysis_result_payload(
  step_id : String,
  config : AnalysisStepConfig,
  execution : AnalysisExecution,
) -> Json {
  let decision = analysis_result_decision(config, execution)
  let payload : Map[String, Json] = {
    "step_id": step_id.to_json(),
    "result_decision": decision.to_json(),
    "requires_review": (decision == "review" || decision == "blocked").to_json(),
    "notify_town": (decision != "no_change").to_json(),
    "model": execution.model_name.to_json(),
    "content": execution.content.to_json(),
    "conversation_id": execution.conversation_id.to_json(),
    "usage": usage_json(execution.usage),
    "metadata": compact_analysis_result_metadata(execution.metadata),
  }
  match analysis_result_content_contract(config) {
    Some(contract) => {
      payload.set("content_contract", contract.to_json())
      if contract == presentation_contract_version() {
        match parse_presentation_deck_spec_text(execution.content) {
          Some(spec) => payload.set("parsed_content", spec.to_json())
          None => ()
        }
      } else if contract == presentation_render_contract_version() {
        match parse_presentation_render_package_text(execution.content) {
          Some(spec) => payload.set("parsed_content", spec.to_json())
          None => ()
        }
      }
    }
    None => ()
  }
  Json::object(payload)
}

///|
fn enabled_tool_names(contract : AnalysisToolContract) -> Array[String] {
  let tools : Array[String] = []
  if contract.shell {
    tools.push("execute_command")
  }
  if contract.list_files {
    tools.push("list_files")
  }
  if contract.glob_files {
    tools.push("glob_files")
  }
  if contract.list_resources {
    tools.push("list_resources")
  }
  if contract.read_resource {
    tools.push("read_resource")
  }
  if contract.runtime_context {
    tools.push("runtime_context")
  }
  if contract.list_worktrees {
    tools.push("list_worktrees")
  }
  if contract.delegate_run {
    tools.push("delegate_run")
  }
  if contract.enter_worktree {
    tools.push("enter_worktree")
  }
  if contract.exit_worktree {
    tools.push("exit_worktree")
  }
  if contract.read_files {
    tools.push("read_file")
  }
  if contract.todo {
    tools.push("todo")
  }
  if contract.search_files {
    tools.push("search_files")
  }
  if contract.web_search {
    tools.push("web_search")
  }
  if contract.web_fetch {
    tools.push("web_fetch")
  }
  if contract.unlimited_ocr {
    tools.push("unlimited_ocr")
  }
  if contract.file_write {
    tools.push("file_write")
  }
  if contract.patch_edit {
    tools.push("patch_edit")
  }
  tools
}

///|
fn runtime_context_tool_result(
  request : AnalysisRequest,
) -> @runtime_context.RuntimeContextResult {
  @runtime_context.RuntimeContextResult::new(
    cwd=request.cwd,
    home=request.home,
    run_id=Some(request.run_id),
    job_id=Some(request.job_id),
    step_id=Some(request.step_id),
    model_name=requested_model_name_or_none(request.model_name),
    execution_mode=request.execution_mode,
    execution_target=request.execution_target,
    execution_isolation=request.execution_isolation,
    enabled_tools=enabled_tool_names(
      constrain_tool_contract_for_request(request),
    ),
  )
}

///|
pub fn configure_analysis_agent_for_contract(
  agent : @agent.Agent,
  cwd : String,
  home : String?,
  contract : AnalysisToolContract,
  sandbox_config? : @execution_sandbox.SandboxExecutorConfig,
) -> Unit {
  let file_manager = @file.manager(cwd~)
  let todo_list = @todo.new(uuid=agent.uuid, cwd=agent.cwd)
  let builtin_tools = []
  if contract.shell {
    builtin_tools.push(
      @execute_command.new(cwd, home?, sandbox_config?).to_agent_tool(),
    )
  }
  if contract.list_files {
    builtin_tools.push(@list_files.new(file_manager).to_agent_tool())
  }
  if contract.glob_files {
    builtin_tools.push(@glob_files.new(agent.cwd).to_agent_tool())
  }
  if contract.list_resources {
    builtin_tools.push(@list_resources.new(agent.cwd, home~).to_agent_tool())
  }
  if contract.read_resource {
    builtin_tools.push(@read_resource.new(agent.cwd, home~).to_agent_tool())
  }
  if contract.enter_worktree {
    builtin_tools.push(@enter_worktree.new(agent.cwd).to_agent_tool())
  }
  if contract.exit_worktree {
    builtin_tools.push(@exit_worktree.new(agent.cwd).to_agent_tool())
  }
  if contract.delegate_run {
    builtin_tools.push(@delegate_run.new().to_agent_tool())
  }
  if contract.read_files {
    builtin_tools.push(@read_file.new(file_manager).to_agent_tool())
  }
  if contract.todo {
    builtin_tools.push(@todo.new_tool(todo_list).to_agent_tool())
  }
  if contract.search_files {
    builtin_tools.push(@search_files.new(agent.cwd).to_agent_tool())
  }
  if !builtin_tools.is_empty() {
    agent.add_tools(builtin_tools)
  }
  if contract.web_search {
    agent.add_tool(@web_search.new())
  }
  if contract.web_fetch {
    agent.add_tool(@web_fetch.new())
  }
  if contract.unlimited_ocr {
    agent.add_tool(@unlimited_ocr.new(agent.cwd))
  }
  if contract.file_write {
    if agent.model.supports_apply_patch {
      agent.add_tool(@apply_patch.new(agent.cwd))
    } else {
      agent.add_tool(@write_to_file.new(agent.cwd))
    }
  }
  if contract.patch_edit {
    agent.add_tool(@patch_edit.new(agent.cwd))
  }
}

///|
pub fn configure_analysis_agent_for_request(
  agent : @agent.Agent,
  request : AnalysisRequest,
  sandbox_config? : @execution_sandbox.SandboxExecutorConfig,
) -> Unit {
  let constrained = constrain_tool_contract_for_request(request)
  configure_analysis_agent_for_contract(
    agent,
    request.cwd,
    request.home,
    constrained,
    sandbox_config?,
  )
  if constrained.runtime_context {
    agent.add_tool(@runtime_context.new(runtime_context_tool_result(request)))
  }
  if constrained.list_worktrees {
    agent.add_tool(@list_worktrees.new(request.cwd))
  }
}

///|
pub fn configure_analysis_agent_tools(
  agent : @agent.Agent,
  cwd : String,
  web_search? : Bool = false,
  sandbox_config? : @execution_sandbox.SandboxExecutorConfig,
) -> Unit {
  configure_analysis_agent_for_contract(
    agent,
    cwd,
    None,
    AnalysisToolContract::new(web_fetch=web_search, web_search~),
    sandbox_config?,
  )
}
