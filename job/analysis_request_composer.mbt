///|
pub async fn compose_job_analysis_request(
  store : SystemStore,
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
) -> AnalysisRequest {
  let execution_isolation = resolve_analysis_execution_isolation(
    context,
    config,
    analysis_working_directory(context, config),
  )
  let working_directory = execution_isolation.cwd
  let skills_prompt = loaded_skills_prompt(
    working_directory,
    config.home,
    config.preferred_skills,
  )
  let memory_prompt = analysis_memory_prompt(store, context, config)
  AnalysisRequest::{
    job_id: context.run.job_id,
    run_id: context.run.id,
    step_id: context.step.id,
    prompt: build_analysis_prompt(context, config, skills_prompt, memory_prompt),
    model_name: config.model.unwrap_or("default"),
    cwd: working_directory,
    home: config.home,
    execution_mode: config.execution_mode,
    execution_target: config.execution_target,
    system_prompt: analysis_system_prompt(config),
    preferred_skills: config.preferred_skills,
    enable_tools: config.enable_tools,
    web_search: config.web_search,
    tool_contract: analysis_tool_contract(config),
    execution_isolation: execution_isolation.metadata,
  }
}
