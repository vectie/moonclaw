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
  web_fetch : Bool
  web_search : Bool
} derive(ToJson, FromJson, Show)

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
  web_fetch? : Bool = false,
  web_search? : Bool = false,
) -> AnalysisToolContract {
  AnalysisToolContract::{
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
    web_fetch,
    web_search,
  }
}

///|
fn default_analysis_tool_contract(
  enable_tools : Bool,
  web_search : Bool,
) -> AnalysisToolContract {
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
      web_fetch=false,
      web_search=false,
    )
  } else {
    AnalysisToolContract::new(
      delegate_run=true,
      patch_edit=true,
      web_fetch=web_search,
      web_search~,
    )
  }
}

///|
pub fn analysis_tool_contract(
  config : AnalysisStepConfig,
) -> AnalysisToolContract {
  let fallback = default_analysis_tool_contract(
    config.enable_tools,
    config.web_search,
  )
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
            web_fetch=contract.web_fetch && execution_tools,
            web_search=contract.web_search && execution_tools,
          )
      }
    }
  }
}

///|
pub fn analysis_result_content_contract(config : AnalysisStepConfig) -> String? {
  metadata_string(config.metadata, "result_content_json_contract")
}

///|
pub fn structured_analysis_result_payload(
  step_id : String,
  config : AnalysisStepConfig,
  execution : AnalysisExecution,
) -> Json {
  let payload : Map[String, Json] = {
    "step_id": step_id.to_json(),
    "model": execution.model_name.to_json(),
    "content": execution.content.to_json(),
    "conversation_id": execution.conversation_id.to_json(),
    "usage": usage_json(execution.usage),
    "metadata": execution.metadata,
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
      constrain_tool_contract_for_role(
        request.tool_contract,
        request.role_runtime_contract,
      ),
    ),
  )
}

///|
pub fn configure_analysis_agent_for_contract(
  agent : @agent.Agent,
  cwd : String,
  home : String?,
  contract : AnalysisToolContract,
) -> Unit {
  let file_manager = @file.manager(cwd~)
  let todo_list = @todo.new(uuid=agent.uuid, cwd=agent.cwd)
  let builtin_tools = []
  if contract.shell {
    builtin_tools.push(@execute_command.new(cwd).to_agent_tool())
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
) -> Unit {
  let constrained = constrain_tool_contract_for_role(
    request.tool_contract,
    request.role_runtime_contract,
  )
  configure_analysis_agent_for_contract(
    agent,
    request.cwd,
    request.home,
    constrained,
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
) -> Unit {
  configure_analysis_agent_for_contract(
    agent,
    cwd,
    None,
    AnalysisToolContract::new(web_fetch=web_search, web_search~),
  )
}
