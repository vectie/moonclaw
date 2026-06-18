///|
fn default_analysis_system_prompt() -> String {
  [
    @prompt.prelude, "You are executing a job workflow analysis step.", "Produce a concise, grounded report using the provided context.",
    "If the step cannot be completed because key inputs are missing, you may return JSON only: {\"verdict\":\"needs_input\",\"summary\":string,\"missing_inputs\":string[]}.",
    "If the step is too broad and should be decomposed before useful execution, you may return JSON only: {\"verdict\":\"needs_subplan\",\"summary\":string,\"suggested_substeps\":[{\"title\":string,\"prompt\":string,\"kind\":string?}]}.",
    "Use normal prose output when you can complete the step directly.",
  ].join("\n\n")
}

///|
pub fn analysis_system_prompt(config : AnalysisStepConfig) -> String {
  config.system_prompt.unwrap_or(default_analysis_system_prompt())
}

///|
fn preferred_skills_prompt(preferred_skills : Array[String]) -> String {
  if preferred_skills.is_empty() {
    ""
  } else {
    let names = preferred_skills.join(", ")
    "Prefer these skills if relevant: \{names}"
  }
}

///|
fn skill_file_candidates(
  cwd : String,
  home : String?,
  skill : String,
) -> Array[String] {
  let candidates : Array[String] = [
    cwd
    |> @pathx.join("skills")
    |> @pathx.join(skill)
    |> @pathx.join("SKILL.md"),
    cwd
    |> @pathx.join("skills")
    |> @pathx.join(skill)
    |> @pathx.join("skill.md"),
    cwd
    |> @pathx.join(".moonclaw")
    |> @pathx.join("skills")
    |> @pathx.join(skill)
    |> @pathx.join("SKILL.md"),
  ]
  match home {
    Some(home) =>
      candidates.push(
        home
        |> @pathx.join(".moonclaw")
        |> @pathx.join("skills")
        |> @pathx.join(skill)
        |> @pathx.join("SKILL.md"),
      )
    None => ()
  }
  candidates
}

///|
async fn load_skill_instruction_text(
  cwd : String,
  home : String?,
  skill : String,
) -> String? {
  for candidate in skill_file_candidates(cwd, home, skill) {
    let exists = @fsx.exists(candidate) catch { _ => false }
    if exists {
      let content = @fsx.read_file(candidate) catch { _ => continue }
      return Some(content)
    }
  }
  let process_cwd = @os.cwd() catch { _ => "" }
  if !process_cwd.is_blank() &&
    @pathx.normalize(process_cwd) != @pathx.normalize(cwd) {
    let extra_candidates : Array[String] = []
    for candidate in skill_file_candidates(process_cwd, home, skill) {
      if !extra_candidates.contains(candidate) {
        extra_candidates.push(candidate)
      }
    }
    for candidate in extra_candidates {
      let exists = @fsx.exists(candidate) catch { _ => false }
      if exists {
        let content = @fsx.read_file(candidate) catch { _ => continue }
        return Some(content)
      }
    }
  }
  None
}

///|
pub async fn loaded_skills_prompt(
  cwd : String,
  home : String?,
  preferred_skills : Array[String],
) -> String {
  let loaded : Array[String] = []
  for skill in preferred_skills {
    match load_skill_instruction_text(cwd, home, skill) {
      Some(content) => loaded.push(["Skill `\{skill}`", content].join("\n\n"))
      None => ()
    }
  }
  if loaded.is_empty() {
    ""
  } else {
    ["Loaded skill instructions:", loaded.join("\n\n---\n\n")].join("\n\n")
  }
}

///|
fn starter_attachment_artifact_priority(artifact_id : String) -> Int {
  if artifact_id.has_suffix("-summary") {
    0
  } else if artifact_id.has_suffix("-text") {
    1
  } else {
    2
  }
}

///|
fn render_starter_attachment_artifacts_prompt(input : Json) -> String {
  let digest_lines : Array[String] = []
  match input {
    { "starter_attachment_digest_excerpt": String(text), .. } => {
      let trimmed = text.trim().to_owned()
      if !trimmed.is_blank() {
        digest_lines.push("Starter attachment digest excerpt:")
        digest_lines.push(trimmed)
      }
    }
    _ => ()
  }
  match input {
    { "starter_attachment_digest_path": String(path), .. } =>
      digest_lines.push("Aggregate starter attachment digest path: \{path}")
    _ => ()
  }
  match input {
    { "starter_attachment_digest_artifact_id": String(artifact_id), .. } =>
      digest_lines.push(
        "Aggregate starter attachment digest artifact: \{artifact_id}",
      )
    _ => ()
  }
  let digest_prompt = digest_lines.join("\n")
  let rendered : Array[String] = []
  match input {
    { "starter_attachment_artifacts": Array(entries), .. } =>
      for entry in entries {
        match entry {
          {
            "id": String(id),
            "filename": filename,
            "artifact_ids": Array(artifact_ids),
            ..
          } => {
            let name = match filename {
              String(name) => name
              _ => id
            }
            let ids = artifact_ids
              .map(fn(value) {
                match value {
                  String(id) => id
                  _ => ""
                }
              })
              .filter(fn(id) { !id.is_blank() })
            if !ids.is_empty() {
              let ids = ids.copy()
              ids.sort_by(fn(left, right) {
                starter_attachment_artifact_priority(left).compare(
                  starter_attachment_artifact_priority(right),
                )
              })
              let joined_ids = ids.join(", ")
              rendered.push("- \{name}: \{joined_ids}")
            }
          }
          { "kind": String(kind), "artifact_id": String(artifact_id), .. } =>
            rendered.push("- \{kind}: \{artifact_id}")
          _ => ()
        }
      }
    _ => ()
  }
  if rendered.is_empty() {
    digest_prompt
  } else {
    let sections = [
      "Starter attachment artifacts:",
      "Prefer `starter_attachment_digest_excerpt` first when present as the immediate compact starter-document overview.",
      "Prefer `starter_attachment_digest_path` first when present as the directly readable aggregate starter-document overview.",
      "Use `starter_attachment_digest_artifact_id` next when artifact-oriented tooling is available.",
      "Prefer `starter_attachment.summary` artifact ids first when available; use the full extracted text artifacts only when you need more detail.",
      "Prefer these durable artifact references before falling back to raw workspace paths.",
      rendered.join("\n"),
    ]
    let sections = if digest_prompt.is_blank() {
      sections
    } else {
      [digest_prompt, ..sections]
    }
    sections.join("\n")
  }
}

///|
pub fn analysis_memory_query(
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
) -> MemoryQuery {
  let workspace = match config.workspace {
    Some(workspace) => Some(workspace)
    None =>
      match context.run.workspace_dir {
        Some(workspace_dir) => Some(workspace_dir)
        None => config.cwd
      }
  }
  MemoryQuery::new(
    workspace~,
    scope=config.artifacts.scope.get(0),
    status=Some(MemoryStatus::Active),
  )
}

///|
pub fn analysis_working_directory(
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
) -> String {
  context.run.workspace_dir.unwrap_or(config.cwd.unwrap_or("."))
}

///|
fn analysis_memory_search_text(
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
) -> String {
  let sections = [config.prompt]
  let sections = match context.initial_input {
    Some(input) => [..sections, input.stringify()]
    None => sections
  }
  if context.outputs.is_empty() {
    sections.join("\n")
  } else {
    let rendered : Array[String] = []
    for step_id, output in context.outputs {
      rendered.push("[\{step_id}] \{output.stringify()}")
    }
    [..sections, rendered.join("\n")].join("\n")
  }
}

///|
pub fn analysis_memory_prompt(
  store : SystemStore,
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
) -> String {
  let memories = MemoryService::new(store~)
  let query = analysis_memory_query(context, config)
  let hits = memories.search(
    analysis_memory_search_text(context, config),
    query~,
    max_hits=4,
  )
  if !hits.is_empty() {
    return render_memory_hits_prompt(
      hits,
      header="Relevant long-term memory for this step",
    )
  }
  let fallback = memories.list(query~)
  fallback.sort_by(fn(left, right) { right.updated_at.compare(left.updated_at) })
  let fallback = if fallback.length() > 4 {
    fallback[:4].to_owned()
  } else {
    fallback
  }
  render_memory_records_prompt(
    fallback,
    header="Relevant long-term memory for this step",
  )
}

///|
pub fn build_analysis_prompt(
  context : WorkflowStepContext,
  config : AnalysisStepConfig,
  skills_prompt : String,
  memory_prompt : String,
) -> String {
  let resume_prompt = match
    resume_instruction_from_input(context.initial_input) {
    Some(trimmed) =>
      [
        "Resume instruction from user:\n\{trimmed}",
        "Treat the resume instruction as authoritative operator guidance. Interpret it directly and adapt your approach accordingly. If it authorizes assumptions, best-effort estimation, or proceeding without further user input, follow that guidance and make clearly labeled assumptions unless completion would require inventing core facts.",
      ].join("\n\n")
    None => ""
  }
  let step_metadata_prompt = match config.metadata {
    { "step_metadata": metadata, .. } =>
      "Step metadata:\n\{metadata.stringify()}"
    _ => ""
  }
  let starter_attachment_artifacts_prompt = match context.initial_input {
    Some(input) => render_starter_attachment_artifacts_prompt(input)
    None => ""
  }
  let sections = [
    config.prompt,
    preferred_skills_prompt(config.preferred_skills),
    skills_prompt,
    memory_prompt,
    step_metadata_prompt,
    starter_attachment_artifacts_prompt,
    resume_prompt,
    "Job id: \{context.run.job_id}",
    "Run id: \{context.run.id}",
    "Step id: \{context.step.id}",
  ]
  let sections = match context.initial_input {
    Some(input) => [..sections, "Initial input:\n\{input.stringify()}"]
    None => sections
  }
  let sections = if context.outputs.is_empty() {
    sections
  } else {
    let rendered : Array[String] = []
    for step_id, output in context.outputs {
      rendered.push("[\{step_id}] \{output.stringify()}")
    }
    let rendered_text = rendered.join("\n")
    [..sections, "Previous step outputs:\n\{rendered_text}"]
  }
  sections.filter(fn(section) { !section.is_blank() }).join("\n\n")
}
