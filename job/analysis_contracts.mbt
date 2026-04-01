///|
pub(all) struct AnalysisToolContract {
  shell : Bool
  list_files : Bool
  glob_files : Bool
  read_resource : Bool
  read_files : Bool
  search_files : Bool
  todo : Bool
  file_write : Bool
  web_fetch : Bool
  web_search : Bool
} derive(ToJson, FromJson, Show)

///|
pub fn AnalysisToolContract::new(
  shell? : Bool = true,
  list_files? : Bool = true,
  glob_files? : Bool = true,
  read_resource? : Bool = true,
  read_files? : Bool = true,
  search_files? : Bool = true,
  todo? : Bool = true,
  file_write? : Bool = true,
  web_fetch? : Bool = false,
  web_search? : Bool = false,
) -> AnalysisToolContract {
  AnalysisToolContract::{
    shell,
    list_files,
    glob_files,
    read_resource,
    read_files,
    search_files,
    todo,
    file_write,
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
      read_resource=false,
      read_files=false,
      search_files=false,
      todo=false,
      file_write=false,
      web_fetch=false,
      web_search=false,
    )
  } else {
    AnalysisToolContract::new(web_fetch=web_search, web_search~)
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
      }
    }
    None => ()
  }
  Json::object(payload)
}

///|
pub fn setup_analysis_agent_for_contract(
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
  if contract.read_resource {
    builtin_tools.push(@read_resource.new(agent.cwd, home=home).to_agent_tool())
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
}

///|
pub fn setup_analysis_agent(
  agent : @agent.Agent,
  cwd : String,
  web_search? : Bool = false,
) -> Unit {
  setup_analysis_agent_for_contract(
    agent,
    cwd,
    None,
    AnalysisToolContract::new(web_fetch=web_search, web_search~),
  )
}
