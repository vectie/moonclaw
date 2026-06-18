///|
/// Provider-task prompt construction and skill hydration.
///
/// This layer is allowed to describe how the provider worker should behave, but
/// it must not materialize provider-owned domain outputs itself.
fn join_bullets(items : Array[String]) -> String {
  if items.is_empty() {
    "- none"
  } else {
    items.map(fn(item) { "- \{item}" }).join("\n")
  }
}

///|
fn compact_provider_prompt_text(
  text : String,
  max_chars? : Int = 600,
) -> String {
  let trimmed = text.trim().to_owned()
  if trimmed.is_blank() {
    return ""
  }
  if trimmed.length() <= max_chars {
    return trimmed
  }
  let prefix = trimmed[:max_chars].to_owned().trim_end()
  "\{prefix}\n...[truncated by MoonClaw runtime]"
}

///|
fn provider_task_request_excerpt(
  request : AnalysisRequest,
  goal : String,
) -> String? {
  let prompt = request.prompt.trim().to_owned()
  if prompt.is_blank() {
    return None
  }
  let compact_prompt = compact_provider_prompt_text(prompt, max_chars=1200)
  let compact_goal = compact_provider_prompt_text(goal, max_chars=1200)
  if compact_prompt == compact_goal {
    None
  } else {
    Some(compact_prompt)
  }
}

///|
fn provider_task_preferred_skills(
  request : AnalysisRequest,
  repair? : Bool = false,
) -> Array[String] {
  let skills : Array[String] = []
  skills.push(
    if repair {
      "provider-task-repair"
    } else {
      "provider-task-execution"
    },
  )
  for skill in request.preferred_skills {
    if !skills.contains(skill) {
      skills.push(skill)
    }
  }
  skills
}

///|
fn provider_task_tool_contract(
  request : AnalysisRequest,
) -> AnalysisToolContract {
  AnalysisToolContract::{ ..request.tool_contract, todo: false }
}

///|
fn provider_task_tool_availability_section(request : AnalysisRequest) -> String {
  if !request.enable_tools {
    return [
      "Runtime tool availability:", "- tool execution is disabled for this provider task",
      "- web_search is unavailable", "- web_fetch is unavailable",
    ].join("\n")
  }
  let contract = provider_task_tool_contract(request)
  let tools = enabled_tool_names(contract)
  let enabled = if tools.is_empty() {
    "- none"
  } else {
    tools.map(fn(tool) { "- \{tool}" }).join("\n")
  }
  [
    "Runtime tool availability:",
    enabled,
    if contract.web_search {
      "- web_search is available"
    } else {
      "- web_search is unavailable; write an explicit blocker if the provider contract requires web search"
    },
    if contract.web_fetch {
      "- web_fetch is available"
    } else {
      "- web_fetch is unavailable; write an explicit blocker if the provider contract requires web fetch"
    },
  ].join("\n")
}

///|
fn provider_task_skill_path_absolute(
  workspace_root : String,
  path : String,
) -> String {
  let trimmed = path.trim().to_owned()
  if @pathx.is_absolute(trimmed) {
    @pathx.normalize(trimmed)
  } else {
    @pathx.join(workspace_root, trimmed)
  }
}

///|
async fn provider_task_loaded_skill_section(
  context : ProviderTaskWorkerContext,
) -> String {
  if context.skill_paths.is_empty() {
    return "Loaded provider skill bodies:\n- none"
  }
  let sections : Array[String] = ["Loaded provider skill bodies:"]
  let mut total_chars = 0
  for path in context.skill_paths {
    if total_chars >= 12000 {
      sections.push(
        "- additional skill bodies omitted by MoonClaw runtime budget",
      )
      break
    }
    let absolute = provider_task_skill_path_absolute(
      context.workspace_root,
      path,
    )
    let exists = @fsx.exists(absolute) catch { _ => false }
    if !exists {
      sections.push("## \{path}\n\n_unavailable at \{absolute}_")
      continue
    }
    let content = @fsx.read_file(absolute) catch { _ => continue }
    let trimmed = content.trim().to_owned()
    let budget = Int::min(3000, 12000 - total_chars)
    let excerpt = if trimmed.length() <= budget {
      trimmed
    } else {
      "\{trimmed[:budget].to_owned()}\n...[truncated by MoonClaw runtime]"
    }
    total_chars += excerpt.length()
    sections.push("## \{path}\n\n\{excerpt}")
  }
  sections.join("\n\n")
}

///|
async fn provider_task_contract_section(
  context : ProviderTaskWorkerContext,
) -> String {
  [
    "Provider output contract:",
    join_bullets(context.output_contract),
    provider_task_loaded_skill_section(context),
  ].join("\n\n")
}

///|
fn provider_task_system_prompt(
  request : AnalysisRequest,
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
) -> String {
  [
    "You are executing a domain-local extension task.",
    "The loaded `provider-task-execution` skill defines the execution method.",
    "Return strict JSON only matching this shape:",
    "{\"task_id\":string,\"summary\":string,\"artifacts\":string[],\"memory_candidates\":[{\"kind\":string,\"title\":string,\"detail\":string,\"durable\":bool,\"target_page\":string|null}],\"requires_review\":bool,\"notify_town\":bool}",
    "Use task_id = \{provider_task_result_task_id(task)}.",
    "Do not wrap the JSON in markdown fences.",
    "Output contract from the harness:",
    join_bullets(context.output_contract),
    provider_task_tool_availability_section(request),
    "Execution discipline:",
    "- Treat `Relevant Pages` and `Available Skill Files` as the primary working set.",
    "- Read concrete candidate files directly before using broad repo-wide search tools.",
    "- Only use broad search to fill a named gap after the primary working set is exhausted.",
    "- Ignore generated or dependency trees such as `.git`, `.moonclaw`, `.mooncakes`, `_build`, `node_modules`, `dist`, and temporary output directories unless the task explicitly requires them.",
    "- For bootstrap gather work, produce at least one `raw/bootstrap/*` artifact before claiming durable wiki revision success.",
    if request.system_prompt.trim().to_owned().is_blank() {
      ""
    } else {
      "Additional runtime instruction:\n\{request.system_prompt}"
    },
  ]
  .filter(fn(line) { !line.trim().to_owned().is_blank() })
  .join("\n\n")
}

///|
async fn provider_task_prompt(
  request : AnalysisRequest,
  task : ProviderTaskSpec,
  context : ProviderTaskWorkerContext,
) -> String {
  let goal = metadata_string_value(request.step_metadata, "extension_goal").unwrap_or(
    metadata_string_value(request.step_metadata, "bookapi_goal").unwrap_or(
      request.source_prompt,
    ),
  )
  let sections : Array[String] = [
    "Provider Scope: \{context.book_id}",
    "Workspace: \{context.workspace_root}",
    "Goal Summary: \{compact_provider_prompt_text(goal, max_chars=600)}",
    "Task: \{task.title}",
    "Task Kind: \{task.kind}",
    "",
    "Task Prompt Summary:",
    compact_provider_prompt_text(context.prompt, max_chars=1400),
    "",
    "Policy:",
    join_bullets(context.policy),
    "",
    "Routines:",
    join_bullets(context.routines),
    "",
    "Relevant Pages:",
    join_bullets(context.context_pages),
    "",
    "Active Memory:",
    join_bullets(context.active_memory),
    "",
    "User Memory:",
    join_bullets(context.user_memory),
    "",
    "Working Memory:",
    join_bullets(context.working_memory),
    "",
    "Memory Summary:",
    if context.memory_summary.trim().to_owned().is_blank() {
      "none"
    } else {
      compact_provider_prompt_text(context.memory_summary, max_chars=800)
    },
  ]
  if !context.skill_paths.is_empty() {
    sections.push("")
    sections.push("Available Skill Files:")
    sections.push(join_bullets(context.skill_paths))
    sections.push("")
    sections.push(provider_task_loaded_skill_section(context))
  }
  match provider_task_request_excerpt(request, goal) {
    Some(excerpt) => {
      sections.push("")
      sections.push("Original MoonClaw Request Excerpt:")
      sections.push(excerpt)
    }
    None => ()
  }
  sections.join("\n")
}
